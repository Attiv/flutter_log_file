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
    final extension = RegExp.escape(_normalizedExtension);
    final stemPattern =
        _config.splitByDay ? _dailyStemPattern() : RegExp.escape(_renderStem());
    _ownedPattern = RegExp(
      '^$stemPattern(?:\\.(\\d+))?\\.$extension\$',
    );
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
      return '${_renderStem()}$suffix.$_normalizedExtension';
    }
    final time = switch (_config.timeZone) {
      LogTimeZone.local => timestamp.toLocal(),
      LogTimeZone.utc => timestamp.toUtc(),
    };
    final day = DateFormat(_config.fileDatePattern).format(time);
    return '${_renderStem(date: day)}$suffix.$_normalizedExtension';
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
      final date = _parseDate(match.group(1)!);
      return ParsedLogFileName(
        date: date,
        part: int.tryParse(match.group(2) ?? '') ?? 0,
      );
    } on FormatException {
      return null;
    }
  }

  String _renderStem({String? date}) => _config.fileNamePattern
      .replaceAll('{prefix}', _config.filePrefix)
      .replaceAll('{date}', date ?? '');

  String _dailyStemPattern() {
    final segments = _config.fileNamePattern.split('{date}');
    final before = segments.first.replaceAll('{prefix}', _config.filePrefix);
    final after = segments.last.replaceAll('{prefix}', _config.filePrefix);
    return '${RegExp.escape(before)}(.+?)${RegExp.escape(after)}';
  }

  DateTime _parseDate(String value) {
    if (_config.fileDatePattern == 'yyyyMMdd' &&
        RegExp(r'^\d{8}$').hasMatch(value)) {
      final year = int.parse(value.substring(0, 4));
      final month = int.parse(value.substring(4, 6));
      final day = int.parse(value.substring(6, 8));
      final parsed = DateTime(year, month, day);
      if (parsed.year == year && parsed.month == month && parsed.day == day) {
        return parsed;
      }
      throw const FormatException('Invalid yyyyMMdd date');
    }
    return DateFormat(_config.fileDatePattern).parseStrict(value);
  }
}
