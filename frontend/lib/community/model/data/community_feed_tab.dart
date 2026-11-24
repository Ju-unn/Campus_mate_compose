import 'package:campus_mate/community/model/data/community_category.dart';

/// 피드 탭 7개. 이름이 서버 `GET /community/feed?tab=` 값(`FeedTab`)과 같다 — 카테고리 탭 셋은 카테고리 서버 값 그대로다.
/// 인기는 최근 7일 참여 수 순 한 쪽뿐이라 서버가 늘 "더 없음" 으로 답하고 커서도 받지 않는다(422). 나머지는 올린 시각 순 · 같은 커서.
enum CommunityFeedTab {
  all,
  popular,
  mine,
  voted,
  free,
  career,
  love;

  /// 카테고리 하나의 탭.
  static CommunityFeedTab of(CommunityCategory category) => switch (category) {
        CommunityCategory.free => free,
        CommunityCategory.career => career,
        CommunityCategory.love => love,
      };

  String toWire() => name;

  /// 다음 쪽이 있는 탭인가. 인기만 아니다 — 시각 커서로 참여 수 순서를 자르면 순서가 엉킨다.
  bool pages() => this != popular;
}
