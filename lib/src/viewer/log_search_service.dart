import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import '../model/log_level.dart';
import 'log_line_parser.dart';

/// Filters and limits for one background file search.
final class LogSearchQuery {
  const LogSearchQuery({
    required this.text,
    this.caseSensitive = false,
    this.useRegex = false,
    this.levels = const {},
    this.tags = const {},
    this.startTime,
    this.endTime,
    this.maximumResults = 5000,
    this.maximumSnippetCharacters = 500,
  })  : assert(maximumResults > 0),
        assert(maximumSnippetCharacters > 0);

  final String text;
  final bool caseSensitive;
  final bool useRegex;
  final Set<LogLevel> levels;
  final Set<String> tags;
  final DateTime? startTime;
  final DateTime? endTime;
  final int maximumResults;
  final int maximumSnippetCharacters;
}

/// One matching physical line represented by a short preview and byte offset.
final class LogSearchResult {
  const LogSearchResult({
    required this.startOffset,
    required this.endOffset,
    required this.lineNumber,
    required this.snippet,
    this.level,
    this.tag,
    this.timestamp,
  });

  final int startOffset;
  final int endOffset;
  final int lineNumber;
  final String snippet;
  final LogLevel? level;
  final String? tag;
  final DateTime? timestamp;
}

/// Terminal result of a search worker.
final class LogSearchOutcome {
  const LogSearchOutcome({
    required this.results,
    this.truncated = false,
    this.cancelled = false,
  });

  final List<LogSearchResult> results;
  final bool truncated;
  final bool cancelled;
}

/// Handle for progress, incremental results, cancellation and completion.
final class LogSearchTask {
  LogSearchTask._(this._request) {
    scheduleMicrotask(_start);
  }

  final Map<String, Object?> _request;
  final StreamController<double> _progress =
      StreamController<double>.broadcast();
  final StreamController<LogSearchResult> _results =
      StreamController<LogSearchResult>.broadcast();
  final Completer<LogSearchOutcome> _done = Completer<LogSearchOutcome>();
  final List<LogSearchResult> _collected = [];

  ReceivePort? _port;
  Isolate? _isolate;
  bool _cancelled = false;
  bool _finished = false;

  Stream<double> get progress => _progress.stream;
  Stream<LogSearchResult> get results => _results.stream;
  Future<LogSearchOutcome> get done => _done.future;

  Future<void> cancel() async {
    if (_finished) {
      return;
    }
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _finish(
      LogSearchOutcome(
        results: List.unmodifiable(_collected),
        cancelled: true,
      ),
    );
  }

