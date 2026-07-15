# VLog Logging Package Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reusable Flutter package named `flutter_log_file` that provides the `VLog` API, configurable console/file logging, Android/Windows private storage, safe file rotation, object/JSON formatting, automatic error capture, and a bounded-memory log viewer with background search.

**Architecture:** A static `VLog` facade delegates to one lifecycle-managed controller. The controller creates immutable log events, sends them through a bounded serial queue, and writes independently to console and rotating file sinks. Viewer services read UTF-8 files by byte range and search them in a separate isolate, while Flutter pages render only visible rows and keep a bounded LRU window.

**Tech Stack:** Flutter 3.32+, Dart 3.8+, `dart:io`, Flutter Material, `path_provider`, `path`, `intl`, `share_plus`, `flutter_test`.

---

## General execution rules

- Apply `@superpowers:test-driven-development` for every production behavior.
- Apply `@superpowers:systematic-debugging` before changing code in response to any unexpected test failure.
- Run tests without selecting an Android device. Do not run `flutter run`, `flutter install`, `adb install`, or any command that deploys to the connected phone.
- Commit after every task only after its focused tests and the full existing suite pass.
- Keep Android and Windows support in pure Dart/Flutter code; do not add native platform source unless a failing test proves it necessary.

## Target file layout

```text
lib/
  flutter_log_file.dart
  src/
    core/
      log_controller.dart
      log_queue.dart
      vlog.dart
    error/
      error_capture.dart
    format/
      caller_resolver.dart
      log_formatter.dart
      message_serializer.dart
    model/
      log_config.dart
      log_entry.dart
      log_file_info.dart
      log_level.dart
      log_redactor.dart
      viewer_config.dart
    sink/
      console_sink.dart
      file_sink.dart
      log_sink.dart
    storage/
      directory_resolver.dart
      file_name_policy.dart
      log_file_manager.dart
    viewer/
      file_chunk_reader.dart
      log_file_controller.dart
      log_line_parser.dart
      log_search_service.dart
      log_viewer_page.dart
      log_file_page.dart
test/
  core/
  error/
  format/
  sink/
  storage/
  viewer/
```

### Task 1: Scaffold the package and define public configuration contracts

**Files:**
- Create: `.gitignore`
- Create: `.metadata`
- Create: `analysis_options.yaml`
- Create: `pubspec.yaml`
- Create: `CHANGELOG.md`
- Create: `LICENSE`
- Create: `README.md`
- Create: `lib/flutter_log_file.dart`
- Create: `lib/src/model/log_level.dart`
- Create: `lib/src/model/log_config.dart`
- Create: `lib/src/model/log_redactor.dart`
- Create: `lib/src/model/viewer_config.dart`
- Test: `test/model/log_config_test.dart`

**Step 1: Scaffold package metadata**

Run:

```bash
flutter create --template=package --project-name=flutter_log_file .
flutter pub add path_provider path intl share_plus
```

Expected: package files are created, dependencies resolve, and no Android device is selected or used.

Set the SDK floor in `pubspec.yaml` to `>=3.3.0 <4.0.0`. Remove the generated calculator API and its test.

**Step 2: Write failing tests for documented defaults**

Create `test/model/log_config_test.dart` with focused tests equivalent to:

```dart
import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the approved file and privacy defaults', () {
    const config = LogConfig();

    expect(config.consoleEnabled, isTrue);
    expect(config.fileEnabled, isTrue);
    expect(config.showTag, isTrue);
    expect(config.prettyJson, isFalse);
    expect(config.filePrefix, 'app_log');
    expect(config.fileExtension, 'txt');
    expect(config.splitByDay, isTrue);
    expect(config.retentionDays, 30);
    expect(config.maxFileSizeBytes, 50 * 1024 * 1024);
    expect(config.captureFlutterErrors, isFalse);
    expect(config.capturePlatformErrors, isFalse);
    expect(config.redactedKeys, isEmpty);
    expect(config.redactors, isEmpty);
  });

  test('accepts optional tag and platform-independent directory override', () {
    const config = LogConfig(
      showTag: false,
      directoryPath: r'C:\temp\vlog',
    );

    expect(config.showTag, isFalse);
    expect(config.directoryPath, r'C:\temp\vlog');
  });

  test('rejects invalid rotation and queue values', () {
    expect(() => LogConfig(retentionDays: -1), throwsArgumentError);
    expect(() => LogConfig(maxFileSizeBytes: 0), throwsArgumentError);
    expect(() => LogConfig(queueCapacity: 0), throwsArgumentError);
  });
}
```

