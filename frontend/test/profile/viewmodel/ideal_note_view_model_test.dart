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
}
