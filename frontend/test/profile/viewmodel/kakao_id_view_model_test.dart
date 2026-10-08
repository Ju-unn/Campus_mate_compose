import 'dart:io';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/draft/shared_preferences_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
