import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../error/error_capture.dart';
import '../format/message_serializer.dart';
import '../model/log_config.dart';
import '../model/log_file_info.dart';
import '../model/log_level.dart';
import '../sink/console_sink.dart';
import '../sink/file_sink.dart';
import '../sink/log_sink.dart';
import '../storage/directory_resolver.dart';
import '../storage/log_file_manager.dart';
import 'log_controller.dart';

/// Static application-facing entry point for console and file logs.
abstract final class VLog {
  static const int _preInitCapacity = 1000;
  static const int _preInitByteCapacity = 2 * 1024 * 1024;
  static const int _preInitMaxEntryBytes = 256 * 1024;
  static final Queue<_PendingLog> _preInit = Queue<_PendingLog>();
  static final ObjectEncoderRegistry _registry = ObjectEncoderRegistry();
  static final MessageSerializer _preInitSerializer = MessageSerializer(
    registry: _registry,
  );
  static int _preInitBytes = 0;

  static Future<void> _lifecycle = Future<void>.value();
  static LogController? _controller;
  static LogFileManager? _fileManager;
  static VLogErrorCapture? _errorCapture;
  static LogConfig? _config;

  static bool get isInitialized => _controller != null;

  static LogConfig? get config => _config;

  static String? get logDirectoryPath => _fileManager?.directory.path;

  static Stream<LogWriteNotification> get writeNotifications =>
      _fileManager?.writes ?? const Stream<LogWriteNotification>.empty();

  static Future<void> init(LogConfig config) =>
      _scheduleLifecycle(() => _initInternal(config));

  static void registerEncoder<T>(Object? Function(T value) encoder) =>
      _registry.register<T>(encoder);

  static void unregisterEncoder<T>() => _registry.unregister<T>();

  static void v(
    Object? message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) =>
      _emit(
        LogLevel.verbose,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        fields: fields,
        callerStack: StackTrace.current,
      );

  static void d(
    Object? message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) =>
      _emit(
        LogLevel.debug,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        fields: fields,
        callerStack: StackTrace.current,
      );

  static void i(
    Object? message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) =>
      _emit(
        LogLevel.info,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        fields: fields,
        callerStack: StackTrace.current,
      );

  static void w(
    Object? message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) =>
      _emit(
        LogLevel.warning,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        fields: fields,
        callerStack: StackTrace.current,
      );

  static void e(
    Object? message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) =>
      _emit(
        LogLevel.error,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        fields: fields,
        callerStack: StackTrace.current,
      );

  static void f(
    Object? message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) =>
      _emit(
        LogLevel.fatal,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        fields: fields,
        callerStack: StackTrace.current,
      );

  static R? runGuarded<R>(
    R Function() body, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) =>
      runZonedGuarded<R>(body, (error, stackTrace) {
        _emit(
          LogLevel.error,
          'Uncaught zone error',
          tag: 'Zone',
          error: error,
          stackTrace: stackTrace,
          callerStack: stackTrace,
        );
        onError?.call(error, stackTrace);
      });

  static Future<void> flush() async {
    await _lifecycle;
    await _controller?.flush();
  }

  static Future<void> close() => _scheduleLifecycle(() async {
        _errorCapture?.uninstall();
        _errorCapture = null;
        final controller = _controller;
        _controller = null;
        _fileManager = null;
        _config = null;
        _preInit.clear();
        _preInitBytes = 0;
        await controller?.close();
      });

  static Future<List<LogFileInfo>> getLogFiles() async {
    await _lifecycle;
    final manager = _fileManager;
    if (manager == null) {
      return const <LogFileInfo>[];
    }
    return manager.listFiles();
  }

  static Future<void> clearLogs() async {
    await flush();
    await _fileManager?.clear();
  }

  static Future<void> deleteLogFiles(Iterable<String> filePaths) async {
    await flush();
    await _fileManager?.deleteFiles(filePaths);
  }

  static Future<void> cleanupLogs() async {
    await flush();
    await _fileManager?.cleanup();
  }

  static Future<List<String>> exportLogs(String destinationDirectory) async {
    await flush();
    final manager = _fileManager;
    if (manager == null) {
      return const <String>[];
    }
    final destination = Directory(destinationDirectory);
    await destination.create(recursive: true);
    final exported = <String>[];
    for (final info in await manager.listFiles()) {
      final target = path.join(destination.path, info.name);
      await File(info.path).copy(target);
      exported.add(target);
    }
    return exported;
  }

