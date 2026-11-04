/// 16f 차단 목록 한 줄. **아바타만 온다** — 실사진은 서버가 주지 않는다(B2).
class BlockedUser {
  const BlockedUser({
    required this.profileId,
    required this.nickname,
    required this.blockedAt,
    this.avatarUrl,
  });

  final String profileId;
  final String nickname;
  final String? avatarUrl;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    return BlockedUser(
      profileId: json['profile_id'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatar_url'] as String?,
      // 서버는 UTC(+00:00) 로 준다. 화면은 차단일을 기기 날짜로 보여 준다.
      blockedAt: DateTime.parse(json['blocked_at'] as String).toLocal(),
    );
  }
}
