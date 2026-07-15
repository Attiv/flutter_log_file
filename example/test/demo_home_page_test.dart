import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlog_demo/demo_home_page.dart';
import 'package:vlog_demo/demo_models.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('vlog_demo_test_');
    VLog.registerEncoder<DemoOrder>(encodeDemoOrder);
    await VLog.init(
      LogConfig(
        consoleEnabled: false,
        fileEnabled: true,
        directoryPath: tempDirectory.path,
        filePrefix: 'demo_test',
        flushInterval: Duration.zero,
      ),
    );
  });

  tearDown(() async {
    await VLog.close();
    VLog.unregisterEncoder<DemoOrder>();
    await tempDirectory.delete(recursive: true);
  });

  Widget testApp({
    Future<void> Function(LogConfig config)? configurationApplier,
    LogViewerRepository? viewerRepository,
  }) =>
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00A884),
          ),
          useMaterial3: true,
        ),
        home: DemoHomePage(
          testDirectoryPath: tempDirectory.path,
          configurationApplier: configurationApplier,
          viewerRepository: viewerRepository,
        ),
      );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('renders Material 3 configuration and log playground',
      (tester) async {
    await tester.pumpWidget(testApp());

    expect(find.text('VLog Playground'), findsOneWidget);
    expect(find.text('Runtime status'), findsOneWidget);
    expect(find.text('Output configuration'), findsOneWidget);
    expect(find.text('Log playground'), findsOneWidget);
    expect(find.byKey(const Key('message-field')), findsOneWidget);
    expect(find.byKey(const Key('tag-field')), findsOneWidget);
    expect(find.byKey(const Key('open-viewer')), findsOneWidget);
  });

  testWidgets('writes text, JSON, object, and error samples', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(testApp());

    await tester.enterText(
      find.byKey(const Key('message-field')),
      'Message from Widget Test',
    );
    await tester.enterText(find.byKey(const Key('tag-field')), 'Widget');
    await tapVisible(tester, find.byKey(const Key('log-info')));
    await tapVisible(tester, find.byKey(const Key('log-json')));
    await tapVisible(tester, find.byKey(const Key('log-object')));
    await tapVisible(tester, find.byKey(const Key('log-exception')));
    await tester.runAsync(VLog.flush);

    final contents = await tester.runAsync(() async {
      final files = await VLog.getLogFiles();
      expect(files, isNotEmpty);
      return File(files.first.path).readAsString();
    });
    expect(contents, contains('Message from Widget Test'));
    expect(contents, contains('Widget'));
    expect(contents, contains('Ada'));
    expect(contents, contains('ORDER-2026-001'));
    expect(contents, contains('Demo request failed'));
    expect(contents, contains('Bad state: Demo API timeout after 3 retries'));
  });

  testWidgets('applies editable configuration', (tester) async {
    LogConfig? appliedConfig;
    await tester.pumpWidget(
      testApp(
        configurationApplier: (config) async => appliedConfig = config,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('prefix-field')),
      'experience_log',
    );
    await tapVisible(tester, find.byKey(const Key('pretty-json-switch')));
    await tapVisible(tester, find.byKey(const Key('apply-config')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(appliedConfig?.filePrefix, 'experience_log');
    expect(appliedConfig?.prettyJson, isTrue);
    expect(appliedConfig?.directoryPath, tempDirectory.path);
    expect(
      find.text('Configuration applied. A new VLog session was created.'),
      findsOneWidget,
    );
  });

  testWidgets('opens the package log viewer', (tester) async {
    await tester
        .pumpWidget(testApp(viewerRepository: _EmptyViewerRepository()));

    await tester.tap(find.byKey(const Key('open-viewer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('VLog Logs'), findsOneWidget);
    expect(find.byType(VLogViewerPage), findsOneWidget);
  });
}

final class _EmptyViewerRepository implements LogViewerRepository {
  @override
  Future<void> cleanup() async {}

  @override
  Future<void> deleteFiles(Iterable<String> paths) async {}

  @override
  Future<List<LogFileInfo>> listFiles() async => const [];

  @override
  Future<void> shareFiles(Iterable<String> paths) async {}
}
