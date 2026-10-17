import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/viewmodel/onboarding_back_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../account/model/fake_account_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  late FakeOnboardingRepository onboarding;
  late FakeMeRepository me;
  late FakeAccountRepository account;
  late ProviderContainer container;

  setUp(() {
    onboarding = FakeOnboardingRepository();
    me = FakeMeRepository(const Success(savedOnboardingProfile));
    account = FakeAccountRepository();
    container = ProviderContainer(
      overrides: [
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        meRepositoryProvider.overrideWithValue(me),
        accountRepositoryProvider.overrideWithValue(account),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> serverAt(OnboardingStep step) async {
    onboarding.nextResult = Success(step);
    await container.read(onboardingStepListenableProvider).refresh();
  }

  OnboardingStep? step() => container.read(onboardingStepListenableProvider).value;
  OnboardingBackViewModel viewModel() => container.read(onboardingBackViewModelProvider.notifier);

  test('뒤로가면 내 프로필을 새로 읽은 뒤 앞 단계로 간다', () async {
    await serverAt(OnboardingStep.kakaoId);
    // 전에 읽어 둔 값이 있어도 다시 읽는다 — 그사이 저장한 값이 바뀌었을 수 있다.
    await container.read(myProfileProvider.future);

    await viewModel().goBack();

    expect(me.calls, 2);
    expect(step(), OnboardingStep.basicInfo);
    expect(container.read(myProfileProvider).value, isA<Success<Object?>>());
  });

  test('앞 단계가 04-1b 면 카카오톡 아이디도 읽어 둔다(폰에는 남기지 않는다)', () async {
    await serverAt(OnboardingStep.photos);

    await viewModel().goBack();

    expect(account.kakaoIdFetches, 1);
    expect(step(), OnboardingStep.kakaoId);
  });

  test('앞 단계가 04-1b 가 아니면 카카오톡 아이디는 읽지 않는다', () async {
    await serverAt(OnboardingStep.myTraits);

    await viewModel().goBack();

    expect(account.kakaoIdFetches, 0);
    expect(step(), OnboardingStep.interests);
  });

  test('읽는 동안은 불러오는 중이고, 두 번 눌러도 한 단계만 간다', () async {
    await serverAt(OnboardingStep.survey);
    me.holdFetch = Completer<void>();

    final first = viewModel().goBack();
    final second = viewModel().goBack();
    expect(container.read(onboardingBackViewModelProvider), isTrue);
    expect(step(), OnboardingStep.survey, reason: '다 읽기 전에는 화면을 바꾸지 않는다');

    me.holdFetch!.complete();
    await Future.wait([first, second]);

    expect(step(), OnboardingStep.myTraits);
    expect(me.calls, 1);
    expect(container.read(onboardingBackViewModelProvider), isFalse);
  });

  test('읽기에 실패해도(인터넷 없음) 앞 단계로 간다 — 메모리에 없는 칸은 빈 칸이 된다', () async {
    await serverAt(OnboardingStep.photos);
    me.profile = const FailureResult(NetworkFailure());
    account.kakaoIdResult = const FailureResult(NetworkFailure());

    await viewModel().goBack();

    expect(step(), OnboardingStep.kakaoId);
    expect(container.read(onboardingBackViewModelProvider), isFalse);
  });

  test('갈 앞 단계가 없으면(04-1 · 04-4) 아무것도 읽지 않고 그대로 둔다', () async {
    for (final server in [OnboardingStep.basicInfo, OnboardingStep.appearanceType]) {
      await serverAt(server);

      await viewModel().goBack();

      expect(step(), server);
    }
    expect(me.calls, 0);
  });
}
