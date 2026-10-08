import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/viewmodel/sign_up_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/fake_school_email_repository.dart';

void main() {
  group('SignUpViewModel', () {
    test('초기 상태는 빈 입력이고 제출할 수 없다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(signUpViewModelProvider);

      expect(state.emailInput, '');
      expect(state.canSubmit, isFalse);
    });

    test('형식이 올바른 이메일을 입력하면 제출할 수 있다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signUpViewModelProvider.notifier).changeEmail('hong@snu.ac.kr');
      final state = container.read(signUpViewModelProvider);

      expect(state.emailInput, 'hong@snu.ac.kr');
      expect(state.canSubmit, isTrue);
    });

    test('형식이 잘못된 이메일을 입력하면 제출할 수 없다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signUpViewModelProvider.notifier).changeEmail('hong@snu');
      final state = container.read(signUpViewModelProvider);

      expect(state.canSubmit, isFalse);
    });

    test('제출에 성공하면 otpSentTo 가 채워진다', () async {
      final repository = FakeSchoolEmailRepository();
      final container = ProviderContainer(
        overrides: [schoolEmailRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(signUpViewModelProvider.notifier);
      viewModel.changeEmail('hong@snu.ac.kr');

      await viewModel.submit();

      final state = container.read(signUpViewModelProvider);
      expect(state.otpSentTo?.toRequestValue(), 'hong@snu.ac.kr');
      expect(state.isSubmitting, isFalse);
      // 학교 메일 인증번호는 임시 연결 저장소(requestCode)로 보낸다 — 메인 로그인용 OTP 가 아니다.
      expect(repository.requestedEmails.map((email) => email.toRequestValue()), ['hong@snu.ac.kr']);
    });

    test('가입 직전 훅이 거절하면 서버 문구를 입력칸 아래 문구로 쓴다', () async {
      final repository = FakeSchoolEmailRepository()
        ..nextRequestCodeResult = const FailureResult(SignUpRejectedFailure('등록되지 않은 학교 메일이에요'));
      final container = ProviderContainer(
        overrides: [schoolEmailRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(signUpViewModelProvider.notifier);
      viewModel.changeEmail('hong@snu.ac.kr');

      await viewModel.submit();

      expect(container.read(signUpViewModelProvider).errorMessage, '등록되지 않은 학교 메일이에요');
    });

    test('제출이 실패하면 errorMessage 가 채워진다', () async {
      final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = const FailureResult(RateLimitedFailure());
      final container = ProviderContainer(
        overrides: [schoolEmailRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(signUpViewModelProvider.notifier);
      viewModel.changeEmail('hong@snu.ac.kr');

      await viewModel.submit();

      final state = container.read(signUpViewModelProvider);
      expect(state.errorMessage, '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요');
      expect(state.otpSentTo, isNull);
    });

    test('acknowledgeNavigation 은 otpSentTo 를 지운다', () async {
      final container = ProviderContainer(
        overrides: [schoolEmailRepositoryProvider.overrideWithValue(FakeSchoolEmailRepository())],
      );
      addTearDown(container.dispose);
      final viewModel = container.read(signUpViewModelProvider.notifier);
      viewModel.changeEmail('hong@snu.ac.kr');
      await viewModel.submit();

      viewModel.acknowledgeNavigation();

      expect(container.read(signUpViewModelProvider).otpSentTo, isNull);
    });
  });
}
