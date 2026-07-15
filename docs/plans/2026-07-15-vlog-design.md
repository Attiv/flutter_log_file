# VLog 日志系统设计

**日期：** 2026-07-15  
**目标平台：** Android、Windows  
**交付形态：** 独立 Flutter Package `flutter_log_file`

## 1. 目标

`flutter_log_file` 为不方便直接查看终端输出的 Android/Windows 设备提供统一日志能力。它同时支持可关闭的彩色终端输出、App 私有目录文件落盘、跨日与按大小轮转、对象和 JSON 格式化、大文件懒加载查看以及流式搜索定位。

业务通过静态入口 `VLog` 使用日志系统，不需要等待每一次日志写入。Package 提供可由宿主应用自由跳转的日志文件列表页和日志阅读页。

## 2. 对外 API

初始化与基本调用：

```dart
await VLog.init(
  LogConfig(
    consoleEnabled: true,
    fileEnabled: true,
    showTag: true,
    prettyJson: false,
    filePrefix: 'app_log',
    splitByDay: true,
    retentionDays: 30,
    maxFileSize: 50 * 1024 * 1024,
  ),
);

VLog.i('应用启动');
VLog.d(data, tag: 'Network');
VLog.e(
  '请求失败',
  tag: 'API',
  error: error,
  stackTrace: stackTrace,
);

await VLog.flush();
await VLog.close();
```

日志等级为 `verbose`、`debug`、`info`、`warning`、`error`、`fatal`。Tag 始终可选；未传入 Tag 时不会输出空的 Tag 占位符。

管理 API 包括：

- `VLog.getLogFiles()`
- `VLog.flush()`
- `VLog.close()`
- `VLog.clearLogs()`
- `VLog.exportLogs()`
- 自定义对象编码器的注册和注销

查看页由宿主自行打开：

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const VLogViewerPage()),
);
```

## 3. 架构

Package 分为五层：

1. **入口层**：`VLog` 收集等级、消息、Tag、异常、堆栈和业务字段。
2. **格式化层**：解析调用文件与行号，完成对象序列化、JSON 格式化、日志前缀和可选脱敏。
3. **输出层**：`ConsoleSink` 与 `FileSink` 独立启停、独立设置最低等级。
4. **存储层**：管理默认目录、文件命名、日期/大小轮转、过期清理与导出。
5. **查看层**：按块读取文件、虚拟列表显示、实时追加、后台搜索和按偏移跳转。

调用数据流：

```text
VLog 调用
  -> 收集时间、调用位置、等级、Tag、异常和上下文
  -> 对象转为可编码数据
  -> 有界异步队列
  -> 后台写入 Worker
  -> ConsoleSink / FileSink
  -> 查看页实时事件（仅当前进程）
