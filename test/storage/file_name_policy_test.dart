import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/storage/file_name_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 7, 15, 23, 59);

  test('uses app_log_yyyy-MM-dd.txt by default', () {
    final policy = FileNamePolicy(LogConfig());

    expect(policy.fileName(day), 'app_log_2026-07-15.txt');
  });

  test('uses prefix.txt when daily splitting is disabled', () {
    final policy = FileNamePolicy(
      LogConfig(splitByDay: false, filePrefix: 'device'),
    );

    expect(policy.fileName(day), 'device.txt');
  });

  test('places size part before the extension', () {
    final daily = FileNamePolicy(LogConfig());
    final fixed = FileNamePolicy(LogConfig(splitByDay: false));

    expect(daily.fileName(day, part: 1), 'app_log_2026-07-15.1.txt');
    expect(fixed.fileName(day, part: 2), 'app_log.2.txt');
  });

  test('escapes custom prefix when matching owned files', () {
    final policy = FileNamePolicy(LogConfig(filePrefix: 'app.log+[prod]'));

    final owned = policy.fileName(day);
    expect(policy.parse(owned), isNotNull);
    expect(policy.matches('appXlog+[prod]_2026-07-15.txt'), isFalse);
  });

  test('does not match unrelated or malformed files', () {
    final policy = FileNamePolicy(LogConfig());

    expect(policy.matches('notes.txt'), isFalse);
    expect(policy.matches('app_log_invalid.txt'), isFalse);
    expect(policy.matches('app_log_2026-02-31.txt'), isFalse);
  });

  test('parses date and numeric part', () {
    final parsed = FileNamePolicy(
      LogConfig(),
    ).parse('app_log_2026-07-15.12.txt');

    expect(parsed?.date, DateTime(2026, 7, 15));
    expect(parsed?.part, 12);
  });

  test('supports the legacy Dookr filename and rotated parts', () {
    final policy = FileNamePolicy(
      LogConfig(
        fileNamePattern: '{date}-logFile',
        fileDatePattern: 'yyyyMMdd',
      ),
    );

    expect(policy.fileName(day), '20260715-logFile.txt');
    expect(policy.fileName(day, part: 1), '20260715-logFile.1.txt');

    final parsed = policy.parse('20260715-logFile.12.txt');
    expect(parsed?.date, DateTime(2026, 7, 15));
    expect(parsed?.part, 12);
    expect(policy.matches('20260715-other.txt'), isFalse);
    expect(policy.matches('20260231-logFile.txt'), isFalse);
  });
}