**Step 3: Run the tests and verify RED**

Run:

```bash
flutter test test/model/log_config_test.dart
```

Expected: FAIL because `LogConfig`, `LogLevel`, `LogRedactor`, and exported public contracts do not exist.

**Step 4: Implement the minimum public models**

Implement:

```dart
enum LogLevel { verbose, debug, info, warning, error, fatal }

enum LogQueueOverflowPolicy { dropLowestLevel, dropNewest }

enum LogTimeZone { local, utc }
```

`LogConfig` must be immutable and expose validated defaults for:

- console/file enablement and per-sink minimum levels;
- `showTag`, `showCaller`, `showSessionId`, `showSequence`, `showFields`;
- global, console, and file JSON pretty-print selection;
- color enablement;
- directory override/resolver;
- prefix, extension, day splitting, date/time patterns;
- 30-day retention and 50 MB rotation;
- queue capacity/overflow policy, flush interval, flush-on-level;
- maximum entry bytes;
- automatic Flutter/platform capture switches;
- empty `redactedKeys` and `redactors` defaults.

`LogRedactor` contains a `RegExp pattern` and `String replacement`. `VLogViewerConfig` contains defaults for chunk size, memory budget, initial tail line count, and line wrapping.

Export only public models from `lib/flutter_log_file.dart`.

**Step 5: Verify GREEN and commit**

Run:

```bash
dart format lib test
flutter analyze
flutter test test/model/log_config_test.dart
```

Expected: all commands pass with no analyzer warnings.

Commit:

```bash
git add .
git commit -m "feat: scaffold VLog package configuration"
```

### Task 2: Implement message serialization, redaction, caller resolution, and line formatting

**Files:**
- Create: `lib/src/model/log_entry.dart`
- Create: `lib/src/format/message_serializer.dart`
- Create: `lib/src/format/caller_resolver.dart`
- Create: `lib/src/format/log_formatter.dart`
- Test: `test/format/message_serializer_test.dart`
- Test: `test/format/log_formatter_test.dart`
- Test: `test/format/caller_resolver_test.dart`

**Step 1: Write failing serializer tests**

Cover each branch independently:

```dart
test('serializes Map and List as compact JSON by default', () { ... });
test('pretty prints JSON only when requested', () { ... });
test('uses a registered encoder before toJson', () { ... });
test('uses toJson when no registered encoder matches', () { ... });
test('falls back to toString when an object cannot be encoded', () { ... });
test('does not redact anything with empty default configuration', () { ... });
test('redacts configured keys case-insensitively', () { ... });
test('applies only explicitly configured regex redactors', () { ... });
```

Use a real test object:

```dart
final class EncodableUser {
  EncodableUser(this.name);
  final String name;
  Map<String, Object?> toJson() => {'name': name};
}
```

**Step 2: Run serializer tests and verify RED**

Run:

```bash
flutter test test/format/message_serializer_test.dart
```

Expected: FAIL because `MessageSerializer` and the encoder registry are missing.

**Step 3: Implement serializer and encoder registry**

The registry API exposed through the eventual facade must support:

```dart
void register<T>(Object? Function(T value) encoder);
void unregister<T>();
```

