import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../model/log_config.dart';
import 'legacy_log_migration.dart';

typedef SupportDirectoryProvider = Future<Directory> Function();

/// A typed failure emitted while resolving or creating the log directory.
final class LogDirectoryException implements Exception {
  const LogDirectoryException(this.message, this.cause, this.stackTrace);

  final String message;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'LogDirectoryException: $message ($cause)';
}

/// Resolves custom storage, Android external files, or App Support/logs.
final class DirectoryResolver {
  DirectoryResolver(
    this._config, {
    SupportDirectoryProvider getSupportDirectory =
        getApplicationSupportDirectory,
    Future<Directory?> Function() getExternalDirectory =
        getExternalStorageDirectory,
    bool? isAndroid,
    this.onMigrationError,
  })  : _getSupportDirectory = getSupportDirectory,
        _getExternalDirectory = getExternalDirectory,
        _isAndroid = isAndroid ?? Platform.isAndroid;

  final LogConfig _config;
  final SupportDirectoryProvider _getSupportDirectory;
  final Future<Directory?> Function() _getExternalDirectory;
  final bool _isAndroid;
  final void Function(Object error, StackTrace stack)? onMigrationError;

  Future<Directory> resolve() async {
    try {
      final String target;
      if (_config.directoryPath != null) {
        target = _config.directoryPath!;
      } else if (_config.directoryResolver != null) {
        target = await _config.directoryResolver!();
      } else if (_isAndroid && _config.useExternalStorageOnAndroid) {
        final external = await _getExternalDirectory();
        if (external == null) {
          throw const FileSystemException(
              'External app files directory unavailable');
        }
        await external.create(recursive: true);
        try {
          final support = await _getSupportDirectory();
          await migrateLegacyLogs(
            Directory(path.join(support.path, 'logs')),
            external,
            _config,
          );
        } catch (error, stack) {
          // Keep logging externally even when an old file cannot be migrated.
          onMigrationError?.call(error, stack);
        }
        target = external.path;
      } else {
        final support = await _getSupportDirectory();
        target = path.join(support.path, 'logs');
      }
      if (target.trim().isEmpty) {
        throw ArgumentError.value(target, 'directory', 'must not be empty');
      }
      final directory = Directory(target);
      await directory.create(recursive: true);
      return directory;
    } catch (error, stackTrace) {
      if (error is LogDirectoryException) {
        rethrow;
      }
      throw LogDirectoryException(
        'Unable to prepare the VLog directory',
        error,
        stackTrace,
      );
    }
  }
}
