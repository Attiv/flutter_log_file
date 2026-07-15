import 'package:flutter/foundation.dart';

import '../format/log_formatter.dart';
import '../format/message_serializer.dart';
import '../model/log_config.dart';
import '../model/log_entry.dart';
import 'log_sink.dart';

typedef ConsolePrinter = void Function(String line);

/// Writes formatted events to the running process terminal/logcat stream.
final class ConsoleSink implements LogSink {
  ConsoleSink(
    this._config, {
    ConsolePrinter? printer,
    ObjectEncoderRegistry? registry,
  })  : _printer = printer ?? debugPrint,
        _formatter = LogFormatter(_config, registry: registry);

  final LogConfig _config;
  final ConsolePrinter _printer;
  final LogFormatter _formatter;

  @override
  Future<void> write(LogEntry entry) async {
    if (!_config.consoleEnabled ||
        !entry.level.isAtLeast(_config.effectiveConsoleMinimumLevel)) {
      return;
    }
    _printer(_formatter.format(entry, target: LogOutputTarget.console));
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
