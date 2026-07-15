/// Metadata for a log file managed by VLog.
final class LogFileInfo {
  const LogFileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.part,
    this.date,
    this.isActive = false,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime? date;
  final int part;
  final bool isActive;
}
