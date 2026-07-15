import '../model/log_level.dart';

/// Best-effort structured representation of one physical log line.
final class ParsedLogLine {
  const ParsedLogLine({
    required this.raw,
    required this.message,
    this.timestamp,
    this.level,
    this.tag,
    this.sessionId,
    this.sequence,
    this.caller,
  });

  final String raw;
  final String message;
  final DateTime? timestamp;
  final LogLevel? level;
  final String? tag;
  final String? sessionId;
  final int? sequence;
  final String? caller;
}

/// Parses VLog's default text format while tolerating unstructured files.
final class LogLineParser {
  const LogLineParser();

  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;]*m');
  static final RegExp _line = RegExp(
    r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?) '
    r'\[(VERBOSE|DEBUG|INFO|WARN|ERROR|FATAL)\](.*?) \| (.*)$',
  );
  static final RegExp _bracket = RegExp(r'\[([^\]]+)\]');
  static final RegExp _caller = RegExp(r'(?:^|\s)(\S+:\d+)$');

  ParsedLogLine parse(String input) {
    final raw = input.replaceAll(_ansi, '').replaceFirst(RegExp(r'\r$'), '');
    final match = _line.firstMatch(raw);
    if (match == null) {
      return ParsedLogLine(raw: raw, message: raw);
    }
    final metadata = match.group(3)!.trim();
    String? tag;
    String? sessionId;
    int? sequence;
    for (final bracket in _bracket.allMatches(metadata)) {
      final value = bracket.group(1)!;
      if (value.startsWith('S:')) {
        sessionId = value.substring(2);
      } else if (value.startsWith('#')) {
        sequence = int.tryParse(value.substring(1));
      } else {
        tag ??= value;
      }
    }
    final caller = _caller.firstMatch(metadata)?.group(1);
    return ParsedLogLine(
      raw: raw,
      message: match.group(4)!,
      timestamp: DateTime.tryParse(match.group(1)!.replaceFirst(' ', 'T')),
      level: _parseLevel(match.group(2)!),
      tag: tag,
      sessionId: sessionId,
      sequence: sequence,
      caller: caller,
    );
  }

  LogLevel _parseLevel(String label) => switch (label) {
        'VERBOSE' => LogLevel.verbose,
        'DEBUG' => LogLevel.debug,
        'INFO' => LogLevel.info,
        'WARN' => LogLevel.warning,
        'ERROR' => LogLevel.error,
        'FATAL' => LogLevel.fatal,
        _ => LogLevel.info,
      };
}
