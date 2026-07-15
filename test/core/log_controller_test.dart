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
}
