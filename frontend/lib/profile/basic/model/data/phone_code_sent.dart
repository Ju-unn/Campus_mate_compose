/// 휴대폰 인증번호 받기의 성공 응답(서버 `POST /phone-verification/send` 200).
/// [alreadySent] 면 문자는 새로 가지 않았다 — 앞서 보낸 인증번호의 남은 시간을 이어서 센다(오류가 아니다).
class PhoneCodeSent {
  const PhoneCodeSent({required this.resendAfter, required this.expiresIn, required this.alreadySent});

  /// 다시 받기까지 남은 시간(`resend_after_seconds`).
  final Duration resendAfter;

  /// 인증번호를 쓸 수 있는 남은 시간(`expires_in_seconds`).
  final Duration expiresIn;
  final bool alreadySent;
}
