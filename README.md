# flutter_log_file

English | [简体中文](README_CN.md)

`flutter_log_file` is a Flutter logging package for Android and Windows. Its public entry point is **`VLog`**. It supports terminal output, files in the app-private directory, daily and size-based rotation, JSON/object formatting, error capture, and lazy loading of large log files.

## Features

- Six log levels through `VLog.v/d/i/w/e/f`, with an optional tag;
- Independently configurable console and file sinks, level filters, and formatting;
- Timestamp, source filename, source line number, and level for quick location;
- Configurable ANSI colors in the console without writing control characters to files;
- App Support private directories by default on Android and Windows, with no public storage permission required;
- Default filename `app_log_yyyy-MM-dd.txt`, with configurable prefix, extension, and daily splitting;
- Configurable retention and rotation, defaulting to 30 days and 50 MB per file;
- Count- and byte-bounded asynchronous queue, defaulting to 10,000 entries and 8 MB retained data;
- Map/List, `toJson()`, and custom object encoder support;
- Independently configurable compact or pretty JSON per sink, compact by default;
- Optional Flutter and platform error capture without replacing existing handlers by default;
- `VLogViewerPage` / `VLogFilePage` with lazy loading, live tailing, search, regex, level/tag/date filters, copy, share, and delete actions;
- Isolate-based search and a bounded byte window in the viewer, so the complete large file is never loaded into memory.

See the detailed [memory audit](docs/memory-audit.md) for queue, viewer, search, and lifecycle bounds.

## Installation

```bash
flutter pub add flutter_log_file
```

The package does not require network permission and never uploads logs automatically.

## Demo App

A complete Material 3 demo for Android and Windows is available in [`example/`](example/). It includes editable VLog configuration, all six log levels, JSON/object/error samples, burst generation, and direct access to the lazy log viewer.

```bash
cd example
flutter pub get
flutter run -d <device-id>
```

## Basic Usage

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

  VLog.i('Application started');
  VLog.d({'retry': 2}, tag: 'Network');
  VLog.w('Cache is about to expire');
  VLog.e(
    'Request failed',
    tag: 'API',
    error: StateError('timeout'),
    stackTrace: StackTrace.current,
  );

  runApp(const MyApp());
}
```

Each `VLog.init()` creates a session. The source location points to the log call site rather than an internal package frame. In release mode, it falls back to `unknown` if the platform does not provide source information in the stack trace.

For multiline pretty-printed JSON, every physical line repeats the timestamp, level, filename, and line-number prefix so it remains easy to search in the terminal or log file.

## Paths and File Rotation

Default paths:

- Android: `logs/` under the app-private Support directory;
- Windows: `logs/` under the App Support directory, usually inside the application's `%APPDATA%` directory.

No public storage permission is required. You can provide an absolute path or an asynchronous resolver:

```dart
LogConfig(
  directoryPath: '/custom/log/path',
  // Or: directoryResolver: () async => await resolveDirectory(),
)
```

Default filenames:

```text
app_log_2026-07-15.txt
app_log_2026-07-15.1.txt
```

Without daily splitting:

```dart
LogConfig(splitByDay: false, filePrefix: 'device')
// device.txt, device.1.txt, ...
```

If the app remains running across midnight, the next log entry automatically switches to the new day's file. Set `retentionDays: 0` to disable automatic expiry cleanup. `maxFileSizeBytes` controls file segmentation within the same day.

## JSON and Objects

```dart
VLog.i({'user': 'Ada', 'roles': ['admin']});

final order = Order(id: 'O-1');
VLog.i(order); // Uses toJson(), then falls back to toString()

VLog.registerEncoder<Order>((value) => {
  'id': value.id,
  'state': value.state.name,
});
```

The encoding order is primitive values, Map/List, registered encoders, `toJson()`, and finally `toString()`. Dart/Flutter release builds do not provide reliable runtime reflection for arbitrary objects, so application models should expose `toJson()` or register an encoder.

Compact and pretty formatting can be configured independently for each sink:

```dart
LogConfig(
  prettyJson: false,
  consolePrettyJson: true,
  filePrettyJson: false,
)
```

### Sensitive Data

Redaction is completely disabled by default: `redactedKeys` is an empty set and `redactors` is an empty list. Data is processed only when explicitly configured:

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

## Error Capture

No global error handler is intercepted by default. Enable capture explicitly when needed:

```dart
await VLog.init(
  LogConfig(
    captureFlutterErrors: true,
    capturePlatformErrors: true,
  ),
);

VLog.runGuarded(() => runApp(const MyApp()));
```

The package records the error first and then invokes the original Flutter/platform handler. A logging failure never swallows the original error.

## Integrating the Log Viewer

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const VLogViewerPage()),
);
```

The file list page supports:

- Files sorted by modification time, with size and active-state indicators;
- Manual refresh and expired-file cleanup;
- Long-press multi-selection for sharing and deletion;
- Copying file paths.

The file reader page supports:

- Initial reading from the end of the file, with byte-block loading in either direction;
- `ListView.builder` rendering only visible lines, with a default decoded-memory budget of about 4 MB;
- Live tail/pause, font-size and wrapping controls, and jump-to-start/end;
- Plain-text, case-sensitive, regex, level, tag, and date-range filters;
- Isolate-based streaming search with progress, cancellation, and byte-offset navigation;
- Copying the current line, surrounding context, or plain JSON/content with the log prefix removed;
- Collapsible JSON and expandable Error/StackTrace sections.

## Lifecycle

```dart
await VLog.flush();
await VLog.close();
```

Log calls do not need to be awaited. The queue is bounded by both `queueCapacity` (10,000 entries by default) and `queueByteCapacity` (8 MB by default), and prioritizes higher-level entries when full. Messages, fields, errors, and stack traces are normalized into bounded snapshots before entering the queue, so application object graphs are not retained by asynchronous logging. `error` and `fatal` entries trigger sink flushing.

## Limitations

- Multiple processes writing to the same log file are not supported;
- The viewer does not use a WebView or build a complete SQLite index;
- Filename and line-number resolution may be unavailable in release/AOT builds without source mapping;
- Native Windows builds should be verified on a Windows host. Local repository checks cover Windows path policies and pure Dart/widget logic.

## Local Development

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter pub publish --dry-run
```
