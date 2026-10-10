import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/paid_card.dart';

/// 카드가 어디서 왔는지(ERD `card_source`). 구매 카드는 조각 7 에서 생긴다.
enum CardSource {
  daily,
  purchased;

  static CardSource fromWire(String value) => value == 'purchased' ? purchased : daily;
}

/// 받은 카드 한 장(화면 10 `W0CjO`).
class DailyCard {
  const DailyCard({
    required this.cardId,
    required this.source,
    required this.profile,
    this.expiresAt,
    this.reasons = const [],
  });

  final String cardId;
  final CardSource source;
  final CardProfile profile;

  /// 무응답 만료 시각. 구매 카드는 만료가 없어 null 이다(설계 §2.4).
  final DateTime? expiresAt;

  /// 산 카드에 서버가 붙여 주는 "맞는 이유". 무료 카드는 빈 목록이다.
  /// 지시문 23: 요약 카드 모양은 그대로라 **데이터만 받아 둔다**(화면에 아직 그리지 않는다).
  final List<ReasonTag> reasons;

  factory DailyCard.fromJson(Map<String, dynamic> json) {
    return DailyCard(
      cardId: json['card_id'] as String,
      source: CardSource.fromWire(json['source'] as String),
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      expiresAt: _parseTime(json['expires_at']),
      reasons: ReasonTag.listFrom(json['reasons']),
    );
  }
}

/// `GET /cards/today` 응답 전체(화면 10 · 11 · 11b 가 이 하나로 갈린다).
class TodayCards {
  const TodayCards({
    required this.cards,
    this.nextIssueAt,
    this.paidCard,
    this.candidatePoolEmpty = false,
  });

  final List<DailyCard> cards;

  /// 다음 지급 시각. 화면 11 의 카운트다운 재료다.
  final DateTime? nextIssueAt;

  /// 결제 카드(잠금 카드) 자리. 없으면 null — 후보 풀이 비었거나 이번 주기에 이미 샀다.
  /// 옛 호환 칸 `locked_card_available` 은 서버가 아직 내려 주지만 앱은 읽지 않는다(지시문 23).
  final PaidCard? paidCard;

  /// 후보 풀 자체가 비었는지. 화면 11(`i4VFS`)과 11b(`iQZoa`)를 가르는 값이다.
  final bool candidatePoolEmpty;

  factory TodayCards.fromJson(Map<String, dynamic> json) {
    return TodayCards(
      cards: (json['cards'] as List<dynamic>)
          .map((card) => DailyCard.fromJson(card as Map<String, dynamic>))
          .toList(),
      nextIssueAt: _parseTime(json['next_issue_at']),
      paidCard: PaidCard.tryParse(json['paid_card']),
      candidatePoolEmpty: json['candidate_pool_empty'] as bool? ?? false,
    );
  }
}

/// 서버는 `+09:00` 이 붙은 시각을 준다. `DateTime.parse` 는 그걸 UTC DateTime 으로 만들어
/// `.hour` 가 9시간 어긋나니(오전 7시 → 22시) 반드시 기기 시간대로 돌려놓는다.
DateTime? _parseTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();
