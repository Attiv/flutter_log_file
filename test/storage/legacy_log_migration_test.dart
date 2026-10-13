import 'dart:io';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_log_file/src/storage/directory_resolver.dart';
import 'package:flutter_log_file/src/storage/legacy_log_migration.dart'
    as migration;

Future<String> resolveLogDirectory({
  required Future<Directory?> Function() externalDirectory,
  Future<Directory> Function()? supportDirectory,
}) async =>
    (await DirectoryResolver(
      LogConfig(filePrefix: 'htf_checkin'),
      isAndroid: true,
      getExternalDirectory: externalDirectory,
      getSupportDirectory: supportDirectory ??
          () async => throw StateError('Unexpected internal fallback'),
    ).resolve())
        .path;

Future<void> migrateLegacyLogs(Directory source, Directory destination) =>
    migration.migrateLegacyLogs(
        source, destination, LogConfig(filePrefix: 'htf_checkin'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Directory external;
  late Directory support;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('htf-log-storage-');
    external = Directory(
      '${temporary.path}/Android/data/com.oangle.htf_checkin/files',
    );
    support = Directory('${temporary.path}/internal/files');
  });
  tearDown(() async {
    await VLog.close();
    await temporary.delete(recursive: true);
  });

  test('migration recognizes custom names, extensions and split settings',
      () async {
    final legacy =
        await Directory('${support.path}/logs').create(recursive: true);
    for (final config in [
      LogConfig(
          fileNamePattern: '{date}-logFile',
          fileDatePattern: 'yyyyMMdd',
          fileExtension: 'log'),
      LogConfig(filePrefix: 'device', splitByDay: false),
    ]) {
      final name = config.splitByDay ? '20261013-logFile.log' : 'device.txt';
      final rotated =
          config.splitByDay ? '20261013-logFile.1.log' : 'device.1.txt';
      await external.create(recursive: true);
      await File('${legacy.path}/$name').writeAsString('old');
      await File('${external.path}/$name').writeAsString('current');
      await migration.migrateLegacyLogs(legacy, external, config);
      expect(await File('${external.path}/$rotated').readAsString(), 'old');
      expect(await File('${external.path}/$name').readAsString(), 'current');
      expect(await File('${legacy.path}/$name').exists(), isFalse);
    }
  });

  test('logger writes in external files and migrates existing logs', () async {
    final legacy =
        await Directory('${support.path}/logs').create(recursive: true);
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final name = 'htf_checkin_$day.txt';
    await File('${legacy.path}/$name').writeAsString('Old log entry\n');
    await File('${legacy.path}/settings.json').writeAsString('unrelated');
    await VLog.init(
      LogConfig(
        directoryResolver: () => resolveLogDirectory(
          externalDirectory: () async => external,
          supportDirectory: () async => support,
        ),
        filePrefix: 'htf_checkin',
        consoleEnabled: false,
      ),
    );
    VLog.i('New log entry');
    await VLog.flush();
    expect(VLog.logDirectoryPath, external.path);
    final content = await File('${external.path}/$name').readAsString();
    expect(content, contains('Old log entry'));
    expect(content, contains('New log entry'));
    expect(await File('${legacy.path}/$name').exists(), isFalse);
    expect(await File('${legacy.path}/settings.json').exists(), isTrue);
    expect(await File('${external.path}/settings.json').exists(), isFalse);
  });

  test(
    'migration preserves collisions and retries without duplicate logs',
    () async {
      final legacy =
          await Directory('${support.path}/logs').create(recursive: true);
      await external.create(recursive: true);
      const stem = 'htf_checkin_2026-10-13';
      final old = File('${legacy.path}/$stem.txt');
      await old.writeAsString('old data');
      final timestamp = DateTime(2026, 10, 13, 9);
      await old.setLastModified(timestamp);
      final current = File('${external.path}/$stem.txt');
      await current.writeAsString('new data');
      await migrateLegacyLogs(legacy, external);
      final moved = File('${external.path}/$stem.1.txt');
      expect(await current.readAsString(), 'new data');
      expect(await moved.readAsString(), 'old data');
      expect(await moved.lastModified(), timestamp);
      // Simulate a restart after a copy succeeded but source deletion did not.
      await old.writeAsString('old data');
      await migrateLegacyLogs(legacy, external);
      expect(await old.exists(), isFalse);
      expect(await external.list().length, 2);
    },
  );

  test(
    'unavailable external storage does not silently select internal files',
    () async {
      await expectLater(
        resolveLogDirectory(externalDirectory: () async => null),
        throwsA(isA<LogDirectoryException>()),
      );
    },
  );

  test(
    'failed migration still allows external logging and retains originals',
    () async {
      final legacy =
          await Directory('${support.path}/logs').create(recursive: true);
      final old = File('${legacy.path}/htf_checkin_2026-10-13.txt');
      await old.writeAsString('keep this log');
      await external.create(recursive: true);
      await Directory('${external.path}/htf_checkin_2026-10-13.txt').create();
      expect(
        await resolveLogDirectory(
          externalDirectory: () async => external,
          supportDirectory: () async => support,
        ),
        external.path,
      );
      expect(await old.readAsString(), 'keep this log');
    },
  );
}
