import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Object? aliasNo = 2, bool isPostAuthor = false}) => {
      'id': 'c1',
      'body': '저는 상관없어요',
      'created_at': '2026-11-10T05:00:00.123456+00:00',
      'alias_no': aliasNo,
      'is_post_author': isPostAuthor,
      'is_mine': true,
      'can_delete': true,
    };

void main() {
  test('서버 칸을 읽는다 — 시각은 기기 시간대로', () {
    final comment = PollComment.fromJson(_json());
    expect(comment.id, 'c1');
    expect(comment.body, '저는 상관없어요');
    expect(comment.aliasNo, 2);
    expect(comment.isPostAuthor, isFalse);
    expect(comment.isMine, isTrue);
    expect(comment.canDelete, isTrue);
    expect(comment.createdAt.isUtc, isFalse);
    expect(comment.createdAt.microsecond, 456);
  });

  test('글쓴이 댓글은 번호가 없다(alias_no null)', () {
    final comment = PollComment.fromJson(_json(aliasNo: null, isPostAuthor: true));
    expect(comment.aliasNo, isNull);
    expect(comment.isPostAuthor, isTrue);
  });

  test('쪽은 댓글 목록과 더 있는지를 읽는다', () {
    final page = PollCommentPage.fromJson({
      'items': [_json()],
      'has_more': true,
    });
    expect(page.comments.single.id, 'c1');
    expect(page.hasMore, isTrue);
  });

  test('글 모델은 comment_count 를 읽고, 없으면(옛 서버) 0 이다', () {
    Map<String, dynamic> poll([Object? count]) => {
          'id': 'p1',
          'question': 'q',
          'option_a_label': '찬성',
          'option_b_label': '반대',
          'created_at': '2026-09-27T05:00:00+00:00',
          'a_count': 1,
          'b_count': 0,
          'my_choice': null,
          'is_mine': false,
          'comment_count': ?count,
        };
    expect(Poll.fromJson(poll(12)).commentCount, 12);
    expect(Poll.fromJson(poll()).commentCount, 0);
  });

  test('withCommentCount 는 댓글 수만 바꾼 사본이다', () {
    final poll = Poll.fromJson({
      'id': 'p1',
      'question': 'q',
      'option_a_label': '찬성',
      'option_b_label': '반대',
      'created_at': '2026-09-27T05:00:00+00:00',
      'a_count': 1,
      'b_count': 0,
      'my_choice': 'a',
      'is_mine': true,
      'comment_count': 3,
    });
    final changed = poll.withCommentCount(4);
    expect(changed.commentCount, 4);
    expect(changed.id, poll.id);
    expect(changed.myChoice, PollChoice.a);
    expect(changed.isMine, isTrue);
  });
}
