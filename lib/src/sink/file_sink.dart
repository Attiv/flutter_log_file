import 'dart:async';

import '../format/log_formatter.dart';
import '../format/message_serializer.dart';
import '../model/log_config.dart';
import '../model/log_entry.dart';
import '../storage/log_file_manager.dart';
import 'log_sink.dart';

typedef RetryDelay = Future<void> Function(Duration duration);

/// Writes file-specific plain text and retries transient file failures.
final class FileSink implements LogSink {
  FileSink(
    this._config,
    this.manager, {
    ObjectEncoderRegistry? registry,
    RetryDelay delay = Future<void>.delayed,
    this.maximumAttempts = 3,
  })  : assert(maximumAttempts > 0),
        _formatter = LogFormatter(_config, registry: registry),
        _delay = delay;

  final LogConfig _config;
  final LogFileManager manager;
  final LogFormatter _formatter;
  final RetryDelay _delay;
  final int maximumAttempts;

  @override
  Future<void> write(LogEntry entry) async {
    if (!_config.fileEnabled ||
        !entry.level.isAtLeast(_config.effectiveFileMinimumLevel)) {
      return;
    }
    final text = _formatter.format(entry, target: LogOutputTarget.file);
    Object? error;
    StackTrace? stackTrace;
    for (var attempt = 0; attempt < maximumAttempts; attempt += 1) {
      try {
        await manager.write(text);
        return;
      } catch (caught, caughtStack) {
        error = caught;
        stackTrace = caughtStack;
        if (attempt + 1 < maximumAttempts) {
          await _delay(Duration(milliseconds: 50 * (1 << attempt)));
        }
      }
    }
    Error.throwWithStackTrace(error!, stackTrace!);
  }

  @override
  Future<void> flush() => manager.flush();

  @override
  Future<void> close() => manager.close();
}
