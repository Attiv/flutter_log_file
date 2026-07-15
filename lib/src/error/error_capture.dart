import 'dart:ui';

import 'package:flutter/foundation.dart';

typedef CapturedErrorReporter = void Function(
    Object error, StackTrace stackTrace, String source);

/// Installs optional Flutter framework and platform-dispatcher error hooks.
final class VLogErrorCapture {
  VLogErrorCapture(this._reporter);

  final CapturedErrorReporter _reporter;

  FlutterExceptionHandler? _previousFlutterHandler;
  FlutterExceptionHandler? _installedFlutterHandler;
  ErrorCallback? _previousPlatformHandler;
  ErrorCallback? _installedPlatformHandler;
  bool _installed = false;

  void install({
    required bool captureFlutterErrors,
    required bool capturePlatformErrors,
  }) {
    if (_installed) {
      uninstall();
    }
    _installed = captureFlutterErrors || capturePlatformErrors;
    if (captureFlutterErrors) {
      _previousFlutterHandler = FlutterError.onError;
      _installedFlutterHandler = (details) {
        try {
          _reporter(
            details.exception,
            details.stack ?? StackTrace.current,
            'FlutterError',
          );
        } catch (_) {
          // Logging must never prevent the application's error handler.
        }
        final previous = _previousFlutterHandler;
        if (previous != null) {
          previous(details);
        } else {
          FlutterError.presentError(details);
        }
      };
      FlutterError.onError = _installedFlutterHandler;
    }
    if (capturePlatformErrors) {
      _previousPlatformHandler = PlatformDispatcher.instance.onError;
      _installedPlatformHandler = (error, stackTrace) {
        try {
          _reporter(error, stackTrace, 'PlatformDispatcher');
        } catch (_) {
          // Preserve platform error delivery even if logging fails.
        }
        return _previousPlatformHandler?.call(error, stackTrace) ?? false;
      };
      PlatformDispatcher.instance.onError = _installedPlatformHandler;
    }
  }

  void uninstall() {
    if (!_installed) {
      return;
    }
    if (identical(FlutterError.onError, _installedFlutterHandler)) {
      FlutterError.onError = _previousFlutterHandler;
    }
    if (identical(
      PlatformDispatcher.instance.onError,
      _installedPlatformHandler,
    )) {
      PlatformDispatcher.instance.onError = _previousPlatformHandler;
    }
    _previousFlutterHandler = null;
    _installedFlutterHandler = null;
    _previousPlatformHandler = null;
    _installedPlatformHandler = null;
    _installed = false;
  }
}
