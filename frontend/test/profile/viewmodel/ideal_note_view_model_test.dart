import 'package:campus_mate/profile/model/ideal_note_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_ideal_note_repository.dart';
import '../model/fake_onboarding_repository.dart';

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

  test('공백만 쓴 글로는 "다음"이 켜지지 않는다', () {
    container.read(idealNoteViewModelProvider.notifier).changeNote('   ');

    expect(container.read(idealNoteViewModelProvider).canSubmit, isFalse);
  });

  test('공백을 뗀 9자로는 "다음"이 켜지지 않는다 — 최소 10자', () {
    container.read(idealNoteViewModelProvider.notifier).changeNote('  말이잘통하는사람요  ');

    final state = container.read(idealNoteViewModelProvider);
    expect(state.canSubmit, isFalse);
    expect(state.lengthMessage, '10자 이상 입력해 주세요');
  });

  test('10자를 채우면 "다음"이 켜지고 길이 안내가 사라진다', () {
    container.read(idealNoteViewModelProvider.notifier).changeNote('말 잘 통하는 사람');

    final state = container.read(idealNoteViewModelProvider);
    expect(state.canSubmit, isTrue);
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
}
