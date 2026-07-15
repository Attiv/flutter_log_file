import '../model/log_entry.dart';

/// Destination for ordered log events.
abstract interface class LogSink {
  Future<void> write(LogEntry entry);

  Future<void> flush();

  Future<void> close();
}
