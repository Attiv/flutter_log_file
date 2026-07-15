import 'dart:async';
import 'dart:collection';

import '../model/log_level.dart';

typedef QueuePriority<T> = int Function(T value);
typedef QueueWeight<T> = int Function(T value);
typedef QueueHandler<T> = Future<void> Function(T value);
typedef QueueErrorHandler = void Function(Object error, StackTrace stackTrace);

/// A bounded, single-consumer asynchronous queue.
final class SerialLogQueue<T> {
  SerialLogQueue({
    required this.capacity,
    required this.overflowPolicy,
    required this.priorityOf,
    required this.handler,
    this.maximumWeight,
    QueueWeight<T>? weightOf,
    QueueErrorHandler? onError,
  })  : assert(capacity > 0),
        assert(maximumWeight == null || maximumWeight > 0),
        assert(maximumWeight == null || weightOf != null),
        _weightOf = weightOf,
        _onError = onError;

  final int capacity;
  final LogQueueOverflowPolicy overflowPolicy;
  final QueuePriority<T> priorityOf;
  final int? maximumWeight;
  final QueueWeight<T>? _weightOf;
  final QueueHandler<T> handler;
  final QueueErrorHandler? _onError;
  final Queue<_QueuedValue<T>> _pending = Queue<_QueuedValue<T>>();

  bool _accepting = true;
  bool _draining = false;
  Completer<void>? _idleCompleter;
  int _droppedCount = 0;
  int _retainedWeight = 0;

  int get droppedCount => _droppedCount;
  int get retainedWeight => _retainedWeight;

  bool get isClosed => !_accepting;

  bool enqueue(T value) {
    if (!_accepting) {
      return false;
    }
    final weight = _itemWeight(value);
    final weightLimit = maximumWeight;
    if (weightLimit != null && weight > weightLimit) {
      _droppedCount += 1;
      return false;
    }
    while (_pending.length >= capacity ||
        (weightLimit != null && _retainedWeight + weight > weightLimit)) {
      if (!_makeRoom(value)) {
        _droppedCount += 1;
        return false;
      }
    }
    _pending.addLast(_QueuedValue<T>(value, weight));
    _retainedWeight += weight;
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
    _QueuedValue<T>? lowest;
    var lowestPriority = 1 << 62;
    for (final item in _pending) {
      final priority = priorityOf(item.value);
      if (priority < lowestPriority) {
        lowest = item;
        lowestPriority = priority;
      }
    }
    if (lowest == null || priorityOf(incoming) <= lowestPriority) {
      return false;
    }
    _pending.remove(lowest);
    _retainedWeight -= lowest.weight;
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
        await handler(item.value);
      } catch (error, stackTrace) {
        _onError?.call(error, stackTrace);
      } finally {
        _retainedWeight -= item.weight;
      }
    }
    _draining = false;
    _idleCompleter?.complete();
    _idleCompleter = null;
    if (_pending.isNotEmpty) {
      _startDrain();
    }
  }

  int _itemWeight(T value) {
    final weight = _weightOf?.call(value) ?? 0;
    if (weight < 0) {
      throw ArgumentError.value(weight, 'weight', 'must be >= 0');
    }
    return weight;
  }
}

final class _QueuedValue<T> {
  const _QueuedValue(this.value, this.weight);

  final T value;
  final int weight;
}
