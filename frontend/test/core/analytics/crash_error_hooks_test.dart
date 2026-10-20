import 'dart:ui';

import 'package:campus_mate/core/analytics/crash_error_hooks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_crash_reporter.dart';

void main() {
  late FakeCrashReporter reporter;
  late FlutterExceptionHandler? originalFlutterHandler;
  late ErrorCallback? originalPlatformHandler;

  setUp(() {
    reporter = FakeCrashReporter();
    originalFlutterHandler = FlutterError.onError;
    originalPlatformHandler = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = originalFlutterHandler;
    PlatformDispatcher.instance.onError = originalPlatformHandler;
  });

  test('프레임워크 오류를 오류 수집에 넘기고, 원래 처리기도 이어서 부른다', () {
    var originalCalls = 0;
    FlutterError.onError = (_) => originalCalls++;
    CrashErrorHooks.install(reporter);

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('깨짐')));

    expect(reporter.calls, ['flutter_fatal:Bad state: 깨짐']);
    expect(originalCalls, 1, reason: '콘솔에 보이던 기존 동작을 덮어쓰지 않는다');
  });

  test('처리되지 않은 비동기 오류를 오류 수집에 넘기고 처리했다고(true) 답한다', () {
    CrashErrorHooks.install(reporter);

    final handled = PlatformDispatcher.instance.onError!(StateError('깨짐'), StackTrace.current);

    expect(handled, isTrue);
    expect(reporter.calls, ['fatal:Bad state: 깨짐']);
  });

  test('비동기 오류 처리기가 이미 있었다면 그것도 이어서 부른다', () {
    var originalCalls = 0;
    PlatformDispatcher.instance.onError = (_, _) {
      originalCalls++;
      return false;
    };
    CrashErrorHooks.install(reporter);

    PlatformDispatcher.instance.onError!(StateError('깨짐'), StackTrace.current);

    expect(originalCalls, 1);
  });
}
