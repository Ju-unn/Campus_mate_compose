import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('탭 7개의 서버 tab 값', () {
    expect([for (final tab in CommunityFeedTab.values) tab.toWire()],
        ['all', 'popular', 'mine', 'voted', 'free', 'career', 'love']);
  });

  test('카테고리 탭은 그 카테고리의 서버 값을 그대로 쓴다', () {
    for (final category in CommunityCategory.values) {
      expect(CommunityFeedTab.of(category).toWire(), category.toWire());
    }
  });

  test('더 불러오기가 없는 탭은 인기뿐이다 — 참여 수 순 한 쪽뿐이다', () {
    expect([for (final tab in CommunityFeedTab.values) if (!tab.pages()) tab], [CommunityFeedTab.popular]);
  });
}
