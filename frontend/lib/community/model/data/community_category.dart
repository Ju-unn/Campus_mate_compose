/// 투표 · 게시물의 카테고리(할 일 19, 사용자 「자유, 진로, 연애」). 글쓰기에서 꼭 고른다.
/// **서버 값 ↔ 앱 값 변환은 이 파일 한 곳** — 피드 · 글쓰기 · 탭(그리고 나중 공지)이 이것만 쓴다.
enum CommunityCategory {
  free,
  career,
  love;

  /// 서버 `category` 값을 읽는다. 모르는 값 · 빈 값은 자유로 본다 — 서버가 나중에 값을 더해도 옛 앱 피드 한 줄이 깨지지 않게.
  static CommunityCategory fromWire(Object? value) =>
      values.firstWhere((category) => category.name == value, orElse: () => free);

  /// 서버에 보내는 값(`free` · `career` · `love`).
  String toWire() => name;
}
