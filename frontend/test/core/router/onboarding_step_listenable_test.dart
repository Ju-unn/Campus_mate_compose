import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../profile/model/fake_onboarding_repository.dart';
import '../analytics/fake_analytics_service.dart';

void main() {
  late FakeOnboardingRepository repository;
  late FakeAnalyticsService analytics;
  late OnboardingStepListenable listenable;
  late int notifyCount;

  setUp(() {
    repository = FakeOnboardingRepository();
    analytics = FakeAnalyticsService();
    listenable = OnboardingStepListenable(repository, analytics: analytics);
    notifyCount = 0;
    listenable.addListener(() => notifyCount++);
    addTearDown(listenable.dispose);
  });

  // 예전에는 조회 전에도 04-1(basicInfo)이라 관문 조회가 먼저 끝나면 온보딩을 마친 사람도 04-1 이 잠깐 보였다.
  test('조회 전에는 아직 모르는 상태(null)로 본다', () {
    expect(listenable.value, isNull);
    expect(repository.fetchCount, 0);
  });

  // 사용 통계 onboarding_complete 이벤트 — 가입을 끝내는 순간(서버 단계가 complete 로 바뀐 때) 한 번만.
  group('온보딩 완료 분석', () {
    test('아직 가입 중이던 단계에서 complete 로 바뀌면 한 번 남긴다', () async {
      repository.nextResult = const Success(OnboardingStep.bio);
      await listenable.refresh();
      repository.nextResult = const Success(OnboardingStep.complete);

      await listenable.refresh();
      await listenable.refresh();

      expect(analytics.calls, ['onboarding_complete']);
    });

    test('앱을 켰더니 이미 complete 인 사람(첫 조회가 complete)은 남기지 않는다', () async {
      repository.nextResult = const Success(OnboardingStep.complete);

      await listenable.refresh();

      expect(analytics.calls, isEmpty);
    });

    test('가입 중 단계끼리 바뀌는 것은 남기지 않는다', () async {
      repository.nextResult = const Success(OnboardingStep.basicInfo);
      await listenable.refresh();
      repository.nextResult = const Success(OnboardingStep.kakaoId);

      await listenable.refresh();

      expect(analytics.calls, isEmpty);
    });
  });

  test('조회에 성공하면 그 단계로 바꾸고 알린다', () async {
    await listenable.refresh();

    expect(listenable.value, OnboardingStep.complete);
    expect(notifyCount, 1);
  });

  test('첫 조회가 04-1 이어도 "모름" 에서 바뀐 것이라 알린다', () async {
    repository.nextResult = const Success(OnboardingStep.basicInfo);

    await listenable.refresh();

    expect(listenable.value, OnboardingStep.basicInfo);
    expect(notifyCount, 1);
  });

  test('첫 조회부터 실패하면 04-1 로 대신하고 알린다 — 스플래시에 갇히지 않게', () async {
    repository.nextResult = const FailureResult(NetworkFailure());

    await listenable.refresh();

    expect(listenable.value, OnboardingStep.basicInfo);
    expect(notifyCount, 1);
  });

  test('아는 단계가 있으면 조회에 실패해도 그대로 둔다', () async {
    await listenable.refresh();

    repository.nextResult = const FailureResult(NetworkFailure());
    await listenable.refresh();

    expect(listenable.value, OnboardingStep.complete);
    expect(notifyCount, 1);
  });

  test('값이 그대로면 알리지 않는다', () async {
    await listenable.refresh();
    await listenable.refresh();

    expect(repository.fetchCount, 2);
    expect(notifyCount, 1);
  });

  test('reset 하면 다시 모르는 상태로 돌아가며 알린다', () async {
    await listenable.refresh();

    listenable.reset();

    expect(listenable.value, isNull);
    expect(notifyCount, 2);
  });

  test('이미 모르는 상태면 reset 해도 알리지 않는다', () {
    listenable.reset();

    expect(listenable.value, isNull);
    expect(notifyCount, 0);
  });

  // 온보딩 뒤로가기(계획서 가-2): 서버 단계는 그대로 두고 "다시 보는 단계" 하나를 앞에 얹는다.
  group('다시 보는 단계', () {
    Future<void> serverAt(OnboardingStep step) async {
      repository.nextResult = Success(step);
      await listenable.refresh();
      notifyCount = 0;
    }

    test('서버가 survey 일 때 goBack 하면 value 가 myTraits 가 되고 한 번 알린다', () async {
      await serverAt(OnboardingStep.survey);

      listenable.goBack();

      expect(listenable.value, OnboardingStep.myTraits);
      expect(listenable.isRevisiting, isTrue);
      expect(notifyCount, 1);
    });

    test('basicInfo 에서 goBack 해도 바뀌지 않고 알리지 않는다', () async {
      await serverAt(OnboardingStep.basicInfo);

      expect(listenable.canGoBack, isFalse);
      listenable.goBack();

      expect(listenable.value, OnboardingStep.basicInfo);
      expect(listenable.isRevisiting, isFalse);
      expect(notifyCount, 0);
    });

    test('사진 경계: interests 에서 두 번 goBack 해도 appearanceType 에서 멈춘다', () async {
      await serverAt(OnboardingStep.interests);

      listenable.goBack();
      listenable.goBack();

      expect(listenable.value, OnboardingStep.appearanceType);
      expect(listenable.canGoBack, isFalse);
      expect(notifyCount, 1);
    });

    test('단계를 모르면(null) goBack 은 아무것도 하지 않는다', () {
      expect(listenable.canGoBack, isFalse);
      listenable.goBack();

      expect(listenable.value, isNull);
      expect(notifyCount, 0);
    });

    test('myTraits 를 다시 보다 stepSaved 하면 서버 단계 survey 로 돌아가 다시 보기가 끝난다', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();

      await listenable.stepSaved();

      expect(listenable.value, OnboardingStep.survey);
      expect(listenable.isRevisiting, isFalse);
    });

    test('두 단계 뒤(interests)에서 stepSaved 하면 myTraits 로 한 칸만 간다', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();
      listenable.goBack();
      expect(listenable.value, OnboardingStep.interests);

      await listenable.stepSaved();

      expect(listenable.value, OnboardingStep.myTraits);
      expect(listenable.isRevisiting, isTrue);
    });

    test('stepSaved 는 서버 단계를 다시 묻는다(다시 보는 중에도)', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();
      final before = repository.fetchCount;

      await listenable.stepSaved();

      expect(repository.fetchCount, before + 1);
    });

    // Review Focus 1: 토큰 갱신 · 세션 알림마다 main.dart 가 refresh 를 부른다 — 그때 화면이 혼자 넘어가면 안 된다.
    test('refresh 는 다시 보는 단계를 건드리지 않는다', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();
      listenable.goBack();

      await listenable.refresh();
      await listenable.refresh();

      expect(listenable.value, OnboardingStep.interests);
      expect(listenable.isRevisiting, isTrue);
    });

    // Review Focus 4: 다음 계정이 앞 계정의 다시 보기를 물려받지 않는다.
    test('reset 하면 다시 보는 단계도 지운다', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();

      listenable.reset();

      expect(listenable.value, isNull);
      expect(listenable.isRevisiting, isFalse);
      repository.nextResult = const Success(OnboardingStep.idealNote);
      await listenable.refresh();
      expect(listenable.value, OnboardingStep.idealNote);
    });

    test('다시 보는 중이 아니면 stepSaved 는 refresh 와 같다', () async {
      await serverAt(OnboardingStep.kakaoId);
      final before = repository.fetchCount;
      repository.nextResult = const Success(OnboardingStep.photos);

      await listenable.stepSaved();

      expect(repository.fetchCount, before + 1);
      expect(listenable.value, OnboardingStep.photos);
      expect(listenable.isRevisiting, isFalse);
      expect(notifyCount, 1);
    });

    // 앞으로 건너뛰기 금지: 보이는 단계(value)는 서버 단계보다 뒤로 갈 수 없다.
    test('서버 단계가 다시 보는 단계와 같거나 앞으로 바뀌면 다시 보기를 끝낸다', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();

      repository.nextResult = const Success(OnboardingStep.myTraits);
      await listenable.refresh();

      expect(listenable.value, OnboardingStep.myTraits);
      expect(listenable.isRevisiting, isFalse);
    });

    test('서버 단계가 앞으로 가도 다시 보는 단계는 그대로다', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();

      repository.nextResult = const Success(OnboardingStep.idealConditions);
      await listenable.refresh();

      expect(listenable.value, OnboardingStep.myTraits);
      await listenable.stepSaved();
      expect(listenable.value, OnboardingStep.survey, reason: '한 칸씩 간다 — 서버 단계로 건너뛰지 않는다');
      expect(listenable.isRevisiting, isTrue);
    });
  });
}
