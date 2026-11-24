import 'package:campus_mate/community/model/data/notice.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Object? imageUrl, Object? isNew = true}) => {
      'id': 'n1',
      'title': '1.0.7 업데이트 안내',
      'text': '<b>굵게</b> 그대로',
      'image_url': imageUrl,
      'created_at': '2026-11-24T05:00:00+00:00',
      'is_new': isNew,
      'comment_count': 3,
    };

void main() {
  test('공지 목록 한 줄을 읽는다 — 본문 글자는 손대지 않고, 시각은 기기 시간대로 바꾼다', () {
    final notice = Notice.fromJson(_json(imageUrl: 'https://img.test/a.webp'));

    expect(notice.id, 'n1');
    expect(notice.title, '1.0.7 업데이트 안내');
    expect(notice.text, '<b>굵게</b> 그대로');
    expect(notice.imageUrl, 'https://img.test/a.webp');
    expect(notice.createdAt, DateTime.utc(2026, 11, 24, 5).toLocal());
    expect(notice.createdAt.isUtc, isFalse);
    expect(notice.isNew, isTrue);
    expect(notice.commentCount, 3);
  });

  test('그림이 없으면 imageUrl 이 null 이고, 상세처럼 is_new 가 없으면 NEW 가 아니다', () {
    final notice = Notice.fromJson(_json(isNew: null));

    expect(notice.imageUrl, isNull);
    expect(notice.isNew, isFalse);
  });

  test('withCommentCount 는 댓글 수만 바꾼 사본이다', () {
    final notice = Notice.fromJson(_json()).withCommentCount(9);

    expect(notice.commentCount, 9);
    expect(notice.title, '1.0.7 업데이트 안내');
    expect(notice.isNew, isTrue);
  });
}
