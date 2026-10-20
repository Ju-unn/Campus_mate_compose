import 'package:campus_mate/core/analytics/performance_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기록 없는 구현은 켜고 꺼도 조용히 받는다', () {
    const PerformanceMonitor monitor = NoPerformanceMonitor();

    expect(() {
      monitor.enableAfterConsent();
      monitor.disable();
    }, returnsNormally);
  });
}
