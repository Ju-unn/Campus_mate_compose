import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_kakao_id_repository.dart';
import '../model/fake_onboarding_repository.dart';

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
}
