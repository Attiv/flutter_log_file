import 'dart:convert';
import 'dart:io';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/storage/log_file_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vlog_manager_test_');
    now = DateTime(2026, 7, 15, 23, 59, 59);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  LogFileManager createManager({
    int maxBytes = 1024,
    int retentionDays = 30,
    bool splitByDay = true,
  }) =>
      LogFileManager(
        directory: directory,
        config: LogConfig(
          maxFileSizeBytes: maxBytes,
          retentionDays: retentionDays,
          splitByDay: splitByDay,
        ),
        clock: () => now,
      );

  test('creates the default dated file on first write', () async {
    final manager = createManager();
    await manager.initialize();

    final notification = await manager.write('hello');
    await manager.flush();

    expect(notification.filePath, endsWith('app_log_2026-07-15.txt'));
    expect(
      await File(notification.filePath).readAsString(),
      'hello\n',
    );
    await manager.close();
  });

  test('continues appending to current non-full part', () async {
    final manager = createManager();

    await manager.write('one');
    await manager.write('two');
    await manager.flush();

    final files = await manager.listFiles();
    expect(files, hasLength(1));
    expect(await File(files.single.path).readAsString(), 'one\ntwo\n');
    await manager.close();
  });

  test('rotates to a new date after midnight without restart', () async {
    final manager = createManager();
    await manager.write('before');

    now = DateTime(2026, 7, 16);
    final notification = await manager.write('after');
    await manager.flush();

    expect(notification.filePath, endsWith('app_log_2026-07-16.txt'));
    expect(await manager.listFiles(), hasLength(2));
    await manager.close();
  });

  test('rotates to next part before exceeding max size', () async {
    final manager = createManager(maxBytes: utf8.encode('first\n').length);
    await manager.write('first');

    final second = await manager.write('next');
    await manager.flush();

    expect(second.filePath, endsWith('app_log_2026-07-15.1.txt'));
    expect(await manager.listFiles(), hasLength(2));
    await manager.close();
  });

  test('allows one entry larger than an empty part limit', () async {
    final manager = createManager(maxBytes: 2);

    final result = await manager.write('larger');
    await manager.flush();

    expect(await File(result.filePath).length(), greaterThan(2));
    expect(result.filePath, endsWith('app_log_2026-07-15.txt'));
    await manager.close();
  });

  test('cleanup removes only owned expired files', () async {
    final oldOwned = File('${directory.path}/app_log_2026-06-01.txt');
    final unrelated = File('${directory.path}/notes.txt');
    await oldOwned.writeAsString('old');
    await unrelated.writeAsString('keep');
    await oldOwned.setLastModified(now.subtract(const Duration(days: 31)));
    await unrelated.setLastModified(now.subtract(const Duration(days: 100)));

    final manager = createManager();
    await manager.initialize();

    expect(await oldOwned.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
    await manager.close();
  });

  test('lists owned files newest first and marks active file', () async {
    final manager = createManager();
    final active = await manager.write('current');
    final older = File('${directory.path}/app_log_2026-07-14.txt');
    await older.writeAsString('older');
    await older.setLastModified(now.subtract(const Duration(days: 1)));

    final files = await manager.listFiles();

    expect(files.first.path, active.filePath);
    expect(files.first.isActive, isTrue);
    expect(files.last.isActive, isFalse);
    await manager.close();
  });

  test('clear removes owned logs and preserves unrelated files', () async {
    final manager = createManager();
    await manager.write('current');
    final unrelated = File('${directory.path}/keep.bin');
    await unrelated.writeAsString('keep');

    await manager.clear();

    expect(await manager.listFiles(), isEmpty);
    expect(await unrelated.exists(), isTrue);
    await manager.close();
  });

  test('recovers when active file is externally removed', () async {
    final manager = createManager();
    final first = await manager.write('first');
    await manager.flush();
    await File(first.filePath).delete();

    final second = await manager.write('second');
    await manager.flush();

    expect(second.filePath, first.filePath);
    expect(await File(second.filePath).readAsString(), 'second\n');
    await manager.close();
  });

  test('emits absolute byte offsets after successful append', () async {
    final manager = createManager();
    final notifications = <LogWriteNotification>[];
    final subscription = manager.writes.listen(notifications.add);

    final first = await manager.write('一');
    final second = await manager.write('two');

    expect(first.startOffset, 0);
    expect(first.endOffset, utf8.encode('一\n').length);
    expect(second.startOffset, first.endOffset);
    expect(notifications, hasLength(2));
    await subscription.cancel();
    await manager.close();
  });
}
