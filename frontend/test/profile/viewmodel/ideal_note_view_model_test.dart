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
}
