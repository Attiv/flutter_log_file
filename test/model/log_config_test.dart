import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogConfig', () {
    test('uses the approved file and privacy defaults', () {
      final config = LogConfig();

      expect(config.consoleEnabled, isTrue);
      expect(config.fileEnabled, isTrue);
      expect(config.showTag, isTrue);
      expect(config.prettyJson, isFalse);
      expect(config.filePrefix, 'app_log');
      expect(config.fileNamePattern, '{prefix}_{date}');
      expect(config.fileExtension, 'txt');
      expect(config.splitByDay, isTrue);
      expect(config.retentionDays, 30);
      expect(config.maxFileSizeBytes, 50 * 1024 * 1024);
      expect(config.queueByteCapacity, 8 * 1024 * 1024);
      expect(config.captureFlutterErrors, isFalse);
      expect(config.capturePlatformErrors, isFalse);
      expect(config.redactedKeys, isEmpty);
      expect(config.redactors, isEmpty);
    });

    test(
      'accepts optional tag and platform-independent directory override',
      () {
        final config = LogConfig(
          showTag: false,
          directoryPath: r'C:\temp\vlog',
        );

        expect(config.showTag, isFalse);
        expect(config.directoryPath, r'C:\temp\vlog');
      },
    );

    test('rejects invalid rotation and queue values', () {
      expect(() => LogConfig(retentionDays: -1), throwsArgumentError);
      expect(() => LogConfig(maxFileSizeBytes: 0), throwsArgumentError);
      expect(() => LogConfig(queueCapacity: 0), throwsArgumentError);
      expect(() => LogConfig(queueByteCapacity: 0), throwsArgumentError);
    });

    test('validates filename templates against daily splitting', () {
      expect(
        LogConfig(splitByDay: false).fileNamePattern,
        '{prefix}',
      );
      expect(
        () => LogConfig(fileNamePattern: ''),
        throwsArgumentError,
      );
      expect(
        () => LogConfig(fileNamePattern: 'logs/{date}'),
        throwsArgumentError,
      );
      expect(
        () => LogConfig(fileNamePattern: '{prefix}'),
        throwsArgumentError,
      );
      expect(
        () => LogConfig(fileNamePattern: '{date}-{date}'),
        throwsArgumentError,
      );
      expect(
        () => LogConfig(
          splitByDay: false,
          fileNamePattern: '{prefix}_{date}',
        ),
        throwsArgumentError,
      );
      expect(
        () => LogConfig(fileNamePattern: '{date}-{unknown}'),
        throwsArgumentError,
      );
    });

    test('uses empty sensitive-data configuration by default', () {
      final config = LogConfig();

      expect(config.redactedKeys, const <String>{});
      expect(config.redactors, const <LogRedactor>[]);
    });
  });

  test('viewer defaults keep decoded memory bounded', () {
    const config = VLogViewerConfig();

    expect(config.chunkSizeBytes, greaterThan(0));
    expect(config.memoryBudgetBytes, 4 * 1024 * 1024);
    expect(config.initialTailLines, greaterThan(0));
  });
}
