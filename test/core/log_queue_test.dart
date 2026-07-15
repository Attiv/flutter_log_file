import 'dart:async';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/core/log_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('executes asynchronous operations in enqueue order', () async {
    final handled = <int>[];
    final queue = SerialLogQueue<int>(
      capacity: 10,
      overflowPolicy: LogQueueOverflowPolicy.dropLowestLevel,
      priorityOf: (value) => value,
      handler: (value) async {
        await Future<void>.delayed(Duration(milliseconds: 3 - value));
        handled.add(value);
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    queue.enqueue(3);
    await queue.flush();

    expect(handled, [1, 2, 3]);
  });

  test('flush waits for the active handler', () async {
    final gate = Completer<void>();
    var finished = false;
    final queue = SerialLogQueue<int>(
      capacity: 2,
      overflowPolicy: LogQueueOverflowPolicy.dropNewest,
      priorityOf: (value) => value,
      handler: (_) async {
        await gate.future;
        finished = true;
      },
    );

    queue.enqueue(1);
    final flushing = queue.flush();
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    gate.complete();
    await flushing;
    expect(finished, isTrue);
  });

  test('default overflow preserves more severe queued values', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final handled = <int>[];
    final queue = SerialLogQueue<int>(
      capacity: 2,
      overflowPolicy: LogQueueOverflowPolicy.dropLowestLevel,
      priorityOf: (value) => value,
      handler: (value) async {
        if (value == 0) {
          started.complete();
          await gate.future;
        }
        handled.add(value);
      },
    );

    queue.enqueue(0);
    await started.future;
    queue.enqueue(1);
    queue.enqueue(2);
    expect(queue.enqueue(3), isTrue);
    expect(queue.droppedCount, 1);
    gate.complete();
    await queue.flush();

    expect(handled, [0, 2, 3]);
  });

  test('drop newest rejects an item when pending queue is full', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final queue = SerialLogQueue<int>(
      capacity: 1,
      overflowPolicy: LogQueueOverflowPolicy.dropNewest,
      priorityOf: (value) => value,
      handler: (value) async {
        if (value == 0) {
          started.complete();
          await gate.future;
        }
      },
    );

    queue.enqueue(0);
    await started.future;
    expect(queue.enqueue(1), isTrue);
    expect(queue.enqueue(2), isFalse);
    gate.complete();
    await queue.close();
    expect(queue.enqueue(3), isFalse);
  });

  test('retained weight includes the active item', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final handled = <int>[];
    final queue = SerialLogQueue<int>(
      capacity: 10,
      maximumWeight: 10,
      weightOf: (value) => value,
      overflowPolicy: LogQueueOverflowPolicy.dropNewest,
      priorityOf: (value) => value,
      handler: (value) async {
        if (value == 6) {
          started.complete();
          await gate.future;
        }
        handled.add(value);
      },
    );

    expect(queue.enqueue(6), isTrue);
    await started.future;
    expect(queue.enqueue(5), isFalse);
    expect(queue.enqueue(4), isTrue);
    gate.complete();
    await queue.flush();

    expect(handled, [6, 4]);
  });

  test('weight overflow drops the lowest priority pending item', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final handled = <int>[];
    final queue = SerialLogQueue<int>(
      capacity: 10,
      maximumWeight: 10,
      weightOf: (_) => 4,
      overflowPolicy: LogQueueOverflowPolicy.dropLowestLevel,
      priorityOf: (value) => value,
      handler: (value) async {
        if (value == 0) {
          started.complete();
          await gate.future;
        }
        handled.add(value);
      },
    );

    queue.enqueue(0);
    await started.future;
    queue.enqueue(1);
    expect(queue.enqueue(2), isTrue);
    expect(queue.droppedCount, 1);
    gate.complete();
    await queue.flush();

    expect(handled, [0, 2]);
  });
}
