import 'package:campus_mate/auth/model/school_email_repository.dart';
import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/auth/viewmodel/sign_up_view_model.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final verifyCodeViewModelProvider = NotifierProvider.family<VerifyCodeViewModel, VerifyCodeUiState, UniversityEmail>(
  VerifyCodeViewModel.new,
);

const _resendCooldown = Duration(seconds: 60);

/// 테스트에서 시각을 고정하는 자리. [VerifyCodeViewModel.build] 도 읽으므로
/// 필드 훅과 달리 화면이 열린 **첫 계산부터** 고정된다.
final verifyCodeNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 코드 유효 시간(pen 값, 2026-09-23 사용자 결정).
/// Supabase Auth 의 `otp_expiry`(supabase/config.toml 300초)와 **같아야 한다** —
/// 여기만 줄이면 화면은 만료라고 말하는데 서버는 코드를 받아 준다.
const codeLifetime = Duration(minutes: 5);

/// 인증코드 입력 화면(DESIGN.md 화면 03)의 흐름을 맡는다.
/// Riverpod 3.x 의 family notifier 는 인자를 생성자로 받는다(2.x `FamilyNotifier.build(arg)` 방식이 아니다).
class VerifyCodeViewModel extends Notifier<VerifyCodeUiState> {
  VerifyCodeViewModel(this._email);

  final UniversityEmail _email;

  /// 코드 확인에 성공한 임시 토큰. complete 가 다시 해 볼 만한 이유로 실패하면(네트워크 · 503 · 미확인) 남겨 두고,
  /// 다음 "확인" 은 verifyCode 를 건너뛰고 complete 만 부른다 — 이미 쓴 코드를 다시 확인하면 "코드가 맞지 않아요" 가 된다.
  /// 메모리에만 있다(앱을 끄면 02 부터).
  String? _temporaryToken;

  /// 테스트에서 시각을 고정하기 위한 훅. 기본은 실제 현재 시각.
  DateTime now() => ref.read(verifyCodeNowProvider)();

  @override
  // 이 화면은 로그인 화면이 코드를 보낸 직후에 열린다 — 화면이 열린 때를 보낸 때로 본다.
  // 쿨다운도 그 시각부터 센다. 안 걸어 두면 화면을 열자마자 "메일 다시 받기"가 켜져 있어
  // 방금 온 코드를 버리고 한 통을 더 보내게 된다(2026-09-23 실기기 테스트에서 확인).
  VerifyCodeUiState build() {
    final sentAt = now();
    return VerifyCodeUiState(
      resendAvailableAt: sentAt.add(_resendCooldown),
      codeExpiresAt: sentAt.add(codeLifetime),
    );
  }

  void changeCode(String value) {
    state = VerifyCodeUiState(
      codeInput: value,
      resendAvailableAt: state.resendAvailableAt,
      codeExpiresAt: state.codeExpiresAt,
    );
  }

  Future<void> submit() async {
    final code = VerificationCode.tryParse(state.codeInput);
    if (code == null) {
      return;
    }
    state = VerifyCodeUiState(
      codeInput: state.codeInput,
      isSubmitting: true,
      resendAvailableAt: state.resendAvailableAt,
      codeExpiresAt: state.codeExpiresAt,
    );
    final result = await _verifyAndComplete(code);
    final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
    if (failure != null) {
      state = _failed(failure);
      return;
    }
    state = VerifyCodeUiState(codeInput: state.codeInput, verified: true);
    // 기존 refresh gate 경로 — 게이트가 다음 관문(학생증)으로 보낸다(02-c 동의 화면과 같이 기다린다).
    await ref.read(verificationGateListenableProvider).refresh();
  }

  /// 임시 연결로 코드를 확인하고, 되면 그 임시 토큰으로 서버에 인증을 마친다. 코드가 틀리면 서버는 부르지 않는다.
  Future<Result<void>> _verifyAndComplete(VerificationCode code) async {
    final token = await _temporaryTokenFor(code);
    return token.when(
      onSuccess: _complete,
      onFailure: (failure) async => FailureResult<void>(failure),
    );
  }

  /// 저장한 임시 토큰이 있으면 그것을, 없으면 코드를 확인해 받는다.
  Future<Result<String>> _temporaryTokenFor(VerificationCode code) async {
    final saved = _temporaryToken;
    if (saved != null) {
      return Success(saved);
    }
    final verified = await ref.read(schoolEmailRepositoryProvider).verifyCode(_email, code);
    _temporaryToken = verified.when(onSuccess: (token) => token, onFailure: (_) => null);
    return verified;
  }

  /// 성공 · 409 · 422 면 시도가 끝났다 — 토큰을 버린다(저장소도 임시 연결을 비운다).
  Future<Result<void>> _complete(String token) async {
    final result = await ref.read(schoolEmailRepositoryProvider).complete(token);
    final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
    if (failure == null || endsSchoolEmailAttempt(failure)) {
      _temporaryToken = null;
    }
    return result;
  }

  /// "다른 학교 메일 입력" — 임시 연결과 토큰을 버리고 02 의 입력값을 비운다. 화면 이동은 화면이 한다.
  Future<void> startOver() async {
    _temporaryToken = null;
    ref.invalidate(signUpViewModelProvider);
    await ref.read(schoolEmailRepositoryProvider).discard();
  }

  /// 이 메일로는 끝낼 수 없는 실패 — 02 로 돌아가는 길을 보인다.
  static bool _needsAnotherEmail(Failure failure) =>
      endsSchoolEmailAttempt(failure) || failure is SchoolEmailNotConfirmedFailure;

  /// 오류는 입력칸 아래 문구로만 보인다(팝업 없음). 다른 소셜 계정이 쓰는 메일이면 둘째 줄을 단다.
  VerifyCodeUiState _failed(Failure failure) {
    return VerifyCodeUiState(
      codeInput: state.codeInput,
      errorMessage: failure.toDisplayMessage(),
      errorHint: failure is SchoolEmailTakenFailure ? failure.toHintMessage() : null,
      canChooseAnotherEmail: _needsAnotherEmail(failure),
      resendAvailableAt: state.resendAvailableAt,
      codeExpiresAt: state.codeExpiresAt,
      isCodeRejected: failure is WrongCodeFailure,
    );
  }

  /// 쿨다운 중이면 아무 일도 하지 않는다(spec §13-38, 60초 재전송 제한).
  Future<void> resend() async {
    if (!state.canResend(now())) {
      return;
    }
    // 새 코드가 오므로 입력칸을 비운다 — 안 비우면 예전 코드가 남아 그대로 제출된다. 저장한 임시 토큰도 버린다.
    _temporaryToken = null;
    state = VerifyCodeUiState(
      resendAvailableAt: now().add(_resendCooldown),
      codeExpiresAt: now().add(codeLifetime),
    );
    await ref.read(schoolEmailRepositoryProvider).requestCode(_email);
  }
}