  /// Save all logs (or selected managed logs) as a ZIP in Android Downloads.
  /// Android 10+ saves directly; older versions use the system save picker.
  /// Returns the saved location, or null when the picker is cancelled.
  static Future<String?> exportLogsToDownloads(
      {Iterable<String>? filePaths}) async {
    await flush();
    final files = await getLogFiles();
    final owned = {
      for (final file in files)
        path.normalize(path.absolute(file.path)): file.path
    };
    final requested =
        filePaths?.map((p) => path.normalize(path.absolute(p))).toSet() ??
            owned.keys.toSet();
    if (requested.isEmpty) throw StateError('No log files to save');
    if (requested.any((p) => !owned.containsKey(p))) {
      throw ArgumentError(
          'Only logs owned by the current configuration can be exported');
    }
    return const MethodChannel('flutter_log_file/downloads')
        .invokeMethod<String>(
      'exportLogsToDownloads',
      {
        'directory': logDirectoryPath,
        'paths': requested.map((p) => owned[p]!).toList(),
      },
    );
  }

  static Future<void> _initInternal(LogConfig config) async {
    _errorCapture?.uninstall();
    _errorCapture = null;
    final oldController = _controller;
    _controller = null;
    _fileManager = null;
    await oldController?.close();

    final sinks = <LogSink>[];
    LogFileManager? manager;
    if (config.consoleEnabled) {
      sinks.add(ConsoleSink(config, registry: _registry));
    }
    if (config.fileEnabled) {
      final directory = await DirectoryResolver(
        config,
        onMigrationError: (error, stack) => w(
          'Some old logs could not be moved; originals retained for the next launch',
          tag: 'VLog',
          error: error,
          stackTrace: stack,
        ),
      ).resolve();
      manager = LogFileManager(directory: directory, config: config);
      await manager.initialize();
      sinks.add(FileSink(config, manager, registry: _registry));
    }

    final controller = LogController(
      config: config,
      sinks: sinks,
      registry: _registry,
    );
    _config = config;
    _fileManager = manager;
    _controller = controller;
    await controller.start();

    final buffered = List<_PendingLog>.of(_preInit);
    _preInit.clear();
    _preInitBytes = 0;
    for (final pending in buffered) {
      controller.log(
        pending.level,
        pending.message,
        tag: pending.tag,
        error: pending.error,
        stackTrace: pending.stackTrace,
        fields: pending.fields,
        callerStack: pending.callerStack,
      );
    }

    final capture = VLogErrorCapture((error, stackTrace, source) {
      _emit(
        LogLevel.error,
        'Uncaught $source error',
        tag: source,
        error: error,
        stackTrace: stackTrace,
        callerStack: stackTrace,
      );
    });
    capture.install(
      captureFlutterErrors: config.captureFlutterErrors,
      capturePlatformErrors: config.capturePlatformErrors,
    );
    _errorCapture = capture;
  }

