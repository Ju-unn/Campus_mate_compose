import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../profile/onboarding/model/repository/fake_onboarding_repository.dart';
import '../analytics/fake_analytics_service.dart';

void main() {
  late FakeOnboardingRepository repository;
  late FakeAnalyticsService analytics;
  late OnboardingStepListenable listenable;
  late int notifyCount;
  late DateTime clock;

  setUp(() {
    repository = FakeOnboardingRepository();
    analytics = FakeAnalyticsService();
    clock = DateTime(2026, 11, 2, 9);
    listenable = OnboardingStepListenable(repository, analytics: analytics, now: () => clock);
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

      // 마지막 단계(bio)를 끝낸 것과 가입을 끝낸 것은 같은 순간이라 둘 다 남는다 — 가입 완료는 한 번뿐이다.
      expect(analytics.calls, ['onboarding_step_complete:bio:0', 'onboarding_complete']);
    });

    test('앱을 켰더니 이미 complete 인 사람(첫 조회가 complete)은 남기지 않는다', () async {
      repository.nextResult = const Success(OnboardingStep.complete);

      await listenable.refresh();

      expect(analytics.calls, isEmpty);
    });

    test('가입 중 단계끼리 바뀌는 것은 가입 완료로 남기지 않는다', () async {
      repository.nextResult = const Success(OnboardingStep.basicInfo);
      await listenable.refresh();
      repository.nextResult = const Success(OnboardingStep.kakaoId);

      await listenable.refresh();

      expect(analytics.calls, isNot(contains('onboarding_complete')));
    });
  });

  // 사용 통계 onboarding_step_complete · onboarding_step_back · onboarding_blocked — 단계 이름(wire)과 머문 초만 나간다.
  group('가입 단계 분석', () {
    Future<void> serverAt(OnboardingStep step) async {
      repository.nextResult = Success(step);
      await listenable.refresh();
    }

    test('서버 단계가 앞으로 나아가면 떠난 단계와 머문 초를 남긴다', () async {
      await serverAt(OnboardingStep.basicInfo);
      clock = clock.add(const Duration(seconds: 42));

      await serverAt(OnboardingStep.kakaoId);

      expect(analytics.calls, ['onboarding_step_complete:basic_info:42']);
    });

    test('머문 초는 그 단계가 처음 보인 때부터 센다 — 같은 단계를 다시 물어도 시계는 그대로다', () async {
      await serverAt(OnboardingStep.kakaoId);
      clock = clock.add(const Duration(seconds: 30));
      await serverAt(OnboardingStep.kakaoId);
      clock = clock.add(const Duration(seconds: 12));

      await serverAt(OnboardingStep.photos);

      expect(analytics.calls, ['onboarding_step_complete:kakao_id:42']);
    });

    test('다음 단계의 시계는 새로 시작한다', () async {
      await serverAt(OnboardingStep.basicInfo);
      clock = clock.add(const Duration(seconds: 100));
      await serverAt(OnboardingStep.kakaoId);
      clock = clock.add(const Duration(seconds: 7));

      await serverAt(OnboardingStep.photos);

      expect(analytics.calls, ['onboarding_step_complete:basic_info:100', 'onboarding_step_complete:kakao_id:7']);
    });

    test('앱을 켜고 처음 알게 된 단계(첫 조회)는 끝낸 것이 아니라서 남기지 않는다', () async {
      await serverAt(OnboardingStep.survey);

      expect(analytics.calls, isEmpty);
    });

    test('서버 단계가 뒤로 물러나거나 초기화되는 것은 끝낸 것이 아니다', () async {
      await serverAt(OnboardingStep.survey);
      await serverAt(OnboardingStep.interests);
      listenable.reset();

      expect(analytics.calls, isEmpty);
    });

    test('앞 단계를 다시 보고 저장해도(서버 단계는 그대로) 끝낸 것으로 다시 세지 않는다', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();
      analytics.calls.clear();

      await listenable.stepSaved();

      expect(analytics.calls, isEmpty);
    });

    test('뒤로가기는 떠난 단계를 남긴다', () async {
      await serverAt(OnboardingStep.survey);

      listenable.goBack();

      expect(analytics.calls, ['onboarding_step_back:survey']);
    });

    test('갈 곳이 없는 뒤로가기(04-1)와 단계를 모를 때의 뒤로가기는 남기지 않는다', () async {
      listenable.goBack();
      await serverAt(OnboardingStep.basicInfo);

      listenable.goBack();

      expect(analytics.calls, isEmpty);
    });

    test('막힘은 지금 보이는 단계와 종류값을 남긴다', () async {
      await serverAt(OnboardingStep.photos);

      listenable.blocked(OnboardingBlockReason.photoDocument);

      expect(analytics.calls, ['onboarding_blocked:photos:photo_document']);
    });

    test('다시 보는 중의 막힘은 다시 보는 단계 이름으로 남긴다', () async {
      await serverAt(OnboardingStep.survey);
      listenable.goBack();
      analytics.calls.clear();

      listenable.blocked(OnboardingBlockReason.network);

      expect(analytics.calls, ['onboarding_blocked:my_traits:network']);
    });

    test('가입이 끝난 뒤(나 탭 편집 등 같은 화면 재사용)와 단계를 모를 때의 막힘은 가입 막힘이 아니라서 남기지 않는다', () async {
      listenable.blocked(OnboardingBlockReason.server);
      await serverAt(OnboardingStep.complete);

      listenable.blocked(OnboardingBlockReason.server);

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

  // 최종 점검 ⑦: 앱을 켤 때 단계 조회만 15초 초과 · 서버 오류로 실패하면 가입을 마친 사람도 04-1 에 갇혔다.
  // 이제 "못 물어봄" 으로 두고 알린다 — 라우터가 01-1(다시 시도)로 보낸다.
  for (final failure in const <Failure>[NetworkFailure(), ServerUnavailableFailure(), UnknownFailure()]) {
    test('첫 조회가 ${failure.runtimeType} 로 실패하면 04-1 로 대신하지 않고 "못 물어봄" 으로 두고 알린다', () async {
      repository.nextResult = FailureResult(failure);

      await listenable.refresh();

      expect(listenable.value, isNull);
      expect(listenable.isUnreachable, isTrue);
      expect(notifyCount, 1);
    });
  }

  // 단계 조회는 관문(학교 메일 · 학과 · 재동의)을 넘어야 답한다 — 거절(403)은 "아직 가입을 시작 못 했다" 는 답이라 지금처럼 04-1 이다.
  test('관문 전이라 서버가 거절하면 지금처럼 04-1 로 두고 "못 물어봄" 이 아니다', () async {
    repository.nextResult = const FailureResult(ServerRejectedFailure('학과 정보를 먼저 입력해 주세요'));

    await listenable.refresh();

    expect(listenable.value, OnboardingStep.basicInfo);
    expect(listenable.isUnreachable, isFalse);
    expect(notifyCount, 1);
  });

  test('못 물어본 뒤 다시 물어 성공하면 그 단계로 바꾸고 "못 물어봄" 을 푼다', () async {
    repository.nextResult = const FailureResult(NetworkFailure());
    await listenable.refresh();

    repository.nextResult = const Success(OnboardingStep.complete);
    await listenable.refresh();

    expect(listenable.value, OnboardingStep.complete);
    expect(listenable.isUnreachable, isFalse);
    expect(notifyCount, 2);
  });

  test('실패가 이어져도 처음 한 번만 알리고 혼자 다시 묻지 않는다', () async {
    repository.nextResult = const FailureResult(NetworkFailure());

    await listenable.refresh();
    await listenable.refresh();
    await listenable.refresh();
    await pumpEventQueue();

    expect(repository.fetchCount, 3);
    expect(listenable.isUnreachable, isTrue);
    expect(notifyCount, 1);
  });

  test('reset 하면 "못 물어봄" 도 지운다', () async {
    repository.nextResult = const FailureResult(NetworkFailure());
    await listenable.refresh();

    listenable.reset();

    expect(listenable.value, isNull);
    expect(listenable.isUnreachable, isFalse);
    expect(notifyCount, 2);
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
