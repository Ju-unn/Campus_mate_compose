import 'package:campus_mate/core/analytics/crash_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기록 없는 구현은 모든 행위를 조용히 받는다', () {
    const CrashReporter reporter = NoCrashReporter();

    expect(() {
      reporter.enableAfterConsent();
      reporter.disable();
      reporter.recordFlutterFatalError(FlutterErrorDetails(exception: 'x'));
      reporter.recordFatalError('x', StackTrace.current);
    }, returnsNormally);
  });
}
