import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/format/caller_resolver.dart';
import 'package:flutter_log_file/src/model/log_entry.dart';
import 'package:flutter_log_file/src/sink/console_sink.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry _entry(LogLevel level) => LogEntry(
      timestamp: DateTime(2026, 7, 15),
      level: level,
      message: {'ok': true},
      caller: const CallerLocation(
        uri: 'package:app/main.dart',
        fileName: 'main.dart',
        line: 10,
        column: 1,
      ),
      sessionId: 'ABCD',
      sequence: 1,
    );

void main() {
  test('disabled console sink writes nothing', () async {
    final lines = <String>[];
    final sink = ConsoleSink(
      LogConfig(consoleEnabled: false),
      printer: lines.add,
    );

    await sink.write(_entry(LogLevel.fatal));

    expect(lines, isEmpty);
  });

  test('honors console minimum level', () async {
    final lines = <String>[];
    final sink = ConsoleSink(
      LogConfig(
        consoleMinimumLevel: LogLevel.warning,
        consoleUseColors: false,
      ),
      printer: lines.add,
    );

    await sink.write(_entry(LogLevel.info));
    await sink.write(_entry(LogLevel.error));

    expect(lines, hasLength(1));
    expect(lines.single, contains('[ERROR]'));
  });

  test('console can pretty print and color independently', () async {
    final lines = <String>[];
    final sink = ConsoleSink(
      LogConfig(consolePrettyJson: true, filePrettyJson: false),
      printer: lines.add,
    );

    await sink.write(_entry(LogLevel.info));

    expect(lines.single, contains('\n'));
    expect(lines.single, contains('\x1B['));
  });
}
