import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/me/model/repository/me_repository_provider.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:campus_mate/profile/viewmodel/survey_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

import '../../me/model/repository/fake_me_repository.dart';
import '../model/fake_ideal_conditions_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../../core/analytics/fake_analytics_service.dart';
import '../../core/draft/fake_draft_store.dart';

void main() {
  late FakeIdealConditionsRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late FakeAnalyticsService analytics;
  late ProviderContainer container;

  setUp(() {
    repository = FakeIdealConditionsRepository();
    onboardingRepository = FakeOnboardingRepository();
    analytics = FakeAnalyticsService();
    container = ProviderContainer(
      overrides: [
        idealConditionsRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
  });

  tearDown(() => container.dispose());

  /// 얼굴상·인상은 필수라(2026-09-20 사용자 결정) 제출 전에 한 개씩은 골라야 한다.
  void pickRequiredAppearance(IdealConditionsViewModel vm) {
    vm.toggleAnimalType(AnimalType.cat);
    vm.toggleImpressionType(ImpressionType.kind);
  }

  test('얼굴상·인상만 고르면 나머지는 기본 범위 그대로 제출할 수 있다', () async {
    final vm = container.read(idealConditionsViewModelProvider.notifier);
    pickRequiredAppearance(vm);
    await vm.submit();

    expect(repository.submitted!.preferredAgeMin, 22);
    expect(repository.submitted!.preferredAgeMax, 27);
    expect(repository.submitted!.preferredHeightMin, 165);
    expect(repository.submitted!.preferredHeightMax, 180);
    expect(container.read(idealConditionsViewModelProvider).completed, isTrue);
    expect(onboardingRepository.fetchCount, 1);
  });

  test('06-2 에서 돌아온 06-1 을 저장하면 06-2 로 돌아가 다시 보기가 끝난다', () async {
    await revisit(
      container,
      onboardingRepository,
      server: OnboardingStep.idealTraits,
      visiting: OnboardingStep.idealConditions,
    );
    final vm = container.read(idealConditionsViewModelProvider.notifier);
    pickRequiredAppearance(vm);

    await vm.submit();

    final steps = container.read(onboardingStepListenableProvider);
    expect(steps.value, OnboardingStep.idealTraits);
    expect(steps.isRevisiting, isFalse);
  });

  // 뷰모델은 앱이 켜진 동안 살아 있어 첫 저장의 completed 가 남는다 — 다시 저장이 실패하면 그대로 머물러야 한다.
  test('같은 세션에서 다시 저장이 실패하면 다음 화면으로 넘어가지 않는다', () async {
    final vm = container.read(idealConditionsViewModelProvider.notifier);
    pickRequiredAppearance(vm);
    await vm.submit();
    await revisit(
      container,
      onboardingRepository,
      server: OnboardingStep.idealTraits,
      visiting: OnboardingStep.idealConditions,
    );
    repository.nextResult = const FailureResult(NetworkFailure());

    await vm.submit();

    expect(container.read(onboardingStepListenableProvider).value, OnboardingStep.idealConditions);
    expect(container.read(idealConditionsViewModelProvider).errorMessage, isNotNull);
    expect(onboardingRepository.fetchCount, 0);
  });

  test('06-2 에서 돌아온 06-1 은 저장해 둔 이상형 조건으로 채워진다', () async {
    final revisiting = ProviderContainer(
      overrides: [
        idealConditionsRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
        meRepositoryProvider.overrideWithValue(FakeMeRepository(const Success(savedOnboardingProfile))),
      ],
    );
    addTearDown(revisiting.dispose);
    await revisiting.read(myProfileProvider.future);
    await revisit(
      revisiting,
      onboardingRepository,
      server: OnboardingStep.idealTraits,
      visiting: OnboardingStep.idealConditions,
    );

    final state = revisiting.read(idealConditionsViewModelProvider);

    expect((state.preferredAgeMin, state.preferredAgeMax, state.ageIgnored), (24, 30, false));
    expect((state.preferredHeightMin, state.preferredHeightMax, state.heightIgnored), (160, 175, false));
    expect(state.preferredMbtiFlags, {'E': true, 'N': true});
    expect(state.preferredAnimalTypes, [AnimalType.dog, AnimalType.cat]);
    expect(state.preferredImpressionTypes, [ImpressionType.kind]);
    // 서버 accepts_smoker 가 아직 null 이라 내 흡연 여부(안 한다)를 따라 싫어요(false)로 열린다.
    expect(state.acceptsSmoker, isFalse);
    expect(state.canSubmit, isTrue);
  });

  // 앱 1.0.2 — 06-1 "흡연하는 사람" 칸. 온보딩에서는 바로 앞 설문(05-11 흡연)에서 고른 값이 처음 값이다.
  group('흡연하는 사람 칸', () {
    test('처음 값은 바로 앞 설문의 답을 따른다 — "안 한다" 는 싫어요(false)', () {
      container.read(surveyViewModelProvider.notifier).changeIsSmoker(false);

      expect(container.read(idealConditionsViewModelProvider).acceptsSmoker, isFalse);
    });

    test('설문에서 "한다" 를 골랐으면 상관없어요(true)', () {
      container.read(surveyViewModelProvider.notifier).changeIsSmoker(true);

      expect(container.read(idealConditionsViewModelProvider).acceptsSmoker, isTrue);
    });

    // 모르면 미리 고르지 않는다(설문 9축과 같은 생각) — "상관없어요"로 열면 비흡연자가 안 고르고 "다음"만 눌러도 감점이 꺼진다.
    test('설문 답을 모르면(앱을 다시 켰으면) 두 칸 다 안 고른 상태(null)로 연다', () {
      container.read(surveyViewModelProvider.notifier).changeIsSmoker(true);
      container.invalidate(surveyViewModelProvider); // 앱을 다시 켠 것처럼 설문 상태를 비운다
      expect(container.read(surveyViewModelProvider).isSmoker, isNull);

      expect(container.read(idealConditionsViewModelProvider).acceptsSmoker, isNull);
    });

    test('모르는 채로 안 누르고 저장해도 "다음" 은 막히지 않고, 값은 null 로 간다(서버가 키 없음으로 읽는다)', () async {
      final vm = container.read(idealConditionsViewModelProvider.notifier);
      pickRequiredAppearance(vm);
      expect(container.read(idealConditionsViewModelProvider).canSubmit, isTrue);

      await vm.submit();

      expect(repository.submitted!.acceptsSmoker, isNull);
      expect(container.read(idealConditionsViewModelProvider).completed, isTrue);
    });

    test('모르는 채로 칸을 누르면 그 값이 저장 본문에 실린다', () async {
      final vm = container.read(idealConditionsViewModelProvider.notifier);
      pickRequiredAppearance(vm);

      vm.changeAcceptsSmoker(false);
      await vm.submit();

      expect(repository.submitted!.acceptsSmoker, isFalse);
    });

    // 설문 상태를 미리 만들면 뒤로가기로 돌아온 설문이 서버 답 대신 빈 값(9축 가운데 · 종교 · 흡연 미선택)으로 열린다
    // (설문 뷰모델은 앱이 켜진 동안 살아 있어, 처음 만들어질 때만 서버 답을 읽는다).
    test('설문 화면을 거치지 않았으면 설문 상태를 만들지 않는다 — 06-1 에서 뒤로가기로 설문을 다시 볼 때 서버 답으로 열리게', () {
      container.read(idealConditionsViewModelProvider);

      expect(container.exists(surveyViewModelProvider), isFalse);
    });

    test('두 칸을 누르면 값이 바뀌고, 저장 본문에 바뀐 값이 실린다', () async {
      container.read(surveyViewModelProvider.notifier).changeIsSmoker(false);
      final vm = container.read(idealConditionsViewModelProvider.notifier);
      pickRequiredAppearance(vm);

      vm.changeAcceptsSmoker(true);
      expect(container.read(idealConditionsViewModelProvider).acceptsSmoker, isTrue);
      await vm.submit();
      expect(repository.submitted!.acceptsSmoker, isTrue);

      vm.changeAcceptsSmoker(false);
      await vm.submit();
      expect(repository.submitted!.acceptsSmoker, isFalse);
    });

    test('손대지 않고 저장해도 처음 값이 본문에 실린다', () async {
      container.read(surveyViewModelProvider.notifier).changeIsSmoker(false);
      final vm = container.read(idealConditionsViewModelProvider.notifier);
      pickRequiredAppearance(vm);

      await vm.submit();

      expect(repository.submitted!.acceptsSmoker, isFalse);
    });
  });

  test('얼굴상·인상은 3개까지만 담기고 다시 누르면 빠진다', () {
    final vm = container.read(idealConditionsViewModelProvider.notifier);
    for (final type in AnimalType.values) {
      vm.toggleAnimalType(type);
    }
    expect(container.read(idealConditionsViewModelProvider).preferredAnimalTypes, hasLength(3));

    vm.toggleAnimalType(AnimalType.dog);
    expect(
      container.read(idealConditionsViewModelProvider).preferredAnimalTypes,
      isNot(contains(AnimalType.dog)),
    );

    for (final type in ImpressionType.values) {
      vm.toggleImpressionType(type);
    }
    expect(container.read(idealConditionsViewModelProvider).preferredImpressionTypes, hasLength(3));
  });

  test('MBTI 토글은 켠 극만 true 로 올라간다', () async {
    final vm = container.read(idealConditionsViewModelProvider.notifier);
    pickRequiredAppearance(vm);
    vm.toggleMbtiPole('E');
    vm.toggleMbtiPole('N');
    vm.toggleMbtiPole('E');

    await vm.submit();

    expect(repository.submitted!.preferredMbtiFlags, {'N': true});
  });

  test('"키는 상관없어요"면 키를 비우고, "나이는 상관없어요"면 전 구간으로 보낸다', () async {
    final vm = container.read(idealConditionsViewModelProvider.notifier);
    pickRequiredAppearance(vm);
    vm.changeAgeRange(25, 26);
    vm.changeHeightRange(170, 175);
    vm.changeAgeIgnored(true);
    vm.changeHeightIgnored(true);

    await vm.submit();

    expect(repository.submitted!.preferredHeightMin, isNull);
    expect(repository.submitted!.preferredHeightMax, isNull);
    expect(repository.submitted!.preferredAgeMin, IdealConditionsUiState.ageFloor);
    expect(repository.submitted!.preferredAgeMax, IdealConditionsUiState.ageCeiling);
  });

  test('얼굴상이나 인상을 고르지 않으면 "다음"이 꺼져 있다', () async {
    final vm = container.read(idealConditionsViewModelProvider.notifier);
    expect(container.read(idealConditionsViewModelProvider).canSubmit, isFalse);

    vm.toggleAnimalType(AnimalType.cat);
    expect(container.read(idealConditionsViewModelProvider).canSubmit, isFalse);

    vm.toggleImpressionType(ImpressionType.kind);
    expect(container.read(idealConditionsViewModelProvider).canSubmit, isTrue);

    await vm.submit();
    expect(repository.submitted!.preferredAnimalTypes, [AnimalType.cat]);
  });

  group('임시 저장', () {
    late FakeDraftStore drafts;

    setUp(() => drafts = FakeDraftStore());

    /// 앱을 다시 연 것처럼 새 컨테이너(새 뷰모델)를 만든다. 저장소는 같은 것을 쓴다.
    ProviderContainer open() {
      final opened = ProviderContainer(
        overrides: [
          idealConditionsRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    test('모든 조건이 저장되고 새로 만들면 돌아온다', () {
      final vm = open().read(idealConditionsViewModelProvider.notifier);
      vm.changeAgeRange(20, 30);
      vm.changeAgeIgnored(true);
      vm.changeHeightRange(160, 175);
      vm.changeHeightIgnored(true);
      vm.toggleMbtiPole('E');
      vm.toggleAnimalType(AnimalType.cat);
      vm.toggleAnimalType(AnimalType.dog);
      vm.toggleImpressionType(ImpressionType.kind);

      final restored = open().read(idealConditionsViewModelProvider);
      expect((restored.preferredAgeMin, restored.preferredAgeMax, restored.ageIgnored), (20, 30, true));
      expect((restored.preferredHeightMin, restored.preferredHeightMax, restored.heightIgnored), (160, 175, true));
      expect(restored.preferredMbtiFlags, {'E': true});
      expect(restored.preferredAnimalTypes, [AnimalType.cat, AnimalType.dog]);
      expect(restored.preferredImpressionTypes, [ImpressionType.kind]);
    });

    test('흡연하는 사람 칸도 저장되고 새로 만들면 돌아온다', () {
      final vm = open().read(idealConditionsViewModelProvider.notifier);
      vm.changeAcceptsSmoker(false);

      expect(open().read(idealConditionsViewModelProvider).acceptsSmoker, isFalse);
    });

    test('모르는 채(null)도 저장되고 새로 만들면 그대로 안 고른 상태로 돌아온다', () {
      final vm = open().read(idealConditionsViewModelProvider.notifier);
      vm.changeAgeRange(20, 30); // 다른 칸만 바꿔 draft 를 남긴다

      final restored = open().read(idealConditionsViewModelProvider);

      expect(restored.preferredAgeMin, 20);
      expect(restored.acceptsSmoker, isNull);
      expect(drafts.dump, contains('"acceptsSmoker":null'));
    });

    test('1.0.1 이 남긴 임시 저장(흡연 키 없음)도 버리지 않고 이어 연다 — 흡연 칸은 안 고른 상태(null)', () {
      drafts.saved['account-a/${DraftScreen.idealConditions.key}'] =
          '{"preferredAgeMin": 20, "preferredAgeMax": 30, "ageIgnored": false, "preferredHeightMin": 165, '
          '"preferredHeightMax": 180, "heightIgnored": false, "preferredMbtiFlags": {}, '
          '"preferredAnimalTypes": ["cat"], "preferredImpressionTypes": ["kind"]}';

      final restored = open().read(idealConditionsViewModelProvider);

      expect((restored.preferredAgeMin, restored.preferredAgeMax), (20, 30));
      expect(restored.preferredAnimalTypes, [AnimalType.cat]);
      expect(restored.acceptsSmoker, isNull);
    });

    test('"다음" 이 성공하면 이 화면 값을 지운다', () async {
      final vm = open().read(idealConditionsViewModelProvider.notifier);
      pickRequiredAppearance(vm);
      vm.changeAgeRange(20, 30);

      await vm.submit();

      expect(drafts.cleared, [DraftScreen.idealConditions]);
      expect(open().read(idealConditionsViewModelProvider).preferredAgeMin, 22);
    });

    test('범위를 벗어난 값이면 버리고 기본값으로 시작한다', () {
      drafts.saved['account-a/${DraftScreen.idealConditions.key}'] =
          '{"preferredAgeMin": 5, "preferredAgeMax": 99, "ageIgnored": false, "preferredHeightMin": 165, '
          '"preferredHeightMax": 180, "heightIgnored": false, "preferredMbtiFlags": {}, '
          '"preferredAnimalTypes": [], "preferredImpressionTypes": []}';

      expect(open().read(idealConditionsViewModelProvider).preferredAgeMin, 22);
    });
  });

  test('저장이 서버 오류로 막히면 가입 막힘으로 남긴다', () async {
    await standAt(container, onboardingRepository, OnboardingStep.idealConditions);
    repository.nextResult = const FailureResult(ServerUnavailableFailure());
    final vm = container.read(idealConditionsViewModelProvider.notifier);
    pickRequiredAppearance(vm);

    await vm.submit();

    expect(analytics.calls, ['onboarding_blocked:ideal_conditions:server']);
  });

}
