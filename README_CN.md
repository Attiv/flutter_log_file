# flutter_log_file

[English](README.md) | 简体中文

`flutter_log_file` 是一个面向 Android 和 Windows 的 Flutter 日志 Package，入口名称为 **`VLog`**。它同时支持终端输出、App 私有目录文件、跨日/按大小轮转、JSON/对象格式化、异常捕获和大文件懒加载查看。

## 功能

- `VLog.v/d/i/w/e/f` 六级日志 API，Tag 可传可不传；
- 控制台和文件 Sink 可分别启停、过滤等级和格式化；
- 时间、调用文件名、调用行号、等级始终可定位；
- 控制台 ANSI 颜色可配置，文件不会写入颜色控制字符；
- Android/Windows 默认使用 App Support 私有目录，无公共存储权限；
- 默认 `app_log_yyyy-MM-dd.txt`，支持自定义前缀、扩展名和按天开文件；
- 默认保留 30 天、单文件 50 MB，均可配置；
- 异步队列同时限制条数和保留字节数，默认 10,000 条和 8 MB；
- Map/List、`toJson()` 和自定义对象编码器；
- JSON 紧凑/美化可分别配置，默认不美化；
- 可选接管 Flutter 和平台异常，默认不接管原处理器；
- `VLogViewerPage` / `VLogFilePage` 支持懒加载、实时追踪、搜索、正则、等级/Tag/日期过滤、复制、分享和删除；
- 搜索在 Isolate 中执行，查看页只保留有界字节窗口，不把完整大文件载入内存。

队列、查看器、搜索和生命周期的内存边界详见英文版 [memory audit](docs/memory-audit.md)。

## 安装

```bash
flutter pub add flutter_log_file
```

当前 Package 不需要网络权限，也不会自动上传日志。

## 体验 Demo

[`example/`](example/) 中提供了支持 Android 和 Windows 的完整 Material 3 Demo，包含可视化配置、六级日志、JSON/对象/异常示例、批量日志生成以及日志查看器入口。

```bash
cd example
flutter pub get
flutter run -d <device-id>
```

## 基本使用

```dart
import 'package:flutter_log_file/flutter_log_file.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await VLog.init(
    LogConfig(
      consoleEnabled: true,
      fileEnabled: true,
      showTag: true,
      prettyJson: false,
      filePrefix: 'app_log',
      splitByDay: true,
      retentionDays: 30,
      maxFileSizeBytes: 50 * 1024 * 1024,
    ),
  );

  VLog.i('应用启动');
  VLog.d({'retry': 2}, tag: 'Network');
  VLog.w('缓存即将过期');
  VLog.e(
    '请求失败',
    tag: 'API',
    error: StateError('timeout'),
    stackTrace: StackTrace.current,
  );

  runApp(const MyApp());
}
```

每次 `VLog.init()` 会生成一个 session。调用位置默认来自日志调用处，而不是 Package 内部栈帧。Release 模式下若平台没有提供源代码栈信息，调用位置会回退为 `unknown`。

当日志内容是多行美化 JSON 时，每个物理行都会重复时间、等级、文件和行号前缀，方便在终端或文件中直接搜索定位。

## 路径和文件轮转

默认路径：

- Android：应用 Support 私有目录下的 `logs/`；
- Windows：应用 Support 目录下的 `logs/`（通常位于 `%APPDATA%` 应用目录）。

不需要申请公共存储权限。开发者可传入绝对路径或异步解析器：

```dart
LogConfig(
  directoryPath: '/custom/log/path',
  // 或：directoryResolver: () async => await resolveDirectory(),
)
```

默认文件名：

```text
app_log_2026-07-15.txt
app_log_2026-07-15.1.txt
```

不按天生成时：

```dart
LogConfig(splitByDay: false, filePrefix: 'device')
// device.txt, device.1.txt, ...
```

应用不重启跨过零点时，下一条日志会自动切换到新日期文件。`retentionDays: 0` 表示关闭自动过期清理；`maxFileSizeBytes` 控制同一天的分片大小。

## JSON 和对象

```dart
VLog.i({'user': 'Ada', 'roles': ['admin']});

final order = Order(id: 'O-1');
VLog.i(order); // 使用 toJson()，没有 toJson() 时回退到 toString()

VLog.registerEncoder<Order>((value) => {
  'id': value.id,
  'state': value.state.name,
});
```

编码顺序为 primitive、Map/List、已注册编码器、`toJson()`、`toString()`。Dart/Flutter Release 没有可靠的任意对象运行时反射，因此业务对象应提供 `toJson()` 或注册编码器。

紧凑/美化可以按输出端分别配置：

```dart
LogConfig(
  prettyJson: false,
  consolePrettyJson: true,
  filePrettyJson: false,
)
```

### 敏感数据

脱敏默认完全关闭：`redactedKeys` 默认为空集合，`redactors` 默认为空列表。只有显式配置才处理：

```dart
LogConfig(
  redactedKeys: {'password', 'token', 'authorization'},
  redactors: [
    LogRedactor(
      pattern: RegExp(r'1\d{10}'),
      replacement: '***',
    ),
  ],
)
```

## 异常捕获

默认不接管任何全局错误处理器。需要时显式打开：

```dart
await VLog.init(
  LogConfig(
    captureFlutterErrors: true,
    capturePlatformErrors: true,
  ),
);

VLog.runGuarded(() => runApp(const MyApp()));
```

Package 会先记录错误，再调用原来的 Flutter/platform handler；记录失败不会吞掉原异常。

## 集成日志查看页

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const VLogViewerPage()),
);
```

文件列表页支持：

- 按修改时间倒序查看文件、大小、活动状态；
- 手动刷新、清理过期文件；
- 长按多选后分享、删除；
- 复制文件路径。

文件阅读页支持：

- 从文件尾部开始读取，向上/向下按字节块加载；
- `ListView.builder` 只构建可见行；默认约 4 MB 解码内存预算；
- 实时追踪/暂停、字号、换行、跳到首尾；
- 普通关键词、大小写、正则、等级、Tag、日期范围过滤；
- Isolate 流式搜索、进度、取消、结果字节偏移跳转；
- 复制当前行、前后文和移除日志前缀的纯 JSON/纯内容；
- JSON 折叠和 Error/StackTrace 展开。

## 生命周期

```dart
await VLog.flush();
await VLog.close();
```

日志调用本身不需要 `await`。队列同时受 `queueCapacity`（默认 10,000 条）和 `queueByteCapacity`（默认 8 MB）限制，队列满时优先保留高等级日志。消息、fields、error 和 StackTrace 会在进入异步队列前转换为有界快照，不会长期持有业务对象图；`error/fatal` 会触发 Sink 刷新。

## 限制

- 不支持多个进程同时写同一个日志文件；
- 不使用 WebView，也不建立 SQLite 全量索引；
- Release/AOT 若没有源映射，文件名/行号可能无法解析；
- Windows 原生构建应在 Windows 主机上验证。本仓库本机检查覆盖 Windows 路径策略和纯 Dart/Widget 逻辑。

## 本地开发

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter pub publish --dry-run
```
