import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

import '../model/fake_ideal_conditions_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../../core/draft/fake_draft_store.dart';

void main() {
  late FakeIdealConditionsRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeIdealConditionsRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        idealConditionsRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
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
}
