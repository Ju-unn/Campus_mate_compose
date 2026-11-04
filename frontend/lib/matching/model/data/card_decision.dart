/// 수락·거절 한 쌍. 카드 결정과 수락함 응답이 같은 값을 쓴다(ERD `card_decision`).
enum CardDecision {
  accept,
  reject;

  String get wire => name;
}
