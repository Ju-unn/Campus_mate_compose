/// go_router 가 다음 화면을 정할 때만 쓰는 굵은 단위 상태.
/// 3b 화면 안의 세부 상태(검토중 사유 등)는 VerificationOutcome 이 따로 다룬다.
enum VerificationGate {
  needsStudentVerification,
  needsSchoolInfo,
  complete,
}
