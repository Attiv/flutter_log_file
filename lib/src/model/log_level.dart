/// Severity of a VLog entry, ordered from least to most severe.
enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  fatal;

  /// Short label used by the text log format.
  String get label => switch (this) {
        LogLevel.verbose => 'VERBOSE',
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARN',
        LogLevel.error => 'ERROR',
        LogLevel.fatal => 'FATAL',
      };

  /// Whether this level is at least [minimum].
  bool isAtLeast(LogLevel minimum) => index >= minimum.index;
}

/// Strategy used when the asynchronous log queue is full.
enum LogQueueOverflowPolicy {
  /// Prefer keeping severe records by evicting the least severe queued record.
  dropLowestLevel,

  /// Keep existing records and discard the newest record.
  dropNewest,
}

/// Time zone used when formatting log timestamps and daily file names.
enum LogTimeZone { local, utc }
