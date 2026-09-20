import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/model/survey_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/survey_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_onboarding_repository.dart';
import '../model/fake_survey_repository.dart';

void main() {
  late FakeSurveyRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeSurveyRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        surveyRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('9축을 전부 답하고 종교·흡연을 고르면 제출 가능하다', () {
    final vm = container.read(surveyViewModelProvider.notifier);
    for (var axis = 1; axis <= 9; axis++) {
      vm.answer(axis, 0.5);
    }
    vm.changeReligion(Religion.none);
    vm.changeIsSmoker(false);
    final state = container.read(surveyViewModelProvider);
    expect(state.canSubmit, isTrue);
  });

  test('축이 하나라도 빠지면 제출할 수 없다', () {
    final vm = container.read(surveyViewModelProvider.notifier);
    for (var axis = 1; axis <= 8; axis++) {
      vm.answer(axis, 0.5);
    }
    vm.changeReligion(Religion.none);
    vm.changeIsSmoker(false);
    final state = container.read(surveyViewModelProvider);
    expect(state.canSubmit, isFalse);
  });

  test('제출에 성공하면 completed 가 켜지고 온보딩 단계를 다시 조회한다', () async {
    final vm = container.read(surveyViewModelProvider.notifier);
    for (var axis = 1; axis <= 9; axis++) {
      vm.answer(axis, 0.5);
    }
    vm.changeReligion(Religion.protestant);
    vm.changeIsSmoker(true);

    await vm.submit();

    final state = container.read(surveyViewModelProvider);
    expect(state.completed, isTrue);
    expect(repository.submittedReligion, Religion.protestant);
    expect(repository.submittedIsSmoker, isTrue);
    expect(repository.submittedAnswers, hasLength(9));
    expect(onboardingRepository.fetchCount, 1);
  });
}
