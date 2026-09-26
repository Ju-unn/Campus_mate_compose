import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/model/survey_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/survey_ui_state.dart';
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

  test('9축 모두 가운데 값이 미리 골라져 있다', () {
    // pen `mkf89` 는 가운데 점이 골라진 채로 열린다 — 아무 쪽도 아닌 사람이 그냥 지나갈 수 있어야 한다.
    final state = container.read(surveyViewModelProvider);
    expect(state.answers, hasLength(9));
    expect(state.answers.values.every((value) => value == 0), isTrue);
  });

  test('축이 하나라도 빠지면 제출할 수 없다', () {
    // 기본값이 생겨 화면에서는 이 상태가 안 나오지만, 서버 계약은 9축을 다 요구한다.
    const state = SurveyUiState(
      answers: {1: 0.5, 2: 0.5, 3: 0.5, 4: 0.5, 5: 0.5, 6: 0.5, 7: 0.5, 8: 0.5},
      religion: Religion.none,
      isSmoker: false,
    );
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
