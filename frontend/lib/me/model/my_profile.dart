/// 화면 15 내 프로필(pen `r8oJc`)이 그리는 값 한 벌. 서버 `GET /me/profile` 응답과 같다.
class MyProfile {
  const MyProfile({
    required this.nickname,
    required this.age,
    required this.university,
    required this.major,
    required this.heightCm,
    required this.mbti,
    required this.avatarUrl,
    required this.photoUrls,
    required this.preferredAgeMin,
    required this.preferredAgeMax,
    required this.preferredHeightMin,
    required this.preferredHeightMax,
    required this.bio,
  });

  final String nickname;

  /// 출생연도가 비었으면 null — 헤더는 ", 나이" 부분을 뺀다.
  final int? age;
  final String university;
  final String? major;
  final int? heightCm;
  final String? mbti;

  /// 공개 URL. 아직 만든 아바타가 없으면 null.
  final String? avatarUrl;

  /// 실사진 서명 URL. 대표 사진(0번)부터 순서대로.
  final List<String> photoUrls;
  final int? preferredAgeMin;
  final int? preferredAgeMax;

  /// "키는 상관없어요"(06-1)면 둘 다 null.
  final int? preferredHeightMin;
  final int? preferredHeightMax;
  final String? bio;
}
