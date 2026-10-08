import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/sign_up_view_model.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/fake_school_email_repository.dart';
import '../model/fake_verification_gate_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  late FakeVerificationGateRepository gateRepository;

  setUp(() => gateRepository = FakeVerificationGateRepository()
    ..nextResult = const Success(VerificationGate.needsStudentVerification));

  ProviderContainer buildContainer(FakeSchoolEmailRepository repository, {DateTime Function()? now}) {
    final container = ProviderContainer(
      overrides: [
        schoolEmailRepositoryProvider.overrideWithValue(repository),
        verificationGateRepositoryProvider.overrideWithValue(gateRepository),
        if (now != null) verifyCodeNowProvider.overrideWithValue(now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('올바른 코드를 제출하면 verified 가 true', () async {
    final container = buildContainer(FakeSchoolEmailRepository());
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    expect(container.read(verifyCodeViewModelProvider(email)).verified, isTrue);
  });

  test('확인에 성공하면 임시 토큰으로 complete 를 이어 부르고 게이트를 다시 읽는다', () async {
    final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const Success('temporary-token');
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    expect(repository.calls, ['verifyCode', 'complete']);
    expect(repository.completedTokens, ['temporary-token']);
    // 기존 refresh gate 경로 — 게이트가 다음 단계(학생증)로 보낸다.
    expect(gateRepository.fetchCount, 1);
    expect(container.read(verificationGateListenableProvider).value, VerificationGate.needsStudentVerification);
  });

  test('코드가 틀리면 complete 를 부르지 않고 여섯 칸을 거부 상태로 둔다', () async {
    final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(WrongCodeFailure());
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('000000');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(repository.calls, ['verifyCode']);
    expect(state.errorMessage, '코드가 맞지 않아요. 다시 확인해 주세요.');
    expect(state.isCodeRejected, isTrue);
    expect(gateRepository.fetchCount, 0);
  });

  test('다른 소셜 계정이 쓰는 메일이면(409) 두 줄 문구를 채우고 게이트는 그대로', () async {
    final repository = FakeSchoolEmailRepository()
      ..nextCompleteResult = const FailureResult(SchoolEmailTakenFailure('서버 문구', 'google'));
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.errorMessage, '이 메일은 구글로 가입돼 있어요');
    expect(state.errorHint, '구글 계정으로 로그인해 주세요');
    expect(state.isCodeRejected, isFalse);
    expect(state.verified, isFalse);
    expect(gateRepository.fetchCount, 0);
  });

  test('서버가 인증을 못 마치면(403 미확인 · 503 · 네트워크) 다시 하라는 문구', () async {
    final repository = FakeSchoolEmailRepository()
      ..nextCompleteResult = const FailureResult(SchoolEmailIncompleteFailure());
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.errorMessage, '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요');
    expect(state.errorHint, isNull);
    expect(state.isSubmitting, isFalse);
  });

  test('422 는 서버 문구를 그대로 입력칸 아래 문구로', () async {
    final repository = FakeSchoolEmailRepository()
      ..nextCompleteResult = const FailureResult(ServerRejectedFailure('재가입이 제한된 메일이에요'));
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    expect(container.read(verifyCodeViewModelProvider(email)).errorMessage, '재가입이 제한된 메일이에요');
  });

  test('검증이 실패하면 errorMessage 가 채워진다', () async {
    final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(UnknownFailure());
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('000000');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.errorMessage, '알 수 없는 오류가 발생했습니다');
    expect(state.verified, isFalse);
  });

  test('화면을 열자마자 60초 쿨다운이 걸려 있다', () {
    // 로그인 화면이 방금 메일을 보내고 이 화면을 연다 — 열자마자 버튼이 켜져 있으면
    // 먼저 온 코드를 버리고 한 통을 더 보내게 된다(실기기 테스트에서 나온 문제).
    final now = DateTime(2026, 1, 1, 12);
    final container = buildContainer(FakeSchoolEmailRepository(), now: () => now);

    final state = container.read(verifyCodeViewModelProvider(email));

    expect(state.resendAvailableAt, now.add(const Duration(seconds: 60)));
    expect(state.canResend(now), isFalse);
  });

  test('재전송하면 60초 뒤로 resendAvailableAt 이 설정된다', () async {
    final repository = FakeSchoolEmailRepository();
    var now = DateTime(2026, 1, 1, 12);
    final container = buildContainer(repository, now: () => now);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    // 화면을 연 순간 걸린 첫 쿨다운을 지나 보낸다.
    now = now.add(const Duration(seconds: 60));

    await viewModel.resend();

    expect(repository.requestedEmails, [email]);
    expect(container.read(verifyCodeViewModelProvider(email)).resendAvailableAt, now.add(const Duration(seconds: 60)));
  });

  test('코드 유효 시간은 5분이고 재전송하면 그만큼 다시 잡힌다', () async {
    // supabase/config.toml 의 otp_expiry(300초)와 같은 값이어야 한다 — 다르면
    // 화면은 만료라고 말하는데 서버는 코드를 받아 준다(2026-09-23 사용자 결정).
    expect(codeLifetime, const Duration(minutes: 5));

    var now = DateTime(2026, 1, 1, 12);
    final container = buildContainer(FakeSchoolEmailRepository(), now: () => now);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    now = now.add(const Duration(seconds: 60));

    await viewModel.resend();

    expect(container.read(verifyCodeViewModelProvider(email)).codeExpiresAt, now.add(codeLifetime));
  });

  test('재전송하면 입력해 둔 코드를 비운다', () async {
    var now = DateTime(2026, 1, 1, 12);
    final container = buildContainer(FakeSchoolEmailRepository(), now: () => now);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');
    now = now.add(const Duration(seconds: 60));

    await viewModel.resend();

    expect(container.read(verifyCodeViewModelProvider(email)).codeInput, isEmpty);
  });

  test('쿨다운 중에는 재전송을 보내지 않는다', () async {
    final repository = FakeSchoolEmailRepository();
    var now = DateTime(2026, 1, 1, 12);
    final container = buildContainer(repository, now: () => now);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    now = now.add(const Duration(seconds: 60));
    await viewModel.resend();
    repository.requestedEmails.clear();

    await viewModel.resend();

    expect(repository.requestedEmails, isEmpty);
  });
  // 지시문 13 A-5: complete 가 실패해도(네트워크 · 503 · 미확인) 같은 03 에서 "확인" 을 다시 누르면 complete 만 다시 부른다.
  group('complete 실패 뒤 다시 시도', () {
    test('verifyCode 는 다시 부르지 않고 저장한 임시 토큰으로 complete 만 부른다', () async {
      final repository = FakeSchoolEmailRepository()
        ..nextVerifyCodeResult = const Success('temporary-token')
        ..nextCompleteResult = const FailureResult(SchoolEmailIncompleteFailure());
      final container = buildContainer(repository);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      viewModel.changeCode('123456');
      await viewModel.submit();
      repository.nextCompleteResult = const Success(null);

      await viewModel.submit();

      expect(repository.calls, ['verifyCode', 'complete', 'complete']);
      expect(repository.completedTokens, ['temporary-token', 'temporary-token']);
      expect(container.read(verifyCodeViewModelProvider(email)).verified, isTrue);
    });

    test('미확인(403)도 같이 complete 만 다시 부른다', () async {
      final repository = FakeSchoolEmailRepository()
        ..nextCompleteResult = const FailureResult(SchoolEmailNotConfirmedFailure());
      final container = buildContainer(repository);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      viewModel.changeCode('123456');
      await viewModel.submit();

      await viewModel.submit();

      expect(repository.calls, ['verifyCode', 'complete', 'complete']);
    });

    test('409 · 422 로 시도가 끝났으면 다시 누를 때 verifyCode 부터', () async {
      for (final failure in [
        const SchoolEmailTakenFailure('서버 문구', 'kakao'),
        const SchoolEmailRejectedFailure('등록되지 않은 학교 메일이에요'),
      ]) {
        final repository = FakeSchoolEmailRepository()..nextCompleteResult = FailureResult(failure);
        final container = buildContainer(repository);
        final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
        viewModel.changeCode('123456');
        await viewModel.submit();

        await viewModel.submit();

        expect(repository.calls, ['verifyCode', 'complete', 'verifyCode', 'complete'], reason: '$failure');
      }
    });

    test('메일을 다시 받으면 새 코드라 verifyCode 부터', () async {
      final repository = FakeSchoolEmailRepository()
        ..nextCompleteResult = const FailureResult(SchoolEmailIncompleteFailure());
      var now = DateTime(2026, 1, 1, 12);
      final container = buildContainer(repository, now: () => now);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      viewModel.changeCode('123456');
      await viewModel.submit();
      now = now.add(const Duration(seconds: 60));
      await viewModel.resend();
      viewModel.changeCode('654321');

      await viewModel.submit();

      expect(repository.calls, ['verifyCode', 'complete', 'requestCode', 'verifyCode', 'complete']);
    });
  });

  // 지시문 13 A-4: 409 · 422 · 미확인이면 "다른 학교 메일 입력" 으로 02 로 돌아갈 수 있다.
  group('다른 학교 메일 입력', () {
    test('409 · 422 · 미확인에서만 보인다', () async {
      final cases = <Failure, bool>{
        const SchoolEmailTakenFailure('서버 문구', 'google'): true,
        const SchoolEmailRejectedFailure('등록되지 않은 학교 메일이에요'): true,
        const SchoolEmailRejectedFailure('재가입이 제한된 메일이에요'): true,
        const SchoolEmailNotConfirmedFailure(): true,
        const SchoolEmailIncompleteFailure(): false,
        const RateLimitedFailure(): false,
      };
      for (final MapEntry(key: failure, value: shown) in cases.entries) {
        final repository = FakeSchoolEmailRepository()..nextCompleteResult = FailureResult(failure);
        final container = buildContainer(repository);
        final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
        viewModel.changeCode('123456');

        await viewModel.submit();

        expect(container.read(verifyCodeViewModelProvider(email)).canChooseAnotherEmail, shown, reason: '$failure');
      }
    });

    test('틀린 코드에는 보이지 않는다', () async {
      final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(WrongCodeFailure());
      final container = buildContainer(repository);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      viewModel.changeCode('000000');

      await viewModel.submit();

      expect(container.read(verifyCodeViewModelProvider(email)).canChooseAnotherEmail, isFalse);
    });

    test('startOver 는 임시 연결을 비우고 02 의 입력값을 비운다', () async {
      final repository = FakeSchoolEmailRepository();
      final container = buildContainer(repository);
      container.read(signUpViewModelProvider.notifier).changeEmail('hong@snu.ac.kr');
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);

      await viewModel.startOver();

      expect(repository.calls, ['discard']);
      expect(container.read(signUpViewModelProvider).emailInput, isEmpty);
      expect(container.read(signUpViewModelProvider).canSubmit, isFalse);
    });
  });
}
