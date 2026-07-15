import 'dart:async';
import 'dart:collection';
import 'dart:io';

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
  static final Queue<_PendingLog> _preInit = Queue<_PendingLog>();
  static final ObjectEncoderRegistry _registry = ObjectEncoderRegistry();

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
      final directory = await DirectoryResolver(config).resolve();
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
    if (_preInit.length >= _preInitCapacity) {
      _preInit.removeFirst();
    }
    _preInit.addLast(
      _PendingLog(
        level: level,
        message: message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        fields: Map.unmodifiable(fields),
        callerStack: callerStack,
      ),
    );
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
  });

  final LogLevel level;
  final Object? message;
  final String? tag;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> fields;
  final StackTrace callerStack;
}
