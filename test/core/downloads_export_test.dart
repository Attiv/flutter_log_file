import 'dart:async';
import 'dart:io';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_log_file/downloads');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('htf-log-export-');
    await VLog.init(
      LogConfig(
        directoryPath: directory.path,
        filePrefix: 'htf_checkin',
        consoleEnabled: false,
      ),
    );
    VLog.i('Buffered export entry');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await VLog.close();
    await directory.delete(recursive: true);
  });

  test(
    'export flushes pending writes before passing log files to Android',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'exportLogsToDownloads');
        final paths = List<String>.from(call.arguments['paths'] as List);
        expect(call.arguments['directory'], directory.path);
        expect(paths, hasLength(1));
        expect(
          await File(paths.single).readAsString(),
          contains('Buffered export entry'),
        );
        return 'Download/htf-logs.zip';
      });
      expect(await VLog.exportLogsToDownloads(), 'Download/htf-logs.zip');
    },
  );

  test('empty logs do not invoke the Android exporter', () async {
    await VLog.close();
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('No files to export'),
    );
    await expectLater(VLog.exportLogsToDownloads(), throwsStateError);
  });

  test('rejects unrelated files before calling Android', () async {
    final other = await File('${directory.path}/settings.json')
        .writeAsString('private settings');
    messenger.setMockMethodCallHandler(
        channel, (_) async => fail('Unmanaged files must not be exported'));
    await expectLater(
      VLog.exportLogsToDownloads(filePaths: [other.path]),
      throwsArgumentError,
    );
  });

  Future<void> openPage(WidgetTester tester) async {
    // Start the viewer's file IO outside the widget test's fake async zone.
    await tester.runAsync(() async {
      await VLog.flush();
      await tester.pumpWidget(const MaterialApp(home: VLogViewerPage()));
      await VLog.getLogFiles();
    });
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Save all logs to Downloads'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  testWidgets(
    'shows directory, blocks repeated saves, and reports destination',
    (tester) async {
      final saved = Completer<String>();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) {
        calls++;
        return saved.future;
      });
      await openPage(tester);
      expect(find.text(directory.path), findsOneWidget);
      expect(find.text('VLog Logs'), findsOneWidget);
      await tapSave(tester);
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 1);
      await tester.runAsync(() async {
        saved.complete('Download/htf-logs.zip');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('Saved to Download/htf-logs.zip'), findsOneWidget);
      expect(find.text('Save all logs to Downloads'), findsOneWidget);
    },
  );

  testWidgets('cancel and storage failure allow another save', (tester) async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await openPage(tester);
    await tapSave(tester);
    await tester.pumpAndSettle();
    expect(find.text('Save cancelled'), findsOneWidget);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'export_failed', message: 'Storage full');
    });
    await tapSave(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not save logs: Storage full'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
