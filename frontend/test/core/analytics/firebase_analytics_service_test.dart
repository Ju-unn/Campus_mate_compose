import 'dart:async';

import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/core/analytics/firebase_analytics_service.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
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

  group('앱 1.0.1 에서 더한 이벤트 — 이름과 매개변수는 정해진 것뿐이다', () {
    setUp(() async {
      service.enableAfterConsent();
      await pumpEventQueue();
    });

    Future<void> sends(void Function() act, String name, Map<String, Object>? parameters) async {
      act();
      await pumpEventQueue();
      verify(() => firebase.logEvent(name: name, parameters: parameters)).called(1);
    }

    test('가입 단계: 끝냄은 단계 이름과 머문 초', () => sends(
          () => service.logOnboardingStepComplete(OnboardingStep.kakaoId, 42),
          'onboarding_step_complete',
          {'step': 'kakao_id', 'seconds': 42},
        ));

    test('가입 단계: 머문 초는 3600 에서 자르고 음수는 0 으로 둔다', () async {
      service.logOnboardingStepComplete(OnboardingStep.photos, 99999);
      service.logOnboardingStepComplete(OnboardingStep.bio, -5);
      await pumpEventQueue();

      verify(() => firebase.logEvent(name: 'onboarding_step_complete', parameters: {'step': 'photos', 'seconds': 3600}))
          .called(1);
      verify(() => firebase.logEvent(name: 'onboarding_step_complete', parameters: {'step': 'bio', 'seconds': 0}))
          .called(1);
    });

    test('가입 단계: 뒤로가기는 떠난 단계 이름', () => sends(
          () => service.logOnboardingStepBack(OnboardingStep.survey),
          'onboarding_step_back',
          {'step': 'survey'},
        ));

    test('가입 단계: 막힘은 단계 이름과 종류값', () => sends(
          () => service.logOnboardingBlocked(OnboardingStep.photos, OnboardingBlockReason.photoDocument),
          'onboarding_blocked',
          {'step': 'photos', 'reason': 'photo_document'},
        ));

    test('카드: 보임 · 상세 · 넘김은 출처만', () async {
      service.logCardView(CardOrigin.free);
      service.logCardDetailOpen(CardOrigin.purchased);
      service.logCardPass(CardOrigin.free);
      await pumpEventQueue();

      verify(() => firebase.logEvent(name: 'card_view', parameters: {'source': 'free'})).called(1);
      verify(() => firebase.logEvent(name: 'card_detail_open', parameters: {'source': 'purchased'})).called(1);
      verify(() => firebase.logEvent(name: 'card_pass', parameters: {'source': 'free'})).called(1);
    });

    test('유료 카드: 칸 보임은 상태, 시트 열림은 매개변수 없음', () async {
      service.logPaidCardView(PaidCardState.offered);
      service.logPaidCardView(PaidCardState.empty);
      service.logPaidCardSheetOpen();
      await pumpEventQueue();

      verify(() => firebase.logEvent(name: 'paid_card_view', parameters: {'state': 'offered'})).called(1);
      verify(() => firebase.logEvent(name: 'paid_card_view', parameters: {'state': 'empty'})).called(1);
      verify(() => firebase.logEvent(name: 'paid_card_sheet_open', parameters: null)).called(1);
    });

    test('하트 상점: 들어온 곳 · 고른 상품 · 결제 결과', () async {
      service.logHeartStoreOpen(HeartStoreEntry.paidCard);
      service.logHeartProductSelect('heart_100');
      service.logHeartPurchaseResult(HeartPurchaseResult.cancel, 'heart_100');
      await pumpEventQueue();

      verify(() => firebase.logEvent(name: 'heart_store_open', parameters: {'from': 'paid_card'})).called(1);
      verify(() => firebase.logEvent(name: 'heart_product_select', parameters: {'product_id': 'heart_100'})).called(1);
      verify(() => firebase.logEvent(
            name: 'heart_purchase_result',
            parameters: {'result': 'cancel', 'product_id': 'heart_100'},
          )).called(1);
    });

    test('푸시 열기는 종류값만', () => sends(
          () => service.logPushOpen(PushOpenType.friendReviewWrite),
          'push_open',
          {'type': 'friend_review_write'},
        ));

    test('앱 투어 끝은 결과와 단계 번호', () => sends(
          () => service.logTourFinish(TourResult.skip, 3),
          'tour_finish',
          {'result': 'skip', 'step': 3},
        ));

    test('커뮤니티: 투표 · 질문 작성은 매개변수 없음', () async {
      service.logPollVote();
      service.logPollCreate();
      await pumpEventQueue();

      verify(() => firebase.logEvent(name: 'poll_vote', parameters: null)).called(1);
      verify(() => firebase.logEvent(name: 'poll_create', parameters: null)).called(1);
    });

    test('Firebase 이름 규칙: 이벤트 이름 40자 이하 snake_case · 문자열 값 100자 이하', () async {
      service
        ..logOnboardingStepComplete(OnboardingStep.idealConditions, 1)
        ..logOnboardingStepBack(OnboardingStep.idealConditions)
        ..logOnboardingBlocked(OnboardingStep.idealConditions, OnboardingBlockReason.rateLimited)
        ..logCardView(CardOrigin.free)
        ..logCardDetailOpen(CardOrigin.free)
        ..logCardPass(CardOrigin.free)
        ..logPaidCardView(PaidCardState.empty)
        ..logPaidCardSheetOpen()
        ..logHeartStoreOpen(HeartStoreEntry.avatarRegen)
        ..logHeartProductSelect('heart_100')
        ..logHeartPurchaseResult(HeartPurchaseResult.fail, 'heart_100')
        ..logPushOpen(PushOpenType.heartTaskRetry)
        ..logTourFinish(TourResult.done, 6)
        ..logPollVote()
        ..logPollCreate();
      await pumpEventQueue();

      final calls = verify(() => firebase.logEvent(name: captureAny(named: 'name'), parameters: captureAny(named: 'parameters')))
          .captured;
      expect(calls, hasLength(30));
      for (var i = 0; i < calls.length; i += 2) {
        expect(calls[i] as String, matches(RegExp(r'^[a-z][a-z0-9_]{0,39}$')));
        final parameters = calls[i + 1] as Map<String, Object>?;
        for (final entry in (parameters ?? const <String, Object>{}).entries) {
          expect(entry.key, matches(RegExp(r'^[a-z][a-z0-9_]{0,39}$')));
          expect(entry.value, anyOf(isA<int>(), isA<String>().having((s) => s.length, 'length', lessThanOrEqualTo(100))));
        }
      }
    });

    // 수집을 켜는 것은 enableAfterConsent 뿐이다 — 이벤트를 보낸다고 켜지지 않는다. 동의 전에는 Firebase 가 기기에
    // 기억한 "꺼짐"(AndroidManifest · Info.plist) 때문에 아무것도 나가지 않는다(켜는 때는 CollectionConsent 가 정한다).
    test('이벤트를 보내는 것만으로는 수집을 켜지 않고, 사용자 식별값도 달지 않는다', () async {
      clearInteractions(firebase);
      service
        ..logPollVote()
        ..logPushOpen(PushOpenType.chat)
        ..logCardView(CardOrigin.free);
      await pumpEventQueue();

      verifyNever(() => firebase.setAnalyticsCollectionEnabled(any()));
      verifyNever(() => firebase.setUserId(id: any(named: 'id')));
      verifyNever(() => firebase.setUserProperty(name: any(named: 'name'), value: any(named: 'value')));
    });
  });

  test('동의 전(켜기 전)에는 새 이벤트도 수집을 켜지 않는다 — 켜는 호출은 한 번도 없다', () async {
    service
      ..logPollVote()
      ..logHeartStoreOpen(HeartStoreEntry.home)
      ..logTourFinish(TourResult.done, 1);
    await pumpEventQueue();

    verifyNever(() => firebase.setAnalyticsCollectionEnabled(true));
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
