import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../format/caller_resolver.dart';
import '../format/message_serializer.dart';
import '../model/log_config.dart';
import '../model/log_entry.dart';
import '../model/log_level.dart';
import '../sink/log_sink.dart';
import 'log_queue.dart';

typedef InternalErrorReporter = void Function(
    Object error, StackTrace stackTrace);

/// Coordinates capture, queueing and isolated sink delivery for one session.
final class LogController {
  LogController({
    required this.config,
    required List<LogSink> sinks,
    DateTime Function()? clock,
    CallerResolver callerResolver = const CallerResolver(),
    ObjectEncoderRegistry? registry,
    InternalErrorReporter? internalErrorReporter,
    String? sessionId,
  })  : _sinks = List.unmodifiable(sinks),
        _clock = clock ?? DateTime.now,
        _callerResolver = callerResolver,
        registry = registry ?? ObjectEncoderRegistry(),
        _internalErrorReporter = internalErrorReporter ?? _defaultReport,
        sessionId = sessionId ?? _newSessionId() {
    _serializer = MessageSerializer(
      registry: this.registry,
      redactedKeys: config.redactedKeys,
      redactors: config.redactors,
      maximumNodes: max(64, min(4096, config.maxEntryBytes ~/ 8)),
      maximumCharacters: config.maxEntryBytes,
    );
    _queue = SerialLogQueue<LogEntry>(
      capacity: config.queueCapacity,
      maximumWeight: config.queueByteCapacity,
      overflowPolicy: config.overflowPolicy,
      priorityOf: (entry) => entry.level.index,
      weightOf: _entryWeight,
      handler: _process,
      onError: _internalErrorReporter,
    );
  }

  final LogConfig config;
  final List<LogSink> _sinks;
  final DateTime Function() _clock;
  final CallerResolver _callerResolver;
  final InternalErrorReporter _internalErrorReporter;
  final ObjectEncoderRegistry registry;
  final String sessionId;
  late final MessageSerializer _serializer;
  late final SerialLogQueue<LogEntry> _queue;

  Timer? _flushTimer;
  int _sequence = 0;
  bool _started = false;
  bool _closed = false;

  int get droppedCount => _queue.droppedCount;

  Future<void> start() async {
    if (_started || _closed) {
      return;
    }
    _started = true;
    _queue.enqueue(
      LogEntry(
        timestamp: _clock(),
        level: LogLevel.info,
        message: '--- VLog session $sessionId started ---',
        caller: CallerLocation.unknown,
        sessionId: sessionId,
        sequence: 0,
        isInternal: true,
      ),
    );
    if (config.flushInterval > Duration.zero) {
      _flushTimer = Timer.periodic(config.flushInterval, (_) {
        unawaited(flush());
      });
    }
  }

