import 'dart:async';

import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_basic_info_repository.dart';
import '../model/fake_onboarding_repository.dart';

const _thisYear = 2026;

void main() {
  late FakeBasicInfoRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeBasicInfoRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        basicInfoNowProvider.overrideWithValue(() => DateTime(_thisYear, 6, 1)),
        basicInfoRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('닉네임 입력이 바뀌면 300ms 디바운스 후 중복 확인을 부른다', (tester) async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    expect(repository.checkedNicknames, ['가나다']);
  });

  testWidgets('디바운스 중 다시 입력하면 마지막 값만 확인한다', (tester) async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나');
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    expect(repository.checkedNicknames, ['가나다']);
  });

  testWidgets('중복 닉네임이면 인라인 에러를 보여준다', (tester) async {
    repository.nextAvailabilityResult = const Success(false);
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('중복닉네임');
    await tester.pump(const Duration(milliseconds: 350));
    final state = container.read(basicInfoViewModelProvider);
    expect(state.nicknameError, '이미 있는 닉네임이에요');
  });

  testWidgets('형식이 안 맞으면 서버에 묻지 않고 왜 안 되는지 알려 준다', (tester) async {
    // 종전에는 조용히 돌아가서 화면에 아무것도 안 떴다(2026-09-26 사용자 지적).
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가');
    await tester.pump(const Duration(milliseconds: 350));
    final state = container.read(basicInfoViewModelProvider);
    expect(state.nicknameError, '한글 또는 영문 2~5자로 입력해 주세요');
    expect(state.nicknameSuccess, isNull);
    expect(repository.checkedNicknames, isEmpty);
  });

  testWidgets('쓸 수 있는 닉네임이면 성공 문구를 보여준다', (tester) async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    final state = container.read(basicInfoViewModelProvider);
    expect(state.nicknameSuccess, '사용할 수 있는 닉네임이에요');
    expect(state.nicknameError, isNull);
  });

  testWidgets('서버 답을 기다리는 동안 "확인 중…" 을 보여주고, 답이 오면 내린다', (tester) async {
    repository.availabilityGate = Completer<void>();
    final vm = container.read(basicInfoViewModelProvider.notifier);

    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    expect(container.read(basicInfoViewModelProvider).nicknameChecking, '확인 중…');

    repository.availabilityGate!.complete();
    await tester.pump();

    final state = container.read(basicInfoViewModelProvider);
    expect(state.nicknameChecking, isNull);
    expect(state.nicknameSuccess, '사용할 수 있는 닉네임이에요');
  });

  testWidgets('확인이 실패하면 아무 말도 하지 않지만 도는 표시는 내린다', (tester) async {
    repository.nextAvailabilityResult = const FailureResult(NetworkFailure());
    final vm = container.read(basicInfoViewModelProvider.notifier);

    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));

    vm.changeBirthYear('2002');
    vm.changeHeight('175');
    vm.changePhoneNumber('01012345678');
    vm.changeGender('male');

    final state = container.read(basicInfoViewModelProvider);
    expect(state.nicknameChecking, isNull);
    expect(state.nicknameError, isNull);
    expect(state.nicknameSuccess, isNull);
    // 확인이 안 됐다고 04-1 에 가두지 않는다 — 진짜 중복이면 제출 때 서버가 막는다.
    expect(state.canSubmit, isTrue);
  });

  testWidgets('입력이 바뀌면 지난 판정은 그 자리에서 지운다', (tester) async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    expect(container.read(basicInfoViewModelProvider).nicknameSuccess, isNotNull);

    vm.changeNickname('가나다라');

    final state = container.read(basicInfoViewModelProvider);
    expect(state.nicknameSuccess, isNull);
    expect(state.nicknameError, isNull);

    // 마지막 입력의 디바운스를 흘려보낸다 — 살아 있는 타이머를 두고 끝내면 테스트가 실패한다.
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('조회가 끝나기 전에 입력이 바뀌면 낡은 결과는 버린다', (tester) async {
    repository.availabilityGate = Completer<void>();
    repository.nextAvailabilityResult = const Success(false);
    final vm = container.read(basicInfoViewModelProvider.notifier);

    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350)); // 조회가 시작돼 문 앞에서 기다린다
    vm.changeNickname('라마바');
    repository.availabilityGate!.complete(); // 이제야 '가나다' 조회가 끝난다
    await tester.pump();

    expect(container.read(basicInfoViewModelProvider).nicknameError, isNull);

    // '라마바' 디바운스도 흘려보낸 뒤 끝낸다.
    await tester.pump(const Duration(milliseconds: 350));
  });

  test('키는 3자리를 다 친 뒤 범위 밖일 때만 오류를 띄운다', () {
    // 치는 도중에 띄우면 한 자 칠 때마다 문구가 깜빡인다(pen 04-1 — 도움말은 필요할 때만).
    final vm = container.read(basicInfoViewModelProvider.notifier);

    vm.changeHeight('1');
    expect(container.read(basicInfoViewModelProvider).heightError, isNull);
    vm.changeHeight('17');
    expect(container.read(basicInfoViewModelProvider).heightError, isNull);

    vm.changeHeight('999');
    expect(container.read(basicInfoViewModelProvider).heightError, '숫자 3자리를 확인해 주세요');

    vm.changeHeight('175');
    expect(container.read(basicInfoViewModelProvider).heightError, isNull);
  });

  testWidgets('만 19세가 안 되는 출생연도는 "다음"이 켜지지 않는다', (tester) async {
    // 서버가 같은 기준을 본다(schemas.py MIN_AGE=19) — 앱이 더 느슨하면 422 를 받고 04-1 에 갇힌다.
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    vm.changeHeight('175');
    vm.changePhoneNumber('01012345678');
    vm.changeGender('male');

    vm.changeBirthYear('${_thisYear - 19}');
    expect(container.read(basicInfoViewModelProvider).canSubmit, isTrue);

    vm.changeBirthYear('${_thisYear - 18}');
    final state = container.read(basicInfoViewModelProvider);
    expect(state.birthYear, isNull);
    expect(state.canSubmit, isFalse);
  });

  test('출생연도는 범위를 벗어나도 오류 문구를 띄우지 않는다', () {
    // pen 04-1 에 출생연도 오류 자리가 없다 — helper "숫자 4자리"만 둔다.
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeBirthYear('1800');
    final state = container.read(basicInfoViewModelProvider);
    expect(state.birthYear, isNull);
    expect(state.canSubmit, isFalse);
  });

  testWidgets('필요한 값을 다 채우면 제출할 수 있다', (tester) async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    vm.changeBirthYear('2002');
    vm.changeHeight('175');
    vm.changePhoneNumber('01012345678');
    vm.changeGender('male');

    final state = container.read(basicInfoViewModelProvider);
    expect(state.canSubmit, isTrue);
  });

  testWidgets('하이픈은 화면에만 남기고 서버에는 숫자만 보낸다', (tester) async {
    // 저장 형식(E.164)은 서버가 정한다 — 앱이 보내는 값에 하이픈이 섞이면 저장값이 두 갈래가 된다.
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    vm.changeBirthYear('2002');
    vm.changeHeight('175');
    vm.changePhoneNumber('010-1234-5678');
    vm.changeGender('male');

    await vm.submit();

    expect(container.read(basicInfoViewModelProvider).phoneNumberInput, '010-1234-5678');
    expect(repository.submitted?.phoneNumber, '01012345678');
  });

  testWidgets('전화번호가 11자리가 되기 전에는 제출할 수 없다', (tester) async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
    vm.changeBirthYear('2002');
    vm.changeHeight('175');
    vm.changeGender('male');

    vm.changePhoneNumber('010-1234-567');
    expect(container.read(basicInfoViewModelProvider).canSubmit, isFalse);

    vm.changePhoneNumber('010-1234-5678');
    expect(container.read(basicInfoViewModelProvider).canSubmit, isTrue);
  });

  testWidgets('제출에 성공하면 completed 가 켜지고 온보딩 단계를 다시 조회한다', (tester) async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 350));
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

  test('MBTI 는 축마다 하나만 켜지고, 네 축을 다 골라야 글자가 완성된다', () {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.toggleMbtiPole('E');
    vm.toggleMbtiPole('I');

    expect(container.read(basicInfoViewModelProvider).mbtiPoles, {'I'});
    expect(container.read(basicInfoViewModelProvider).mbti, isNull);

    vm.toggleMbtiPole('N');
    vm.toggleMbtiPole('T');
    vm.toggleMbtiPole('J');

    expect(container.read(basicInfoViewModelProvider).mbti, 'INTJ');
  });

  test('"모름"을 누르면 고른 MBTI 가 비워지고, 다시 고르면 모름이 꺼진다', () {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    for (final pole in ['I', 'N', 'T', 'J']) {
      vm.toggleMbtiPole(pole);
    }

    vm.toggleMbtiUnknown();

    final unknown = container.read(basicInfoViewModelProvider);
    expect(unknown.isMbtiUnknown, isTrue);
    expect(unknown.mbtiPoles, isEmpty);
    expect(unknown.mbti, isNull);

    vm.toggleMbtiPole('E');

    final again = container.read(basicInfoViewModelProvider);
    expect(again.isMbtiUnknown, isFalse);
    expect(again.mbtiPoles, {'E'});
  });
}
