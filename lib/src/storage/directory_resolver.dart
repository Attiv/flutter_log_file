import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../model/log_config.dart';

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

/// Resolves the configured directory or an App Support `logs` child.
final class DirectoryResolver {
  DirectoryResolver(
    this._config, {
    SupportDirectoryProvider getSupportDirectory =
        getApplicationSupportDirectory,
  }) : _getSupportDirectory = getSupportDirectory;

  final LogConfig _config;
  final SupportDirectoryProvider _getSupportDirectory;

  Future<Directory> resolve() async {
    try {
      final String target;
      if (_config.directoryPath != null) {
        target = _config.directoryPath!;
      } else if (_config.directoryResolver != null) {
        target = await _config.directoryResolver!();
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
