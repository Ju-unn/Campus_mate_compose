import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/ideal_note_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

import '../../me/model/fake_me_repository.dart';
import '../model/fake_ideal_note_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../../core/draft/fake_draft_store.dart';

void main() {
  late FakeIdealNoteRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeIdealNoteRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        idealNoteRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('쓴 글은 앞뒤 공백을 떼고 저장한다', () async {
    final vm = container.read(idealNoteViewModelProvider.notifier);
    vm.changeNote('  대화가 잘 통하는 사람  ');

    await vm.submit();

    expect(repository.submittedNote, '대화가 잘 통하는 사람');
  });

  test('06-2b 에서 돌아온 06-2a 를 저장하면 06-2b 로 돌아가 다시 보기가 끝난다', () async {
    await revisit(container, onboardingRepository, server: OnboardingStep.bio, visiting: OnboardingStep.idealNote);
    final vm = container.read(idealNoteViewModelProvider.notifier);
    vm.changeNote('대화가 잘 통하는 사람이면 좋겠어요');

    await vm.submit();

    final steps = container.read(onboardingStepListenableProvider);
    expect(steps.value, OnboardingStep.bio);
    expect(steps.isRevisiting, isFalse);
  });

  // 뷰모델은 앱이 켜진 동안 살아 있어 첫 저장의 completed 가 남는다 — 다시 저장이 실패하면 그대로 머물러야 한다.
  test('같은 세션에서 다시 저장이 실패하면 다음 화면으로 넘어가지 않는다', () async {
    final vm = container.read(idealNoteViewModelProvider.notifier);
    vm.changeNote('대화가 잘 통하는 사람이면 좋겠어요');
    await vm.submit();
    await revisit(container, onboardingRepository, server: OnboardingStep.bio, visiting: OnboardingStep.idealNote);
    repository.nextResult = const FailureResult(NetworkFailure());

    await vm.submit();

    expect(container.read(onboardingStepListenableProvider).value, OnboardingStep.idealNote);
    expect(container.read(idealNoteViewModelProvider).completed, isFalse);
    expect(container.read(idealNoteViewModelProvider).errorMessage, isNotNull);
    expect(onboardingRepository.fetchCount, 0);
  });

  group('되돌아온 06-2a 채우기', () {
    ProviderContainer open({FakeDraftStore? drafts, Result<MyProfile> profile = const Success(savedOnboardingProfile)}) {
      final opened = ProviderContainer(
        overrides: [
          idealNoteRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          meRepositoryProvider.overrideWithValue(FakeMeRepository(profile)),
          if (drafts != null) draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    test('06-2b 에서 돌아온 06-2a 는 저장해 둔 이상형 글로 채워진다', () async {
      final revisiting = open();
      await revisiting.read(myProfileProvider.future);
      await revisit(revisiting, onboardingRepository, server: OnboardingStep.bio, visiting: OnboardingStep.idealNote);

      expect(revisiting.read(idealNoteViewModelProvider).note, savedOnboardingProfile.idealNote);
    });

    test('같은 세션에서 돌아온 06-2a 는 메모리 값 그대로다', () async {
      final revisiting = open();
      revisiting.read(idealNoteViewModelProvider.notifier).changeNote('쓰던 글');
      await revisiting.read(myProfileProvider.future);
      await revisit(revisiting, onboardingRepository, server: OnboardingStep.bio, visiting: OnboardingStep.idealNote);

      expect(revisiting.read(idealNoteViewModelProvider).note, '쓰던 글');
    });

    test('폰 임시 저장이 서버 값보다 먼저다', () async {
      final drafts = FakeDraftStore();
      drafts.saved['account-a/${DraftScreen.idealNote.key}'] = '{"note": "폰에 남긴 글"}';
      final revisiting = open(drafts: drafts);
      await revisiting.read(myProfileProvider.future);
      await revisit(revisiting, onboardingRepository, server: OnboardingStep.bio, visiting: OnboardingStep.idealNote);

      expect(revisiting.read(idealNoteViewModelProvider).note, '폰에 남긴 글');
    });

    test('서버 글을 못 읽었으면 빈 칸이다', () async {
      final revisiting = open(profile: const FailureResult(NetworkFailure()));
      await revisiting.read(myProfileProvider.future);
      await revisit(revisiting, onboardingRepository, server: OnboardingStep.bio, visiting: OnboardingStep.idealNote);

      expect(revisiting.read(idealNoteViewModelProvider).note, isEmpty);
    });
  });

  test('아무것도 쓰지 않으면 저장하지 않는다 — 건너뛰는 길은 없다', () async {
    await container.read(idealNoteViewModelProvider.notifier).submit();

    expect(repository.submittedNote, isNull);
    expect(container.read(idealNoteViewModelProvider).completed, isFalse);
  });

  test('공백만 써도 "다음"은 눌린다 — 누르면 빨간 오류로 이유를 알려준다', () {
    container.read(idealNoteViewModelProvider.notifier).changeNote('   ');

    expect(container.read(idealNoteViewModelProvider).canSubmit, isTrue);
  });

  test('공백을 뗀 9자면 쓰는 도중 회색 안내가 나오고 오류는 아직 없다', () {
    container.read(idealNoteViewModelProvider.notifier).changeNote('  말이잘통하는사람요  ');

    final state = container.read(idealNoteViewModelProvider);
    expect(state.lengthMessage, '10자 이상 입력해 주세요');
    expect(state.errorMessage, isNull);
  });

  test('10자를 채우면 "다음"이 켜지고 길이 안내가 사라진다', () {
    container.read(idealNoteViewModelProvider.notifier).changeNote('말 잘 통하는 사람');

    final state = container.read(idealNoteViewModelProvider);
    expect(state.lengthMessage, isNull);
  });

  test('아직 아무것도 쓰지 않았으면 길이 안내를 보여주지 않는다', () {
    expect(container.read(idealNoteViewModelProvider).lengthMessage, isNull);
  });

  test('10자 미만이면 저장을 부르지 않는다', () async {
    final vm = container.read(idealNoteViewModelProvider.notifier);
    vm.changeNote('말이잘통하는사람요');

    await vm.submit();

    expect(repository.submittedNote, isNull);
  });

  test('10자 전에 "다음"을 누르면 저장하지 않고 빨간 오류를 띄운다', () async {
    final vm = container.read(idealNoteViewModelProvider.notifier);
    vm.changeNote('말이잘통하는사람요');

    await vm.submit();

    expect(repository.submittedNote, isNull);
    expect(container.read(idealNoteViewModelProvider).errorMessage, '10자 이상 입력해 주세요');
  });

  test('아무것도 안 쓰고 "다음"을 눌러도 빨간 오류를 띄운다', () async {
    await container.read(idealNoteViewModelProvider.notifier).submit();

    expect(container.read(idealNoteViewModelProvider).errorMessage, '10자 이상 입력해 주세요');
  });

  test('오류 뒤에 다시 쓰면 오류가 지워지고, 10자 전이면 회색 안내로 돌아간다', () async {
    final vm = container.read(idealNoteViewModelProvider.notifier);
    vm.changeNote('말이잘통하는');
    await vm.submit();

    vm.changeNote('말이잘통하는사');

    final state = container.read(idealNoteViewModelProvider);
    expect(state.errorMessage, isNull);
    expect(state.lengthMessage, '10자 이상 입력해 주세요');
  });

  group('임시 저장', () {
    late FakeDraftStore drafts;

    setUp(() => drafts = FakeDraftStore());

    /// 앱을 다시 연 것처럼 새 컨테이너(새 뷰모델)를 만든다. 저장소는 같은 것을 쓴다.
    ProviderContainer open() {
      final opened = ProviderContainer(
        overrides: [
          idealNoteRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    test('쓰던 글은 저장되고 새로 만들면 돌아온다', () {
      open().read(idealNoteViewModelProvider.notifier).changeNote('대화가 잘 통하는');

      expect(open().read(idealNoteViewModelProvider).note, '대화가 잘 통하는');
    });

    test('"다음" 이 성공하면 이 화면 값을 지운다', () async {
      final vm = open().read(idealNoteViewModelProvider.notifier);
      vm.changeNote('대화가 잘 통하는 사람이 좋아요');

      await vm.submit();

      expect(drafts.cleared, [DraftScreen.idealNote]);
      expect(open().read(idealNoteViewModelProvider).note, isEmpty);
    });

    test('짧아서 보내지 않았으면 글은 남는다', () async {
      final vm = open().read(idealNoteViewModelProvider.notifier);
      vm.changeNote('짧은 글');

      await vm.submit();

      expect(drafts.cleared, isEmpty);
      expect(open().read(idealNoteViewModelProvider).note, '짧은 글');
    });

    test('다른 계정으로 로그인하면 앞사람 글이 보이지 않는다', () {
      open().read(idealNoteViewModelProvider.notifier).changeNote('앞사람이 쓰던 글');

      drafts.accountId = 'account-b';

      expect(open().read(idealNoteViewModelProvider).note, isEmpty);
    });
  });
}
