import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/ideal_conditions_edit_view_model.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

import '../../profile/model/fake_ideal_conditions_repository.dart';
import '../../profile/model/fake_onboarding_repository.dart';
import '../model/fake_me_repository.dart';
import '../../core/draft/fake_draft_store.dart';

MyProfile _profile({
  int? ageMin = 25,
  int? ageMax = 30,
  int? heightMin = 160,
  int? heightMax = 175,
}) =>
    MyProfile(
      nickname: '여우',
      age: 23,
      university: '가나대학교',
      major: null,
      heightCm: null,
      mbti: null,
      avatarUrl: null,
      preferredAgeMin: ageMin,
      preferredAgeMax: ageMax,
      preferredHeightMin: heightMin,
      preferredHeightMax: heightMax,
      bio: '안녕하세요',
      preferredMbtiFlags: const {'E': true, 'N': true},
      preferredAnimalTypes: const [AnimalType.dog, AnimalType.fox],
      preferredImpressionTypes: const [ImpressionType.kind],
    );

void main() {
  late FakeMeRepository me;
  late FakeIdealConditionsRepository conditions;
  late FakeOnboardingRepository onboarding;
  late ProviderContainer container;
  late ProviderSubscription<IdealConditionsUiState> subscription;
  late FakeDraftStore drafts;

  Future<void> open(MyProfile profile) async {
    drafts = FakeDraftStore();
    me = FakeMeRepository(Success(profile));
    conditions = FakeIdealConditionsRepository();
    onboarding = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        idealConditionsRepositoryProvider.overrideWithValue(conditions),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        draftStoreProvider.overrideWithValue(drafts),
      ],
    );
    addTearDown(container.dispose);
    // 06-1 편집은 화면 15 의 선호 행에서 열린다 — 그때는 내 프로필이 이미 읽혀 있다.
    await container.read(myProfileProvider.future);
    subscription = container.listen(idealConditionsEditViewModelProvider, (_, _) {});
  }

  IdealConditionsEditViewModel viewModel() => container.read(idealConditionsEditViewModelProvider.notifier);

  test('열면 서버 값으로 채워진다 — 나이 · 키 · MBTI · 얼굴상 · 인상', () async {
    await open(_profile());

    final state = subscription.read();
    expect((state.preferredAgeMin, state.preferredAgeMax, state.ageIgnored), (25, 30, false));
    expect((state.preferredHeightMin, state.preferredHeightMax, state.heightIgnored), (160, 175, false));
    expect(state.preferredMbtiFlags, {'E': true, 'N': true});
    expect(state.preferredAnimalTypes, [AnimalType.dog, AnimalType.fox]);
    expect(state.preferredImpressionTypes, [ImpressionType.kind]);
    expect(state.canSubmit, isTrue);
  });

  test('나이가 전 구간(19~35)이면 "나이는 상관없어요" 가 켜진 채 열린다(화면 15 결정 3 과 같은 뜻), 슬라이더는 기본 22~27', () async {
    await open(_profile(ageMin: IdealConditionsUiState.ageFloor, ageMax: IdealConditionsUiState.ageCeiling));

    final state = subscription.read();
    expect((state.ageIgnored, state.preferredAgeMin, state.preferredAgeMax), (true, 22, 27));
  });

  test('선호 키가 비었으면 "키는 상관없어요" 가 켜진 채 열린다, 슬라이더는 기본 165~180', () async {
    await open(_profile(heightMin: null, heightMax: null));

    final state = subscription.read();
    expect((state.heightIgnored, state.preferredHeightMin, state.preferredHeightMax), (true, 165, 180));
  });

  test('저장 본문은 온보딩과 같은 규칙 — 키 무시는 null, 나이 무시는 19 · 35', () async {
    await open(_profile(ageMin: 19, ageMax: 35, heightMin: null, heightMax: null));

    await viewModel().submit();

    final sent = conditions.submitted!;
    expect((sent.preferredAgeMin, sent.preferredAgeMax), (19, 35));
    expect((sent.preferredHeightMin, sent.preferredHeightMax), (null, null));
    expect(sent.preferredMbtiFlags, {'E': true, 'N': true});
    expect(sent.preferredAnimalTypes, [AnimalType.dog, AnimalType.fox]);
    expect(sent.preferredImpressionTypes, [ImpressionType.kind]);
  });

  test('저장하면 화면 15 값을 다시 읽게 한다 — 온보딩 단계는 조회하지 않는다', () async {
    await open(_profile());

    await viewModel().submit();
    await container.read(myProfileProvider.future);

    expect(subscription.read().completed, isTrue);
    expect(me.calls, 2);
    expect(onboarding.fetchCount, 0);
  });

  test('저장이 실패하면 문구를 보이고 끝나지 않는다', () async {
    await open(_profile());
    conditions.nextResult = const FailureResult(NetworkFailure());

    await viewModel().submit();

    expect(subscription.read().completed, isFalse);
    expect(subscription.read().errorMessage, const NetworkFailure().toDisplayMessage());
    expect(me.calls, 1);
  });

  test('온보딩 모드는 그대로 — 저장 뒤 온보딩 단계를 다시 조회하고 화면 15 값은 건드리지 않는다', () async {
    await open(_profile());
    final onboardingViewModel = container.read(idealConditionsViewModelProvider.notifier);
    onboardingViewModel.toggleAnimalType(AnimalType.cat);
    onboardingViewModel.toggleImpressionType(ImpressionType.kind);

    await onboardingViewModel.submit();
    await Future<void>.delayed(Duration.zero);

    expect(onboarding.fetchCount, 1);
    expect(me.calls, 1);
  });

  test('저장 중에 화면을 떠나도(autoDispose) 끝난 저장이 오류를 내지 않고 화면 15 는 다시 읽힌다', () async {
    await open(_profile());
    conditions.hold = Completer<void>();
    final saving = viewModel().submit();

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    conditions.hold!.complete();
    await saving;
    await container.read(myProfileProvider.future);

    expect(me.calls, 2);
  });

  test('ideal_conditions_edit_is_filled_from_the_server_each_time_it_opens — 고르다 만 값은 닫으면 사라진다(Review Focus 5)', () async {
    await open(_profile());
    viewModel().changeAgeRange(20, 21);
    viewModel().toggleAnimalType(AnimalType.dog);

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    subscription = container.listen(idealConditionsEditViewModelProvider, (_, _) {});

    final state = subscription.read();
    expect((state.preferredAgeMin, state.preferredAgeMax), (25, 30));
    expect(state.preferredAnimalTypes, [AnimalType.dog, AnimalType.fox]);
  });

  test('편집 모드는 임시 저장을 하지 않는다 — 온보딩 값을 쓰지도 지우지도 않는다', () async {
    // 편집은 열 때마다 서버 값으로 채운다. 고르다 만 값이 온보딩 임시 저장 자리에 섞이면 안 된다.
    await open(_profile());
    viewModel().changeAgeRange(24, 29);

    await viewModel().submit();

    expect(subscription.read().completed, isTrue);
    expect(drafts.saved, isEmpty);
    expect(drafts.cleared, isEmpty);
  });
}
