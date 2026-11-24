import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/ideal/viewmodel/ideal_intro_view_model.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../onboarding/model/repository/fake_onboarding_repository.dart';

void main() {
  late FakeOnboardingRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeOnboardingRepository()..nextResult = const Success(OnboardingStep.idealConditions);
    container = ProviderContainer(overrides: [onboardingRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
  });

  IdealIntroViewModel viewModel() => container.read(idealIntroViewModelProvider.notifier);

  test('가입 길에서 06-1 에 처음 들어오면 보인다', () async {
    await container.read(onboardingStepListenableProvider).refresh();

    expect(viewModel().shouldShow(), isTrue);
  });

  test('한 번 보인 뒤에는(06-1 에서 설문으로 돌아갔다 다시 와도) 다시 안 보인다', () async {
    await container.read(onboardingStepListenableProvider).refresh();

    viewModel().markSeen();

    expect(viewModel().shouldShow(), isFalse);
  });

  test('06-2 에서 뒤로 돌아온 06-1(다시 보는 중)에서는 안 보인다', () async {
    await revisit(container, repository, server: OnboardingStep.idealTraits, visiting: OnboardingStep.idealConditions);

    expect(viewModel().shouldShow(), isFalse);
  });
}
