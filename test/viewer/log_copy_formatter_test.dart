import 'package:flutter_log_file/src/viewer/log_copy_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes repeated metadata prefixes from pretty JSON lines', () {
    final result = const LogCopyFormatter().payloadOnly([
      '2026-07-15 10:00:00.000 [INFO] main.dart:1 | {',
      '2026-07-15 10:00:00.000 [INFO] main.dart:1 |   "ok": true',
      '2026-07-15 10:00:00.000 [INFO] main.dart:1 | }',
    ]);

    expect(result, '{\n  "ok": true\n}');
  });
}
