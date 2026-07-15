import 'dart:io';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File file;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vlog_search_test_');
    file = File('${root.path}/search.txt');
    await file.writeAsString('''
2026-07-15 10:00:00.000 [INFO] [API] api.dart:1 | Alpha request
2026-07-15 10:01:00.000 [ERROR] [DB] db.dart:2 | alpha failed
2026-07-15 10:02:00.000 [WARN] [API] api.dart:3 | slow request
plain external Alpha line
'''
        .trimLeft());
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<LogSearchOutcome> search(LogSearchQuery query) =>
      LogSearchService().search(file.path, query).done;

  test('finds plain keyword with optional case sensitivity', () async {
    final insensitive = await search(const LogSearchQuery(text: 'alpha'));
    final sensitive = await search(
      const LogSearchQuery(text: 'Alpha', caseSensitive: true),
    );

    expect(insensitive.results, hasLength(3));
    expect(sensitive.results, hasLength(2));
  });

  test('supports regular expressions and validates them before spawn',
      () async {
    final outcome = await search(
      const LogSearchQuery(text: r'(request|failed)$', useRegex: true),
    );

    expect(outcome.results, hasLength(3));
    expect(
      () => LogSearchService().search(
        file.path,
        const LogSearchQuery(text: '[', useRegex: true),
      ),
      throwsFormatException,
    );
  });

  test('filters by level tag and time range', () async {
    final outcome = await search(
      LogSearchQuery(
        text: '',
        levels: const {LogLevel.warning},
        tags: const {'API'},
        startTime: DateTime(2026, 7, 15, 10, 1),
        endTime: DateTime(2026, 7, 15, 10, 3),
      ),
    );

    expect(outcome.results.single.snippet, contains('slow request'));
  });

  test('returns byte offsets consumable by file controller', () async {
    final outcome = await search(
      const LogSearchQuery(text: 'alpha failed', caseSensitive: true),
    );
    final result = outcome.results.single;
    final controller = LogFileController(filePath: file.path);
    await controller.open();

    await controller.jumpToOffset(result.startOffset);

    expect(
      controller.lines.map((line) => line.text),
      contains(result.snippet),
    );
    await controller.close();
  });

  test('reports monotonic progress and bounded results', () async {
    await file.writeAsString(List.filled(100, 'match').join('\n'));
    final task = LogSearchService().search(
      file.path,
      const LogSearchQuery(text: 'match', maximumResults: 5),
    );
    final progress = <double>[];
    final subscription = task.progress.listen(progress.add);

    final outcome = await task.done;
    await subscription.cancel();

    expect(outcome.results, hasLength(5));
    expect(outcome.truncated, isTrue);
    expect(progress, isNotEmpty);
    for (var index = 1; index < progress.length; index += 1) {
      expect(progress[index], greaterThanOrEqualTo(progress[index - 1]));
    }
  });

  test('can cancel before an isolate begins scanning', () async {
    final task = LogSearchService().search(
      file.path,
      const LogSearchQuery(text: 'Alpha'),
    );

    await task.cancel();
    final outcome = await task.done;

    expect(outcome.cancelled, isTrue);
  });
}
