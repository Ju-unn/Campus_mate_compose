import 'package:campus_mate/common/failure.dart';

/// 휴대폰 문자 인증의 큰 단계(pen 04-1 2c). 인증번호 줄(OtpEntryRow `EqLaR`)은 [codeSent] 에서만 보인다.
enum PhoneVerifyStep {
  /// ① ② ⑦ ⑫ — 아직 안 보냈거나, 보내기가 막혀 인증번호 줄을 닫았다.
  idle,

  /// ③ ④ ⑤ ⑪ ⑬ — 인증번호를 보냈다.
  codeSent,

  /// ⑥ — 인증됐다. 번호 칸이 잠기고 "번호 바꾸기" 가 보인다.
  verified,
}

/// 인증번호 자릿수(서버 `VerifyRequest.code` ASCII 숫자 6자리). 칸 길이 제한과 자동 확인이 같이 쓴다.
const int verificationCodeLength = 6;

/// `copyWith` 에서 "이 칸은 건드리지 않는다" 를 뜻하는 표식.
const Object _keep = Object();

/// 04-1 휴대폰 문자 인증의 상태(기본 정보 상태의 `phoneVerify` 칸).
/// 남은 시간은 뷰모델이 서버가 준 초로 마감 시각을 잡고 1초마다 다시 센 값이다 — 화면은 그대로 그린다.
class PhoneVerifyUiState {
  const PhoneVerifyUiState({
    this.step = PhoneVerifyStep.idle,
    this.isSending = false,
    this.isVerifying = false,
    this.error,
    this.codeInput = '',
    this.codeError,
    this.isCodeLocked = false,
    this.codeSecondsLeft = 0,
    this.resendSecondsLeft = 0,
    this.verifiedDigits,
  });

  final PhoneVerifyStep step;

  /// ⑩ 인증번호를 보내는 중.
  final bool isSending;

  /// ⑪ 인증번호를 확인하는 중.
  final bool isVerifying;

  /// 번호 줄 아래 상태 줄의 오류(⑦ 이미 쓰는 번호 · ⑫ 오늘 한도 · 잠시 후 · 010 번호만).
  final Failure? error;
  final String codeInput;

  /// 인증번호 줄의 오류(④ 틀림 · ⑤ 시간 지남 · ⑬ 잠김 · 그 밖의 확인 실패).
  final Failure? codeError;

  /// ⑬ 5번 틀려 잠겼다 — 다시 받아야 풀린다.
  final bool isCodeLocked;

  /// 인증번호를 쓸 수 있는 남은 초(칸 안 타이머).
  final int codeSecondsLeft;

  /// 다시 받기까지 남은 초. 0 보다 크면 받기 · 다시 받기가 꺼진다.
  final int resendSecondsLeft;

  /// 인증된 번호(숫자만). [step] 이 [PhoneVerifyStep.verified] 일 때만 있다.
  final String? verifiedDigits;

  /// ⑤ — 보낸 인증번호의 시간이 다 됐다.
  bool get isCodeExpired => step == PhoneVerifyStep.codeSent && codeSecondsLeft == 0;

  /// 인증번호 확인을 보낼 수 있는가(확인 버튼 분홍). 6자리가 되기 전에는 꺼 둔다(사용자 결정 11-10).
  bool get canVerify =>
      step == PhoneVerifyStep.codeSent &&
      codeInput.length == verificationCodeLength &&
      !isSending &&
      !isVerifying &&
      !isCodeExpired &&
      !isCodeLocked;

  /// ⑫ 오늘 받기 한도에 걸렸다 — 번호를 고칠 때까지 받기를 끈다(1초 시계는 돌리지 않는다).
  bool get isDailyLimited => switch (error) {
        AppErrorFailure(error: AppError.phoneDailyLimit) => true,
        _ => false,
      };

  /// 번호 칸이 잠긴 모양인가(⑥ 인증됨 · ⑩ 보내는 중 · ⑪ 확인 중 · ⑬ 잠김).
  bool get isPhoneLocked => isSending || isVerifying || step == PhoneVerifyStep.verified || isCodeLocked;

  /// ⑦ — 다른 계정이 쓰는 번호. 번호 칸 테두리만 빨갛다(⑫ · 잠시 후 · 010 줄은 테두리가 보통이다).
  bool get isInUse => switch (error) {
        AppErrorFailure(error: AppError.phoneInUse) => true,
        _ => false,
      };

  PhoneVerifyUiState copyWith({
    PhoneVerifyStep? step,
    bool? isSending,
    bool? isVerifying,
    Object? error = _keep,
    String? codeInput,
    Object? codeError = _keep,
    bool? isCodeLocked,
    int? codeSecondsLeft,
    int? resendSecondsLeft,
    Object? verifiedDigits = _keep,
  }) {
    return PhoneVerifyUiState(
      step: step ?? this.step,
      isSending: isSending ?? this.isSending,
      isVerifying: isVerifying ?? this.isVerifying,
      error: identical(error, _keep) ? this.error : error as Failure?,
      codeInput: codeInput ?? this.codeInput,
      codeError: identical(codeError, _keep) ? this.codeError : codeError as Failure?,
      isCodeLocked: isCodeLocked ?? this.isCodeLocked,
      codeSecondsLeft: codeSecondsLeft ?? this.codeSecondsLeft,
      resendSecondsLeft: resendSecondsLeft ?? this.resendSecondsLeft,
      verifiedDigits: identical(verifiedDigits, _keep) ? this.verifiedDigits : verifiedDigits as String?,
    );
  }
}
