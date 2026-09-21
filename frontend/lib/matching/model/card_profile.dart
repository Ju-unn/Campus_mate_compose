/// 카드 앞면·수락함 행이 쓰는 최소 프로필(설계 §7.1 — 실명·연락처는 서버가 내려보내지 않는다).
class CardProfile {
  const CardProfile({
    required this.profileId,
    required this.nickname,
    required this.age,
    this.university,
    this.major,
    this.avatarUrl,
  });

  final String profileId;
  final String nickname;
  final int age;
  final String? university;
  final String? major;

  /// 표시용 만화 아바타. 실사진은 신뢰 확인(조각 5) 전까지 존재하지 않는다(§5.2).
  final String? avatarUrl;

  /// pen `eWD7g` 가 "여우비, 23" 한 줄로 쓴다.
  String get nameWithAge => '$nickname, $age';

  /// pen `Q8c2Y3` 가 "서울대학교 · 컴퓨터공학과" 한 줄로 쓴다. 한쪽이 비면 가운뎃점도 없앤다.
  String get schoolLine => [university, major].whereType<String>().join(' · ');

  factory CardProfile.fromJson(Map<String, dynamic> json) {
    return CardProfile(
      profileId: json['profile_id'] as String,
      nickname: json['nickname'] as String,
      age: json['age'] as int,
      university: json['university'] as String?,
      major: json['major'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
