import 'package:campus_mate/profile/model/profile_enums.dart';

/// 화면 15 내 프로필(pen `r8oJc`)과 편집 화면(15c · 태그 3종 · 06-1 편집)이 읽는 값 한 벌.
/// 서버 `GET /me/profile` 응답과 같다(계획서 2026-09-27-me-edit.md 2-1).
class MyProfile {
  const MyProfile({
    required this.nickname,
    required this.age,
    required this.university,
    required this.major,
    required this.heightCm,
    required this.mbti,
    required this.avatarUrl,
    required this.preferredAgeMin,
    required this.preferredAgeMax,
    required this.preferredHeightMin,
    required this.preferredHeightMax,
    required this.bio,
    this.photos = const [],
    this.interestTags = const [],
    this.myTraits = const [],
    this.idealTraits = const [],
    this.preferredMbtiFlags = const {},
    this.preferredAnimalTypes = const [],
    this.preferredImpressionTypes = const [],
    this.heartBalance = 0,
    this.avatarRegenCost = 0,
    this.nicknameChangeableAt,
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
  final int? preferredAgeMin;
  final int? preferredAgeMax;

  /// "키는 상관없어요"(06-1)면 둘 다 null.
  final int? preferredHeightMin;
  final int? preferredHeightMax;
  final String? bio;

  /// 실사진 행. 대표 사진(0번)부터 자리 순서대로.
  final List<MyPhoto> photos;

  /// 15c 칩과 태그 편집(04-5 · 04-6 · 06-2 편집 모드)을 채운다.
  final List<String> interestTags;
  final List<String> myTraits;
  final List<String> idealTraits;

  /// 06-1 편집을 채운다. 켠 극만 true 로 온다.
  final Map<String, bool> preferredMbtiFlags;
  final List<AnimalType> preferredAnimalTypes;
  final List<ImpressionType> preferredImpressionTypes;

  /// 하트 잔액. 하트를 받은 적이 없으면 0.
  final int heartBalance;

  /// 0 = 이번 다시 만들기는 무료, 10 = 하트 10.
  final int avatarRegenCost;

  /// 닉네임이 잠겨 있으면 풀리는 때(기기 시간대). null = 지금 바꿀 수 있음 — 판정은 서버 시계로 한다.
  final DateTime? nicknameChangeableAt;

  /// 실사진 서명 URL. 대표 사진(0번)부터 순서대로 — 화면 15 슬라이더가 읽는다.
  List<String> get photoUrls => [for (final photo in photos) photo.url];
}

/// 내 실사진 한 장. [id] 는 사진 한 번에 저장(`PUT /me/photos`)이 "남길 사진" 으로 되돌려 보낸다.
class MyPhoto {
  const MyPhoto({required this.id, required this.url, required this.isAvatarSource});

  final String id;

  /// 서명 URL(1시간).
  final String url;

  /// 아바타를 만든 원본 사진인지.
  final bool isAvatarSource;
}
