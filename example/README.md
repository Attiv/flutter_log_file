# VLog 接入示例

业务 App 中先初始化 Package，再从任意按钮进入查看页：

```dart
await VLog.init(
  LogConfig(
    consoleEnabled: true,
    fileEnabled: true,
    showTag: true,
    splitByDay: true,
  ),
);

VLog.i('ready', tag: 'Bootstrap');

Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const VLogViewerPage()),
);
```

查看页自身负责懒加载和搜索；业务不需要预先读取日志文件。
