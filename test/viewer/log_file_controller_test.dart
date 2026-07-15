import 'dart:async';
import 'dart:io';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/storage/log_file_manager.dart';
import 'package:flutter_log_file/src/viewer/log_file_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File file;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vlog_view_controller_');
    file = File('${root.path}/app_log.txt');
    await file.writeAsString(
      '${List.generate(20, (index) => 'line-$index').join('\n')}\n',
    );
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('opens only the configured tail and loads older lines', () async {
    final controller = LogFileController(
      filePath: file.path,
      config: const VLogViewerConfig(
        chunkSizeBytes: 24,
        memoryBudgetBytes: 1024,
        initialTailLines: 3,
      ),
    );

    await controller.open();
    expect(controller.lines.map((line) => line.text), [
      'line-17',
      'line-18',
      'line-19',
    ]);
    await controller.loadOlder();
    expect(controller.lines.first.text, isNot('line-17'));
    await controller.close();
  });

  test('keeps decoded window within memory budget while paging', () async {
    final controller = LogFileController(
      filePath: file.path,
      config: const VLogViewerConfig(
        chunkSizeBytes: 30,
        memoryBudgetBytes: 45,
        initialTailLines: 2,
      ),
    );

    await controller.open();
    for (var i = 0; i < 10; i += 1) {
      await controller.loadOlder();
    }

    expect(controller.decodedBytes, lessThanOrEqualTo(45));
    await controller.close();
  });

  test('jump to offset replaces window with surrounding context', () async {
    final controller = LogFileController(filePath: file.path);
    await controller.open();

    await controller.jumpToOffset(10);

    expect(controller.lines.map((line) => line.text), contains('line-1'));
    await controller.close();
  });

  test('live notification appends only while follow is enabled', () async {
    final events = StreamController<LogWriteNotification>.broadcast();
    final controller = LogFileController(
      filePath: file.path,
      writeNotifications: events.stream,
      config: const VLogViewerConfig(initialTailLines: 2),
    );
    await controller.open();
    controller.setFollow(false);
    await file.writeAsString('paused\n', mode: FileMode.append);
    events.add(
      LogWriteNotification(
        filePath: file.path,
        startOffset: 150,
        endOffset: 157,
        text: 'paused\n',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
        controller.lines.map((line) => line.text), isNot(contains('paused')));

    await controller.setFollow(true);
    expect(controller.lines.map((line) => line.text), contains('paused'));
    await controller.close();
    await events.close();
  });
}
