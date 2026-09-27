import 'package:campus_mate/matching/model/card_detail.dart';

/// 14c 상대 프로필(`GET /profiles/{profile_id}`). 게이트(서로 수락) 뒤에만 카톡 아이디 · 실사진이 붙는다.
class PartnerProfile {
  const PartnerProfile({
    required this.matchId,
    required this.detail,
    this.kakaoId,
    this.photoUrls,
  });

  final String matchId;
  final CardDetail detail;

  /// 게이트 뒤라도 상대가 적지 않았으면 null 이다. 공개 여부는 [isRevealed] 로 가른다.
  final String? kakaoId;

  /// 서명 URL. 게이트 전에는 서버가 키 자체를 주지 않아 null 이다.
  final List<String>? photoUrls;

  bool get isRevealed => photoUrls != null;

  factory PartnerProfile.fromJson(Map<String, dynamic> json) {
    return PartnerProfile(
      matchId: json['match_id'] as String,
      // 키가 카드 상세와 같아 모델을 다시 만들지 않는다 — 그래서 detail.cardId 에는 match id 가 든다.
      detail: CardDetail.fromJson({...json, 'card_id': json['match_id']}),
      kakaoId: json['kakao_id'] as String?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((url) => url as String).toList(),
    );
  }
}