Encoding order must be primitive/Map/List, registered runtime-type encoder, `toJson()`, then `toString()`. Recursively redact only configured map keys. Apply regex redactors to the final string. Catch faulty encoders and `toJson()` implementations and fall back without throwing into business code.

**Step 4: Write failing caller and formatter tests**

Tests must prove:

- package-internal frames are skipped;
- `CallerLocation` contains basename and positive source line when resolvable;
- Tag omission produces no empty brackets;
- Tag hiding ignores a supplied Tag;
- local/UTC and custom clock formatting are deterministic;
- session and sequence fields are optional;
- every physical pretty-JSON line repeats the metadata prefix;
- file output contains no ANSI bytes;
- console colors map distinctly by level when enabled;
- error and stack trace are appended without losing the primary message.

Example assertion:

```dart
expect(
  formatted,
  '2026-07-15 14:32:08.126 [INFO] sample.dart:87 | ready',
);
```

**Step 5: Verify RED**

Run:

```bash
flutter test test/format/caller_resolver_test.dart test/format/log_formatter_test.dart
```

Expected: FAIL because caller and formatter implementations are absent.

**Step 6: Implement minimal caller and formatter behavior**

`LogEntry` is immutable and includes timestamp, level, message payload, optional Tag/error/stack/fields, caller, session ID, and sequence. `LogFormatter` accepts a sink-specific formatting mode so console and file JSON/color settings remain independent. Use `intl` for approved patterns and `package:path/path.dart` for basenames.

For multiline values, split on line endings and prepend the same metadata prefix to every physical line. Normalize written line endings to `\n`.

**Step 7: Verify all format tests and commit**

Run:

```bash
dart format lib test
flutter analyze
flutter test test/format
flutter test
```

Expected: PASS.

Commit:

```bash
git add lib test
git commit -m "feat: format structured VLog entries"
```

### Task 3: Implement cross-platform directory resolution and file naming

**Files:**
- Create: `lib/src/model/log_file_info.dart`
- Create: `lib/src/storage/directory_resolver.dart`
- Create: `lib/src/storage/file_name_policy.dart`
- Test: `test/storage/directory_resolver_test.dart`
- Test: `test/storage/file_name_policy_test.dart`

**Step 1: Write failing file naming tests**

Cover:

```dart
test('uses app_log_yyyy-MM-dd.txt by default', () { ... });
test('uses prefix.txt when daily splitting is disabled', () { ... });
test('places size part before the extension', () { ... });
test('escapes custom prefix when matching owned files', () { ... });
test('does not match unrelated files in the same directory', () { ... });
```

Required values:

```text
app_log_2026-07-15.txt
app_log_2026-07-15.1.txt
app_log.txt
app_log.1.txt
```

**Step 2: Write failing directory tests**

Inject a fake `getApplicationSupportDirectory` callback rather than invoking a platform plugin in a unit test. Prove:

- explicit `directoryPath` wins;
- async directory resolver wins over the default platform resolver;
- Android and Windows default to `<support>/logs`;
- the directory is created recursively;
- resolver errors are represented as a typed initialization failure rather than an obscure null error.

**Step 3: Verify RED**

Run:

```bash
flutter test test/storage/directory_resolver_test.dart test/storage/file_name_policy_test.dart
```

Expected: FAIL because policies do not exist.

**Step 4: Implement policies**

`DirectoryResolver` uses `getApplicationSupportDirectory()` in production and accepts the injected callback in tests. `FileNamePolicy` owns both generation and strict matching/parsing. `LogFileInfo` exposes path, name, byte size, modified time, parsed date/part, and `isActive`.

Do not use `Platform.isAndroid` to change semantics; both approved platforms share the support-directory behavior.

**Step 5: Verify GREEN and commit**

Run:

```bash
dart format lib test
flutter analyze
flutter test test/storage
flutter test
```

Expected: PASS.

Commit:

```bash
git add lib test
git commit -m "feat: resolve VLog directories and names"
```

