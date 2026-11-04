/// 16e 계정 화면이 그리는 값 한 벌. 로그인 수단은 이 기기의 로그인 세션, 나머지는 서버 `GET /account`.
/// 실명은 받지 않는다(2026-10-17 학생증 제거) — 서버가 옛 앱 호환으로 `real_name` 칸을 내려 줘도 읽지 않는다.
class AccountInfo {
  const AccountInfo({
    required this.loginProvider,
    required this.birthYear,
    required this.university,
    required this.joinedAt,
    required this.kakaoId,
  });

  /// 세션 `app_metadata.provider`(kakao · google · apple …). 못 읽으면 null.
  /// 소셜 로그인 뒤 `user.email` 은 개인 메일이거나(구글) 비어 있어(카카오) 이 화면에 쓰지 않는다.
  final String? loginProvider;

  /// 04-1 전이면 null.
  final int? birthYear;
  final String university;
  final DateTime joinedAt;

  /// 04-1b 전이면 null.
  final String? kakaoId;
}
