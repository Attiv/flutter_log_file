import 'package:path/path.dart' as path;

/// Source location associated with a log invocation.
final class CallerLocation {
  const CallerLocation({
    required this.uri,
    required this.fileName,
    required this.line,
    required this.column,
  });

  static const unknown = CallerLocation(
    uri: '',
    fileName: 'unknown',
    line: 0,
    column: 0,
  );

  final String uri;
  final String fileName;
  final int line;
  final int column;

  bool get isKnown => line > 0 && fileName != 'unknown';

  @override
  bool operator ==(Object other) =>
      other is CallerLocation &&
      other.uri == uri &&
      other.fileName == fileName &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(uri, fileName, line, column);
}

/// Finds the first caller outside this package's implementation frames.
final class CallerResolver {
  const CallerResolver();

  static final RegExp _locationPattern = RegExp(
    r'(package:[^\s\)]+|file:[^\s\)]+|[A-Za-z]:[/\\][^\s\)]+):(\d+):(\d+)',
  );

  CallerLocation resolve(StackTrace stackTrace) {
    for (final frame in stackTrace.toString().split('\n')) {
      if (_isInternal(frame)) {
        continue;
      }
      final match = _locationPattern.firstMatch(frame);
      if (match == null) {
        continue;
      }
      final uri = match.group(1)!;
      final line = int.tryParse(match.group(2)!);
      final column = int.tryParse(match.group(3)!);
      if (line == null || column == null) {
        continue;
      }
      return CallerLocation(
        uri: uri,
        fileName: _basename(uri),
        line: line,
        column: column,
      );
    }
    return CallerLocation.unknown;
  }

  bool _isInternal(String frame) =>
      frame.contains('package:flutter_log_file/src/') ||
      frame.contains('/flutter_log_file/lib/src/');

  String _basename(String uri) {
    final normalized = uri.replaceAll('\\', '/');
    return path.posix.basename(normalized);
  }
}
