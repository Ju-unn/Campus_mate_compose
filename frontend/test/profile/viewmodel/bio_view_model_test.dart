import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/bio_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/bio_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_bio_repository.dart';
import '../model/fake_onboarding_repository.dart';

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
}
