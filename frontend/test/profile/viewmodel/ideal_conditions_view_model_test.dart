import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_ideal_conditions_repository.dart';
import '../model/fake_onboarding_repository.dart';

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

  test('아무것도 고치지 않아도 기본 범위 그대로 제출할 수 있다', () async {
    await container.read(idealConditionsViewModelProvider.notifier).submit();

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
    vm.toggleMbtiPole('E');
    vm.toggleMbtiPole('N');
    vm.toggleMbtiPole('E');

    await vm.submit();

    expect(repository.submitted!.preferredMbtiFlags, {'N': true});
  });

  test('"키는 상관없어요"면 키를 비우고, "나이는 상관없어요"면 전 구간으로 보낸다', () async {
    final vm = container.read(idealConditionsViewModelProvider.notifier);
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
}
