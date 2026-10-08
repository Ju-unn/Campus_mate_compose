import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/appearance_type_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/appearance_type_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

import '../model/fake_appearance_type_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../../core/draft/fake_draft_store.dart';

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

  group('임시 저장', () {
    late FakeDraftStore drafts;

    setUp(() => drafts = FakeDraftStore());

    /// 앱을 다시 연 것처럼 새 컨테이너(새 뷰모델)를 만든다. 저장소는 같은 것을 쓴다.
    ProviderContainer open() {
      final opened = ProviderContainer(
        overrides: [
          appearanceTypeRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    test('고른 값은 저장되고 뷰모델을 새로 만들면 돌아온다', () {
      final vm = open().read(appearanceTypeViewModelProvider.notifier);
      vm.changeAnimalType(AnimalType.fox);
      vm.changeImpressionType(ImpressionType.tofu);

      final restored = open().read(appearanceTypeViewModelProvider);
      expect(restored.animalType, AnimalType.fox);
      expect(restored.impressionType, ImpressionType.tofu);
    });

    test('"다음" 이 성공하면 이 화면 값을 지운다', () async {
      final vm = open().read(appearanceTypeViewModelProvider.notifier);
      vm.changeAnimalType(AnimalType.fox);
      vm.changeImpressionType(ImpressionType.tofu);

      await vm.submit();

      expect(drafts.cleared, [DraftScreen.appearanceType]);
      expect(open().read(appearanceTypeViewModelProvider).animalType, isNull);
    });

    test('모르는 값(앱 업데이트로 사라진 종류)이면 버리고 빈 화면으로 시작한다', () {
      drafts.saved['account-a/${DraftScreen.appearanceType.key}'] = '{"animalType": "unicorn"}';

      expect(open().read(appearanceTypeViewModelProvider).animalType, isNull);
    });
  });
}
