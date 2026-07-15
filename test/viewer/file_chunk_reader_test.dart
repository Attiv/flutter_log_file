import 'dart:io';

import 'package:flutter_log_file/src/viewer/file_chunk_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File file;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vlog_reader_test_');
    file = File('${root.path}/large.txt');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('tail returns whole final lines and absolute offsets', () async {
    await file.writeAsString('one\n中文\nemoji🙂\nlast\n');
    final reader = FileChunkReader(file.path, chunkSizeBytes: 7);

    final tail = await reader.readTail(maxLines: 2);

    expect(tail.lines.map((line) => line.text), ['emoji🙂', 'last']);
    expect(tail.endOffset, await file.length());
    expect(tail.hasMoreBefore, isTrue);
  });

  test('read before and after have no duplicate or missing lines', () async {
    await file.writeAsString('one\ntwo\nthree\nfour\n');
    final reader = FileChunkReader(file.path, chunkSizeBytes: 9);
    final tail = await reader.readTail(maxLines: 2);

    final before = await reader.readBefore(tail.startOffset);
    final combined = [...before.lines, ...tail.lines];

    expect(combined.map((line) => line.text), ['one', 'two', 'three', 'four']);
    expect(before.endOffset, tail.startOffset);
  });

  test('decodes UTF8 characters crossing nominal byte chunks', () async {
    await file.writeAsString('ASCII\n一二三四五\n🙂🙂🙂\n');
    final reader = FileChunkReader(file.path, chunkSizeBytes: 5);

    final chunks = <LogFileChunk>[];
    var offset = 0;
    do {
      final chunk = await reader.readAfter(offset);
      chunks.add(chunk);
      if (chunk.endOffset <= offset) break;
      offset = chunk.endOffset;
    } while (chunks.last.hasMoreAfter);

    expect(
      chunks.expand((chunk) => chunk.lines).map((line) => line.text),
      ['ASCII', '一二三四五', '🙂🙂🙂'],
    );
  });

  test('normalizes CRLF without changing byte offsets', () async {
    await file.writeAsString('one\r\ntwo\r\n');
    final reader = FileChunkReader(file.path, chunkSizeBytes: 64);

    final result = await reader.readAfter(0);

    expect(result.lines.map((line) => line.text), ['one', 'two']);
    expect(result.endOffset, await file.length());
  });

  test('sees a concurrently appended complete line', () async {
    await file.writeAsString('one\n');
    final reader = FileChunkReader(file.path, chunkSizeBytes: 8);
    final first = await reader.readAfter(0);
    await file.writeAsString('two\n', mode: FileMode.append);

    final second = await reader.readAfter(first.endOffset);

    expect(second.lines.single.text, 'two');
  });

  test('jump around an offset includes the target line', () async {
    await file.writeAsString('one\ntarget-value\nthree\n');
    final reader = FileChunkReader(file.path, chunkSizeBytes: 8);

    final result = await reader.readAround(8);

    expect(result.lines.map((line) => line.text), contains('target-value'));
  });

  test('bounds memory for a physical line larger than maximumLineBytes',
      () async {
    await file.writeAsString('${'x' * 200000}\nlast\n');
    final reader = FileChunkReader(
      file.path,
      chunkSizeBytes: 1024,
      maximumLineBytes: 64,
    );

    final first = await reader.readAfter(0);

    expect(first.lines.first.text.length, lessThan(120));
    expect(first.lines.first.text, contains('line truncated'));
    expect(first.lines.first.endOffset, 200001);
    final next = await reader.readAfter(first.lines.first.endOffset);
    expect(next.lines.single.text, 'last');
  });

  test('bounds the retained tail by bytes as well as line count', () async {
    await file.writeAsString(
      '${List.generate(100, (index) => '${'x' * 128}-$index').join('\n')}\n',
    );
    final reader = FileChunkReader(
      file.path,
      chunkSizeBytes: 256,
      maximumLineBytes: 1024,
    );

    final tail = await reader.readTail(
      maxLines: 100,
      maximumBytes: 1024,
    );

    expect(
      tail.lines.fold<int>(0, (sum, line) => sum + line.byteLength),
      lessThanOrEqualTo(1024),
    );
    expect(tail.lines.last.text, endsWith('-99'));
    expect(tail.hasMoreBefore, isTrue);
  });
}
