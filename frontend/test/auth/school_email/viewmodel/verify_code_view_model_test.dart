import 'package:campus_mate/account/model/data/login_notice.dart';
import 'package:campus_mate/auth/school_email/model/repository/school_email_repository_provider.dart';
import 'package:campus_mate/auth/gate/model/data/verification_gate.dart';
import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/school_email/model/data/university_email.dart';
import 'package:campus_mate/auth/school_email/viewmodel/sign_up_view_model.dart';
import 'package:campus_mate/auth/school_email/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/repository/fake_school_email_repository.dart';
import '../../gate/model/repository/fake_verification_gate_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  late FakeVerificationGateRepository gateRepository;

  setUp(() => gateRepository = FakeVerificationGateRepository()
    ..nextResult = const Success(VerificationGate.needsSchoolInfo));

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
    // 기존 refresh gate 경로 — 게이트가 다음 단계(학과 · 학번 3c)로 보낸다(10-17 학생증 제거).
    expect(gateRepository.fetchCount, 1);
    expect(container.read(verificationGateListenableProvider).value, VerificationGate.needsSchoolInfo);
  });

  test('코드가 틀리면 complete 를 부르지 않고 여섯 칸을 거부 상태로 둔다', () async {
    final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(WrongCodeFailure());
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('000000');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(repository.calls, ['verifyCode']);
    expect(state.error, isA<WrongCodeFailure>());
    expect(state.isCodeRejected, isTrue);
    expect(gateRepository.fetchCount, 0);
  });

  /// 409 로 끝난 03 상태. [mine] 은 지금 로그인한 소셜(저장소가 덧붙인다).
  Future<(ProviderContainer, VerifyCodeViewModel)> takenBy(String owner, {String? mine}) async {
    final repository = FakeSchoolEmailRepository()
      ..nextCompleteResult = FailureResult(SchoolEmailTakenFailure('서버 문구', owner, myProvider: mine));
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');
    await viewModel.submit();
    return (container, viewModel);
  }

  // 설계 5-3 B안 세 줄(10-17 학생증 제거).
  test('다른 소셜이 쥔 메일이면(409) 두 줄 문구 · 다시 로그인 단추 · 다른 학교 메일 입력을 채우고 게이트는 그대로', () async {
    final (container, _) = await takenBy('google', mine: 'kakao');

    final state = container.read(verifyCodeViewModelProvider(email));
    // 글자(첫 줄 · 둘째 줄 · 다시 로그인 단추)는 화면이 이 실패에서 만든다 — verify_code_screen_test 가 지킨다.
    expect(state.error, isA<SchoolEmailTakenFailure>().having((failure) => failure.otherSocialProvider(), 'otherSocialProvider', 'google'));
    expect(state.isTakenBySocial, isTrue);
    expect(state.canChooseAnotherEmail, isTrue);
    expect(state.isCodeRejected, isFalse);
    expect(state.verified, isFalse);
    expect(gateRepository.fetchCount, 0);
  });

  test('같은 소셜이 쥔 다른 계정이면 빌려 쓰기 문구, 다시 로그인 단추는 없다', () async {
    final (container, _) = await takenBy('kakao', mine: 'kakao');

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.error, isA<SchoolEmailTakenFailure>().having((failure) => failure.otherSocialProvider(), 'otherSocialProvider', isNull));
    expect(state.isTakenBySocial, isTrue);
    expect(state.canChooseAnotherEmail, isTrue);
  });

  test('옛 이메일 가입자가 쥔 메일이면 지금 문구 그대로(한 줄 · 03 배치 그대로)', () async {
    final (container, _) = await takenBy('email', mine: 'kakao');

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.error, isA<SchoolEmailTakenFailure>().having((failure) => failure.isTakenByEmailAccount(), 'isTakenByEmailAccount', isTrue));
    expect(state.isTakenBySocial, isFalse);
    expect(state.canChooseAnotherEmail, isTrue);
  });

  group('다시 로그인(relogin)', () {
    late List<String> signedOut;

    setUp(() => signedOut = []);
    tearDown(LoginNotice.take);

    test('누르면 시작 화면 토스트 문구(info)를 남기고 로그아웃한다 — 자동 로그아웃은 없다', () async {
      final repository = FakeSchoolEmailRepository()
        ..nextCompleteResult = const FailureResult(SchoolEmailTakenFailure('서버 문구', 'kakao', myProvider: 'google'));
      final container = ProviderContainer(
        overrides: [
          schoolEmailRepositoryProvider.overrideWithValue(repository),
          verificationGateRepositoryProvider.overrideWithValue(gateRepository),
          signOutProvider.overrideWithValue(() async => signedOut.add('signOut')),
        ],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      viewModel.changeCode('123456');
      await viewModel.submit();
      expect(signedOut, isEmpty, reason: '409 만으로는 로그아웃하지 않는다');

      await viewModel.relogin('이 학교 메일은 카카오로 가입돼 있어요. 카카오로 로그인해 주세요');
      await viewModel.relogin('이 학교 메일은 카카오로 가입돼 있어요. 카카오로 로그인해 주세요'); // 연타 — 로그아웃은 한 번만

      expect(signedOut, ['signOut']);
      final notice = LoginNotice.take();
      expect(notice?.message, '이 학교 메일은 카카오로 가입돼 있어요. 카카오로 로그인해 주세요');
      expect(notice?.isInfo, isTrue);
    });

    test('다시 로그인할 소셜이 없으면(같은 소셜 · 이메일 방식) 아무 일도 하지 않는다', () async {
      final repository = FakeSchoolEmailRepository()
        ..nextCompleteResult = const FailureResult(SchoolEmailTakenFailure('서버 문구', 'kakao', myProvider: 'kakao'));
      final container = ProviderContainer(
        overrides: [
          schoolEmailRepositoryProvider.overrideWithValue(repository),
          verificationGateRepositoryProvider.overrideWithValue(gateRepository),
          signOutProvider.overrideWithValue(() async => signedOut.add('signOut')),
        ],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      viewModel.changeCode('123456');
      await viewModel.submit();

      await viewModel.relogin('아무 글');

      expect(signedOut, isEmpty);
      expect(LoginNotice.take(), isNull);
    });
  });

  test('서버가 인증을 못 마치면(403 미확인 · 503 · 네트워크) 다시 하라는 문구', () async {
    final repository = FakeSchoolEmailRepository()
      ..nextCompleteResult = const FailureResult(SchoolEmailIncompleteFailure());
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.error, isA<SchoolEmailIncompleteFailure>());
    expect(state.isSubmitting, isFalse);
  });

  test('422 는 서버 문구를 그대로 입력칸 아래 문구로', () async {
    final repository = FakeSchoolEmailRepository()
      ..nextCompleteResult = const FailureResult(ServerRejectedFailure('재가입이 제한된 메일이에요'));
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    expect(
      (container.read(verifyCodeViewModelProvider(email)).error! as ServerRejectedFailure).serverMessage,
      '재가입이 제한된 메일이에요',
    );
  });

  test('검증이 실패하면 error 가 채워진다', () async {
    final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(UnknownFailure());
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('000000');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.error, isA<UnknownFailure>());
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

  // 11-24 보안 점검 A2: 다시 보내기가 실패하면(네트워크 · 503 · 429) "보냈다" 처럼 보이면 안 된다.
  group('다시 보내기가 실패하면', () {
    // 서버가 받고 거절했다(429 한도 · 422 가입 거절) — 바로 다시 눌러도 같은 답이라 60초 잠금을 그대로 둔다.
    test('서버가 거절했으면 오류를 보이고 다시 받기 버튼은 잠긴 채', () async {
      for (final failure in [const RateLimitedFailure(), const SignUpRejectedFailure('서버 문구')]) {
        final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = FailureResult(failure);
        final opened = DateTime(2026, 1, 1, 12);
        var now = opened;
        final container = buildContainer(repository, now: () => now);
        final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
        now = now.add(const Duration(seconds: 60));

        await viewModel.resend();

        final state = container.read(verifyCodeViewModelProvider(email));
        expect(state.resendError, same(failure), reason: '$failure');
        expect(state.error, isNull, reason: '$failure');
        expect(state.canResend(now), isFalse, reason: '$failure');
        expect(state.codeExpiresAt, opened.add(codeLifetime), reason: '$failure');
      }
    });

    // 요청이 서버에 안 닿았거나 서버 문제 — 새 코드도 한도 소모도 없으니 바로 다시 누를 수 있게 둘 다 되돌린다.
    test('안 닿았거나 서버 문제면 오류를 보이고 남은 시간 · 다시 받기를 되돌린다', () async {
      for (final failure in [
        const NetworkFailure(),
        const CodeNotSentFailure(),
        const ServerUnavailableFailure(),
        const UnknownFailure(),
      ]) {
        final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = FailureResult(failure);
        final opened = DateTime(2026, 1, 1, 12);
        var now = opened;
        final container = buildContainer(repository, now: () => now);
        final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
        now = now.add(const Duration(seconds: 60));

        await viewModel.resend();

        final state = container.read(verifyCodeViewModelProvider(email));
        expect(state.resendError, same(failure), reason: '$failure');
        expect(state.error, isNull, reason: '$failure');
        expect(state.canResend(now), isTrue, reason: '$failure');
        expect(state.codeExpiresAt, opened.add(codeLifetime), reason: '$failure');
      }
    });

    test('옛 코드가 살아 있으니 저장한 임시 토큰으로 complete 만 다시 부른다', () async {
      final repository = FakeSchoolEmailRepository()
        ..nextCompleteResult = const FailureResult(SchoolEmailIncompleteFailure())
        ..nextRequestCodeResult = const FailureResult(NetworkFailure());
      var now = DateTime(2026, 1, 1, 12);
      final container = buildContainer(repository, now: () => now);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..changeCode('123456');
      await viewModel.submit();
      now = now.add(const Duration(seconds: 60));
      await viewModel.resend();
      repository.nextCompleteResult = const Success(null);
      viewModel.changeCode('123456');

      await viewModel.submit();

      expect(repository.calls, ['verifyCode', 'complete', 'requestCode', 'complete']);
      expect(container.read(verifyCodeViewModelProvider(email)).verified, isTrue);
    });

    // 검토 권고: 응답을 기다리는 사이 옛 코드를 넣고 "확인" 을 누르면 늦은 실패가 확인 중 상태를 지우면 안 된다.
    test('기다리는 사이 확인을 눌렀으면 늦은 실패는 확인 중 상태를 덮지 않는다', () async {
      final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = const FailureResult(CodeNotSentFailure());
      var now = DateTime(2026, 1, 1, 12);
      final container = buildContainer(repository, now: () => now);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      now = now.add(const Duration(seconds: 60));
      final resending = viewModel.resend();
      viewModel.changeCode('123456');
      final submitting = viewModel.submit();

      await resending;

      final state = container.read(verifyCodeViewModelProvider(email));
      expect((state.isSubmitting, state.codeInput, state.error, state.resendError), (true, '123456', null, null));
      await submitting;
    });

    test('기다리는 사이 적은 코드는 늦은 실패 뒤에도 남는다', () async {
      final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = const FailureResult(CodeNotSentFailure());
      var now = DateTime(2026, 1, 1, 12);
      final container = buildContainer(repository, now: () => now);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      now = now.add(const Duration(seconds: 60));
      final resending = viewModel.resend();
      viewModel.changeCode('12');

      await resending;

      final state = container.read(verifyCodeViewModelProvider(email));
      expect(state.codeInput, '12');
      expect(state.resendError, isA<CodeNotSentFailure>());
    });

    // pen jj8YS: 다시 보내기 실패는 만료 줄 아래 따로 보인다 — 확인 실패 칸(입력칸 아래 · 여섯 칸 빨강 · 다른 학교 메일 입력)은 비운다.
    test('확인 실패 칸은 비우고 다시 보내기 실패 칸만 채운다', () async {
      final repository = FakeSchoolEmailRepository()
        ..nextVerifyCodeResult = const FailureResult(WrongCodeFailure())
        ..nextRequestCodeResult = const FailureResult(SignUpRejectedFailure('서버 문구'));
      var now = DateTime(2026, 1, 1, 12);
      final container = buildContainer(repository, now: () => now);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..changeCode('000000');
      await viewModel.submit();
      now = now.add(const Duration(seconds: 60));

      await viewModel.resend();

      final state = container.read(verifyCodeViewModelProvider(email));
      expect(state.resendError, isA<SignUpRejectedFailure>());
      expect((state.error, state.isCodeRejected, state.canChooseAnotherEmail), (null, false, false));
    });

    group('다시 보내기 실패 칸은 다음 동작에서 비운다', () {
      // 기다리는 사이 코드를 적어 두면 실패 뒤에도 코드가 남는다 — 그래야 바로 확인을 눌러 볼 수 있다.
      Future<(ProviderContainer, VerifyCodeViewModel, FakeSchoolEmailRepository)> failedWithCode() async {
        final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = const FailureResult(NetworkFailure());
        var now = DateTime(2026, 1, 1, 12);
        final container = buildContainer(repository, now: () => now);
        final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
        now = now.add(const Duration(seconds: 60));
        final resending = viewModel.resend();
        viewModel.changeCode('123456');
        await resending;
        expect(container.read(verifyCodeViewModelProvider(email)).resendError, isA<NetworkFailure>());
        return (container, viewModel, repository);
      }

      test('코드를 고치면', () async {
        final (container, viewModel, _) = await failedWithCode();

        viewModel.changeCode('12345');

        expect(container.read(verifyCodeViewModelProvider(email)).resendError, isNull);
      });

      test('다시 보내기에 성공하면', () async {
        final (container, viewModel, repository) = await failedWithCode();
        repository.nextRequestCodeResult = const Success(null);

        await viewModel.resend();

        expect(container.read(verifyCodeViewModelProvider(email)).resendError, isNull);
      });

      test('확인을 누르면 — 확인이 실패해도 확인 실패 칸만 채운다', () async {
        final (container, viewModel, repository) = await failedWithCode();
        repository.nextVerifyCodeResult = const FailureResult(WrongCodeFailure());

        final submitting = viewModel.submit();
        expect(container.read(verifyCodeViewModelProvider(email)).resendError, isNull);
        await submitting;

        final state = container.read(verifyCodeViewModelProvider(email));
        expect(state.resendError, isNull);
        expect(state.error, isA<WrongCodeFailure>());
      });
    });
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

    // 03 뒤로가기(사용자 10-16) — 02 에서 같은 메일로 다시 오면 적던 코드 · 오류 · 옛 만료 시각이 남아 있으면 안 된다.
    test('startOver 뒤에는 적던 코드 · 오류가 비고, 만료 · 다시 받기 시각은 처음부터 다시 센다', () async {
      var now = DateTime(2026, 10, 16, 9);
      final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(WrongCodeFailure());
      final container = buildContainer(repository, now: () => now);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      viewModel.changeCode('000000');
      await viewModel.submit();
      expect(container.read(verifyCodeViewModelProvider(email)).error, isNotNull);
      now = now.add(const Duration(minutes: 3));

      await viewModel.startOver();

      final state = container.read(verifyCodeViewModelProvider(email));
      expect((state.codeInput, state.error, state.isCodeRejected), ('', null, false));
      expect(state.codeExpiresAt, now.add(codeLifetime));
      expect(state.resendAvailableAt, now.add(const Duration(seconds: 60)));
    });
  });

  // 11-17: 코드 확인 · 인증 마치기 · 처음으로 돌리기를 기다리는 사이 로그아웃으로 버려지면 늦게 온 답이 버려진 상태 · ref 를 건드려 던진다.
  group('기다리는 사이 버려지면 늦게 온 답은 버린다', () {
    test('코드를 확인하는 중', () async {
      final repository = FakeSchoolEmailRepository();
      final container = buildContainer(repository);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..changeCode('123456');
      final submitting = viewModel.submit();

      container.dispose();

      await expectLater(submitting, completes);
      expect(repository.calls, ['verifyCode']);
    });

    test('인증을 마치는 중(저장한 임시 토큰으로 다시 보냄)', () async {
      final repository = FakeSchoolEmailRepository()..nextCompleteResult = const FailureResult(NetworkFailure());
      final container = buildContainer(repository);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..changeCode('123456');
      await viewModel.submit();
      repository.nextCompleteResult = const Success(null);
      final submitting = viewModel.submit();

      container.dispose();

      await expectLater(submitting, completes);
    });

    test('메일을 다시 보내는 중(실패로 풀림)', () async {
      final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = const FailureResult(NetworkFailure());
      var now = DateTime(2026, 1, 1, 12);
      final container = buildContainer(repository, now: () => now);
      final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
      now = now.add(const Duration(seconds: 60));
      final resending = viewModel.resend();

      container.dispose();

      await expectLater(resending, completes);
      expect(repository.calls, ['requestCode']);
    });

    test('처음으로 돌리는 중', () async {
      final container = buildContainer(FakeSchoolEmailRepository());
      final going = container.read(verifyCodeViewModelProvider(email).notifier).startOver();

      container.dispose();

      await expectLater(going, completes);
    });
  });
}
