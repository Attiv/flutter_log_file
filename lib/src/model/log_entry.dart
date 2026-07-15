import '../format/caller_resolver.dart';
import 'log_level.dart';

/// Immutable data captured at the point where a log call is made.
final class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    required this.caller,
    required this.sessionId,
    required this.sequence,
    this.tag,
    this.error,
    this.stackTrace,
    this.fields = const {},
    this.isInternal = false,
    this.estimatedBytes = 0,
  });

  final DateTime timestamp;
  final LogLevel level;
  final Object? message;
  final String? tag;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> fields;
  final CallerLocation caller;
  final String sessionId;
  final int sequence;
  final bool isInternal;
  final int estimatedBytes;
}
