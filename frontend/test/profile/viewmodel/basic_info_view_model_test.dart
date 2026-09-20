import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_view_model.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_basic_info_repository.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  late FakeBasicInfoRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeBasicInfoRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        basicInfoRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('닉네임 입력이 바뀌면 300ms 디바운스 후 중복 확인을 부른다', () async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(repository.checkedNicknames, ['가나다']);
  });

  test('디바운스 중 다시 입력하면 마지막 값만 확인한다', () async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나');
    vm.changeNickname('가나다');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(repository.checkedNicknames, ['가나다']);
  });

  test('중복 닉네임이면 인라인 에러를 보여준다', () async {
    repository.nextAvailabilityResult = const Success(false);
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('중복닉네임');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final state = container.read(basicInfoViewModelProvider);
    expect(state.nicknameError, '이미 있는 닉네임이에요');
  });

  test('필요한 값을 다 채우면 제출할 수 있다', () async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    vm.changeBirthYear('2002');
    vm.changeHeight('175');
    vm.changePhoneNumber('01012345678');
    vm.changeGender('male');

    final state = container.read(basicInfoViewModelProvider);
    expect(state.canSubmit, isTrue);
  });

  test('제출에 성공하면 completed 가 켜지고 온보딩 단계를 다시 조회한다', () async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    vm.changeBirthYear('2002');
    vm.changeHeight('175');
    vm.changePhoneNumber('01012345678');
    vm.changeGender('male');

    await vm.submit();

    final state = container.read(basicInfoViewModelProvider);
    expect(state.completed, isTrue);
    expect(repository.submitted?.nickname, '가나다');
    expect(onboardingRepository.fetchCount, 1);
  });
}
