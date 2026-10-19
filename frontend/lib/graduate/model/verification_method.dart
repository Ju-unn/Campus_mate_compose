/// 가입 때 고르는 신분 인증 길. [wire] 는 서버 `PUT /me/verification-method` · `verification-status` 문자열 그대로다.
/// 아직 고르지 않은 것(null)은 값이 아니라 "없음" 이다.
enum VerificationMethod {
  schoolEmail('school_email'),
  graduateCertificate('graduate_certificate');

  const VerificationMethod(this.wire);

  final String wire;

  /// 모르는 값 · 없는 값은 null — 서버가 새 길을 더해도 옛 앱이 죽지 않고 "아직 안 고름" 으로 본다.
  static VerificationMethod? tryParse(Object? wire) {
    for (final method in values) {
      if (method.wire == wire) return method;
    }
    return null;
  }
}
