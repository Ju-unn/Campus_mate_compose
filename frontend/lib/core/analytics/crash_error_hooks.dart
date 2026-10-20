import 'package:campus_mate/core/analytics/crash_reporter.dart';
import 'package:flutter/foundation.dart';

/// 앱 전체의 처리되지 않은 오류를 [CrashReporter] 에 잇는다. `main()` 이 Firebase 를 켠 직후 한 번 부른다.
/// 수집이 꺼져 있으면(약관 동의 전) reporter 가 아무것도 보내지 않는다 — 여기서는 동의 여부를 따지지 않는다.
///
/// 이미 걸려 있던 처리기는 덮어쓰지 않고 이어서 부른다 — 디버그 콘솔에 오류가 찍히는 기존 동작을 지킨다.
abstract final class CrashErrorHooks {
  static void install(CrashReporter reporter) {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      reporter.recordFlutterFatalError(details);
    };
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      previousPlatformHandler?.call(error, stack);
      reporter.recordFatalError(error, stack);
      // true 로 답하면 Flutter 가 콘솔에 찍던 "Unhandled Exception" 이 사라진다 — 개발 중에는 우리가 대신 찍는다.
      if (kDebugMode) debugPrint('처리되지 않은 오류: $error\n$stack');
      return true;
    };
  }
}
