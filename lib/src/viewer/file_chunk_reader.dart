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

  Future<LogFileChunk> readTail({
    required int maxLines,
    int? maximumBytes,
  }) async {
    if (maxLines <= 0) {
      throw ArgumentError.value(maxLines, 'maxLines', 'must be > 0');
    }
    if (maximumBytes != null && maximumBytes <= 0) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes', 'must be > 0');
    }
    final file = File(filePath);
    final length = await file.length();
    if (length == 0) {
      return _empty(0);
    }
    final start = await _tailStart(length, maxLines);
    final lines = await _readAligned(
      start,
      length,
      maximumLines: maxLines,
      maximumBytes: maximumBytes,
      keepTail: true,
    );
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
    if (lines.isEmpty && end > 0) {
      var target = end - 1;
      if (await _byteAt(target) == 0x0A && target > 0) target -= 1;
      start = await _lineStart(target);
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

  Future<List<LogFileLine>> _readAligned(
    int start,
    int end, {
    int? maximumLines,
    int? maximumBytes,
    bool keepTail = false,
  }) async {
    if (end <= start) {
      return const [];
    }
    final file = await File(filePath).open();
    try {
      final result = <LogFileLine>[];
      var retainedBytes = 0;

      void retain(LogFileLine line) {
        result.add(line);
        retainedBytes += line.byteLength;
        if (!keepTail) return;
        while (result.length > 1 &&
            ((maximumLines != null && result.length > maximumLines) ||
                (maximumBytes != null && retainedBytes > maximumBytes))) {
          retainedBytes -= result.removeAt(0).byteLength;
        }
      }

      final fileLength = await file.length();
      var position = start;
      var lineStart = start;
      var aligned = start == 0 || await _byteAtWith(file, start - 1) == 0x0A;
      var lineBytes = <int>[];
      var lineTruncated = false;
      while (position < end) {
        await file.setPosition(position);
        final bytes = await file.read(min(chunkSizeBytes, end - position));
        for (var index = 0; index < bytes.length; index += 1) {
          final absolute = position + index;
          final byte = bytes[index];
          if (!aligned) {
            if (byte == 0x0A) {
              aligned = true;
              lineStart = absolute + 1;
            }
            continue;
          }
          if (byte == 0x0A) {
            retain(
              LogFileLine(
                text: _decodeLine(lineBytes, lineTruncated),
                startOffset: lineStart,
                endOffset: absolute + 1,
              ),
            );
            lineStart = absolute + 1;
            lineBytes = <int>[];
            lineTruncated = false;
          } else if (lineBytes.length < maximumLineBytes) {
            lineBytes.add(byte);
          } else {
            lineTruncated = true;
          }
        }
        position += bytes.length;
        if (bytes.isEmpty) break;
      }
      if (aligned && lineStart < end && end == fileLength) {
        retain(
          LogFileLine(
            text: _decodeLine(lineBytes, lineTruncated),
            startOffset: lineStart,
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

  Future<int> _tailStart(int length, int maxLines) async {
    final file = await File(filePath).open();
    try {
      var position = length;
      if (position > 0) {
        await file.setPosition(position - 1);
        if (await file.readByte() == 0x0A) position -= 1;
      }
      var newlineCount = 0;
      while (position > 0) {
        final blockStart = max(0, position - chunkSizeBytes);
        await file.setPosition(blockStart);
        final bytes = await file.read(position - blockStart);
        for (var index = bytes.length - 1; index >= 0; index -= 1) {
          if (bytes[index] != 0x0A) continue;
          newlineCount += 1;
          if (newlineCount == maxLines) return blockStart + index + 1;
        }
        position = blockStart;
      }
      return 0;
    } finally {
      await file.close();
    }
  }

  Future<int> _byteAt(int offset) async {
    final file = await File(filePath).open();
    try {
      return _byteAtWith(file, offset);
    } finally {
      await file.close();
    }
  }

  Future<int> _byteAtWith(RandomAccessFile file, int offset) async {
    await file.setPosition(offset);
    return file.readByte();
  }

  String _decodeLine(List<int> bytes, bool truncated) {
    var value = bytes;
    if (bytes.isNotEmpty && bytes.last == 0x0D) {
      value = bytes.sublist(0, bytes.length - 1);
    }
    final text = utf8.decode(value, allowMalformed: true);
    return truncated ? '$text… [line truncated]' : text;
  }

  LogFileChunk _empty(int offset, {bool hasMoreAfter = false}) => LogFileChunk(
        lines: const [],
        startOffset: offset,
        endOffset: offset,
        hasMoreBefore: offset > 0,
        hasMoreAfter: hasMoreAfter,
      );
}