### Task 4: Implement rotating file management and retention

**Files:**
- Create: `lib/src/storage/log_file_manager.dart`
- Test: `test/storage/log_file_manager_test.dart`

**Step 1: Write one failing test per storage behavior**

Use `Directory.systemTemp.createTemp()` and an injected clock. Tests:

```dart
test('creates the default dated file on first write', () async { ... });
test('continues appending to the current non-full part', () async { ... });
test('rotates to a new date after midnight without restart', () async { ... });
test('rotates to the next numbered part before exceeding max size', () async { ... });
test('allows one truncated entry to fit the configured entry bound', () async { ... });
test('deletes owned files older than retentionDays', () async { ... });
test('preserves unrelated and recent files during cleanup', () async { ... });
test('lists owned files newest first and marks the active file', () async { ... });
test('clear removes owned logs but leaves unrelated files', () async { ... });
test('recovers when the active file is externally removed', () async { ... });
```

**Step 2: Run and verify RED**

Run:

```bash
flutter test test/storage/log_file_manager_test.dart
```

Expected: FAIL because `LogFileManager` is missing.

**Step 3: Implement the minimal manager**

The manager must serialize `open/write/flush/close/rotate/cleanup` calls, inspect the date before every entry, and check byte length before append. It must discover the highest valid existing part on initialization. File ownership is determined only by `FileNamePolicy`.

Expose a broadcast write notification containing file path, start/end byte offsets, and written text for same-process live viewing.

**Step 4: Verify GREEN under repeated runs**

Run:

```bash
flutter test test/storage/log_file_manager_test.dart
flutter test test/storage/log_file_manager_test.dart --test-randomize-ordering-seed=random
flutter test
```

Expected: PASS without leaked files or timers.

**Step 5: Commit**

```bash
git add lib test
git commit -m "feat: rotate and retain VLog files"
```

### Task 5: Implement sinks, bounded serial queue, and controller lifecycle

**Files:**
- Create: `lib/src/sink/log_sink.dart`
- Create: `lib/src/sink/console_sink.dart`
- Create: `lib/src/sink/file_sink.dart`
- Create: `lib/src/core/log_queue.dart`
- Create: `lib/src/core/log_controller.dart`
- Test: `test/sink/console_sink_test.dart`
- Test: `test/core/log_queue_test.dart`
- Test: `test/core/log_controller_test.dart`

**Step 1: Write failing sink tests**

Inject a console printer and temporary file manager. Prove:

- disabled sinks do nothing;
- per-sink minimum levels are honored;
- console formatting may be pretty/colored while file formatting is compact/plain;
- failure of one sink does not prevent the other sink;
- internal errors go only to the injected internal reporter and do not recurse.

**Step 2: Verify sink tests RED**

Run:

```bash
flutter test test/sink/console_sink_test.dart
```

Expected: FAIL because sinks are absent.

**Step 3: Implement sink contracts and minimum sinks**

Use:

```dart
abstract interface class LogSink {
  Future<void> write(LogEntry entry);
  Future<void> flush();
  Future<void> close();
}
```

The controller must catch each sink failure independently.

**Step 4: Write failing queue tests**

Tests must prove:

- asynchronous operations execute in enqueue order;
- `flush` completes only after all earlier writes complete;
- the capacity is bounded;
- default overflow drops the lowest-level queued entry first;
- `error/fatal` displace a lower level when possible;
- a synthetic warning reports the count of dropped entries once capacity is available;
- close drains once, cancels the flush timer, and rejects later file writes safely.

**Step 5: Verify queue tests RED**

Run:

```bash
flutter test test/core/log_queue_test.dart
```

Expected: FAIL because the queue is missing.

**Step 6: Implement the queue**

Use a `Queue<PendingLog>` and one drain future. Never create a future chain that grows forever. Store at most `queueCapacity` pending items. Keep drop accounting separate from user entries.

**Step 7: Write failing controller lifecycle tests**

