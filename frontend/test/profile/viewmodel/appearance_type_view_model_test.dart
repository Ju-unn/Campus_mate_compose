import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/appearance_type_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/appearance_type_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_appearance_type_repository.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  late FakeAppearanceTypeRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeAppearanceTypeRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        appearanceTypeRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('동물상만 고르면 아직 제출할 수 없다', () {
    container.read(appearanceTypeViewModelProvider.notifier).changeAnimalType(AnimalType.cat);
    expect(container.read(appearanceTypeViewModelProvider).canSubmit, isFalse);
  });

  test('동물상과 인상을 모두 고르면 제출할 수 있다', () {
    final vm = container.read(appearanceTypeViewModelProvider.notifier);
    vm.changeAnimalType(AnimalType.cat);
    vm.changeImpressionType(ImpressionType.chic);
    expect(container.read(appearanceTypeViewModelProvider).canSubmit, isTrue);
  });

  test('제출에 성공하면 고른 값이 그대로 올라가고 온보딩 단계를 다시 조회한다', () async {
    final vm = container.read(appearanceTypeViewModelProvider.notifier);
    vm.changeAnimalType(AnimalType.fox);
    vm.changeImpressionType(ImpressionType.innocent);

    await vm.submit();

    expect(container.read(appearanceTypeViewModelProvider).completed, isTrue);
    expect(repository.submittedAnimalType, AnimalType.fox);
    expect(repository.submittedImpressionType, ImpressionType.innocent);
    expect(onboardingRepository.fetchCount, 1);
  });

  test('제출에 실패하면 오류 문구가 남고 온보딩 단계를 다시 조회하지 않는다', () async {
    repository.nextResult = const FailureResult<void>(UnknownFailure());
    final vm = container.read(appearanceTypeViewModelProvider.notifier);
    vm.changeAnimalType(AnimalType.dog);
    vm.changeImpressionType(ImpressionType.kind);

    await vm.submit();

    final state = container.read(appearanceTypeViewModelProvider);
    expect(state.completed, isFalse);
    expect(state.errorMessage, isNotNull);
    expect(onboardingRepository.fetchCount, 0);
  });
}
