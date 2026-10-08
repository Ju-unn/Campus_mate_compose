import 'package:campus_mate/profile/model/ideal_note_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

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