Prove:

- pre-initialization calls are buffered up to capacity;
- `init` starts one ordered writer and writes a session marker;
- repeated `init` flushes and closes the old controller before replacement;
- sequence starts at one per session;
- `flushOnLevel` forces file flush for error/fatal;
- max entry bytes truncates at a valid UTF-8 boundary and marks original byte length;
- `flush` and `close` are idempotent.

**Step 8: Implement controller lifecycle**

The controller owns configuration, session ID, sequence, serializer, sinks, queue, periodic flush timer, and file write stream. It captures the timestamp and caller at log-call time so queued processing does not report worker frames.

**Step 9: Verify and commit**

Run:

```bash
dart format lib test
flutter analyze
flutter test test/sink test/core
flutter test
```

Expected: PASS and no pending timers.

Commit:

```bash
git add lib test
git commit -m "feat: queue and persist VLog events"
```

### Task 6: Implement the `VLog` facade and configurable automatic error capture

**Files:**
- Create: `lib/src/core/vlog.dart`
- Create: `lib/src/error/error_capture.dart`
- Modify: `lib/flutter_log_file.dart`
- Test: `test/core/vlog_test.dart`
- Test: `test/error/error_capture_test.dart`

**Step 1: Write failing facade tests**

Use an injected controller factory/test sink and cover:

```dart
VLog.v(message, tag: optionalTag, fields: fields);
VLog.d(...);
VLog.i(...);
VLog.w(...);
VLog.e(message, error: error, stackTrace: stackTrace);
VLog.f(...);
```

Prove Tag is optional, correct level is used, caller stack is captured at the public call site, encoders can be registered/unregistered, and management methods delegate correctly.

**Step 2: Verify RED**

Run:

```bash
flutter test test/core/vlog_test.dart
```

Expected: FAIL because `VLog` does not exist.

**Step 3: Implement the facade**

All level methods return `void`. Lifecycle and management methods return `Future`. Export `VLog`, configurations, models, and viewer pages from `flutter_log_file.dart`; keep implementation helpers private.

**Step 4: Write failing automatic capture tests**

Using saved/restored callbacks in `tearDown`, prove:

- capture is not installed by default;
- enabled Flutter capture logs details then invokes the previous handler;
- enabled platform capture logs then preserves the previous handler result;
- uninstall restores exact previous callbacks;
- `runGuarded` logs zone errors and invokes the caller's error callback;
- installation is idempotent and close removes hooks.

**Step 5: Verify RED**

Run:

```bash
flutter test test/error/error_capture_test.dart
```

Expected: FAIL because capture support is missing.

**Step 6: Implement capture without swallowing errors**

When no previous Flutter handler exists, call `FlutterError.presentError`. When no previous platform handler exists, return `false`. Never route capture failures back through `VLog` recursively.

**Step 7: Verify and commit**

Run:

```bash
dart format lib test
flutter analyze
flutter test test/core/vlog_test.dart test/error/error_capture_test.dart
flutter test
```

Expected: PASS.

Commit:

```bash
git add lib test
git commit -m "feat: expose VLog API and error capture"
```

### Task 7: Implement bounded byte-range file reading and line parsing

**Files:**
- Create: `lib/src/viewer/log_line_parser.dart`
- Create: `lib/src/viewer/file_chunk_reader.dart`
- Create: `lib/src/viewer/log_file_controller.dart`
- Test: `test/viewer/log_line_parser_test.dart`
- Test: `test/viewer/file_chunk_reader_test.dart`
- Test: `test/viewer/log_file_controller_test.dart`

**Step 1: Write failing parser tests**

Prove parser extraction for timestamp, level, optional Tag, caller, session, sequence, message, fields, multiline continuation, malformed external lines, and both LF/CRLF.

**Step 2: Write failing chunk reader tests**

Create real temporary UTF-8 files and cover:

