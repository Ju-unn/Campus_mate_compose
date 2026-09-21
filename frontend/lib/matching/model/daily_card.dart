import 'package:campus_mate/matching/model/card_profile.dart';

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
  });

  final String cardId;
  final CardSource source;
  final CardProfile profile;

  /// 무응답 만료 시각. 구매 카드는 만료가 없어 null 이다(설계 §2.4).
  final DateTime? expiresAt;

  factory DailyCard.fromJson(Map<String, dynamic> json) {
    return DailyCard(
      cardId: json['card_id'] as String,
      source: CardSource.fromWire(json['source'] as String),
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      expiresAt: _parseTime(json['expires_at']),
    );
  }
}

/// `GET /cards/today` 응답 전체(화면 10 · 11 · 11b 가 이 하나로 갈린다).
class TodayCards {
  const TodayCards({
    required this.cards,
    this.nextIssueAt,
    this.lockedCardAvailable = false,
    this.candidatePoolEmpty = false,
  });

  final List<DailyCard> cards;

  /// 다음 지급 시각. 화면 11 의 카운트다운 재료다.
  final DateTime? nextIssueAt;

  /// 잠금 카드를 열 후보가 남아 있는지. **조각 7(하트) 전까지는 읽지 않는다.**
  final bool lockedCardAvailable;

  /// 후보 풀 자체가 비었는지. 화면 11(`i4VFS`)과 11b(`iQZoa`)를 가르는 값이다.
  final bool candidatePoolEmpty;

  factory TodayCards.fromJson(Map<String, dynamic> json) {
    return TodayCards(
      cards: (json['cards'] as List<dynamic>)
          .map((card) => DailyCard.fromJson(card as Map<String, dynamic>))
          .toList(),
      nextIssueAt: _parseTime(json['next_issue_at']),
      lockedCardAvailable: json['locked_card_available'] as bool? ?? false,
      candidatePoolEmpty: json['candidate_pool_empty'] as bool? ?? false,
    );
  }
}

DateTime? _parseTime(Object? value) => value == null ? null : DateTime.parse(value as String);
