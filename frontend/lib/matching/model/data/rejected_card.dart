import 'package:campus_mate/matching/model/data/card_profile.dart';

/// 거절한 줄이 어디서 왔는지(`GET /cards/rejected` 의 `source`, 1.0.7 #20). 이름이 서버 값과 같다.
/// 어느 상세 읽기로 읽기 전용 프로필을 여는지도 이것으로 가른다 — [card] 는 `GET /cards/{card_id}`(보낸 신청 [프로필 보기]와 같은 길),
/// [acceptance] 는 `GET /cards/acceptances/{card_id}`.
enum RejectedSource {
  /// 내 카드를 넘겼다 → [다시 신청하기] 는 대화 신청을 새로 보낸다(그 줄은 보낸 신청으로 간다).
  card,

  /// 받은 신청에 거절로 답했다 → 되돌리면 바로 매칭(사용자 「바로 매칭」).
  acceptance,
}

/// 아직 되돌릴 수 있는 내 거절 한 건(대화 탭 [거절한 카드]). 되돌릴 수 있는지 · 남은 날 · 순서는 전부 서버가 정한다 —
/// 거절 시각 · 기한은 화면에 쓰지 않아 읽지 않는다. 남은 날은 서버의 [daysLeft] 하나만 본다(보낸 신청과 같다).
class RejectedCard {
  const RejectedCard({
    required this.cardId,
    required this.source,
    required this.profile,
    required this.daysLeft,
  });

  final String cardId;
  final RejectedSource source;

  /// 상대 프로필. 서버가 상대 profile_id 는 싣지 않는다(보낸 신청과 같은 모양).
  final CardProfile profile;

  /// 되돌릴 수 있는 기한까지 남은 날 — 남은 시간의 올림이라 최소 1 이다.
  final int daysLeft;

  factory RejectedCard.fromJson(Map<String, dynamic> json) {
    return RejectedCard(
      cardId: json['card_id'] as String,
      source: RejectedSource.values.byName(json['source'] as String),
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      daysLeft: json['days_left'] as int,
    );
  }
}

/// 거절한 카드 목록(일급 컬렉션). 서버 순서(최신 거절 먼저, 상한 50) 그대로다.
class RejectedCards {
  const RejectedCards(this._cards);

  static const RejectedCards empty = RejectedCards([]);

  final List<RejectedCard> _cards;

  /// 서버가 나중에 종류를 늘려도 목록 전체가 실패하지 않게, 모르는 source 줄만 건너뛴다.
  factory RejectedCards.fromJson(Map<String, dynamic> json) {
    final known = RejectedSource.values.asNameMap();
    return RejectedCards((json['rejected'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((item) => known.containsKey(item['source']))
        .map(RejectedCard.fromJson)
        .toList());
  }

  bool get isEmpty => _cards.isEmpty;

  /// 그 줄을 뺀 새 목록 — 되돌린 줄을 다시 읽기 전에 먼저 지운다.
  RejectedCards without(String cardId) =>
      RejectedCards(_cards.where((card) => card.cardId != cardId).toList());

  RejectedCard? find(String cardId) => _cards.where((card) => card.cardId == cardId).firstOrNull;

  /// 화면이 줄을 그릴 때 쓴다. 바꿀 수 없는 사본이다.
  List<RejectedCard> toList() => List.unmodifiable(_cards);
}
