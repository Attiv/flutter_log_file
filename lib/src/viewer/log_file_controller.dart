import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/viewer_config.dart';
import '../storage/log_file_manager.dart';
import 'file_chunk_reader.dart';

/// Bounded decoded-file window used by the lazy viewer page.
final class LogFileController extends ChangeNotifier {
  LogFileController({
    required this.filePath,
    this.config = const VLogViewerConfig(),
    Stream<LogWriteNotification>? writeNotifications,
    FileChunkReader? reader,
  })  : _notifications = writeNotifications,
        _reader = reader ??
            FileChunkReader(
              filePath,
              chunkSizeBytes: config.chunkSizeBytes,
              maximumLineBytes: config.maximumLineBytes,
            );

  final String filePath;
  final VLogViewerConfig config;
  final Stream<LogWriteNotification>? _notifications;
  final FileChunkReader _reader;

  final List<LogFileLine> _lines = [];
  StreamSubscription<LogWriteNotification>? _subscription;
  bool _opened = false;
  bool _closed = false;
  bool _follow = true;
  bool _loading = false;
  bool _hasMoreBefore = false;
  bool _hasMoreAfter = false;
  Object? _error;

  List<LogFileLine> get lines => List.unmodifiable(_lines);
  bool get isLoading => _loading;
  bool get isFollowing => _follow;
  bool get hasMoreBefore => _hasMoreBefore;
  bool get hasMoreAfter => _hasMoreAfter;
  Object? get error => _error;
  int get decodedBytes => _lines.fold(0, (sum, line) => sum + line.byteLength);

  Future<void> open() async {
    if (_opened || _closed) {
      return;
    }
    _opened = true;
    _subscription = _notifications?.listen(_onWrite);
    await refreshTail();
  }

  Future<void> refreshTail() => _guard(() async {
        final chunk = await _reader.readTail(maxLines: config.initialTailLines);
        _replace(chunk);
      });

  Future<void> loadOlder() => _guard(() async {
        if (_lines.isEmpty || !_hasMoreBefore) {
          return;
        }
        final chunk = await _reader.readBefore(_lines.first.startOffset);
        _lines.insertAll(0, chunk.lines);
        _hasMoreBefore = chunk.hasMoreBefore;
        _trim(addedAtStart: true);
      });

  Future<void> loadNewer() => _guard(() async {
        if (_lines.isEmpty) {
          await refreshTail();
          return;
        }
        final chunk = await _reader.readAfter(_lines.last.endOffset);
        _lines.addAll(chunk.lines);
        _hasMoreAfter = chunk.hasMoreAfter;
        _trim(addedAtStart: false);
      });

  Future<void> jumpToOffset(int offset) => _guard(() async {
        _replace(await _reader.readAround(offset));
      });

  Future<void> jumpToStart() => _guard(() async {
        _replace(await _reader.readAfter(0));
      });

  Future<void> jumpToEnd() => refreshTail();

  Future<void> setFollow(bool value) async {
    if (_follow == value || _closed) {
      return;
    }
    _follow = value;
    notifyListeners();
    if (value) {
      await refreshTail();
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onWrite(LogWriteNotification notification) {
    if (!_follow || notification.filePath != filePath || _closed) {
      return;
    }
    unawaited(loadNewer());
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_loading || _closed) {
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      if (!_closed) {
        notifyListeners();
      }
    }
  }

  void _replace(LogFileChunk chunk) {
    _lines
      ..clear()
      ..addAll(chunk.lines);
    _hasMoreBefore = chunk.hasMoreBefore;
    _hasMoreAfter = chunk.hasMoreAfter;
    _trim(addedAtStart: false);
  }

  void _trim({required bool addedAtStart}) {
    while (decodedBytes > config.memoryBudgetBytes && _lines.length > 1) {
      if (addedAtStart) {
        _lines.removeLast();
        _hasMoreAfter = true;
      } else {
        _lines.removeAt(0);
        _hasMoreBefore = true;
      }
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
