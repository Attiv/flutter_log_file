# VLog Material 3 Demo

这是 `flutter_log_file` 的完整体验 App，支持 Android 和 Windows。Demo 使用本地路径依赖引用上一级 Package，不需要先发布到 pub.dev。

## 运行

```bash
cd example
flutter pub get
```

Android：

```bash
flutter devices
flutter run -d <android-device-id>
```

Windows：

```bash
flutter run -d windows
```

## 可以体验什么

### 输出配置

- 独立开启或关闭终端、文件输出；
- 配置是否显示 Tag；
- 开启或关闭 JSON 格式化；
- 配置是否按天生成日志文件；
- 修改日志文件前缀；
- 开启终端 ANSI 颜色；
- 设置最低日志等级；
- 点击“应用配置”创建新的 VLog session。

### 日志实验台

- 输入任意日志内容和可选 Tag；
- 分别输出 Verbose、Debug、Info、Warning、Error、Fatal；
- 输出 Map/List 嵌套 JSON；
- 输出带 `toJson()` 的 `DemoUser`；
- 使用注册编码器输出 `DemoOrder`；
- 输出 Error、StackTrace 和结构化 fields；
- 一次生成 200 条日志，体验大文件懒加载与搜索。

### 日志查看器

点击右上角“查看日志”或页面底部“打开日志查看器”，进入 Package 自带的 `VLogViewerPage`。可以继续体验：

- 文件列表、大小、活动文件状态；
- 从文件尾部懒加载；
- 实时追踪与暂停；
- 关键词、正则、等级、Tag 和日期过滤；
- Isolate 流式搜索与结果定位；
- 复制、分享、删除和过期日志清理。

## 测试

```bash
cd example
flutter analyze
flutter test
```

Widget 测试使用临时目录，不依赖 Android 或 Windows 的目录插件。
