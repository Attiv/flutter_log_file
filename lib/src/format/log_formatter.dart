import 'package:intl/intl.dart';

import '../model/log_config.dart';
import '../model/log_entry.dart';
import '../model/log_level.dart';
import 'message_serializer.dart';

enum LogOutputTarget { console, file }

/// Produces human-readable text lines for console and file sinks.
final class LogFormatter {
  LogFormatter(LogConfig config, {ObjectEncoderRegistry? registry})
      : _config = config,
        _serializer = MessageSerializer(
          registry: registry,
          redactedKeys: config.redactedKeys,
          redactors: config.redactors,
        );

  final LogConfig _config;
  final MessageSerializer _serializer;

  String format(LogEntry entry, {required LogOutputTarget target}) {
    final pretty = switch (target) {
      LogOutputTarget.console => _config.effectiveConsolePrettyJson,
      LogOutputTarget.file => _config.effectiveFilePrettyJson,
    };
    final payloadLines = <String>[
      ..._serializer
          .serialize(entry.message)
          .render(pretty: pretty)
          .split('\n'),
    ];

    if (_config.showFields && entry.fields.isNotEmpty) {
      final fields = _serializer.serialize(entry.fields).render(pretty: pretty);
      final fieldLines = fields.split('\n');
      payloadLines.add('fields=${fieldLines.first}');
      payloadLines.addAll(fieldLines.skip(1));
    }
    if (entry.error != null) {
      payloadLines.add('error: ${entry.error}');
    }
    if (entry.stackTrace != null) {
      final stackLines = entry.stackTrace.toString().trimRight().split('\n');
      if (stackLines.isNotEmpty) {
        payloadLines.add('stackTrace: ${stackLines.first}');
        payloadLines.addAll(stackLines.skip(1));
      }
    }

    final prefix = _prefix(entry);
    return payloadLines.map((payload) {
      final line = '$prefix | $payload';
      if (target == LogOutputTarget.console && _config.consoleUseColors) {
        return '${_ansiFor(entry.level)}$line\x1B[0m';
      }
      return line;
    }).join('\n');
  }

  String _prefix(LogEntry entry) {
    final timestamp = switch (_config.timeZone) {
      LogTimeZone.local => entry.timestamp.toLocal(),
      LogTimeZone.utc => entry.timestamp.toUtc(),
    };
    final parts = <String>[
      DateFormat(_config.timestampPattern).format(timestamp),
      '[${entry.level.label}]',
    ];
    final tag = entry.tag?.trim();
    if (_config.showTag && tag != null && tag.isNotEmpty) {
      parts.add('[$tag]');
    }
    if (_config.showSessionId) {
      parts.add('[S:${entry.sessionId}]');
    }
    if (_config.showSequence) {
      parts.add('[#${entry.sequence}]');
    }
    if (_config.showCaller) {
      parts.add('${entry.caller.fileName}:${entry.caller.line}');
    }
    return parts.join(' ');
  }

  String _ansiFor(LogLevel level) => switch (level) {
        LogLevel.verbose => '\x1B[90m',
        LogLevel.debug => '\x1B[36m',
        LogLevel.info => '\x1B[32m',
        LogLevel.warning => '\x1B[33m',
        LogLevel.error => '\x1B[31m',
        LogLevel.fatal => '\x1B[1;35m',
      };
}
