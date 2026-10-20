import 'dart:async';

import 'package:campus_mate/core/analytics/firebase_performance_monitor.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebasePerformance extends Mock implements FirebasePerformance {}

void main() {
  late _MockFirebasePerformance firebase;
  late FirebasePerformanceMonitor monitor;

  setUpAll(() => registerFallbackValue(HttpMethod.Get));

  setUp(() {
    firebase = _MockFirebasePerformance();
    when(() => firebase.setPerformanceCollectionEnabled(any())).thenAnswer((_) async {});
    monitor = FirebasePerformanceMonitor(firebase);
  });

  test('동의 뒤 켜면 수집을 켜고, 끄면 수집을 끈다', () async {
    monitor.enableAfterConsent();
    monitor.disable();
    await pumpEventQueue();

    verifyInOrder([
      () => firebase.setPerformanceCollectionEnabled(true),
      () => firebase.setPerformanceCollectionEnabled(false),
    ]);
  });

  // 사용자 지정 추적(HttpMetric · Trace)은 만들지 않는다 — 요청 주소에 계정 번호가 섞일 수 있다. 자동 수집만 쓴다.
  test('사용자 지정 추적(HttpMetric · Trace)은 만들지 않는다', () async {
    monitor.enableAfterConsent();
    await pumpEventQueue();

    verifyNever(() => firebase.newHttpMetric(any(), any()));
    verifyNever(() => firebase.newTrace(any()));
  });

  test('Firebase 가 던져도 앱 흐름으로 올리지 않는다', () async {
    when(() => firebase.setPerformanceCollectionEnabled(any())).thenAnswer((_) async => throw StateError('플랫폼 오류'));

    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      monitor.enableAfterConsent();
      await pumpEventQueue();
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });
}
