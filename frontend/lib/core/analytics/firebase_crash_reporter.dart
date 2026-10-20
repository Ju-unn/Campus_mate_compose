import 'dart:async';

import 'package:campus_mate/core/analytics/crash_reporter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// 진짜 Firebase Crashlytics. `Firebase.initializeApp()` 이 끝난 뒤에만 만든다(main.dart).
/// 오류 처리기 안에서 다시 오류를 던지면 처리기가 처리기를 부르는 고리가 된다 — 실패는 삼키고 종류만 로그한다.
class FirebaseCrashReporter implements CrashReporter {
  FirebaseCrashReporter(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  void enableAfterConsent() => _fire(() => _crashlytics.setCrashlyticsCollectionEnabled(true));

  @override
  void disable() => _fire(() => _crashlytics.setCrashlyticsCollectionEnabled(false));

  @override
  void recordFlutterFatalError(FlutterErrorDetails details) => _fire(() => _crashlytics.recordFlutterFatalError(details));

  @override
  void recordFatalError(Object error, StackTrace stack) => _fire(() => _crashlytics.recordError(error, stack, fatal: true));

  void _fire(Future<void> Function() action) {
    unawaited(action().catchError((Object error) => debugPrint('오류 수집 실패: ${error.runtimeType}')));
  }
}
