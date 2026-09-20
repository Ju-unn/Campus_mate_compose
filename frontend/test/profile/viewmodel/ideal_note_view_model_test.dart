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

  test('건너뛰어도 빈 문자열을 저장해 다시 묻지 않게 한다', () async {
    await container.read(idealNoteViewModelProvider.notifier).skip();

    expect(repository.submittedNote, '');
    expect(container.read(idealNoteViewModelProvider).completed, isTrue);
    expect(onboardingRepository.fetchCount, 1);
  });

  test('쓴 글은 앞뒤 공백을 떼고 저장한다', () async {
    final vm = container.read(idealNoteViewModelProvider.notifier);
    vm.changeNote('  대화가 잘 통하는 사람  ');

    await vm.submit();

    expect(repository.submittedNote, '대화가 잘 통하는 사람');
  });

  test('아무것도 쓰지 않으면 "다음"으로는 저장되지 않는다', () async {
    await container.read(idealNoteViewModelProvider.notifier).submit();

    expect(repository.submittedNote, isNull);
  });
}
