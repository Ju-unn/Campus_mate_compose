import 'package:campus_mate/core/analytics/crash_reporter.dart';
import 'package:flutter/foundation.dart';

/// 시험이 Crashlytics 를 켜지 않고도 "무엇이 보고됐는지" 만 보는 가짜 구현.
class FakeCrashReporter implements CrashReporter {
  final List<String> calls = [];

  /// 마지막으로 켜고 끈 결과. 처음에는 꺼져 있다(앱의 기본값과 같다).
  bool collecting = false;

  @override
  void enableAfterConsent() {
    collecting = true;
    calls.add('enable');
  }

  @override
  void disable() {
    collecting = false;
    calls.add('disable');
  }

  @override
  void recordFlutterFatalError(FlutterErrorDetails details) => calls.add('flutter_fatal:${details.exception}');

  @override
  void recordFatalError(Object error, StackTrace stack) => calls.add('fatal:$error');
}
