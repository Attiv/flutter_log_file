import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/format/caller_resolver.dart';
import 'package:flutter_log_file/src/format/log_formatter.dart';
import 'package:flutter_log_file/src/model/log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry entry({
  Object? message = 'ready',
  String? tag,
  Object? error,
  StackTrace? stackTrace,
  Map<String, Object?> fields = const {},
}) =>
    LogEntry(
      timestamp: DateTime(2026, 7, 15, 14, 32, 8, 126),
      level: LogLevel.info,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
      caller: const CallerLocation(
        uri: 'package:sample/sample.dart',
        fileName: 'sample.dart',
        line: 87,
        column: 2,
      ),
      sessionId: '7F3A',
      sequence: 1842,
    );

void main() {
  test('formats the required metadata and optional tag', () {
    final formatter = LogFormatter(LogConfig(consoleUseColors: false));

    expect(
      formatter.format(entry(), target: LogOutputTarget.file),
      '2026-07-15 14:32:08.126 [INFO] sample.dart:87 | ready',
    );
    expect(
      formatter.format(entry(tag: 'Network'), target: LogOutputTarget.file),
      '2026-07-15 14:32:08.126 [INFO] [Network] sample.dart:87 | ready',
    );
  });

  test('hides a supplied tag when showTag is false', () {
    final formatter = LogFormatter(
      LogConfig(showTag: false, consoleUseColors: false),
    );

    expect(
      formatter.format(entry(tag: 'Network'), target: LogOutputTarget.file),
      isNot(contains('Network')),
    );
  });

  test('shows session sequence and fields only when configured', () {
    final formatter = LogFormatter(
      LogConfig(
        showSessionId: true,
        showSequence: true,
        consoleUseColors: false,
      ),
    );

    final result = formatter.format(
      entry(fields: {'requestId': 'R-1'}),
      target: LogOutputTarget.file,
    );

    expect(result, contains('[S:7F3A]'));
    expect(result, contains('[#1842]'));
    expect(result, contains('fields={"requestId":"R-1"}'));
  });

  test('repeats metadata for every pretty JSON physical line', () {
    final formatter = LogFormatter(LogConfig(filePrettyJson: true));

    final lines = formatter
        .format(
          entry(message: {
            'items': [1, 2],
          }),
          target: LogOutputTarget.file,
        )
        .split('\n');

    expect(lines.length, greaterThan(2));
    for (final line in lines) {
      expect(line, startsWith('2026-07-15 14:32:08.126 [INFO]'));
      expect(line, contains('sample.dart:87 |'));
    }
  });

  test('file output never contains ANSI control bytes', () {
    final formatter = LogFormatter(LogConfig(consoleUseColors: true));

    expect(
      formatter.format(entry(), target: LogOutputTarget.file),
      isNot(contains('\x1B[')),
    );
    expect(
      formatter.format(entry(), target: LogOutputTarget.console),
      contains('\x1B['),
    );
  });

  test('appends error and stack trace with a prefix on every line', () {
    final formatter = LogFormatter(LogConfig(consoleUseColors: false));

    final result = formatter.format(
      entry(
        error: StateError('failed'),
        stackTrace: StackTrace.fromString('first\nsecond'),
      ),
      target: LogOutputTarget.file,
    );

    expect(result, contains('Bad state: failed'));
    expect(result.split('\n'), hasLength(4));
    for (final line in result.split('\n')) {
      expect(line, contains('sample.dart:87 |'));
    }
  });
}
