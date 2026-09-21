import 'package:campus_mate/matching/model/card_profile.dart';

/// 나를 수락한 사람 한 명(13 대화 화면의 수락 대기 행 `XCN1f`).
/// 7일이 지난 수락은 서버가 아예 내려보내지 않는다 — 앱은 만료를 계산하지 않는다.
class Acceptance {
  const Acceptance({required this.cardId, required this.profile, this.expiresAt});

  final String cardId;
  final CardProfile profile;
  final DateTime? expiresAt;

  factory Acceptance.fromJson(Map<String, dynamic> json) {
    return Acceptance(
      cardId: json['card_id'] as String,
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
    );
  }
}

/// 수락함에 응답한 결과. 쌍방 수락이면 [matched] 가 참이고 [matchId] 가 채워진다.
class AcceptanceOutcome {
  const AcceptanceOutcome({required this.matched, this.matchId});

  final bool matched;
  final String? matchId;

  factory AcceptanceOutcome.fromJson(Map<String, dynamic> json) {
    return AcceptanceOutcome(
      matched: json['matched'] as bool,
      matchId: json['match_id'] as String?,
    );
  }
}
