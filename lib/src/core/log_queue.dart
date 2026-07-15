import 'dart:async';
import 'dart:collection';

import '../model/log_level.dart';

typedef QueuePriority<T> = int Function(T value);
typedef QueueHandler<T> = Future<void> Function(T value);
typedef QueueErrorHandler = void Function(Object error, StackTrace stackTrace);

/// A bounded, single-consumer asynchronous queue.
final class SerialLogQueue<T> {
  SerialLogQueue({
    required this.capacity,
    required this.overflowPolicy,
    required this.priorityOf,
    required this.handler,
    QueueErrorHandler? onError,
  })  : assert(capacity > 0),
        _onError = onError;

  final int capacity;
  final LogQueueOverflowPolicy overflowPolicy;
  final QueuePriority<T> priorityOf;
  final QueueHandler<T> handler;
  final QueueErrorHandler? _onError;
  final Queue<T> _pending = Queue<T>();

  bool _accepting = true;
  bool _draining = false;
  Completer<void>? _idleCompleter;
  int _droppedCount = 0;

  int get droppedCount => _droppedCount;

  bool get isClosed => !_accepting;

  bool enqueue(T value) {
    if (!_accepting) {
      return false;
    }
    if (_pending.length >= capacity && !_makeRoom(value)) {
      _droppedCount += 1;
      return false;
    }
    _pending.addLast(value);
    _startDrain();
    return true;
  }

  int takeDroppedCount() {
    final value = _droppedCount;
    _droppedCount = 0;
    return value;
  }

  Future<void> flush() =>
      _draining ? _idleCompleter!.future : Future<void>.value();

  Future<void> close() {
    _accepting = false;
    return flush();
  }

  bool _makeRoom(T incoming) {
    if (overflowPolicy == LogQueueOverflowPolicy.dropNewest) {
      return false;
    }
    T? lowest;
    var lowestPriority = 1 << 62;
    for (final item in _pending) {
      final priority = priorityOf(item);
      if (priority < lowestPriority) {
        lowest = item;
        lowestPriority = priority;
      }
    }
    if (lowest == null || priorityOf(incoming) <= lowestPriority) {
      return false;
    }
    _pending.remove(lowest);
    _droppedCount += 1;
    return true;
  }

  void _startDrain() {
    if (_draining) {
      return;
    }
    _draining = true;
    _idleCompleter = Completer<void>();
    scheduleMicrotask(_drain);
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final item = _pending.removeFirst();
      try {
        await handler(item);
      } catch (error, stackTrace) {
        _onError?.call(error, stackTrace);
      }
    }
    _draining = false;
    _idleCompleter?.complete();
    _idleCompleter = null;
    if (_pending.isNotEmpty) {
      _startDrain();
    }
  }
}
