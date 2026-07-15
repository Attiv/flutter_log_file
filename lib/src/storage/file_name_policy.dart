import 'package:intl/intl.dart';

import '../model/log_config.dart';
import '../model/log_level.dart';

/// Parsed components of a file name owned by VLog.
final class ParsedLogFileName {
  const ParsedLogFileName({required this.part, this.date});

  final DateTime? date;
  final int part;
}

/// Generates and strictly recognizes files created by one [LogConfig].
final class FileNamePolicy {
  FileNamePolicy(this._config) {
    final prefix = RegExp.escape(_config.filePrefix);
    final extension = RegExp.escape(_normalizedExtension);
    _ownedPattern = _config.splitByDay
        ? RegExp('^${prefix}_(.+?)(?:\\.(\\d+))?\\.$extension\$')
        : RegExp('^$prefix(?:\\.(\\d+))?\\.$extension\$');
  }

  final LogConfig _config;
  late final RegExp _ownedPattern;

  String get _normalizedExtension =>
      _config.fileExtension.replaceFirst(RegExp(r'^\.+'), '');

  String fileName(DateTime timestamp, {int part = 0}) {
    if (part < 0) {
      throw ArgumentError.value(part, 'part', 'must be >= 0');
    }
    final suffix = part == 0 ? '' : '.$part';
    if (!_config.splitByDay) {
      return '${_config.filePrefix}$suffix.$_normalizedExtension';
    }
    final time = switch (_config.timeZone) {
      LogTimeZone.local => timestamp.toLocal(),
      LogTimeZone.utc => timestamp.toUtc(),
    };
    final day = DateFormat(_config.fileDatePattern).format(time);
    return '${_config.filePrefix}_$day$suffix.$_normalizedExtension';
  }

  bool matches(String fileName) => parse(fileName) != null;

  ParsedLogFileName? parse(String fileName) {
    final match = _ownedPattern.firstMatch(fileName);
    if (match == null) {
      return null;
    }
    if (!_config.splitByDay) {
      return ParsedLogFileName(part: int.tryParse(match.group(1) ?? '') ?? 0);
    }
    try {
      final date = DateFormat(
        _config.fileDatePattern,
      ).parseStrict(match.group(1)!);
      return ParsedLogFileName(
        date: date,
        part: int.tryParse(match.group(2) ?? '') ?? 0,
      );
    } on FormatException {
      return null;
    }
  }
}
