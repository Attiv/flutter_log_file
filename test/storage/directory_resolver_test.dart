import 'dart:io';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/storage/directory_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vlog_directory_test_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('explicit directory path wins and is created recursively', () async {
    final target = '${root.path}/custom/nested';
    final resolver = DirectoryResolver(
      LogConfig(directoryPath: target),
      getSupportDirectory: () async => throw StateError('must not be called'),
    );

    final result = await resolver.resolve();

    expect(result.path, target);
    expect(await result.exists(), isTrue);
  });

  test('async custom resolver wins over platform support directory', () async {
    final target = '${root.path}/resolved';
    final resolver = DirectoryResolver(
      LogConfig(directoryResolver: () async => target),
      getSupportDirectory: () async => throw StateError('must not be called'),
    );

    expect((await resolver.resolve()).path, target);
  });

  test('default resolves to support directory logs child', () async {
    final resolver = DirectoryResolver(
      LogConfig(),
      getSupportDirectory: () async => root,
    );

    final result = await resolver.resolve();

    expect(result.path, '${root.path}/logs');
    expect(await result.exists(), isTrue);
  });

  test('wraps platform resolver errors in typed initialization failure', () {
    final resolver = DirectoryResolver(
      LogConfig(),
      getSupportDirectory: () async => throw StateError('plugin unavailable'),
    );

    expect(
      resolver.resolve,
      throwsA(
        isA<LogDirectoryException>().having(
          (error) => error.cause.toString(),
          'cause',
          contains('plugin unavailable'),
        ),
      ),
    );
  });

  test('Android can explicitly retain internal storage', () async {
    final resolver = DirectoryResolver(
      LogConfig(useExternalStorageOnAndroid: false),
      isAndroid: true,
      getExternalDirectory: () async => throw StateError('must not be called'),
      getSupportDirectory: () async => root,
    );
    expect((await resolver.resolve()).path, '${root.path}/logs');
  });

  test('Android custom paths bypass external storage and migration', () async {
    final target = '${root.path}/chosen';
    final resolver = DirectoryResolver(
      LogConfig(directoryPath: target),
      isAndroid: true,
      getExternalDirectory: () async => throw StateError('must not be called'),
      getSupportDirectory: () async => throw StateError('must not be called'),
    );
    expect((await resolver.resolve()).path, target);
  });
}
