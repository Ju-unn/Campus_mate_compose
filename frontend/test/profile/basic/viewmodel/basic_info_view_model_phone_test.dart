import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/profile/basic/model/data/phone_code_sent.dart';
import 'package:campus_mate/profile/basic/model/repository/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/basic/viewmodel/basic_info_view_model.dart';
import 'package:campus_mate/profile/basic/viewmodel/phone_verify_ui_state.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/analytics/fake_analytics_service.dart';
import '../../onboarding/model/repository/fake_onboarding_repository.dart';
import '../model/repository/fake_basic_info_repository.dart';

/// 04-1 휴대폰 문자 인증(pen 2c ①~⑬)의 흐름. 시계는 가짜다 — 테스트가 [now] 를 옮기고 같은 만큼 타이머를 돌린다.
Matcher _kind(AppError error) => isA<AppErrorFailure>().having((failure) => failure.error, 'error', error);

const _phone = '010-0135-2468';
const _digits = '01001352468';

PhoneCodeSent _sent(int resend, int expires, {bool alreadySent = false}) => PhoneCodeSent(
      resendAfter: Duration(seconds: resend),
      expiresIn: Duration(seconds: expires),
      alreadySent: alreadySent,
    );

ServerRejectedFailure _rejected(String code, {int? remaining}) =>
    ServerRejectedFailure('server', code: code, remainingAttempts: remaining);

