import 'dart:io';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/format/caller_resolver.dart';
import 'package:flutter_log_file/src/model/log_entry.dart';
import 'package:flutter_log_file/src/sink/file_sink.dart';
import 'package:flutter_log_file/src/storage/log_file_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vlog_file_sink_test_');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  LogEntry entry(LogLevel level) => LogEntry(
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

  test('writes compact plain text with file-specific settings', () async {
    final config = LogConfig(
      directoryPath: directory.path,
      consolePrettyJson: true,
      filePrettyJson: false,
    );
    final manager = LogFileManager(
      directory: directory,
      config: config,
      clock: () => DateTime(2026, 7, 15),
    );
    final sink = FileSink(config, manager);

    await sink.write(entry(LogLevel.info));
    await sink.flush();

    final file = File((await manager.listFiles()).single.path);
    final content = await file.readAsString();
    expect(content, contains('{"ok":true}'));
    expect(content, isNot(contains('\x1B[')));
    await sink.close();
  });

  test('honors file-specific minimum level', () async {
    final config = LogConfig(fileMinimumLevel: LogLevel.error);
    final manager = LogFileManager(directory: directory, config: config);
    final sink = FileSink(config, manager);

    await sink.write(entry(LogLevel.info));

    expect(await manager.listFiles(), isEmpty);
    await sink.close();
  });

  test('uses bounded retry delays and then rethrows write failure', () async {
    final config = LogConfig();
    final manager = LogFileManager(directory: directory, config: config);
    await manager.close();
    final delays = <Duration>[];
    final sink = FileSink(
      config,
      manager,
      delay: (duration) async => delays.add(duration),
      maximumAttempts: 3,
    );

    await expectLater(sink.write(entry(LogLevel.error)), throwsStateError);

    expect(delays, [
      const Duration(milliseconds: 50),
      const Duration(milliseconds: 100),
    ]);
  });
}
