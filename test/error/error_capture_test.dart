import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_log_file/src/error/error_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterExceptionHandler? originalFlutter;
  late ErrorCallback? originalPlatform;

  setUp(() {
    originalFlutter = FlutterError.onError;
    originalPlatform = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = originalFlutter;
    PlatformDispatcher.instance.onError = originalPlatform;
  });

  test('does not install capture when both switches are false', () {
    final capture = VLogErrorCapture((error, stackTrace, source) {});

    capture.install(captureFlutterErrors: false, capturePlatformErrors: false);

    expect(FlutterError.onError, same(originalFlutter));
    expect(PlatformDispatcher.instance.onError, same(originalPlatform));
  });

  test('logs Flutter error and invokes previous handler', () {
    final events = <String>[];
    FlutterError.onError = (_) => events.add('previous');
    final capture = VLogErrorCapture(
      (error, _, source) => events.add('$source:$error'),
    );
    capture.install(captureFlutterErrors: true, capturePlatformErrors: false);

    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('flutter failed')),
    );

    expect(events.first, contains('FlutterError:Bad state: flutter failed'));
    expect(events.last, 'previous');
    capture.uninstall();
  });

  test('platform capture preserves previous handler result', () {
    final events = <String>[];
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      events.add('previous');
      return true;
    };
    final previous = PlatformDispatcher.instance.onError;
    final capture = VLogErrorCapture(
      (error, _, source) => events.add('$source:$error'),
    );
    capture.install(captureFlutterErrors: false, capturePlatformErrors: true);

    final handled = PlatformDispatcher.instance.onError!(
      StateError('platform failed'),
      StackTrace.current,
    );

    expect(handled, isTrue);
    expect(
        events, ['PlatformDispatcher:Bad state: platform failed', 'previous']);
    capture.uninstall();
    expect(PlatformDispatcher.instance.onError, same(previous));
  });

  test('platform capture returns false when there was no previous handler', () {
    PlatformDispatcher.instance.onError = null;
    final capture = VLogErrorCapture((error, stackTrace, source) {});
    capture.install(captureFlutterErrors: false, capturePlatformErrors: true);

    expect(
      PlatformDispatcher.instance.onError!(
        StateError('unhandled'),
        StackTrace.current,
      ),
      isFalse,
    );
    capture.uninstall();
  });
}
