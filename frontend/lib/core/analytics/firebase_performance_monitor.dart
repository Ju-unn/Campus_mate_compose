import 'dart:async';

import 'package:campus_mate/core/analytics/performance_monitor.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// 진짜 Firebase Performance. `Firebase.initializeApp()` 이 끝난 뒤에만 만든다(main.dart).
/// 켜고 끄기만 한다 — `newHttpMetric` · `newTrace` 는 부르지 않는다([PerformanceMonitor]).
class FirebasePerformanceMonitor implements PerformanceMonitor {
  FirebasePerformanceMonitor(this._performance);

  final FirebasePerformance _performance;

  @override
  void enableAfterConsent() => _fire(() => _performance.setPerformanceCollectionEnabled(true));

  @override
  void disable() => _fire(() => _performance.setPerformanceCollectionEnabled(false));

  void _fire(Future<void> Function() action) {
    unawaited(action().catchError((Object error) => debugPrint('성능 측정 실패: ${error.runtimeType}')));
  }
}
