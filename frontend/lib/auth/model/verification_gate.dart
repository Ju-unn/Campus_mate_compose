/// go_router 가 다음 화면을 정할 때만 쓰는 굵은 단위 상태.
/// 3b 화면 안의 세부 상태(검토중 사유 등)는 VerificationOutcome 이 따로 다룬다.
enum VerificationGate {
  /// 아직 묻는 중이다(앱을 켠 직후 · 로그아웃 뒤). 스플래시에 머문다 — 동의 화면이 깜빡이지 않게(결정 13).
  unknown,

  /// 처음 묻는 것부터 실패했다. 01-1 인터넷 없음 화면에서 "다시 시도" 를 기다린다(결정 13, B10).
  /// 한 번이라도 알아낸 뒤의 실패는 이 값이 되지 않는다 — 아는 관문을 그대로 쓴다.
  unreachable,

  /// 약관 동의(02-c)가 첫 관문이다 — 동의 전에는 실명 · 학생증(3b)을 받지 않는다.
  needsConsent,

  /// 약관이 바뀌어 다시 동의해야 한다(02-c-4). 온보딩을 마친 계정도 여기로 온다.
  needsConsentRenewal,
  needsStudentVerification,
  needsSchoolInfo,
  complete,
}
