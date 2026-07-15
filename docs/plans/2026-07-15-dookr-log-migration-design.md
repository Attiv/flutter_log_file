# Dookr VLog Migration Design

**Date:** 2026-07-15

## Goal

Extend `flutter_log_file` with safe configurable file-name templates, then
replace the custom logger and inline log reader in `/Users/mac/projects/dookr-apk`
while preserving its existing log directory and file names.

## File naming

`LogConfig` gains a `fileNamePattern` option. The default remains
`{prefix}_{date}`, preserving the package's existing names. Supported tokens
are `{prefix}` and `{date}`. The pattern represents the filename stem; the
configured extension and automatic numeric rotation suffix remain managed by
the package.

For Dookr the configuration is:

```dart
LogConfig(
  directoryPath: fileDownloadProvider.logsStorage?.path,
  fileNamePattern: '{date}-logFile',
  fileDatePattern: 'yyyyMMdd',
)
```

This produces:

```text
20260715-logFile.txt
20260715-logFile.1.txt
```

The package validates that rendered stems are non-empty filenames rather than
paths. File matching, date parsing, rotation, retention, listing, deletion,
sharing, and the viewer all continue to use the same `FileNamePolicy`.

## Dookr logging architecture

Dookr will initialize `VLog` after `FileDownloadProvider`, because that service
resolves the existing external `logs` directory. The old `Logger` service,
buffer, timer, cleanup, locking, and file writer will be removed. Business
callers will use `VLog.i`, `VLog.w`, and `VLog.e` directly so source filename
and line-number metadata point at the real call site.

The existing Flutter and platform error handlers remain application-owned and
log through `VLog`. The platform handler continues to return `true`, preserving
current application behavior. Package automatic capture remains disabled to
avoid duplicate entries.

## Option Page

The existing device status and operational controls remain available:

- copy diagnostics;
- refresh access codes;
- reconnect MQTT;
- send diagnostics.

The custom file discovery, reverse chunk reader, loaded-line filtering, and
inline log list are removed. The page instead opens the package's
`VLogViewerPage`, which provides bounded-memory file browsing, search,
filtering, copy, share, and deletion.

## Compatibility

Dookr updates its Dart constraint to `>=3.4.0 <4.0.0`, adds a Flutter 3.22
floor, upgrades `intl` to `^0.20.2`, and consumes `flutter_log_file ^0.1.1`.
Its current Flutter 3.32/Dart 3.8 toolchain already satisfies these bounds.

The library version becomes `0.1.1`. Existing consumers receive the unchanged
default file-name behavior unless they explicitly configure
`fileNamePattern`.

## Verification

- Add red/green unit tests for default and Dookr-compatible names, matching,
  date parsing, and rotated parts.
- Keep the complete package test suite green.
- Add Dookr tests for logging configuration and opening the package viewer.
- Run formatting, analysis, and tests in both repositories.
- Build a Dookr Android debug APK without deploying it.
- Run package publication dry-run, publish `0.1.1`, and verify it through the
  pub.dev package API.
