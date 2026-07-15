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
    );
    _queue = SerialLogQueue<LogEntry>(
      capacity: config.queueCapacity,
      overflowPolicy: config.overflowPolicy,
      priorityOf: (entry) => entry.level.index,
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
    final entry = LogEntry(
      timestamp: _clock(),
      level: level,
      message: _truncateMessage(message),
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      fields: Map.unmodifiable(fields),
      caller: _callerResolver.resolve(callerStack),
      sessionId: sessionId,
      sequence: ++_sequence,
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

  Object? _truncateMessage(Object? message) {
    final rendered = _serializer.serialize(message).render();
    final bytes = utf8.encode(rendered);
    if (bytes.length <= config.maxEntryBytes) {
      return message;
    }
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
