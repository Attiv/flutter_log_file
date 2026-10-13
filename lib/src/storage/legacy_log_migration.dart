import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../model/log_config.dart';
import '../model/log_level.dart';
import 'file_name_policy.dart';

/// Migrate only files owned by this configuration, without overwriting logs.
Future<void> migrateLegacyLogs(
  Directory source,
  Directory destination,
  LogConfig config,
) async {
  if (!await source.exists()) return;
  await destination.create(recursive: true);
  if (path.equals(await source.resolveSymbolicLinks(),
      await destination.resolveSymbolicLinks())) {
    return;
  }
  final policy = FileNamePolicy(config);
  await for (final entity in source.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = path.basename(entity.path);
    final parsed = policy.parse(name);
    if (parsed == null) continue;
    var target = File(path.join(destination.path, name));
    var part = parsed.part;
    var date = parsed.date ?? DateTime.now();
    if (config.timeZone == LogTimeZone.utc) {
      date = DateTime.utc(date.year, date.month, date.day);
    }
    while (await target.exists()) {
      if (await entity.length() == await target.length() &&
          await sha256.bind(entity.openRead()).first ==
              await sha256.bind(target.openRead()).first) {
        // Retry after a completed copy without creating a duplicate.
        break;
      }
      target = File(
          path.join(destination.path, policy.fileName(date, part: ++part)));
    }
    if (!await target.exists()) {
      final temporary = File('${target.path}.migrating');
      await entity.copy(temporary.path);
      await temporary.setLastModified(await entity.lastModified());
      await temporary.rename(target.path);
    }
    await entity.delete();
  }
}
