/// go_router 가 다음 화면을 정할 때만 쓰는 굵은 단위 상태.
/// 3b 화면 안의 세부 상태(검토중 사유 등)는 VerificationOutcome 이 따로 다룬다.
enum VerificationGate {
  /// 약관 동의(02-c)가 첫 관문이다 — 동의 전에는 실명 · 학생증(3b)을 받지 않는다.
  needsConsent,

  /// 약관이 바뀌어 다시 동의해야 한다(02-c-4). 온보딩을 마친 계정도 여기로 온다.
  needsConsentRenewal,
  needsStudentVerification,
  needsSchoolInfo,
  complete,
}
