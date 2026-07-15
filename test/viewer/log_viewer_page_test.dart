import 'package:flutter/material.dart';
import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeLogViewerRepository implements LogViewerRepository {
  FakeLogViewerRepository(this.files);

  List<LogFileInfo> files;
  List<String> deleted = [];
  List<String> shared = [];
  int cleanupCalls = 0;

  @override
  Future<void> cleanup() async => cleanupCalls += 1;

  @override
  Future<void> deleteFiles(Iterable<String> paths) async {
    deleted = paths.toList();
    files = files.where((file) => !deleted.contains(file.path)).toList();
  }

  @override
  Future<List<LogFileInfo>> listFiles() async => List.of(files);

  @override
  Future<void> shareFiles(Iterable<String> paths) async {
    shared = paths.toList();
  }
}

LogFileInfo info(String name, DateTime modified, {bool active = false}) =>
    LogFileInfo(
      path: '/logs/$name',
      name: name,
      sizeBytes: 2048,
      modifiedAt: modified,
      part: 0,
      isActive: active,
    );

void main() {
  testWidgets('shows files newest first with active status', (tester) async {
    final repository = FakeLogViewerRepository([
      info('old.txt', DateTime(2026, 7, 14)),
      info('new.txt', DateTime(2026, 7, 15), active: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: VLogViewerPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('old.txt'), findsOneWidget);
    expect(find.byKey(const Key('active-log-badge')), findsOneWidget);
    final newY = tester.getTopLeft(find.text('new.txt')).dy;
    final oldY = tester.getTopLeft(find.text('old.txt')).dy;
    expect(newY, lessThan(oldY));
  });

  testWidgets('opens a selected file using injected page builder',
      (tester) async {
    final repository = FakeLogViewerRepository([
      info('app_log.txt', DateTime(2026, 7, 15)),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: VLogViewerPage(
          repository: repository,
          filePageBuilder: (context, file) => Text('opened:${file.name}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app_log.txt'));
    await tester.pumpAndSettle();

    expect(find.text('opened:app_log.txt'), findsOneWidget);
  });

  testWidgets('shares and deletes selected files after confirmation',
      (tester) async {
    final repository = FakeLogViewerRepository([
      info('app_log.txt', DateTime(2026, 7, 15)),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: VLogViewerPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('app_log.txt'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('share-selected-logs')));
    await tester.pump();
    expect(repository.shared, ['/logs/app_log.txt']);

    await tester.tap(find.byKey(const Key('delete-selected-logs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleted, ['/logs/app_log.txt']);
    expect(find.text('No log files'), findsOneWidget);
  });

  testWidgets('renders a useful empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
          home: VLogViewerPage(repository: FakeLogViewerRepository([]))),
    );
    await tester.pumpAndSettle();

    expect(find.text('No log files'), findsOneWidget);
    expect(find.byKey(const Key('refresh-log-files')), findsOneWidget);
  });
}
