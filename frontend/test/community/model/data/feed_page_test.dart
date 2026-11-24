import 'package:campus_mate/community/model/data/feed_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('{items, has_more} 를 읽는다 — 피드 · 댓글이 같은 모양이다', () {
    final page = FeedPage.fromJson({
      'items': [
        {'n': 1},
        {'n': 2},
      ],
      'has_more': true,
    }, (json) => json['n'] as int);

    expect(page.items, [1, 2]);
    expect(page.hasMore, isTrue);
  });

  test('커서는 시각(UTC)과 id 를 같은 이름 짝으로 싣는다 — 하나만 보내면 서버가 422 로 막는다', () {
    final cursor = (createdAt: DateTime.utc(2026, 9, 27, 5), id: 'p9');

    expect(cursor.toQuery('before'), {'before': '2026-09-27T05:00:00.000Z', 'before_id': 'p9'});
    expect(cursor.toQuery('after'), {'after': '2026-09-27T05:00:00.000Z', 'after_id': 'p9'});
  });

  test('지역 시각도 UTC 로 바꿔 보낸다', () {
    final local = DateTime.utc(2026, 9, 27, 5).toLocal();

    expect((createdAt: local, id: 'p9').toQuery('before')['before'], '2026-09-27T05:00:00.000Z');
  });
}
