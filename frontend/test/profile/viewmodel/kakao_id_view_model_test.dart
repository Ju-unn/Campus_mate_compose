import 'dart:io';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/draft/shared_preferences_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../account/model/fake_account_repository.dart';
import '../model/fake_kakao_id_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../../core/draft/fake_draft_store.dart';

void main() {
  late FakeKakaoIdRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeKakaoIdRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        kakaoIdRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('빈 값이면 제출할 수 없다', () {
    final vm = container.read(kakaoIdViewModelProvider.notifier);
    vm.changeKakaoId('   ');
    expect(container.read(kakaoIdViewModelProvider).canSubmit, isFalse);
  });

  test('값을 채우면 제출할 수 있고 성공하면 completed 가 켜진다', () async {
    final vm = container.read(kakaoIdViewModelProvider.notifier);
    vm.changeKakaoId('my_kakao_id');
    await vm.submit();
    expect(repository.submitted, ['my_kakao_id']);
    expect(container.read(kakaoIdViewModelProvider).completed, isTrue);
    expect(onboardingRepository.fetchCount, 1);
  });

  test('다시 보는 04-1b 를 저장하면 서버 단계(04-2)에 닿아 다시 보기가 끝난다', () async {
    await revisit(container, onboardingRepository, server: OnboardingStep.photos, visiting: OnboardingStep.kakaoId);
    final vm = container.read(kakaoIdViewModelProvider.notifier);
    vm.changeKakaoId('my_kakao_id');

    await vm.submit();

    final steps = container.read(onboardingStepListenableProvider);
    expect(steps.value, OnboardingStep.photos);
    expect(steps.isRevisiting, isFalse);
  });

  // 뷰모델은 앱이 켜진 동안 살아 있어 첫 저장의 completed 가 남는다 — 다시 저장이 실패하면 그대로 머물러야 한다.
  test('같은 세션에서 다시 저장이 실패하면 다음 화면으로 넘어가지 않는다', () async {
    final vm = container.read(kakaoIdViewModelProvider.notifier);
    vm.changeKakaoId('my_kakao_id');
    await vm.submit();
    await revisit(container, onboardingRepository, server: OnboardingStep.photos, visiting: OnboardingStep.kakaoId);
    repository.nextResult = const FailureResult(NetworkFailure());

    await vm.submit();

    expect(container.read(onboardingStepListenableProvider).value, OnboardingStep.kakaoId);
    expect(container.read(kakaoIdViewModelProvider).errorMessage, isNotNull);
    expect(onboardingRepository.fetchCount, 0);
  });

  group('되돌아온 04-1b 채우기', () {
    late FakeAccountRepository account;
    late FakeDraftStore drafts;
    late ProviderContainer revisiting;

    setUp(() {
      account = FakeAccountRepository()..kakaoIdResult = const Success('fox_rain_22');
      drafts = FakeDraftStore();
      revisiting = ProviderContainer(
        overrides: [
          kakaoIdRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          accountRepositoryProvider.overrideWithValue(account),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      addTearDown(revisiting.dispose);
    });

    test('04-2 에서 돌아오면 저장해 둔 카카오톡 아이디로 채우고, 폰 임시 저장에는 남기지 않는다', () async {
      await revisit(revisiting, onboardingRepository, server: OnboardingStep.photos, visiting: OnboardingStep.kakaoId);
      await revisiting.read(savedKakaoIdProvider.future);

      final state = revisiting.read(kakaoIdViewModelProvider);
      revisiting.read(kakaoIdViewModelProvider.notifier).changeKakaoId('fox_rain_23');

      expect(state.kakaoIdInput, 'fox_rain_22');
      expect(state.canSubmit, isTrue);
      expect(drafts.saved, isEmpty);
      expect(drafts.dump, isNot(contains('fox_rain')));
    });

    test('다시 보는 중이 아니면 카카오톡 아이디를 읽지 않고 빈 칸으로 연다', () async {
      onboardingRepository.nextResult = const Success(OnboardingStep.kakaoId);
      await revisiting.read(onboardingStepListenableProvider).refresh();

      expect(revisiting.read(kakaoIdViewModelProvider).kakaoIdInput, isEmpty);
      expect(account.kakaoIdFetches, 0);
    });

    test('미리 읽어 둔 아이디가 없으면 뷰모델이 서버를 부르지 않는다', () async {
      await revisit(revisiting, onboardingRepository, server: OnboardingStep.photos, visiting: OnboardingStep.kakaoId);

      expect(revisiting.read(kakaoIdViewModelProvider).kakaoIdInput, isEmpty);
      expect(account.kakaoIdFetches, 0);
    });

    test('읽기에 실패했으면 빈 칸으로 연다', () async {
      account.kakaoIdResult = const FailureResult(NetworkFailure());
      await revisit(revisiting, onboardingRepository, server: OnboardingStep.photos, visiting: OnboardingStep.kakaoId);
      await revisiting.read(savedKakaoIdProvider.future);

      expect(revisiting.read(kakaoIdViewModelProvider).kakaoIdInput, isEmpty);
    });
  });

  test('제출에 실패하면 errorMessage 가 채워진다', () async {
    repository.nextResult = const FailureResult(UnknownFailure());
    final vm = container.read(kakaoIdViewModelProvider.notifier);
    vm.changeKakaoId('my_kakao_id');
    await vm.submit();
    expect(container.read(kakaoIdViewModelProvider).errorMessage, isNotNull);
    expect(container.read(kakaoIdViewModelProvider).completed, isFalse);
  });

  group('임시 저장하지 않는다', () {
    // 카카오톡 아이디는 평문으로 폰에 남기지 않는다(2026-10-08 사용자 결정) — 저장 대상 화면 목록에도 없다.
    ProviderContainer open(DraftStore store) {
      final opened = ProviderContainer(
        overrides: [
          kakaoIdRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          draftStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    test('카카오톡 아이디는 저장소에 들어가지 않고, 다시 열면 빈 칸이다', () async {
      final drafts = FakeDraftStore();
      final vm = open(drafts).read(kakaoIdViewModelProvider.notifier);
      vm.changeKakaoId('secret_kakao');
      repository.nextResult = const FailureResult(NetworkFailure());
      await vm.submit();

      expect(drafts.saved, isEmpty);
      expect(drafts.dump, isNot(contains('secret_kakao')));
      expect(open(drafts).read(kakaoIdViewModelProvider).kakaoIdInput, isEmpty);
    });

    testWidgets('진짜 저장소(shared_preferences)로도 디스크에 남지 않는다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesDraftStore(
        preferences,
        accountId: () => 'account-a',
        fileDirectory: Directory.systemTemp.path,
      );

      open(store).read(kakaoIdViewModelProvider.notifier).changeKakaoId('secret_kakao');
      await tester.pump(const Duration(seconds: 1));

      expect(preferences.getKeys(), isEmpty);
    });
  });
}