  static void _emit(
    LogLevel level,
    Object? message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
    required StackTrace callerStack,
  }) {
    final controller = _controller;
    if (controller != null) {
      controller.log(
        level,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        fields: fields,
        callerStack: callerStack,
      );
      return;
    }
    final messageSnapshot = _snapshotPreInitValue(message);
    final fieldsSnapshot = _snapshotPreInitFields(fields);
    final errorSnapshot =
        error == null ? null : _snapshotPreInitText(error.toString());
    final stackSnapshot = stackTrace == null
        ? null
        : StackTrace.fromString(_snapshotPreInitText(stackTrace.toString()));
    final callerSnapshot = StackTrace.fromString(
      _snapshotPreInitText(callerStack.toString()),
    );
    final tagSnapshot = tag == null ? null : _snapshotPreInitText(tag);
    final pending = _PendingLog(
      level: level,
      message: messageSnapshot,
      tag: tagSnapshot,
      error: errorSnapshot,
      stackTrace: stackSnapshot,
      fields: fieldsSnapshot,
      callerStack: callerSnapshot,
      estimatedBytes: _estimatePreInitBytes(
        messageSnapshot,
        fieldsSnapshot,
        tagSnapshot,
        errorSnapshot,
        stackSnapshot,
        callerSnapshot,
      ),
    );
    while (_preInit.isNotEmpty &&
        (_preInit.length >= _preInitCapacity ||
            _preInitBytes + pending.estimatedBytes > _preInitByteCapacity)) {
      _preInitBytes -= _preInit.removeFirst().estimatedBytes;
    }
    if (pending.estimatedBytes <= _preInitByteCapacity) {
      _preInit.addLast(pending);
      _preInitBytes += pending.estimatedBytes;
    }
  }

  static Object? _snapshotPreInitValue(Object? value) {
    final serialized = _preInitSerializer.serialize(value);
    final rendered = serialized.render();
    final bytes = utf8.encode(rendered);
    if (bytes.length <= _preInitMaxEntryBytes) {
      return serialized.value;
    }
    return _truncatePreInit(rendered, bytes);
  }

  static Map<String, Object?> _snapshotPreInitFields(
    Map<String, Object?> fields,
  ) {
    if (fields.isEmpty) return const {};
    final serialized = _preInitSerializer.serialize(fields);
    final rendered = serialized.render();
    final bytes = utf8.encode(rendered);
    final value = serialized.value;
    if (bytes.length <= _preInitMaxEntryBytes && value is Map) {
      return Map.unmodifiable(value.cast<String, Object?>());
    }
    return Map.unmodifiable({
      '_truncated': 'fields truncated from ${bytes.length}B',
    });
  }

  static String _snapshotPreInitText(String value) {
    var used = 0;
    var fits = true;
    for (final rune in value.runes) {
      used += _runeUtf8Width(rune);
      if (used > _preInitMaxEntryBytes) {
        fits = false;
        break;
      }
    }
    if (fits) return value;

    final marker = '…[truncated:${value.length} chars]';
    final budget = _preInitMaxEntryBytes - utf8.encode(marker).length;
    final buffer = StringBuffer();
    used = 0;
    for (final rune in value.runes) {
      final width = _runeUtf8Width(rune);
      if (used + width > budget) break;
      buffer.writeCharCode(rune);
      used += width;
    }
    return '$buffer$marker';
  }

  static int _runeUtf8Width(int rune) {
    if (rune <= 0x7F) return 1;
    if (rune <= 0x7FF) return 2;
    if (rune <= 0xFFFF) return 3;
    return 4;
  }

  static String _truncatePreInit(String value, List<int> bytes) {
    var marker = '…[truncated:${bytes.length}B]';
    var markerBytes = utf8.encode(marker);
    if (markerBytes.length >= _preInitMaxEntryBytes) {
      marker = '[truncated]';
      markerBytes = utf8.encode(marker);
    }
    var end = _preInitMaxEntryBytes - markerBytes.length;
    var prefix = '';
    while (end >= 0) {
      try {
        prefix = utf8.decode(bytes.sublist(0, end));
        break;
      } on FormatException {
        end -= 1;
      }
    }
    return '$prefix$marker';
  }

  static int _estimatePreInitBytes(
    Object? message,
    Map<String, Object?> fields,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    StackTrace callerStack,
  ) {
    var bytes = 128;
    bytes += utf8.encode(_preInitSerializer.serialize(message).render()).length;
    if (fields.isNotEmpty) {
      bytes +=
          utf8.encode(_preInitSerializer.serialize(fields).render()).length;
    }
    if (tag != null) bytes += utf8.encode(tag).length;
    if (error != null) bytes += utf8.encode(error.toString()).length;
    if (stackTrace != null) bytes += utf8.encode(stackTrace.toString()).length;
    bytes += utf8.encode(callerStack.toString()).length;
    return bytes > 0 ? bytes : 1;
  }

  static Future<void> _scheduleLifecycle(
    Future<void> Function() operation,
  ) {
    final completer = Completer<void>();
    _lifecycle = _lifecycle.catchError((Object _) {}).then((_) async {
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final class _PendingLog {
  const _PendingLog({
    required this.level,
    required this.message,
    required this.tag,
    required this.error,
    required this.stackTrace,
    required this.fields,
    required this.callerStack,
    required this.estimatedBytes,
  });

  final LogLevel level;
  final Object? message;
  final String? tag;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> fields;
  final StackTrace callerStack;
  final int estimatedBytes;
}
