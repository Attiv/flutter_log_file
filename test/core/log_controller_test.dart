import 'dart:async';
import 'dart:convert';

import 'package:flutter_log_file/flutter_log_file.dart';
import 'package:flutter_log_file/src/core/log_controller.dart';
import 'package:flutter_log_file/src/model/log_entry.dart';
import 'package:flutter_log_file/src/sink/log_sink.dart';
import 'package:flutter_test/flutter_test.dart';

final class MemorySink implements LogSink {
  final entries = <LogEntry>[];
  int flushes = 0;
  int closes = 0;
  bool failWrites = false;

  @override
  Future<void> write(LogEntry entry) async {
    if (failWrites) {
      throw StateError('sink failed');
    }
    entries.add(entry);
  }

  @override
  Future<void> flush() async => flushes += 1;

  @override
  Future<void> close() async => closes += 1;
}

final class LargeApplicationObject {
  LargeApplicationObject(this.values);

  final List<int> values;

  @override
  String toString() => 'large-object';
}

final class BlockingSink implements LogSink {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<void> write(LogEntry entry) async {
    if (!started.isCompleted) {
      started.complete();
      await gate.future;
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

void main() {
  test('isolates sink failures and preserves sequence order', () async {
    final failed = MemorySink()..failWrites = true;
    final healthy = MemorySink();
    final internalErrors = <Object>[];
    final controller = LogController(
      config: LogConfig(flushInterval: Duration.zero),
      sinks: [failed, healthy],
      clock: () => DateTime(2026, 7, 15),
      internalErrorReporter: (error, _) => internalErrors.add(error),
      sessionId: 'TEST',
    );
    await controller.start();

    controller.log(LogLevel.info, 'one', callerStack: StackTrace.current);
    controller.log(LogLevel.warning, 'two', callerStack: StackTrace.current);
    await controller.flush();

    final userEntries = healthy.entries.where((entry) => !entry.isInternal);
    expect(userEntries.map((entry) => entry.sequence), [1, 2]);
    expect(userEntries.map((entry) => entry.message), ['one', 'two']);
    expect(internalErrors, isNotEmpty);
    await controller.close();
  });

  test('flush on error level flushes sinks after writing', () async {
    final sink = MemorySink();
    final controller = LogController(
      config: LogConfig(flushInterval: Duration.zero),
      sinks: [sink],
      sessionId: 'TEST',
    );
    await controller.start();

    controller.log(LogLevel.error, 'bad', callerStack: StackTrace.current);
    await controller.flush();

    expect(sink.flushes, greaterThanOrEqualTo(1));
    await controller.close();
  });

  test('truncates oversized message at a valid UTF8 boundary', () async {
    final sink = MemorySink();
    final controller = LogController(
      config: LogConfig(maxEntryBytes: 32, flushInterval: Duration.zero),
      sinks: [sink],
      sessionId: 'TEST',
    );
    await controller.start();

    controller.log(
      LogLevel.info,
      '一' * 100,
      callerStack: StackTrace.current,
    );
    await controller.flush();

    final message = sink.entries.last.message.toString();
    expect(message, contains('truncated'));
    expect(() => utf8.decode(utf8.encode(message)), returnsNormally);
    await controller.close();
  });

  test('flush and close are idempotent', () async {
    final sink = MemorySink();
    final controller = LogController(
      config: LogConfig(flushInterval: Duration.zero),
      sinks: [sink],
      sessionId: 'TEST',
    );
    await controller.start();

    await controller.flush();
    await controller.flush();
    await controller.close();
    await controller.close();

    expect(sink.closes, 1);
  });

  test('snapshots application objects before enqueueing', () async {
    final sink = MemorySink();
    final controller = LogController(
      config: LogConfig(flushInterval: Duration.zero),
      sinks: [sink],
      sessionId: 'TEST',
    );
    await controller.start();
    final object = LargeApplicationObject(List<int>.filled(100000, 7));
    final nestedValues = <int>[1, 2, 3];
    final fields = <String, Object?>{'values': nestedValues};

    controller.log(
      LogLevel.info,
      object,
      fields: fields,
      error: StateError('failed'),
      stackTrace: StackTrace.fromString('frame-1\nframe-2'),
      callerStack: StackTrace.current,
    );
    nestedValues.add(4);
    fields['later'] = true;
    await controller.flush();

    final entry = sink.entries.last;
    expect(entry.message, 'large-object');
    expect(identical(entry.message, object), isFalse);
    expect(entry.fields, {
      'values': [1, 2, 3],
    });
    expect(entry.error, 'Bad state: failed');
    expect(entry.stackTrace.toString(), 'frame-1\nframe-2');
    expect(entry.estimatedBytes, greaterThan(0));
    await controller.close();
  });

  test('queue byte capacity prevents retained log growth', () async {
    final sink = BlockingSink();
    final controller = LogController(
      config: LogConfig(
        queueCapacity: 1000,
        queueByteCapacity: 1024,
        maxEntryBytes: 512,
        flushInterval: Duration.zero,
      ),
      sinks: [sink],
      sessionId: 'TEST',
    );
    await controller.start();
    await sink.started.future;

    for (var index = 0; index < 100; index += 1) {
      controller.log(
        LogLevel.info,
        'x' * 400,
        callerStack: StackTrace.current,
      );
    }

    expect(controller.droppedCount, greaterThan(0));
    sink.gate.complete();
    await controller.flush();
    await controller.close();
  });
}
