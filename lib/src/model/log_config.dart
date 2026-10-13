import 'dart:collection';

import 'log_level.dart';
import 'log_redactor.dart';

/// Resolves a custom log directory asynchronously.
typedef LogDirectoryResolver = Future<String> Function();

/// Configuration for [VLog].
///
/// File and console sinks can be enabled and filtered independently. The
/// asynchronous queue is bounded by both [queueCapacity] and
/// [queueByteCapacity]. Sensitive data processing is opt-in: [redactedKeys]
/// and [redactors] are empty unless explicitly supplied.
final class LogConfig {
  LogConfig({
    this.consoleEnabled = true,
    this.fileEnabled = true,
    this.minimumLevel = LogLevel.verbose,
    this.consoleMinimumLevel,
    this.fileMinimumLevel,
    this.showTag = true,
    this.showCaller = true,
    this.showSessionId = false,
    this.showSequence = false,
    this.showFields = true,
    this.prettyJson = false,
    this.consolePrettyJson,
    this.filePrettyJson,
    this.consoleUseColors = true,
    this.directoryPath,
    this.directoryResolver,
    this.useExternalStorageOnAndroid = true,
    this.filePrefix = 'app_log',
    String? fileNamePattern,
    this.fileExtension = 'txt',
    this.splitByDay = true,
    this.fileDatePattern = 'yyyy-MM-dd',
    this.timestampPattern = 'yyyy-MM-dd HH:mm:ss.SSS',
    this.timeZone = LogTimeZone.local,
    this.retentionDays = 30,
    this.maxFileSizeBytes = 50 * 1024 * 1024,
    this.queueCapacity = 10000,
    this.queueByteCapacity = 8 * 1024 * 1024,
    this.overflowPolicy = LogQueueOverflowPolicy.dropLowestLevel,
    this.flushInterval = const Duration(seconds: 1),
    this.flushOnLevel = LogLevel.error,
    this.maxEntryBytes = 256 * 1024,
    this.captureFlutterErrors = false,
    this.capturePlatformErrors = false,
    Set<String> redactedKeys = const <String>{},
    List<LogRedactor> redactors = const <LogRedactor>[],
  })  : fileNamePattern =
            fileNamePattern ?? (splitByDay ? '{prefix}_{date}' : '{prefix}'),
        redactedKeys = UnmodifiableSetView<String>(
          redactedKeys.map((key) => key.toLowerCase()).toSet(),
        ),
        redactors = UnmodifiableListView<LogRedactor>(redactors) {
    if (retentionDays < 0) {
      throw ArgumentError.value(retentionDays, 'retentionDays', 'must be >= 0');
    }
    if (maxFileSizeBytes <= 0) {
      throw ArgumentError.value(
        maxFileSizeBytes,
        'maxFileSizeBytes',
        'must be > 0',
      );
    }
    if (queueCapacity <= 0) {
      throw ArgumentError.value(queueCapacity, 'queueCapacity', 'must be > 0');
    }
    if (queueByteCapacity <= 0) {
      throw ArgumentError.value(
        queueByteCapacity,
        'queueByteCapacity',
        'must be > 0',
      );
    }
    if (maxEntryBytes <= 0) {
      throw ArgumentError.value(maxEntryBytes, 'maxEntryBytes', 'must be > 0');
    }
    if (flushInterval.isNegative) {
      throw ArgumentError.value(
        flushInterval,
        'flushInterval',
        'must not be negative',
      );
    }
    if (filePrefix.trim().isEmpty) {
      throw ArgumentError.value(filePrefix, 'filePrefix', 'must not be empty');
    }
    final patternWithoutTokens = this
        .fileNamePattern
        .replaceAll('{prefix}', '')
        .replaceAll('{date}', '');
    final dateTokenCount = RegExp(
      r'\{date\}',
    ).allMatches(this.fileNamePattern).length;
    if (this.fileNamePattern.trim().isEmpty ||
        this.fileNamePattern.contains('/') ||
        this.fileNamePattern.contains(r'\') ||
        patternWithoutTokens.contains('{') ||
        patternWithoutTokens.contains('}') ||
        (splitByDay && dateTokenCount != 1) ||
        (!splitByDay && dateTokenCount != 0)) {
      throw ArgumentError.value(
        this.fileNamePattern,
        'fileNamePattern',
        splitByDay
            ? 'must be a filename stem containing exactly one {date} token'
            : 'must be a filename stem without a {date} token',
      );
    }
    if (fileExtension.trim().isEmpty) {
      throw ArgumentError.value(
        fileExtension,
        'fileExtension',
        'must not be empty',
      );
    }
    if (directoryPath != null && directoryResolver != null) {
      throw ArgumentError(
        'directoryPath and directoryResolver cannot both be supplied',
      );
    }
  }

  final bool consoleEnabled;
  final bool fileEnabled;
  final LogLevel minimumLevel;
  final LogLevel? consoleMinimumLevel;
  final LogLevel? fileMinimumLevel;
  final bool showTag;
  final bool showCaller;
  final bool showSessionId;
  final bool showSequence;
  final bool showFields;
  final bool prettyJson;
  final bool? consolePrettyJson;
  final bool? filePrettyJson;
  final bool consoleUseColors;
  final String? directoryPath;
  final LogDirectoryResolver? directoryResolver;

  /// Use `Android/data/<package>/files` when no custom directory is supplied.
  /// Owned logs from the previous Support/logs default are migrated on startup.
  /// Set false to retain the internal Support/logs location on Android.
  final bool useExternalStorageOnAndroid;
  final String filePrefix;

  /// Filename stem template using `{prefix}` and, for daily logs, `{date}`.
  final String fileNamePattern;
  final String fileExtension;
  final bool splitByDay;
  final String fileDatePattern;
  final String timestampPattern;
  final LogTimeZone timeZone;
  final int retentionDays;
  final int maxFileSizeBytes;
  final int queueCapacity;
  final int queueByteCapacity;
  final LogQueueOverflowPolicy overflowPolicy;
  final Duration flushInterval;
  final LogLevel flushOnLevel;
  final int maxEntryBytes;
  final bool captureFlutterErrors;
  final bool capturePlatformErrors;
  final Set<String> redactedKeys;
  final List<LogRedactor> redactors;

  LogLevel get effectiveConsoleMinimumLevel =>
      consoleMinimumLevel ?? minimumLevel;

  LogLevel get effectiveFileMinimumLevel => fileMinimumLevel ?? minimumLevel;

  bool get effectiveConsolePrettyJson => consolePrettyJson ?? prettyJson;

  bool get effectiveFilePrettyJson => filePrettyJson ?? prettyJson;
}
