import 'dart:io';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

final class DeviceState {
  DeviceState(this.id);

  final int id;
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vlog_facade_test_');
    await VLog.close();
  });

  tearDown(() async {
    await VLog.close();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('writes every public level and accepts an optional tag', () async {
    await VLog.init(
      LogConfig(
        directoryPath: root.path,
        consoleEnabled: false,
        flushInterval: Duration.zero,
      ),
    );

    VLog.v('v');
    VLog.d('d', tag: 'DebugTag');
    VLog.i('i');
    VLog.w('w');
    VLog.e('e', error: StateError('bad'), stackTrace: StackTrace.current);
    VLog.f('f');
    await VLog.flush();

    final content =
        await File((await VLog.getLogFiles()).single.path).readAsString();
    for (final level in [
      'VERBOSE',
      'DEBUG',
      'INFO',
      'WARN',
      'ERROR',
      'FATAL'
    ]) {
      expect(content, contains('[$level]'));
    }
    expect(content, contains('[DebugTag]'));
    expect(content, isNot(contains('[]')));
    expect(content, contains('vlog_test.dart:'));
  });

  test('buffers calls made before initialization', () async {
    VLog.i('before-init');

    await VLog.init(
      LogConfig(
        directoryPath: root.path,
        consoleEnabled: false,
        flushInterval: Duration.zero,
      ),
    );
    await VLog.flush();

    final content =
        await File((await VLog.getLogFiles()).single.path).readAsString();
    expect(content, contains('before-init'));
  });

  test('registered object encoder is shared by file sink', () async {
    VLog.registerEncoder<DeviceState>((state) => {'deviceId': state.id});
    await VLog.init(
      LogConfig(
        directoryPath: root.path,
        consoleEnabled: false,
        flushInterval: Duration.zero,
      ),
    );

    VLog.i(DeviceState(42));
    await VLog.flush();

    final content =
        await File((await VLog.getLogFiles()).single.path).readAsString();
    expect(content, contains('{"deviceId":42}'));
    VLog.unregisterEncoder<DeviceState>();
  });

  test('lists exports and clears only managed logs', () async {
    await VLog.init(
      LogConfig(
        directoryPath: root.path,
        consoleEnabled: false,
        flushInterval: Duration.zero,
      ),
    );
    VLog.i('export me');
    await VLog.flush();
    final unrelated = File('${root.path}/keep.txt');
    await unrelated.writeAsString('keep');
    final destination = Directory('${root.path}/exported');

    final exported = await VLog.exportLogs(destination.path);
    await VLog.clearLogs();

    expect(exported, hasLength(1));
    expect(await File(exported.single).readAsString(), contains('export me'));
    expect(await VLog.getLogFiles(), isEmpty);
    expect(await unrelated.exists(), isTrue);
  });

  test('reinitialization switches directories after draining old logs',
      () async {
    final second = Directory('${root.path}/second');
    await VLog.init(
      LogConfig(
        directoryPath: root.path,
        consoleEnabled: false,
        flushInterval: Duration.zero,
      ),
    );
    VLog.i('old');

    await VLog.init(
      LogConfig(
        directoryPath: second.path,
        consoleEnabled: false,
        flushInterval: Duration.zero,
      ),
    );
    VLog.i('new');
    await VLog.flush();

    final oldContent = await File(
      root
          .listSync()
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('.txt'))
          .path,
    ).readAsString();
    final newContent =
        await File((await VLog.getLogFiles()).single.path).readAsString();
    expect(oldContent, contains('old'));
    expect(newContent, contains('new'));
  });

  test('runGuarded logs zone failures and calls the supplied handler',
      () async {
    await VLog.init(
      LogConfig(
        directoryPath: root.path,
        consoleEnabled: false,
        flushInterval: Duration.zero,
      ),
    );
    Object? handled;

    VLog.runGuarded<void>(
      () => throw StateError('zone failed'),
      onError: (error, stackTrace) => handled = error,
    );
    await VLog.flush();

    expect(handled, isA<StateError>());
    final content =
        await File((await VLog.getLogFiles()).single.path).readAsString();
    expect(content, contains('zone failed'));
  });

  test('deletes only selected managed file paths', () async {
    await VLog.init(
      LogConfig(
        directoryPath: root.path,
        consoleEnabled: false,
        maxFileSizeBytes: 120,
        flushInterval: Duration.zero,
      ),
    );
    for (var index = 0; index < 10; index += 1) {
      VLog.i('entry-$index-${'x' * 40}');
    }
    await VLog.flush();
    final before = await VLog.getLogFiles();
    expect(before.length, greaterThan(1));

    await VLog.deleteLogFiles([
      before.last.path,
      '${root.path}/unmanaged.txt',
    ]);

    final after = await VLog.getLogFiles();
    expect(after.length, before.length - 1);
    expect(after.map((file) => file.path), isNot(contains(before.last.path)));
  });
}
