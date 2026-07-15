import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// One decoded line and its absolute byte range in the source file.
final class LogFileLine {
  const LogFileLine({
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });

  final String text;
  final int startOffset;
  final int endOffset;

  int get byteLength => endOffset - startOffset;
}

/// A bounded, whole-line byte range returned by [FileChunkReader].
final class LogFileChunk {
  const LogFileChunk({
    required this.lines,
    required this.startOffset,
    required this.endOffset,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
  });

  final List<LogFileLine> lines;
  final int startOffset;
  final int endOffset;
  final bool hasMoreBefore;
  final bool hasMoreAfter;
}

/// Reads large UTF-8 text files without loading the full file into memory.
final class FileChunkReader {
  FileChunkReader(
    this.filePath, {
    this.chunkSizeBytes = 128 * 1024,
    this.maximumLineBytes = 1024 * 1024,
  })  : assert(chunkSizeBytes > 0),
        assert(maximumLineBytes > 0);

  final String filePath;
  final int chunkSizeBytes;
  final int maximumLineBytes;

  Future<LogFileChunk> readTail({required int maxLines}) async {
    final file = File(filePath);
    final length = await file.length();
    if (length == 0) {
      return _empty(0);
    }
    var start = max(0, length - chunkSizeBytes);
    List<LogFileLine> lines = const [];
    while (true) {
      lines = await _readAligned(start, length);
      if (lines.length >= maxLines || start == 0) {
        break;
      }
      start = max(0, start - chunkSizeBytes);
    }
    if (lines.length > maxLines) {
      lines = lines.sublist(lines.length - maxLines);
    }
    final first = lines.isEmpty ? length : lines.first.startOffset;
    return LogFileChunk(
      lines: lines,
      startOffset: first,
      endOffset: length,
      hasMoreBefore: first > 0,
      hasMoreAfter: false,
    );
  }

  Future<LogFileChunk> readBefore(int endOffset) async {
    final length = await File(filePath).length();
    final end = endOffset.clamp(0, length);
    if (end == 0) {
      return _empty(0, hasMoreAfter: length > 0);
    }
    var start = max(0, end - chunkSizeBytes);
    var lines = await _readAligned(start, end);
    while (lines.isEmpty && start > 0 && end - start < maximumLineBytes) {
      start = max(0, start - chunkSizeBytes);
      lines = await _readAligned(start, end);
    }
    final actualStart = lines.isEmpty ? end : lines.first.startOffset;
    return LogFileChunk(
      lines: lines,
      startOffset: actualStart,
      endOffset: end,
      hasMoreBefore: actualStart > 0,
      hasMoreAfter: end < length,
    );
  }

  Future<LogFileChunk> readAfter(int startOffset) async {
    final length = await File(filePath).length();
    final start = startOffset.clamp(0, length);
    if (start == length) {
      return _empty(length);
    }
    var end = min(length, start + chunkSizeBytes);
    if (end < length) {
      end = await _nextLineBoundary(end, length);
    }
    final lines = await _readAligned(start, end);
    final actualEnd = lines.isEmpty ? start : lines.last.endOffset;
    return LogFileChunk(
      lines: lines,
      startOffset: lines.isEmpty ? start : lines.first.startOffset,
      endOffset: actualEnd,
      hasMoreBefore: start > 0,
      hasMoreAfter: actualEnd < length,
    );
  }

  Future<LogFileChunk> readAround(int offset) async {
    final length = await File(filePath).length();
    if (length == 0) {
      return _empty(0);
    }
    final target = offset.clamp(0, length - 1);
    final lineStart = await _lineStart(target);
    final before = await readBefore(lineStart);
    final after = await readAfter(lineStart);
    final lines = <LogFileLine>[...before.lines, ...after.lines];
    return LogFileChunk(
      lines: lines,
      startOffset: lines.isEmpty ? lineStart : lines.first.startOffset,
      endOffset: lines.isEmpty ? lineStart : lines.last.endOffset,
      hasMoreBefore: before.hasMoreBefore,
      hasMoreAfter: after.hasMoreAfter,
    );
  }

  Future<List<LogFileLine>> _readAligned(int start, int end) async {
    if (end <= start) {
      return const [];
    }
    final file = await File(filePath).open();
    try {
      await file.setPosition(start);
      final bytes = await file.read(end - start);
      var alignedStartIndex = 0;
      var absoluteStart = start;
      if (start > 0) {
        await file.setPosition(start - 1);
        final previous = await file.readByte();
        if (previous != 0x0A) {
          final newline = bytes.indexOf(0x0A);
          if (newline < 0) {
            return const [];
          }
          alignedStartIndex = newline + 1;
          absoluteStart += alignedStartIndex;
        }
      }

      final result = <LogFileLine>[];
      var lineStart = alignedStartIndex;
      for (var index = alignedStartIndex; index < bytes.length; index += 1) {
        if (bytes[index] != 0x0A) {
          continue;
        }
        final contentEnd =
            index > lineStart && bytes[index - 1] == 0x0D ? index - 1 : index;
        result.add(
          LogFileLine(
            text: utf8.decode(bytes.sublist(lineStart, contentEnd)),
            startOffset: absoluteStart + lineStart - alignedStartIndex,
            endOffset: start + index + 1,
          ),
        );
        lineStart = index + 1;
      }
      if (lineStart < bytes.length && end == await file.length()) {
        result.add(
          LogFileLine(
            text: utf8.decode(bytes.sublist(lineStart)),
            startOffset: absoluteStart + lineStart - alignedStartIndex,
            endOffset: end,
          ),
        );
      }
      return result;
    } finally {
      await file.close();
    }
  }

  Future<int> _nextLineBoundary(int offset, int length) async {
    final file = await File(filePath).open();
    try {
      var position = offset;
      await file.setPosition(position);
      while (position < length) {
        final bytes = await file.read(min(chunkSizeBytes, length - position));
        final newline = bytes.indexOf(0x0A);
        if (newline >= 0) {
          return position + newline + 1;
        }
        position += bytes.length;
      }
      return length;
    } finally {
      await file.close();
    }
  }

  Future<int> _lineStart(int offset) async {
    final file = await File(filePath).open();
    try {
      var cursor = offset;
      while (cursor > 0) {
        final blockStart = max(0, cursor - chunkSizeBytes);
        await file.setPosition(blockStart);
        final bytes = await file.read(cursor - blockStart);
        final newline = bytes.lastIndexOf(0x0A);
        if (newline >= 0) {
          return blockStart + newline + 1;
        }
        cursor = blockStart;
      }
      return 0;
    } finally {
      await file.close();
    }
  }

  LogFileChunk _empty(int offset, {bool hasMoreAfter = false}) => LogFileChunk(
        lines: const [],
        startOffset: offset,
        endOffset: offset,
        hasMoreBefore: offset > 0,
        hasMoreAfter: hasMoreAfter,
      );
}
