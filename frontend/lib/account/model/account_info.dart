/// 16e 계정 화면이 그리는 값 한 벌. 이메일은 이 기기의 로그인 세션, 나머지는 서버 `GET /account`.
class AccountInfo {
  const AccountInfo({
    required this.email,
    required this.realName,
    required this.birthYear,
    required this.university,
    required this.joinedAt,
    required this.kakaoId,
  });

  final String email;

  /// 본인만 여기서 본다(CLAUDE.md §7). 학생증 제출 전이면 null.
  final String? realName;

  /// 04-1 전이면 null.
  final int? birthYear;
  final String university;
  final DateTime joinedAt;

  /// 04-1b 전이면 null.
  final String? kakaoId;
}