  bool log(
    LogLevel level,
    Object? message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
    required StackTrace callerStack,
  }) {
    if (_closed || !level.isAtLeast(config.minimumLevel)) {
      return false;
    }
    final messageSnapshot = _snapshotMessage(message);
    final fieldsSnapshot = _snapshotFields(fields);
    final errorSnapshot =
        error == null ? null : _snapshotText(error.toString());
    final stackSnapshot = stackTrace == null
        ? null
        : StackTrace.fromString(_snapshotText(stackTrace.toString()));
    final tagSnapshot = tag == null ? null : _snapshotText(tag);
    final entry = LogEntry(
      timestamp: _clock(),
      level: level,
      message: messageSnapshot,
      tag: tagSnapshot,
      error: errorSnapshot,
      stackTrace: stackSnapshot,
      fields: fieldsSnapshot,
      caller: _callerResolver.resolve(callerStack),
      sessionId: sessionId,
      sequence: ++_sequence,
      estimatedBytes: _estimateEntryBytes(
        messageSnapshot,
        fieldsSnapshot,
        tagSnapshot,
        errorSnapshot,
        stackSnapshot,
      ),
    );
    return _queue.enqueue(entry);
  }

  Future<void> flush() async {
    await _queue.flush();
    await _forEachSink((sink) => sink.flush());
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _queue.close();
    await _forEachSink((sink) => sink.flush());
    await _forEachSink((sink) => sink.close());
  }

  Future<void> _process(LogEntry entry) async {
    final dropped = _queue.takeDroppedCount();
    if (dropped > 0) {
      await _writeToSinks(
        LogEntry(
          timestamp: _clock(),
          level: LogLevel.warning,
          message: 'VLog dropped $dropped queued log entries',
          caller: CallerLocation.unknown,
          sessionId: sessionId,
          sequence: 0,
          isInternal: true,
        ),
      );
    }
    await _writeToSinks(entry);
    if (entry.level.isAtLeast(config.flushOnLevel)) {
      await _forEachSink((sink) => sink.flush());
    }
  }

  Future<void> _writeToSinks(LogEntry entry) =>
      _forEachSink((sink) => sink.write(entry));

  Future<void> _forEachSink(
    Future<void> Function(LogSink sink) operation,
  ) async {
    for (final sink in _sinks) {
      try {
        await operation(sink);
      } catch (error, stackTrace) {
        _internalErrorReporter(error, stackTrace);
      }
    }
  }

  Object? _snapshotMessage(Object? message) {
    final serialized = _serializer.serialize(message);
    final rendered = serialized.render();
    final bytes = utf8.encode(rendered);
    if (bytes.length <= config.maxEntryBytes) {
      return serialized.value;
    }
    return _truncateRendered(rendered, bytes);
  }

  Map<String, Object?> _snapshotFields(Map<String, Object?> fields) {
    if (fields.isEmpty) {
      return const {};
    }
    final serialized = _serializer.serialize(fields);
    final rendered = serialized.render();
    final bytes = utf8.encode(rendered);
    final value = serialized.value;
    if (bytes.length <= config.maxEntryBytes && value is Map) {
      return Map.unmodifiable(value.cast<String, Object?>());
    }
    return Map.unmodifiable({
      '_truncated': 'fields truncated from ${bytes.length}B',
    });
  }

  String _snapshotText(String value) {
    return _boundTextUtf8(value, config.maxEntryBytes);
  }

  String _boundTextUtf8(String value, int maximumBytes) {
    var used = 0;
    var fits = true;
    for (final rune in value.runes) {
      used += _runeUtf8Width(rune);
      if (used > maximumBytes) {
        fits = false;
        break;
      }
    }
    if (fits) return value;

    final marker = '…[truncated:${value.length} chars]';
    final budget = max(0, maximumBytes - utf8.encode(marker).length);
    final buffer = StringBuffer();
    used = 0;
    for (final rune in value.runes) {
      final width = _runeUtf8Width(rune);
      if (used + width > budget) break;
      buffer.writeCharCode(rune);
      used += width;
    }
    return '$buffer$marker';
  }

  int _runeUtf8Width(int rune) {
    if (rune <= 0x7F) return 1;
    if (rune <= 0x7FF) return 2;
    if (rune <= 0xFFFF) return 3;
    return 4;
  }

  String _truncateRendered(String rendered, List<int> bytes) {
    var marker = '…[truncated:${bytes.length}B]';
    var markerBytes = utf8.encode(marker);
    if (markerBytes.length >= config.maxEntryBytes) {
      marker = '[truncated]';
      markerBytes = utf8.encode(marker);
    }
    final prefixBudget = max(0, config.maxEntryBytes - markerBytes.length);
    var end = min(prefixBudget, bytes.length);
    String prefix = '';
    while (end >= 0) {
      try {
        prefix = utf8.decode(bytes.sublist(0, end));
        break;
      } on FormatException {
        end -= 1;
      }
    }
    return '$prefix$marker';
  }

  int _entryWeight(LogEntry entry) => entry.estimatedBytes > 0
      ? entry.estimatedBytes
      : _estimateEntryBytes(
          entry.message,
          entry.fields,
          entry.tag,
          entry.error,
          entry.stackTrace,
        );

  int _estimateEntryBytes(
    Object? message,
    Map<String, Object?> fields,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  ) {
    var bytes = 128;
    bytes += utf8.encode(_serializer.serialize(message).render()).length;
    if (fields.isNotEmpty) {
      bytes += utf8.encode(_serializer.serialize(fields).render()).length;
    }
    if (tag != null) bytes += utf8.encode(tag).length;
    if (error != null) bytes += utf8.encode(error.toString()).length;
    if (stackTrace != null) {
      bytes += utf8.encode(stackTrace.toString()).length;
    }
    return max(1, bytes);
  }

  static String _newSessionId() => Random.secure()
      .nextInt(0x10000)
      .toRadixString(16)
      .padLeft(4, '0')
      .toUpperCase();

  static void _defaultReport(Object error, StackTrace stackTrace) {
    // Avoid VLog recursion while still making internal failures observable.
    // ignore: avoid_print
    print('VLog internal error: $error\n$stackTrace');
  }
}
