/// 홈 프로필 완성도 카드의 "더 채울 수 있는 것" 한 칸(2026-11-15 사용자 「~더 채우기 칩 모양으로」).
/// [code] 는 서버 `GET /home/summary` `profile_completion_missing` 값 그대로다 — 순서도 서버 순서(= 이 선언 순서).
enum ProfileCompletionItem {
  photos('photos'),
  mbti('mbti'),
  preferredHeight('preferred_height'),
  interestTags('interest_tags');

  const ProfileCompletionItem(this.code);

  final String code;

  /// 모르는 값(새 서버의 새 항목 등)은 null — 목록에서 건너뛴다.
  static ProfileCompletionItem? tryParse(Object? code) {
    for (final item in values) {
      if (item.code == code) return item;
    }
    return null;
  }
}
