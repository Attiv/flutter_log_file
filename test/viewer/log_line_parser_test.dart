import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/viewer/log_line_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts standard metadata including optional location fields', () {
    final parsed = const LogLineParser().parse(
      '2026-07-15 14:32:08.126 [INFO] [Network] [S:7F3A] [#1842] '
      'api.dart:87 | completed',
    );

    expect(parsed.level, LogLevel.info);
    expect(parsed.tag, 'Network');
    expect(parsed.sessionId, '7F3A');
    expect(parsed.sequence, 1842);
    expect(parsed.caller, 'api.dart:87');
    expect(parsed.message, 'completed');
    expect(parsed.timestamp, DateTime(2026, 7, 15, 14, 32, 8, 126));
  });

  test('parses lines without tag session or sequence', () {
    final parsed = const LogLineParser().parse(
      '2026-07-15 14:32:08.126 [WARN] main.dart:12 | warning',
    );

    expect(parsed.level, LogLevel.warning);
    expect(parsed.tag, isNull);
    expect(parsed.sessionId, isNull);
    expect(parsed.sequence, isNull);
  });

  test('returns a plain record for malformed external lines', () {
    final parsed = const LogLineParser().parse('external unstructured line\r');

    expect(parsed.level, isNull);
    expect(parsed.message, 'external unstructured line');
  });
}
