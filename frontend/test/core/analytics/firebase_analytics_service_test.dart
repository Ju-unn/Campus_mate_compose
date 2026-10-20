import 'dart:async';

import 'package:campus_mate/core/analytics/firebase_analytics_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

void main() {
  late _MockFirebaseAnalytics firebase;
  late FirebaseAnalyticsService service;

  setUp(() {
    firebase = _MockFirebaseAnalytics();
    when(() => firebase.setAnalyticsCollectionEnabled(any())).thenAnswer((_) async {});
    when(() => firebase.logEvent(name: any(named: 'name'), parameters: any(named: 'parameters'))).thenAnswer((_) async {});
    when(() => firebase.logScreenView(screenName: any(named: 'screenName'))).thenAnswer((_) async {});
    service = FirebaseAnalyticsService(firebase);
  });

  test('동의 뒤 켜면 수집을 켜고, 끄면 수집을 끈다', () async {
    service.enableAfterConsent();
    await pumpEventQueue();
    verify(() => firebase.setAnalyticsCollectionEnabled(true)).called(1);

    service.disable();
    await pumpEventQueue();
    verify(() => firebase.setAnalyticsCollectionEnabled(false)).called(1);
  });

  test('이벤트 이름과 매개변수는 정해진 것뿐이고 개인 값이 들어가지 않는다', () async {
    service.enableAfterConsent();
    await pumpEventQueue();

    service.logOnboardingComplete();
    service.logChatRequestSent();
    service.logHeartPurchase('heart_100');
    await pumpEventQueue();

    verify(() => firebase.logEvent(name: 'onboarding_complete', parameters: null)).called(1);
    verify(() => firebase.logEvent(name: 'chat_request_sent', parameters: null)).called(1);
    verify(() => firebase.logEvent(name: 'heart_purchase', parameters: {'product_id': 'heart_100'})).called(1);
    verifyNever(() => firebase.setUserId(id: any(named: 'id')));
    verifyNever(() => firebase.setUserProperty(name: any(named: 'name'), value: any(named: 'value')));
  });

  test('화면 이름은 screen_view 로 기록한다', () async {
    service.enableAfterConsent();
    await pumpEventQueue();

    service.logScreen('/chat/:matchId');
    await pumpEventQueue();

    verify(() => firebase.logScreenView(screenName: '/chat/:matchId')).called(1);
  });

  test('동의 전에 한 로그인은 기억해 두었다가 동의 뒤 켠 다음에 기록한다 — 켜기보다 먼저 가지 않는다', () async {
    service.logLogin('kakao');
    await pumpEventQueue();
    verifyNever(() => firebase.logEvent(name: 'login', parameters: any(named: 'parameters')));

    service.enableAfterConsent();
    await pumpEventQueue();

    verifyInOrder([
      () => firebase.setAnalyticsCollectionEnabled(true),
      () => firebase.logEvent(name: 'login', parameters: {'method': 'kakao'}),
    ]);
  });

  test('이미 켜져 있을 때의 로그인은 바로 기록하고, 다시 켜도 한 번 더 기록하지 않는다', () async {
    service.enableAfterConsent();
    await pumpEventQueue();

    service.logLogin('google');
    await pumpEventQueue();
    service.enableAfterConsent();
    await pumpEventQueue();

    verify(() => firebase.logEvent(name: 'login', parameters: {'method': 'google'})).called(1);
  });

  test('Firebase 가 던져도 앱 흐름으로 올리지 않는다', () async {
    when(() => firebase.logEvent(name: any(named: 'name'), parameters: any(named: 'parameters')))
        .thenAnswer((_) async => throw StateError('플랫폼 오류'));
    service.enableAfterConsent();
    await pumpEventQueue();

    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      service.logChatRequestSent();
      await pumpEventQueue();
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });
}
