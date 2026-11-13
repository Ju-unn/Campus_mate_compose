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

  // 11-13 출시 전 점검: 사진 로딩이 실패하면 Flutter 가 예외 글자("HTTP request failed, statusCode: 403, <주소>")와
  // 덧붙는 정보("Image provider: NetworkImage(<주소>)")에 서명된 사진 주소(토큰 포함)를 싣는다 — 그대로 보내면 주소가 샌다.
  test('그림 로딩 오류는 오류 수집에 보내지 않는다(서명된 사진 주소가 원문에 있다), 원래 처리기는 그대로 부른다', () {
    const signedUrl = 'https://project.supabase.co/storage/v1/object/sign/profile-photos/a.jpg?token=secret';
    var originalCalls = 0;
    FlutterError.onError = (_) => originalCalls++;
    CrashErrorHooks.install(reporter);

    FlutterError.onError!(FlutterErrorDetails(
      exception: Exception('HTTP request failed, statusCode: 403, $signedUrl'),
      library: 'image resource service',
      context: ErrorDescription('resolving an image codec'),
      informationCollector: () => [DiagnosticsProperty<String>('Image provider', 'NetworkImage("$signedUrl")')],
    ));

    expect(reporter.calls, isEmpty);
    expect(originalCalls, 1);
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
