import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/bio_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/bio_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

import '../model/fake_bio_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../../core/draft/fake_draft_store.dart';

void main() {
  late FakeBioRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeBioRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        bioRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('초안 생성 화면 진입 시 자동으로 draft API 를 부르고 결과를 06-3 입력값으로 채운다', () async {
    await container.read(bioViewModelProvider.notifier).loadDraft();

    final state = container.read(bioViewModelProvider);
    expect(state.bio, '안녕하세요! 활발한 성격이에요.');
    expect(state.draftLoaded, isTrue);
    expect(state.isLoadingDraft, isFalse);
  });

  test('생성 실패하면 빈 값으로 06-3 에 진입하되 왜 비었는지 알려 준다', () async {
    repository.nextDraftResult = const FailureResult<String>(UnknownFailure());

    await container.read(bioViewModelProvider.notifier).loadDraft();

    final state = container.read(bioViewModelProvider);
    expect(state.bio, '');
    expect(state.draftLoaded, isTrue);
    expect(state.errorMessage, '초안을 만들지 못했어요. 직접 써 주세요');
  });

  test('초안은 한 번만 부른다(서버는 두 번째부터 저장해 둔 초안을 그대로 준다)', () async {
    final vm = container.read(bioViewModelProvider.notifier);
    await vm.loadDraft();
    await vm.loadDraft();

    expect(repository.draftCount, 1);
  });

  test('자기소개를 저장하면 온보딩 단계를 다시 조회한다', () async {
    final vm = container.read(bioViewModelProvider.notifier);
    vm.changeBio('  같이 밥 먹을 사람 찾아요  ');

    await vm.submit();

    expect(repository.submittedBio, '같이 밥 먹을 사람 찾아요');
    expect(container.read(bioViewModelProvider).completed, isTrue);
    expect(onboardingRepository.fetchCount, 1);
  });

  test('자기소개가 비어 있으면 저장하지 않는다', () async {
    await container.read(bioViewModelProvider.notifier).submit();

    expect(repository.submittedBio, isNull);
  });

  test('"직접 쓸게요"를 누르면 기다리지 않고 06-3 으로 넘어간다', () async {
    final vm = container.read(bioViewModelProvider.notifier);
    final pending = vm.loadDraft();

    vm.skipDraft();

    final skipped = container.read(bioViewModelProvider);
    expect(skipped.isLoadingDraft, isFalse);
    expect(skipped.draftLoaded, isTrue);

    await pending;
  });

  test('"직접 쓸게요" 뒤 늦게 온 초안은 사용자가 쓰던 글을 덮지 않는다', () async {
    final vm = container.read(bioViewModelProvider.notifier);
    final pending = vm.loadDraft();

    vm.skipDraft();
    vm.changeBio('제가 직접 쓴 소개예요');
    await pending;

    expect(container.read(bioViewModelProvider).bio, '제가 직접 쓴 소개예요');
  });

  group('임시 저장', () {
    late FakeDraftStore drafts;

    setUp(() => drafts = FakeDraftStore());

    /// 앱을 다시 연 것처럼 새 컨테이너(새 뷰모델)를 만든다. 저장소는 같은 것을 쓴다.
    ProviderContainer open() {
      final opened = ProviderContainer(
        overrides: [
          bioRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    test('사용자가 고친 글은 저장되고, 새로 만들면 그 글로 06-3 에 바로 들어간다(초안을 다시 만들지 않는다)', () async {
      final vm = open().read(bioViewModelProvider.notifier);
      await vm.loadDraft();
      vm.changeBio('직접 고친 자기소개');
      final draftsBefore = repository.draftCount;

      final reopened = open();
      await reopened.read(bioViewModelProvider.notifier).loadDraft();

      final restored = reopened.read(bioViewModelProvider);
      expect(restored.bio, '직접 고친 자기소개');
      expect(restored.draftLoaded, isTrue);
      expect(repository.draftCount, draftsBefore, reason: '고친 글을 AI 초안으로 덮지 않는다');
    });

    test('글만 저장한다 — 안내 문구 · 진행 표시는 남기지 않는다', () async {
      repository.nextDraftResult = const FailureResult<String>(UnknownFailure());
      final vm = open().read(bioViewModelProvider.notifier);
      await vm.loadDraft();
      vm.changeBio('직접 쓴 글');

      expect(drafts.dump, contains('직접 쓴 글'));
      expect(drafts.dump, isNot(contains('초안을 만들지 못했어요')));
    });

    test('AI 초안이 도착한 순간의 글도 저장된다 — 고치기 전에 꺼져도 같은 글로 06-3 에 바로 들어간다', () async {
      // 06-3 입력칸의 글이 바뀔 때마다 남긴다. 초안 도착(빈 글 → 초안)도 그 변화 중 하나다.
      await open().read(bioViewModelProvider.notifier).loadDraft();
      final draftsBefore = repository.draftCount;

      final reopened = open();
      await reopened.read(bioViewModelProvider.notifier).loadDraft();

      expect(drafts.dump, contains('안녕하세요! 활발한 성격이에요.'));
      expect(reopened.read(bioViewModelProvider).bio, '안녕하세요! 활발한 성격이에요.');
      expect(repository.draftCount, draftsBefore, reason: '초안을 다시 만들지 않는다');
    });

    test('빈 글은 복원하지 않는다 — 다시 열면 초안부터 받는다', () {
      open().read(bioViewModelProvider.notifier).changeBio('   ');

      expect(open().read(bioViewModelProvider).draftLoaded, isFalse);
    });

    test('"다음" 이 성공하면 이 화면 값을 지운다', () async {
      final vm = open().read(bioViewModelProvider.notifier);
      vm.changeBio('저장할 자기소개');

      await vm.submit();

      expect(drafts.cleared, [DraftScreen.bio]);
      expect(open().read(bioViewModelProvider).bio, isEmpty);
    });
  });
}