  Future<void> _start() async {
    if (_cancelled) {
      return;
    }
    _progress.add(0);
    final port = ReceivePort();
    _port = port;
    port.listen(_onMessage);
    try {
      final request = Map<String, Object?>.of(_request)
        ..['sendPort'] = port.sendPort;
      final isolate = await Isolate.spawn<Map<String, Object?>>(
        _searchWorker,
        request,
        onError: port.sendPort,
        errorsAreFatal: true,
      );
      if (_cancelled || _finished) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (error, stackTrace) {
      _finishError(error, stackTrace);
    }
  }

  void _onMessage(Object? message) {
    if (_finished) {
      return;
    }
    if (message is List && message.length >= 2) {
      _finishError(
        StateError(message.first.toString()),
        StackTrace.fromString(message[1].toString()),
      );
      return;
    }
    if (message is! Map) {
      return;
    }
    switch (message['type']) {
      case 'progress':
        _progress.add((message['value'] as num).toDouble().clamp(0, 1));
      case 'result':
        final result = _resultFromMap(message.cast<String, Object?>());
        _collected.add(result);
        _results.add(result);
      case 'done':
        _progress.add(1);
        _finish(
          LogSearchOutcome(
            results: List.unmodifiable(_collected),
            truncated: message['truncated'] as bool? ?? false,
          ),
        );
      case 'error':
        _finishError(
          StateError(message['error'].toString()),
          StackTrace.fromString(message['stack'].toString()),
        );
    }
  }

  LogSearchResult _resultFromMap(Map<String, Object?> map) => LogSearchResult(
        startOffset: map['startOffset'] as int,
        endOffset: map['endOffset'] as int,
        lineNumber: map['lineNumber'] as int,
        snippet: map['snippet'] as String,
        level:
            map['level'] == null ? null : LogLevel.values[map['level'] as int],
        tag: map['tag'] as String?,
        timestamp: map['timestamp'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(map['timestamp'] as int),
      );

  void _finish(LogSearchOutcome outcome) {
    if (_finished) {
      return;
    }
    _finished = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _port = null;
    unawaited(_progress.close());
    unawaited(_results.close());
    _done.complete(outcome);
  }

  void _finishError(Object error, StackTrace stackTrace) {
    if (_finished) {
      return;
    }
    _finished = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _port = null;
    unawaited(_progress.close());
    unawaited(_results.close());
    _done.completeError(error, stackTrace);
  }
}

/// Spawns one bounded-memory isolate per search operation.
final class LogSearchService {
  LogSearchTask search(String filePath, LogSearchQuery query) {
    if (query.useRegex) {
      RegExp(query.text, caseSensitive: query.caseSensitive);
    }
    return LogSearchTask._(<String, Object?>{
      'filePath': filePath,
      'text': query.text,
      'caseSensitive': query.caseSensitive,
      'useRegex': query.useRegex,
      'levels': query.levels.map((level) => level.index).toList(),
      'tags': query.tags.toList(),
      'startTime': query.startTime?.microsecondsSinceEpoch,
      'endTime': query.endTime?.microsecondsSinceEpoch,
      'maximumResults': query.maximumResults,
      'maximumSnippetCharacters': query.maximumSnippetCharacters,
    });
  }
}

Future<void> _searchWorker(Map<String, Object?> request) async {
  final sendPort = request['sendPort'] as SendPort;
  RandomAccessFile? file;
  try {
    file = await File(request['filePath'] as String).open();
    final totalBytes = await file.length();
    const chunkSize = 128 * 1024;
    var position = 0;
    var carry = <int>[];
    var lineNumber = 0;
    var resultCount = 0;
    var truncated = false;
    final matcher = _WorkerMatcher(request);

    Future<bool> processLine(List<int> bytes, int start, int end) async {
      lineNumber += 1;
      if (bytes.isNotEmpty && bytes.last == 0x0D) {
        bytes = bytes.sublist(0, bytes.length - 1);
      }
      final raw = utf8.decode(bytes, allowMalformed: true);
      final parsed = const LogLineParser().parse(raw);
      if (!matcher.matches(raw, parsed)) {
        return false;
      }
      if (resultCount >= matcher.maximumResults) {
        truncated = true;
        return true;
      }
      resultCount += 1;
      final snippet = raw.length <= matcher.maximumSnippetCharacters
          ? raw
          : '${raw.substring(0, matcher.maximumSnippetCharacters)}…';
      sendPort.send(<String, Object?>{
        'type': 'result',
        'startOffset': start,
        'endOffset': end,
        'lineNumber': lineNumber,
        'snippet': snippet,
        'level': parsed.level?.index,
        'tag': parsed.tag,
        'timestamp': parsed.timestamp?.microsecondsSinceEpoch,
      });
      return false;
    }

    scan:
    while (position < totalBytes) {
      await file.setPosition(position);
      final next = await file.read(min(chunkSize, totalBytes - position));
      final baseOffset = position - carry.length;
      final data = <int>[...carry, ...next];
      var lineStart = 0;
      for (var index = 0; index < data.length; index += 1) {
        if (data[index] != 0x0A) {
          continue;
        }
        final shouldStop = await processLine(
          data.sublist(lineStart, index),
          baseOffset + lineStart,
          baseOffset + index + 1,
        );
        lineStart = index + 1;
        if (shouldStop) {
          break scan;
        }
      }
      carry = data.sublist(lineStart);
      position += next.length;
      sendPort.send(<String, Object?>{
        'type': 'progress',
        'value': totalBytes == 0 ? 1.0 : position / totalBytes,
      });
    }
    if (!truncated && carry.isNotEmpty) {
      await processLine(carry, totalBytes - carry.length, totalBytes);
    }
    sendPort.send(<String, Object?>{
      'type': 'done',
      'truncated': truncated,
    });
  } catch (error, stackTrace) {
    sendPort.send(<String, Object?>{
      'type': 'error',
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
  } finally {
    await file?.close();
  }
}

final class _WorkerMatcher {
  _WorkerMatcher(Map<String, Object?> request)
      : text = request['text'] as String,
        caseSensitive = request['caseSensitive'] as bool,
        useRegex = request['useRegex'] as bool,
        levels = (request['levels'] as List).cast<int>().toSet(),
        tags = (request['tags'] as List).cast<String>().toSet(),
        startTime = request['startTime'] as int?,
        endTime = request['endTime'] as int?,
        maximumResults = request['maximumResults'] as int,
        maximumSnippetCharacters = request['maximumSnippetCharacters'] as int {
    if (useRegex) {
      regex = RegExp(text, caseSensitive: caseSensitive);
    }
  }

  final String text;
  final bool caseSensitive;
  final bool useRegex;
  final Set<int> levels;
  final Set<String> tags;
  final int? startTime;
  final int? endTime;
  final int maximumResults;
  final int maximumSnippetCharacters;
  RegExp? regex;

  bool matches(String raw, ParsedLogLine parsed) {
    if (levels.isNotEmpty &&
        (parsed.level == null || !levels.contains(parsed.level!.index))) {
      return false;
    }
    if (tags.isNotEmpty && (parsed.tag == null || !tags.contains(parsed.tag))) {
      return false;
    }
    final timestamp = parsed.timestamp?.microsecondsSinceEpoch;
    if (startTime != null && (timestamp == null || timestamp < startTime!)) {
      return false;
    }
    if (endTime != null && (timestamp == null || timestamp > endTime!)) {
      return false;
    }
    if (text.isEmpty) {
      return true;
    }
    if (useRegex) {
      return regex!.hasMatch(raw);
    }
    if (caseSensitive) {
      return raw.contains(text);
    }
    return raw.toLowerCase().contains(text.toLowerCase());
  }
}
