import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/viewer/log_file_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File file;
  late LogFileInfo fileInfo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vlog_file_page_test_');
    file = File('${root.path}/app_log.txt');
    final lines = <String>[];
    for (var index = 0; index < 30; index += 1) {
      final message = index == 4
          ? 'needle-value'
          : index == 29
              ? '{"ok":true}'
              : 'line-$index';
      lines.add(
        '2026-07-15 10:00:${index.toString().padLeft(2, '0')}.000 '
        '[${index == 28 ? 'ERROR' : 'INFO'}] [API] main.dart:$index | $message',
      );
    }
    await file.writeAsString('${lines.join('\n')}\n');
    fileInfo = LogFileInfo(
      path: file.path,
      name: 'app_log.txt',
      sizeBytes: await file.length(),
      modifiedAt: DateTime(2026, 7, 15),
      part: 0,
      isActive: true,
    );
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  testWidgets('renders only the lazy tail with level-aware rows',
      (tester) async {
    final controller = LogFileController(
      filePath: file.path,
      config: const VLogViewerConfig(initialTailLines: 4),
    );
    await tester.runAsync(controller.open);

    await tester.pumpWidget(
      MaterialApp(
        home: VLogFilePage(file: fileInfo, controller: controller),
      ),
    );
    await tester.pump();

    expect(find.textContaining('line-0'), findsNothing);
    expect(find.textContaining('{"ok":true}'), findsOneWidget);
    expect(find.byKey(const Key('log-level-error')), findsOneWidget);
    expect(find.byKey(const Key('load-older-logs')), findsOneWidget);
    await controller.close();
  });

  testWidgets('searches in isolate and jumps to selected byte offset',
      (tester) async {
    final controller = LogFileController(
      filePath: file.path,
      config: const VLogViewerConfig(initialTailLines: 4),
    );
    await tester.runAsync(controller.open);
    await tester.pumpWidget(
      MaterialApp(
        home: VLogFilePage(file: fileInfo, controller: controller),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('toggle-log-search')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('log-search-field')),
      'needle-value',
    );
    await tester.tap(find.byKey(const Key('submit-log-search')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.text('1 个结果'), findsOneWidget);
    await tester.tap(find.byKey(const Key('search-result-0')));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (!controller.isLoading &&
            controller.lines
                .any((line) => line.text.contains('needle-value'))) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.textContaining('needle-value'), findsAtLeastNWidgets(2));
    await controller.close();
  });

  testWidgets('toggles wrap live follow and font controls', (tester) async {
    final controller = LogFileController(filePath: file.path);
    await tester.runAsync(controller.open);
    await tester.pumpWidget(
      MaterialApp(
        home: VLogFilePage(file: fileInfo, controller: controller),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('toggle-line-wrap')));
    await tester.tap(find.byKey(const Key('toggle-live-follow')));
    await tester.tap(find.byKey(const Key('increase-log-font')));
    await tester.pump();

    expect(controller.isFollowing, isFalse);
    expect(find.text('实时追踪已暂停'), findsOneWidget);
    await controller.close();
  });
}
