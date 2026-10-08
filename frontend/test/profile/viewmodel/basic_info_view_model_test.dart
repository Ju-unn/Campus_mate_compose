import 'dart:async';

import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/draft/shared_preferences_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/fake_basic_info_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../../core/draft/fake_draft_store.dart';

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

  testWidgets('300ms 가 차기 전에는 중복 확인을 부르지 않는다', (tester) async {
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeNickname('가나다');
    await tester.pump(const Duration(milliseconds: 290));
    expect(repository.checkedNicknames, isEmpty);

    await tester.pump(const Duration(milliseconds: 20));
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

  test('출생연도는 4자리를 다 친 뒤 나이가 모자랄 때만 "○○년생부터" 오류를 띄운다', () {
    // 서버 422 문구(schemas.py)와 같다(사용자 결정 2026-09-29). 치는 도중엔 띄우지 않는다 — 키 칸과 같은 방식.
    final vm = container.read(basicInfoViewModelProvider.notifier);

    vm.changeBirthYear('201');
    expect(container.read(basicInfoViewModelProvider).birthYearError, isNull);

    vm.changeBirthYear('${_thisYear - 18}');
    expect(container.read(basicInfoViewModelProvider).birthYearError, '${_thisYear - 19}년생부터 가입할 수 있어요');

    vm.changeBirthYear('${_thisYear - 19}');
    expect(container.read(basicInfoViewModelProvider).birthYearError, isNull);
  });

  test('1950 이전 출생연도는 오류 문구 없이 "다음"만 꺼진다', () {
    // 문구는 나이 미달에만 단다(사용자 결정 2026-09-29) — 그 밖은 helper "숫자 4자리"만 둔다.
    final vm = container.read(basicInfoViewModelProvider.notifier);
    vm.changeBirthYear('1800');
    final state = container.read(basicInfoViewModelProvider);
    expect(state.birthYear, isNull);
    expect(state.birthYearError, isNull);
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

  group('임시 저장', () {
    late FakeDraftStore drafts;

    setUp(() => drafts = FakeDraftStore());

    /// 앱을 다시 연 것처럼 새 컨테이너(새 뷰모델)를 만든다. 저장소는 같은 것을 쓴다.
    ProviderContainer open({DraftStore? store}) {
      final opened = ProviderContainer(
        overrides: [
          basicInfoNowProvider.overrideWithValue(() => DateTime(_thisYear, 6, 1)),
          basicInfoRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          draftStoreProvider.overrideWithValue(store ?? drafts),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    const phone = '010-1234-5678';

    void fillAll(BasicInfoViewModel vm) {
      vm.changeNickname('가나다');
      vm.changeBirthYear('2000');
      vm.changeHeight('170');
      vm.changePhoneNumber(phone);
      vm.changeGender('female');
      vm.toggleMbtiPole('E');
      vm.toggleMbtiPole('N');
    }

    test('쓰던 값은 저장되고, 뷰모델을 새로 만들면 전화번호만 빼고 그대로 돌아온다', () {
      fillAll(open().read(basicInfoViewModelProvider.notifier));

      final restored = open().read(basicInfoViewModelProvider);
      expect(restored.nicknameInput, '가나다');
      expect(restored.birthYearInput, '2000');
      expect(restored.heightInput, '170');
      expect(restored.gender, 'female');
      expect(restored.mbtiPoles, {'E', 'N'});
      expect(restored.phoneNumberInput, isEmpty, reason: '전화번호는 다시 입력받는다');
    });

    test('MBTI "모름" 도 돌아온다', () {
      open().read(basicInfoViewModelProvider.notifier).toggleMbtiUnknown();

      expect(open().read(basicInfoViewModelProvider).isMbtiUnknown, isTrue);
    });

    test('전화번호는 저장소에 들어가지 않는다', () {
      fillAll(open().read(basicInfoViewModelProvider.notifier));

      expect(drafts.dump, contains('가나다'), reason: '나머지 값은 저장돼야 이 시험이 뜻이 있다');
      for (final piece in ['1234', '5678', '01012345678', phone]) {
        expect(drafts.dump, isNot(contains(piece)));
      }
    });

    testWidgets('진짜 저장소(shared_preferences)로도 전화번호는 디스크에 남지 않는다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesDraftStore(preferences, accountId: () => 'account-a');

      fillAll(open(store: store).read(basicInfoViewModelProvider.notifier));
      await tester.pump(const Duration(seconds: 1));

      final disk = [for (final key in preferences.getKeys()) '$key=${preferences.get(key)}'].join('\n');
      expect(disk, contains('가나다'));
      expect(disk, isNot(contains('1234')));
      expect(disk, isNot(contains('5678')));
    });

    test('"다음" 이 성공하면 이 화면 값을 지운다', () async {
      final vm = open().read(basicInfoViewModelProvider.notifier);
      fillAll(vm);

      await vm.submit();

      expect(drafts.cleared, contains(DraftScreen.basicInfo));
      expect(open().read(basicInfoViewModelProvider).nicknameInput, isEmpty);
    });

    test('"다음" 이 실패하면 값은 남는다', () async {
      repository.nextSubmitResult = const FailureResult(NetworkFailure());
      final vm = open().read(basicInfoViewModelProvider.notifier);
      fillAll(vm);

      await vm.submit();

      expect(drafts.cleared, isEmpty);
      expect(open().read(basicInfoViewModelProvider).nicknameInput, '가나다');
    });

    test('다른 계정으로 로그인하면 앞사람 값이 보이지 않는다', () {
      fillAll(open().read(basicInfoViewModelProvider.notifier));

      drafts.accountId = 'account-b';

      expect(open().read(basicInfoViewModelProvider).nicknameInput, isEmpty);
    });

    test('모양이 맞지 않는 값은 버리고 빈 화면으로 시작한다', () {
      drafts.saved['account-a/${DraftScreen.basicInfo.key}'] = '{"nickname": 42}';

      final state = open().read(basicInfoViewModelProvider);

      expect(state.nicknameInput, isEmpty);
      expect(drafts.saved, isEmpty);
    });
  });
}
