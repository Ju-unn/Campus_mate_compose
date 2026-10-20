import 'package:campus_mate/core/analytics/collection_switch.dart';
import 'package:flutter/foundation.dart';

/// 오류 수집(Firebase Crashlytics). 사용자 식별값(`setUserIdentifier`)과 사용자 정의 키(`setCustomKey`)는 쓰지 않는다 —
/// 어느 사용자의 오류인지는 보내지 않는다(2026-10-20).
///
/// 약관 동의 전에는 수집하지 않는다 — 켜고 끄는 때는 [CollectionConsent] 가 정한다.
/// 시험과 Firebase 를 켜지 못한 빌드는 [NoCrashReporter] 를 쓴다(`analytics_provider.dart`).
abstract interface class CrashReporter implements CollectionSwitch {
  /// `FlutterError.onError` 가 잡은 프레임워크 오류(치명).
  void recordFlutterFatalError(FlutterErrorDetails details);

  /// `PlatformDispatcher.onError` 가 잡은, 어디서도 처리하지 않은 비동기 오류(치명).
  void recordFatalError(Object error, StackTrace stack);
}

/// 아무것도 보고하지 않는 구현 — 시험과 Firebase 를 켜지 못한 빌드의 기본값이다.
class NoCrashReporter implements CrashReporter {
  const NoCrashReporter();

  @override
  void enableAfterConsent() {}

  @override
  void disable() {}

  @override
  void recordFlutterFatalError(FlutterErrorDetails details) {}

  @override
  void recordFatalError(Object error, StackTrace stack) {}
}
