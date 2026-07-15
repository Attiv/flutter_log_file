import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../model/log_config.dart';
import '../model/log_file_info.dart';
import 'file_name_policy.dart';

/// A successful append notification used by the live log viewer.
final class LogWriteNotification {
  const LogWriteNotification({
    required this.filePath,
    required this.startOffset,
    required this.endOffset,
    required this.text,
  });

  final String filePath;
  final int startOffset;
  final int endOffset;
  final String text;
}

/// Owns log files, rotation, retention and ordered UTF-8 appends.
final class LogFileManager {
  LogFileManager({
    required this.directory,
    required LogConfig config,
    DateTime Function()? clock,
  })  : _config = config,
        _clock = clock ?? DateTime.now,
        _namePolicy = FileNamePolicy(config);

  final Directory directory;
  final LogConfig _config;
  final DateTime Function() _clock;
  final FileNamePolicy _namePolicy;
  final StreamController<LogWriteNotification> _writes =
      StreamController<LogWriteNotification>.broadcast(sync: true);

  Future<void> _tail = Future<void>.value();
  RandomAccessFile? _handle;
  File? _activeFile;
  String? _activeDateName;
  int _part = 0;
  int _length = 0;
  bool _initialized = false;
  bool _closed = false;

  Stream<LogWriteNotification> get writes => _writes.stream;

  String? get activePath => _activeFile?.path;

  Future<void> initialize() => _serialized(_initializeInternal);

  Future<LogWriteNotification> write(String text) =>
      _serialized(() => _writeInternal(text));

  Future<void> flush() => _serialized(() async {
        await _handle?.flush();
      });

  Future<List<LogFileInfo>> listFiles() => _serialized(_listFilesInternal);

  Future<void> cleanup() => _serialized(_cleanupInternal);

  Future<void> clear() => _serialized(() async {
        await _closeHandle();
        await for (final entity in directory.list()) {
          if (entity is File &&
              _namePolicy.matches(path.basename(entity.path))) {
            try {
              await entity.delete();
            } on FileSystemException {
              // A concurrently removed file is already clear.
            }
          }
        }
        _activeFile = null;
        _activeDateName = null;
        _part = 0;
        _length = 0;
      });

  Future<void> close() {
    if (_closed) {
      return _tail;
    }
    return _serialized(() async {
      if (_closed) {
        return;
      }
      await _closeHandle();
      _closed = true;
      await _writes.close();
    }, allowClosed: true);
  }

  Future<T> _serialized<T>(
    Future<T> Function() action, {
    bool allowClosed = false,
  }) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      if (_closed && !allowClosed) {
        completer.completeError(StateError('LogFileManager is closed'));
        return;
      }
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _initializeInternal() async {
    if (_initialized) {
      return;
    }
    await directory.create(recursive: true);
    await _cleanupInternal();
    await _selectActiveFor(_clock());
    _initialized = true;
  }

  Future<LogWriteNotification> _writeInternal(String text) async {
    await _initializeInternal();
    final now = _clock();
    final expectedDateName = _namePolicy.fileName(now);
    if (_config.splitByDay && _activeDateName != expectedDateName) {
      await _closeHandle();
      await _selectActiveFor(now);
    }

    var normalized = text;
    if (!normalized.endsWith('\n')) {
      normalized = '$normalized\n';
    }
    final bytes = utf8.encode(normalized);
    await _ensureOpen(now);
    if (_length > 0 && _length + bytes.length > _config.maxFileSizeBytes) {
      await _rotateToNextPart(now);
    }

    final filePath = _activeFile!.path;
    final startOffset = _length;
    await _handle!.writeFrom(bytes);
    _length += bytes.length;
    final notification = LogWriteNotification(
      filePath: filePath,
      startOffset: startOffset,
      endOffset: _length,
      text: normalized,
    );
    _writes.add(notification);
    return notification;
  }

  Future<void> _ensureOpen(DateTime now) async {
    final active = _activeFile;
    if (_handle != null && active != null && await active.exists()) {
      return;
    }
    await _closeHandle();
    _activeFile ??= File(
      path.join(directory.path, _namePolicy.fileName(now, part: _part)),
    );
    await _activeFile!.parent.create(recursive: true);
    _handle = await _activeFile!.open(mode: FileMode.append);
    _length = await _activeFile!.length();
  }

  Future<void> _rotateToNextPart(DateTime now) async {
    await _closeHandle();
    do {
      _part += 1;
      _activeFile = File(
        path.join(directory.path, _namePolicy.fileName(now, part: _part)),
      );
      _length = await _activeFile!.exists() ? await _activeFile!.length() : 0;
    } while (_length >= _config.maxFileSizeBytes);
    await _ensureOpen(now);
  }

  Future<void> _selectActiveFor(DateTime now) async {
    final dateName = _namePolicy.fileName(now);
    final parsedTarget = _namePolicy.parse(dateName);
    var highestPart = -1;
    File? selected;
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final parsed = _namePolicy.parse(path.basename(entity.path));
      if (parsed == null || !_sameTarget(parsed, parsedTarget)) {
        continue;
      }
      if (parsed.part > highestPart) {
        highestPart = parsed.part;
        selected = entity;
      }
    }
    _part = highestPart < 0 ? 0 : highestPart;
    _activeFile = selected ??
        File(path.join(directory.path, _namePolicy.fileName(now, part: _part)));
    _activeDateName = dateName;
    _length = await _activeFile!.exists() ? await _activeFile!.length() : 0;
  }

  bool _sameTarget(
    ParsedLogFileName candidate,
    ParsedLogFileName? target,
  ) {
    if (!_config.splitByDay) {
      return true;
    }
    if (candidate.date == null || target?.date == null) {
      return false;
    }
    return candidate.date!.year == target!.date!.year &&
        candidate.date!.month == target.date!.month &&
        candidate.date!.day == target.date!.day;
  }

  Future<List<LogFileInfo>> _listFilesInternal() async {
    await _initializeInternal();
    final result = <LogFileInfo>[];
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = path.basename(entity.path);
      final parsed = _namePolicy.parse(name);
      if (parsed == null) {
        continue;
      }
      try {
        final stat = await entity.stat();
        result.add(
          LogFileInfo(
            path: entity.path,
            name: name,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
            date: parsed.date,
            part: parsed.part,
            isActive: entity.path == _activeFile?.path,
          ),
        );
      } on FileSystemException {
        // Ignore a file removed while the directory is being enumerated.
      }
    }
    result.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return result;
  }

  Future<void> _cleanupInternal() async {
    if (_config.retentionDays == 0 || !await directory.exists()) {
      return;
    }
    final cutoff = _clock().subtract(Duration(days: _config.retentionDays));
    await for (final entity in directory.list()) {
      if (entity is! File ||
          !_namePolicy.matches(path.basename(entity.path)) ||
          entity.path == _activeFile?.path) {
        continue;
      }
      try {
        final modified = await entity.lastModified();
        if (modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // Ignore concurrent removal and continue cleaning other files.
      }
    }
  }

  Future<void> _closeHandle() async {
    final handle = _handle;
    _handle = null;
    if (handle == null) {
      return;
    }
    await handle.flush();
    await handle.close();
  }
}