- tail begins on a whole line and returns end offset;
- read-before and read-after have no duplicate or missing lines;
- multibyte Chinese and emoji crossing a requested byte boundary decode correctly;
- CRLF is normalized without leaving `\r`;
- a line larger than the nominal chunk expands up to the safe maximum;
- a concurrently appended final line becomes visible on refresh;
- truncation invalidates stale offsets safely.

**Step 3: Verify RED**

Run:

```bash
flutter test test/viewer/log_line_parser_test.dart test/viewer/file_chunk_reader_test.dart
```

Expected: FAIL because viewer readers are missing.

**Step 4: Implement parser and byte reader**

Newline byte `0x0A` is the boundary authority. Align arbitrary start positions to the next complete line, and expand backward when finding a previous chunk. Decode only complete byte ranges. Return records containing text and absolute start/end offsets.

**Step 5: Write failing bounded controller tests**

Prove:

- initial open contains only the configured tail;
- requesting older/newer pages updates the window;
- retained decoded byte count does not exceed the configured memory budget, except for one permitted oversized line;
- eviction occurs opposite the user's navigation direction;
- jump-to-offset loads surrounding context;
- active file notifications append only when live follow is enabled;
- pause prevents visual appends without losing the ability to refresh.

**Step 6: Implement bounded controller**

The controller exposes immutable view state through `ChangeNotifier` or `ValueNotifier`, owns only a bounded list of decoded lines, and closes subscriptions/files in `dispose`.

**Step 7: Verify and commit**

Run:

```bash
dart format lib test
flutter analyze
flutter test test/viewer/log_line_parser_test.dart test/viewer/file_chunk_reader_test.dart test/viewer/log_file_controller_test.dart
flutter test
```

Expected: PASS.

Commit:

```bash
git add lib test
git commit -m "feat: lazily read large VLog files"
```

### Task 8: Implement cancellable isolate search and filtering

**Files:**
- Create: `lib/src/viewer/log_search_service.dart`
- Test: `test/viewer/log_search_service_test.dart`

**Step 1: Write failing search tests**

Use a generated multi-megabyte temporary file. Cover:

- plain keyword matching;
- optional case sensitivity;
- regular expressions and invalid-regex validation;
- level, Tag, and time range filters;
- result summaries contain absolute byte offsets but not the full file;
- progress is monotonic from zero to one;
- cancellation terminates the worker and closes streams;
- maximum result count stops scanning with a truncated flag;
- clicking a result offset can be consumed by `LogFileController.jumpToOffset`.

**Step 2: Verify RED**

Run:

```bash
flutter test test/viewer/log_search_service_test.dart
```

Expected: FAIL because search service is missing.

**Step 3: Implement an explicit isolate worker**

Use `Isolate.spawn` with sendable request objects and a `ReceivePort` for progress/results/completion. Read `RandomAccessFile` in bounded byte blocks. Return `LogSearchTask` with a results/progress stream, completion future, and `cancel()` that kills the isolate and closes resources.

Do not use a global isolate or retain entire file contents/results. Limit snippet length and result count.

**Step 4: Verify and commit**

Run:

```bash
dart format lib test
flutter analyze
flutter test test/viewer/log_search_service_test.dart
flutter test
```

Expected: PASS with no hanging isolate after cancellation.

Commit:

```bash
git add lib test
git commit -m "feat: search VLog files in an isolate"
```

### Task 9: Build the log file list and lazy viewer pages

**Files:**
- Create: `lib/src/viewer/log_viewer_page.dart`
- Create: `lib/src/viewer/log_file_page.dart`
- Modify: `lib/flutter_log_file.dart`
- Test: `test/viewer/log_viewer_page_test.dart`
- Test: `test/viewer/log_file_page_test.dart`

**Step 1: Write failing file-list widget tests**

Inject a fake log repository. Prove:

- files render newest first with name, size, time, and active marker;
- loading, empty, and recoverable error states are visible;
- tap opens the selected file page;
- selection supports single/batch delete with confirmation;
- cleanup and refresh invoke repository methods;
- share/export passes only explicitly selected paths to an injected share adapter;
- copy-path provides feedback.

**Step 2: Verify RED**

Run:

```bash
flutter test test/viewer/log_viewer_page_test.dart
```

Expected: FAIL because `VLogViewerPage` is missing.

**Step 3: Implement file list UI**

Use Material widgets and constructor injection for testability. Production defaults delegate to `VLog` and `share_plus`. Do not request broad storage permissions.

**Step 4: Write failing file-viewer widget tests**

Prove:

- only rows supplied by the bounded controller are built;
- scrolling near the top/bottom requests the correct adjacent block;
- levels use distinct accessible colors plus text labels;
- wrap/horizontal mode, font size, jump-to-start/end, live follow/pause work;
- keyword/regex/filter controls start and cancel search;
- selecting a search result jumps to its byte offset and highlights it;
- previous/next match navigation works;
- line/context copy strips JSON metadata prefixes when requested;
- JSON and stack sections expand/collapse;
- controller and search task are disposed on navigation pop.

**Step 5: Verify RED**

Run:

```bash
flutter test test/viewer/log_file_page_test.dart
```

Expected: FAIL because the file page is missing.

**Step 6: Implement the viewer UI**

Use `ListView.builder` with stable keys based on byte offsets. Debounce search input. Keep search results in a separate bounded result list. Show progress/cancel affordances for long searches. Parsing failures display as plain text rather than crashing the page.

**Step 7: Verify widget suite and commit**

Run:

```bash
dart format lib test
flutter analyze
flutter test test/viewer
flutter test
```

Expected: PASS with no overflow or pending timer exceptions.

Commit:

```bash
git add lib test
git commit -m "feat: add lazy VLog viewer pages"
```

### Task 10: Complete documentation, package quality checks, and non-device verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `pubspec.yaml`
- Create: `example/README.md`
- Test: all existing tests

**Step 1: Write documentation acceptance checklist**

Before editing README, create a temporary checklist in the task notes covering:

- initialization and all `VLog` levels;
- optional Tag examples;
- Android/Windows default paths;
- custom directory;
- daily/non-daily naming and prefix;
- 30-day/50 MB configurable defaults;
- compact/pretty JSON;
- `toJson` and custom encoder examples;
- optional error capture and `runGuarded`;
- optional redaction with empty defaults clearly stated;
- opening `VLogViewerPage`;
- flush/close and export/cleanup;
- performance and multi-process limitations.

**Step 2: Update README and changelog**

Document the real final API only. Do not create a deployable example application because the requested deliverable is the package, not Package + Example App. `example/README.md` may contain copyable integration snippets without a runnable phone target.

**Step 3: Run final static and automated verification**

Apply `@superpowers:verification-before-completion`, then run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter pub get
flutter analyze
flutter test --test-randomize-ordering-seed=random
flutter pub publish --dry-run
git status --short
```

Expected:

- formatting exits zero;
- dependency resolution succeeds;
- analyzer reports no issues;
- all tests pass in randomized order;
- publish dry run reports no blocking package errors;
- only intentional documentation/metadata changes remain before commit.

Do **not** run Android deployment commands. Windows compilation cannot be performed from macOS; document that limitation while retaining unit/widget coverage for Windows path semantics.

**Step 4: Inspect package surface and size**

Run:

```bash
dart doc --dry-run
git diff --check
```

Expected: public APIs are documented sufficiently for doc generation and no whitespace errors exist.

**Step 5: Commit final documentation**

```bash
git add README.md CHANGELOG.md pubspec.yaml example/README.md
git commit -m "docs: document VLog integration"
```

**Step 6: Record final evidence**

Capture the exact analyzer, test, and publish dry-run summaries in the completion response, explicitly state that no app was installed on the connected phone, and list any platform verification that must later be performed on a Windows host.