```

日志调用保持无 `await` 的低摩擦 API。`flush()` 和 `close()` 为需要确保持久化的生命周期节点提供显式屏障。初始化完成前的日志放入有界内存缓冲区。

## 4. 日志格式

默认单行格式：

```text
2026-07-15 14:32:08.126 [INFO] [Network] api_client.dart:87 | request completed
```

必须包含：

- 当前日志时间；
- 日志等级；
- 调用文件名；
- 调用行号；
- 日志正文。

Tag 可传可不传，并可通过配置全局隐藏。时间格式和本地时间/UTC 可配置。调用位置解析会跳过 Package 自己的调用栈帧。

控制台可使用 ANSI 颜色区分日志等级，颜色功能可关闭。日志文件永远不保存 ANSI 控制字符。

当 JSON 美化产生多行时，每个物理行都附带同一条日志的时间、等级、调用位置等前缀，确保任意搜索结果均能单独定位。查看页复制 JSON 时移除这些前缀并提供纯 JSON。

每次初始化生成短 `sessionId`，本次运行内每条日志拥有递增序号。二者的展示均可配置。启动时写入会话分隔记录。业务还可以传入 `fields`：

```dart
VLog.i(
  '支付请求完成',
  tag: 'Payment',
  fields: {'requestId': requestId, 'orderId': orderId},
);
```

这些字段用于按 session、序号、Tag、requestId、orderId 或时间快速串联问题。

## 5. JSON 与对象编码

消息编码按以下优先级处理：

1. `String`、`num`、`bool`、`null`；
2. `Map`、`List`；
3. 已注册的自定义对象编码器；
4. 对象公开的 `toJson()`；
5. 回退至 `toString()`。

Dart/Flutter Release 模式不能可靠反射任意对象字段，因此不承诺自动展开没有 `toJson()`、自定义编码器或有效 `toString()` 的任意对象。

JSON 美化默认关闭。文件与控制台可分别覆盖 JSON 美化配置。

敏感信息处理完全由开发者选择：

- `redactedKeys` 默认是空集合；
- `redactors` 默认是空列表；
- 没有显式配置时不修改任何日志内容。

## 6. 文件管理

默认目录：

- Android：App Support 私有目录下的 `logs/`；
- Windows：应用 Support 目录下的 `logs/`。

目录通过 `path_provider` 解析。开发者可以传入绝对目录或异步目录解析函数。核心实现不依赖 Android 专属 API。

默认文件名为：

```text
app_log_2026-07-15.txt
```

配置项包括前缀、扩展名、是否按天生成及日期格式。不按天生成时使用 `app_log.txt`。应用持续跨天运行时，下一条日志到达前会检测日期变化，关闭旧文件并创建当天文件。

默认保留 30 天，每个文件最大 50 MB，两者都可配置。同一天超出大小后依次创建：

```text
app_log_2026-07-15.1.txt
app_log_2026-07-15.2.txt
```

清理仅匹配当前配置生成的日志文件，不删除目录内其他文件。清理发生在初始化和轮转维护阶段，也可由查看页手动触发。

## 7. 并发、刷新与错误处理

- 所有文件写入通过单一顺序队列执行，保持调用顺序并避免内容交叉。
- 控制台和文件输出互相隔离，一个 Sink 失败不影响另一个 Sink。
- 队列有上限；默认优先丢弃低等级日志并记录丢弃数量，`error/fatal` 优先保留。
- 刷新间隔、错误等级立即刷新和队列溢出策略均可配置。
- 重复初始化时先排空旧队列，再切换配置。
- 文件创建或写入失败时进行有上限的退避重试，并通过可用的控制台报告内部错误。
- 日志系统内部错误不再次进入自身队列，避免递归。
- 单条日志拥有可配置的最大字节数，超限后截断并标记原始长度。
- 文件使用 UTF-8 和 `\n` 写入；读取器同时兼容 `\n`、`\r\n`。

## 8. 自动异常捕获

自动捕获默认关闭，可分别启用：

- `FlutterError.onError`；
- `PlatformDispatcher.instance.onError`；
- `VLog.runGuarded(() => runApp(...))`。

启用后先记录异常，再调用开发者原有错误处理器，不吞掉原异常。业务始终可以只使用 `VLog.e(..., error:, stackTrace:)` 手动记录错误。

## 9. 日志查看页

### 9.1 文件列表

- 按修改时间倒序显示文件名、大小、修改时间和活动状态；
- 单选或多选删除；
- 分享、导出和复制路径；
- 清理过期日志和手动刷新；
- 允许打开正在写入的文件。

### 9.2 大文件读取

页面不使用 WebView，也不会把整个文件读入内存：

- 首次从文件尾部反向扫描，只显示最后一批日志；
- 向上滚动加载更早字节块，向下滚动加载后续块；
- 使用 LRU 缓存，默认内存预算约 4 MB且可配置；
- 当前活动文件支持实时追踪、暂停和恢复；
- 正确处理超大行、UTF-8 字符跨块、并发追加、文件截断和轮转。

Flutter 的 `ListView.builder` 只构建可见行，结合有界字节块缓存实现稳定内存占用。

### 9.3 搜索与定位

- 普通关键词、大小写匹配、正则表达式；
- 按等级、Tag 和时间范围过滤；
- 后台 Isolate 分块搜索，显示进度并允许取消；
- 搜索结果仅保存摘要和文件字节偏移；
- 点击结果按偏移加载前后文；
- 支持上一个/下一个结果；
- 支持复制当前行、复制前后若干行和导出筛选结果。

### 9.4 阅读体验

- 不同等级使用不同颜色；
- 自动换行和单行横向滚动可切换；
- 字号可调，可跳转文件首尾；
- JSON 可折叠、展开和复制纯内容；
- Error 可展开异常与 StackTrace。

## 10. 平台与权限

第一版正式支持 Android 与 Windows。默认使用 App 私有 Support 目录，不申请公共存储权限，不需要网络权限，也不自动上传日志。导出或分享只在开发者或用户主动操作时发生。

## 11. 测试策略

实现遵循测试先行：

- 单元测试：格式化、等级、Tag、调用位置、JSON、对象编码、脱敏、文件命名；
- 文件测试：按日轮转、跨零点、大小分片、过期清理、并发顺序、flush/close；
- 读取测试：反向分块、UTF-8 边界、CRLF、超大行、搜索偏移、缓存上限；
- Widget 测试：文件列表、日志行虚拟显示、过滤、搜索结果跳转、实时追踪状态；
- 平台测试：Android/Windows 默认路径分支及路径覆盖逻辑。

开发阶段只在本机运行格式化、静态检查和自动化测试，不安装或运行到当前连接的 Android 手机。

## 12. 非目标

第一版不实现：

- 日志自动上传或远程日志服务；
- SQLite 全量索引；
- WebView 日志阅读器；
- Dart 任意对象运行时反射；
- 多进程同时写同一日志文件。

后续若百万级日志的重复搜索成为瓶颈，可在保持文本文件为事实来源的前提下增加可选持久化索引。