void main() {
  late FakeBasicInfoRepository repository;
  late ProviderContainer container;
  late DateTime now;

  setUp(() {
    repository = FakeBasicInfoRepository();
    now = DateTime(2026, 6, 1, 12);
    container = ProviderContainer(
      overrides: [
        basicInfoNowProvider.overrideWithValue(() => now),
        basicInfoRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      ],
    );
  });

  tearDown(() => container.dispose());

  BasicInfoViewModel vm() => container.read(basicInfoViewModelProvider.notifier);
  PhoneVerifyUiState phone() => container.read(basicInfoViewModelProvider).phoneVerify;

  /// 가짜 시계를 [by] 만큼 옮기고 1초 타이머를 그만큼 돌린다.
  Future<void> elapse(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(by);
  }

  /// 기본 정보의 다른 필수 칸을 채운다(번호는 인증 전). 닉네임 중복 확인(300ms)까지 끝낸다.
  Future<void> fillOthers(WidgetTester tester) async {
    vm()
      ..changeNickname('가나다')
      ..changeBirthYear('2002')
      ..changeHeight('175')
      ..changeGender('male');
    await tester.pump(const Duration(milliseconds: 350));
  }

  group('① ② 번호 입력', () {
    test('11자리를 다 치기 전에는 인증번호를 받을 수 없다', () {
      vm().changePhoneNumber('010-0135-246');
      expect(container.read(basicInfoViewModelProvider).canSendCode, isFalse);

      vm().changePhoneNumber(_phone);
      expect(container.read(basicInfoViewModelProvider).canSendCode, isTrue);
    });

    test('가입용 번호 규칙에 걸리는 번호는 받을 수 없고 상태 줄에 이유를 띄운다', () {
      vm().changePhoneNumber('010-1234-5678');

      final state = container.read(basicInfoViewModelProvider);
      expect(state.canSendCode, isFalse);
      expect(state.phoneStatusError, _kind(AppError.phoneInvalid));
    });

    test('받을 수 없는 번호로 sendCode 를 불러도 서버에 가지 않는다', () async {
      vm().changePhoneNumber('010-0135-24');

      await vm().sendCode();

      expect(repository.sentPhones, isEmpty);
    });
  });

  group('⑩ ③ 인증번호 받기', () {
    testWidgets('보내는 동안 isSending 이고 두 번 눌러도 한 번만 간다', (tester) async {
      repository.sendGate = Completer<void>();
      vm().changePhoneNumber(_phone);

      unawaited(vm().sendCode());
      unawaited(vm().sendCode());
      await tester.pump();

      expect(phone().isSending, isTrue);
      expect(phone().isPhoneLocked, isTrue, reason: '보내는 동안 번호 칸은 잠긴다(⑩)');
      expect(repository.sentPhones, [_digits], reason: '숫자만 보낸다');

      repository.sendGate!.complete();
      await tester.pump();

      expect(phone().isSending, isFalse);
      expect(phone().step, PhoneVerifyStep.codeSent);
      container.dispose();
    });

    testWidgets('서버가 준 초로 인증 시간 · 다시 받기를 센다', (tester) async {
      repository.nextSendResult = Success(_sent(45, 179));
      vm().changePhoneNumber(_phone);

      await vm().sendCode();

      expect(phone().codeSecondsLeft, 179);
      expect(phone().resendSecondsLeft, 45);
      expect(container.read(basicInfoViewModelProvider).canSendCode, isFalse, reason: '③ 받기 버튼은 회색');
      container.dispose();
    });

    testWidgets('[확인] 은 인증번호가 6자리가 되기 전에는 꺼져 있다(사용자 결정 11-10)', (tester) async {
      repository.nextVerifyResult = FailureResult(_rejected('phone_code_mismatch', remaining: 4));
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      expect(phone().canVerify, isFalse, reason: '빈 칸');
      await vm().changeCode('48291');
      expect(phone().canVerify, isFalse, reason: '5자리');

      await vm().changeCode('482915'); // 6자리 — 자동 확인 뒤 ④ 로 남는다
      expect(phone().canVerify, isTrue, reason: '6자리가 그대로 남은 ④ 는 분홍');
      container.dispose();
    });

    testWidgets('1초마다 줄고, 다시 받기가 0 이 되면 다시 받을 수 있다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      await elapse(tester, const Duration(seconds: 15));
      expect(phone().codeSecondsLeft, 165);
      expect(phone().resendSecondsLeft, 45);

      await elapse(tester, const Duration(seconds: 45));
      expect(phone().resendSecondsLeft, 0);
      expect(container.read(basicInfoViewModelProvider).canSendCode, isTrue);
      container.dispose();
    });

    testWidgets('⑤ 인증 시간이 0 이 되면 시간 지남 오류를 띄우고 확인을 끈다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      await elapse(tester, const Duration(seconds: 180));

      expect(phone().codeSecondsLeft, 0);
      expect(phone().isCodeExpired, isTrue);
      expect(phone().codeError, _kind(AppError.phoneCodeExpired));
      expect(phone().canVerify, isFalse);
      expect(container.read(basicInfoViewModelProvider).canSendCode, isTrue, reason: '⑤ 다시 받기 분홍');
    });

    testWidgets('다시 받으면 적던 인증번호 · 오류를 지우고 시간을 새로 센다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      await elapse(tester, const Duration(seconds: 180));

      await vm().sendCode();

      expect(repository.sentPhones, [_digits, _digits]);
      expect(phone().codeError, isNull);
      expect(phone().codeInput, '');
      expect(phone().codeSecondsLeft, 180);
      expect(phone().resendSecondsLeft, 60);
      container.dispose();
    });

    testWidgets('already_sent 는 오류가 아니다 — 문자 없이 남은 시간을 이어서 센다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      await vm().changeCode('12');
      await elapse(tester, const Duration(seconds: 60));
      repository.nextSendResult = Success(_sent(5, 115, alreadySent: true));

      await vm().sendCode();

      expect(phone().step, PhoneVerifyStep.codeSent);
      expect(phone().codeSecondsLeft, 115);
      expect(phone().resendSecondsLeft, 5);
      expect(phone().codeInput, '12', reason: '새 문자가 아니라 적던 인증번호는 그대로다');
      expect(phone().error, isNull);
      container.dispose();
    });

    testWidgets('번호를 고치면 인증번호 줄과 시간이 사라지고 ② 로 돌아간다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      vm().changePhoneNumber('010-0135-246');

      expect(phone().step, PhoneVerifyStep.idle);
      expect(phone().codeSecondsLeft, 0);
      expect(phone().resendSecondsLeft, 0);
      await elapse(tester, const Duration(seconds: 2));
      expect(phone().codeError, isNull, reason: '멈춘 타이머가 시간 지남을 띄우지 않는다');
    });

    testWidgets('하이픈만 다시 그려진 같은 번호는 지우지 않는다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      vm().changePhoneNumber(_digits);

      expect(phone().step, PhoneVerifyStep.codeSent);
      container.dispose();
    });
  });

  group('받기 실패', () {
    test('⑦ 409 phone_number_in_use 는 상태 줄 오류이고 받기는 다시 켜진다', () async {
      repository.nextSendResult = FailureResult(_rejected('phone_number_in_use'));
      vm().changePhoneNumber(_phone);

      await vm().sendCode();

      final state = container.read(basicInfoViewModelProvider);
      expect(state.phoneVerify.step, PhoneVerifyStep.idle);
      expect(state.phoneStatusError, _kind(AppError.phoneInUse));
      expect(state.phoneVerify.isInUse, isTrue);
      expect(state.canSendCode, isTrue);
    });

    test('400 phone_number_invalid 는 010 줄이고 같은 번호로는 다시 받지 않는다 — 번호를 고치면 걷힌다', () async {
      repository.nextSendResult = FailureResult(_rejected('phone_number_invalid'));
      vm().changePhoneNumber(_phone);

      await vm().sendCode();

      expect(container.read(basicInfoViewModelProvider).phoneStatusError, _kind(AppError.phoneNotMobile));
      expect(container.read(basicInfoViewModelProvider).canSendCode, isFalse);

      vm().changePhoneNumber('010-5932-8406');

      expect(container.read(basicInfoViewModelProvider).phoneStatusError, isNull);
      expect(container.read(basicInfoViewModelProvider).canSendCode, isTrue);
    });

    testWidgets('⑫ 429 가 60초를 넘으면 오늘 한도 — 인증번호 줄을 닫고 받기를 끈다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      await elapse(tester, const Duration(seconds: 60));
      repository.nextSendResult = const FailureResult(RateLimitedFailure('server', 3600));

      await vm().sendCode();

      final state = container.read(basicInfoViewModelProvider);
      expect(state.phoneVerify.step, PhoneVerifyStep.idle);
      expect(state.phoneStatusError, _kind(AppError.phoneDailyLimit));
      expect(state.canSendCode, isFalse);
      expect(state.phoneVerify.isInUse, isFalse, reason: '⑫ 번호 칸은 빨간 테두리가 아니다');
      container.dispose();
    });

    testWidgets('⑫ 오늘 한도는 1초 시계를 돌리지 않고 받기를 회색으로 둔다 — 번호를 고치면 풀린다', (tester) async {
      repository.nextSendResult = const FailureResult(RateLimitedFailure('server', 36000));
      vm().changePhoneNumber(_phone);
      var changes = 0;
      container.listen(basicInfoViewModelProvider, (_, _) => changes++);

      await vm().sendCode();
      final afterLimit = changes;
      await elapse(tester, const Duration(seconds: 5));

      expect(changes, afterLimit, reason: '몇 시간 동안 매초 다시 그리지 않는다');
      expect(container.read(basicInfoViewModelProvider).canSendCode, isFalse);

      vm().changePhoneNumber('010-5932-8406');

      final state = container.read(basicInfoViewModelProvider);
      expect(state.phoneStatusError, isNull);
      expect(state.canSendCode, isTrue);
      // container 를 닫지 않고 끝낸다 — 시계가 돌고 있으면 testWidgets 가 끝에서 "Timer is still pending" 으로 실패한다.
    });

    testWidgets('429 가 60초 이하면 다시 받기 시간만 센다 — 인증번호 줄은 그대로', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      await elapse(tester, const Duration(seconds: 60));
      repository.nextSendResult = const FailureResult(RateLimitedFailure('server', 20));

      await vm().sendCode();

      expect(phone().step, PhoneVerifyStep.codeSent);
      expect(phone().resendSecondsLeft, 20);
      expect(phone().error, isNull);
      await elapse(tester, const Duration(seconds: 20));
      expect(container.read(basicInfoViewModelProvider).canSendCode, isTrue);
      container.dispose();
    });

    testWidgets('첫 받기가 429(60초 이하)면 "잠시 후" 줄을 띄우고 그 시간 동안 받기를 끈다', (tester) async {
      repository.nextSendResult = const FailureResult(RateLimitedFailure('server', 30));
      vm().changePhoneNumber(_phone);

      await vm().sendCode();

      expect(phone().step, PhoneVerifyStep.idle);
      expect(phone().error, _kind(AppError.tryLater));
      expect(container.read(basicInfoViewModelProvider).canSendCode, isFalse);
      await elapse(tester, const Duration(seconds: 29));
      expect(phone().error, _kind(AppError.tryLater), reason: '아직 기다리는 중');
      await elapse(tester, const Duration(seconds: 1));
      expect(container.read(basicInfoViewModelProvider).canSendCode, isTrue);
      expect(phone().error, isNull, reason: '받기가 다시 켜지면 "잠시 후" 줄은 걷힌다');
    });

    test('503 sms_unavailable 은 "잠시 후" 줄이고 바로 다시 누를 수 있다', () async {
      repository.nextSendResult = const FailureResult(ServerUnavailableFailure());
      vm().changePhoneNumber(_phone);

      await vm().sendCode();

      expect(container.read(basicInfoViewModelProvider).phoneStatusError, _kind(AppError.tryLater));
      expect(container.read(basicInfoViewModelProvider).canSendCode, isTrue);
    });

    test('네트워크 실패는 그 종류 그대로 상태 줄에 띄운다', () async {
      repository.nextSendResult = const FailureResult(NetworkFailure());
      vm().changePhoneNumber(_phone);

      await vm().sendCode();

      expect(container.read(basicInfoViewModelProvider).phoneStatusError, isA<NetworkFailure>());
    });
  });

  group('⑪ 확인', () {
    testWidgets('6자리를 치면 한 번만 자동으로 확인한다 — 확인 중에 또 불러도 한 번이다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      repository.verifyGate = Completer<void>();

      await vm().changeCode('48291');
      expect(repository.verifiedCodes, isEmpty, reason: '5자리는 보내지 않는다');

      unawaited(vm().changeCode('482915'));
      unawaited(vm().verifyCode());
      await tester.pump();

      expect(phone().isVerifying, isTrue);
      expect(phone().isPhoneLocked, isTrue);
      expect(repository.verifiedCodes, [(_digits, '482915')]);

      repository.verifyGate!.complete();
      await tester.pump();
      expect(repository.verifiedCodes, hasLength(1));
    });

    testWidgets('⑥ 맞으면 인증됨 — 인증번호 줄을 닫고 시계를 멈춘다', (tester) async {
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      await vm().changeCode('482915');

      final state = container.read(basicInfoViewModelProvider);
      expect(state.phoneVerify.step, PhoneVerifyStep.verified);
      expect(state.isPhoneVerified, isTrue);
      expect(state.phoneVerify.isPhoneLocked, isTrue);
      expect(state.canSendCode, isFalse);
      // 시계가 멈췄다 — 남은 타이머가 있으면 testWidgets 가 끝에서 실패한다.
    });

    testWidgets('④ 틀리면 남은 기회를 든 오류 — 인증번호를 고치면 오류가 걷힌다', (tester) async {
      repository.nextVerifyResult = FailureResult(_rejected('phone_code_mismatch', remaining: 4));
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      await vm().changeCode('482915');

      expect(phone().codeError, isA<PhoneCodeMismatchFailure>().having((f) => f.remaining, 'remaining', 4));
      expect(phone().step, PhoneVerifyStep.codeSent);
      expect(phone().canVerify, isTrue, reason: '④ 확인 분홍 유지');

      await vm().changeCode('48291');
      expect(phone().codeError, isNull);
      container.dispose();
    });

    testWidgets('⑬ 5번 틀려 잠기면 확인을 끄고 번호 칸을 잠근다 — 다시 받기로 푼다', (tester) async {
      repository.nextVerifyResult = FailureResult(_rejected('phone_code_locked'));
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      await vm().changeCode('123456');

      expect(phone().isCodeLocked, isTrue);
      expect(phone().codeError, _kind(AppError.phoneCodeLocked));
      expect(phone().canVerify, isFalse);
      expect(phone().isPhoneLocked, isTrue);

      await elapse(tester, const Duration(seconds: 60));
      repository.nextVerifyResult = const Success(null);
      await vm().sendCode();

      expect(phone().isCodeLocked, isFalse);
      expect(phone().codeError, isNull);
      container.dispose();
    });

    testWidgets('서버가 phone_code_expired 면 ⑤ — 남은 시간을 0 으로 내린다', (tester) async {
      repository.nextVerifyResult = FailureResult(_rejected('phone_code_expired'));
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      await vm().changeCode('123456');

      expect(phone().codeError, _kind(AppError.phoneCodeExpired));
      expect(phone().codeSecondsLeft, 0);
      expect(phone().isCodeExpired, isTrue);
      container.dispose();
    });

    testWidgets('확인 실패(네트워크)는 인증번호 줄 오류이고 확인을 다시 누를 수 있다', (tester) async {
      repository.nextVerifyResult = const FailureResult(NetworkFailure());
      vm().changePhoneNumber(_phone);
      await vm().sendCode();

      await vm().changeCode('123456');

      expect(phone().codeError, isA<NetworkFailure>());
      repository.nextVerifyResult = const Success(null);
      await vm().verifyCode();
      expect(phone().step, PhoneVerifyStep.verified);
    });
  });

  group('번호 바꾸기 · 다음', () {
    testWidgets('인증된 번호여야만 "다음" 이 켜진다', (tester) async {
      await fillOthers(tester);
      vm().changePhoneNumber(_phone);
      expect(container.read(basicInfoViewModelProvider).canSubmit, isFalse);

      await vm().sendCode();
      await vm().changeCode('482915');

      expect(container.read(basicInfoViewModelProvider).canSubmit, isTrue);
    });

    testWidgets('번호 바꾸기는 인증을 지우고 번호 칸을 연다 — 다시 인증해야 "다음" 이 켜진다', (tester) async {
      await fillOthers(tester);
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      await vm().changeCode('482915');

      vm().changePhoneAgain();

      final state = container.read(basicInfoViewModelProvider);
      expect(state.phoneVerify.step, PhoneVerifyStep.idle);
      expect(state.phoneVerify.isPhoneLocked, isFalse);
      expect(state.isPhoneVerified, isFalse);
      expect(state.canSubmit, isFalse);
      expect(state.canSendCode, isTrue);
    });

    testWidgets('저장이 422 phone_not_verified 면 ⑤ 처럼 인증번호를 다시 받으라고 한다', (tester) async {
      await fillOthers(tester);
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      await vm().changeCode('482915');
      repository.nextSubmitResult = FailureResult(_rejected('phone_not_verified'));

      await vm().submit();

      final state = container.read(basicInfoViewModelProvider);
      expect(state.error, isNull, reason: '버튼 위 오류가 아니라 인증번호 줄 오류다');
      expect(state.isPhoneVerified, isFalse);
      expect(state.phoneVerify.step, PhoneVerifyStep.codeSent);
      expect(state.phoneVerify.isCodeExpired, isTrue);
      expect(state.phoneVerify.codeError, _kind(AppError.phoneCodeExpired));
      expect(state.canSendCode, isTrue);
      expect(state.canSubmit, isFalse);
    });

    testWidgets('저장이 409 phone_number_in_use 면 ⑦', (tester) async {
      await fillOthers(tester);
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      await vm().changeCode('482915');
      repository.nextSubmitResult = FailureResult(_rejected('phone_number_in_use'));

      await vm().submit();

      final state = container.read(basicInfoViewModelProvider);
      expect(state.error, isNull);
      expect(state.phoneVerify.step, PhoneVerifyStep.idle);
      expect(state.phoneStatusError, _kind(AppError.phoneInUse));
      expect(state.canSubmit, isFalse);
    });

    testWidgets('code 없는 409(닉네임 · 잠금)는 종전대로 버튼 위 오류이고 인증은 그대로다', (tester) async {
      await fillOthers(tester);
      vm().changePhoneNumber(_phone);
      await vm().sendCode();
      await vm().changeCode('482915');
      repository.nextSubmitResult = const FailureResult(ServerRejectedFailure('이미 있는 닉네임이에요'));

      await vm().submit();

      final state = container.read(basicInfoViewModelProvider);
      expect(state.error, isA<ServerRejectedFailure>());
      expect(state.isPhoneVerified, isTrue);
    });
  });

  testWidgets('화면을 닫으면(뷰모델 폐기) 1초 타이머도 멈춘다', (tester) async {
    vm().changePhoneNumber(_phone);
    await vm().sendCode();

    container.dispose();
    // 남은 타이머가 있으면 testWidgets 가 끝에서 "Timer is still pending" 으로 실패한다.
    await tester.pump(const Duration(seconds: 2));
  });
}
