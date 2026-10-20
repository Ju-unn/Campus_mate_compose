import 'package:campus_mate/core/analytics/performance_monitor.dart';

/// 시험이 Firebase Performance 를 켜지 않고도 "켜고 껐는지" 만 보는 가짜 구현.
class FakePerformanceMonitor implements PerformanceMonitor {
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
}
