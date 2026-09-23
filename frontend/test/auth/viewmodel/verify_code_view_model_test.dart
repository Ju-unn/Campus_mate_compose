import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/fake_auth_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  ProviderContainer buildContainer(FakeAuthRepository repository) {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('올바른 코드를 제출하면 verified 가 true', () async {
    final container = buildContainer(FakeAuthRepository());
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.submit();

    expect(container.read(verifyCodeViewModelProvider(email)).verified, isTrue);
  });

  test('검증이 실패하면 errorMessage 가 채워진다', () async {
    final repository = FakeAuthRepository()..nextVerifyOtpResult = const FailureResult(UnknownFailure());
    final container = buildContainer(repository);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('000000');

    await viewModel.submit();

    final state = container.read(verifyCodeViewModelProvider(email));
    expect(state.errorMessage, '알 수 없는 오류가 발생했습니다');
    expect(state.verified, isFalse);
  });

  test('재전송하면 60초 뒤로 resendAvailableAt 이 설정된다', () async {
    final repository = FakeAuthRepository();
    final container = buildContainer(repository);
    final now = DateTime(2026, 1, 1, 12);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..now = () => now;

    await viewModel.resend();

    expect(repository.requestedEmails, [email]);
    expect(container.read(verifyCodeViewModelProvider(email)).resendAvailableAt, now.add(const Duration(seconds: 60)));
  });

  test('코드 유효 시간은 5분이고 재전송하면 그만큼 다시 잡힌다', () async {
    // supabase/config.toml 의 otp_expiry(300초)와 같은 값이어야 한다 — 다르면
    // 화면은 만료라고 말하는데 서버는 코드를 받아 준다(2026-09-23 사용자 결정).
    expect(codeLifetime, const Duration(minutes: 5));

    final container = buildContainer(FakeAuthRepository());
    final now = DateTime(2026, 1, 1, 12);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..now = () => now;

    await viewModel.resend();

    expect(container.read(verifyCodeViewModelProvider(email)).codeExpiresAt, now.add(codeLifetime));
  });

  test('재전송하면 입력해 둔 코드를 비운다', () async {
    final container = buildContainer(FakeAuthRepository());
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier);
    viewModel.changeCode('123456');

    await viewModel.resend();

    expect(container.read(verifyCodeViewModelProvider(email)).codeInput, isEmpty);
  });

  test('쿨다운 중에는 재전송을 보내지 않는다', () async {
    final repository = FakeAuthRepository();
    final container = buildContainer(repository);
    final now = DateTime(2026, 1, 1, 12);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)..now = () => now;
    await viewModel.resend();
    repository.requestedEmails.clear();

    await viewModel.resend();

    expect(repository.requestedEmails, isEmpty);
  });
}
