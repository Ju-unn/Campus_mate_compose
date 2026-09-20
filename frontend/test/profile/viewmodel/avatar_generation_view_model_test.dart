import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_avatar_repository.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  late FakeAvatarRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeAvatarRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        avatarRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('생성에 성공하면 ready 상태가 되고 completed 가 켜진다', () async {
    repository.nextResult = const Success(AvatarReady('aa/uuid.png'));
    final vm = container.read(avatarGenerationViewModelProvider.notifier);

    await vm.generate();

    final state = container.read(avatarGenerationViewModelProvider);
    expect(state.status, AvatarGenerationStatus.ready);
    expect(state.avatarPath, 'aa/uuid.png');
    expect(state.completed, isTrue);
    expect(onboardingRepository.fetchCount, 1);
  });

  test('아바타 생성 실패 응답을 받으면 다시 시도 버튼을 보여준다', () async {
    repository.nextResult = const Success(AvatarFailed());
    final vm = container.read(avatarGenerationViewModelProvider.notifier);

    await vm.generate();

    final state = container.read(avatarGenerationViewModelProvider);
    expect(state.canRetry, isTrue);
    expect(state.completed, isFalse);
  });

  test('fallback 응답을 받으면 보상 하트 안내 다이얼로그 상태를 켠다', () async {
    repository.nextResult = const Success(AvatarFallback(10));
    final vm = container.read(avatarGenerationViewModelProvider.notifier);

    await vm.generate();

    final state = container.read(avatarGenerationViewModelProvider);
    expect(state.showCompensationDialog, isTrue);
    expect(state.compensationHearts, 10);
    expect(state.completed, isTrue);
  });
}
