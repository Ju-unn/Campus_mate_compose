import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_tags.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson 은 reviewer 를 펼치고 시각을 UTC 로 읽는다', () {
    final review = FriendReview.fromJson({
      'id': 'r1',
      'reviewer': {'nickname': '달빛', 'avatar_url': null, 'university': '테스트대학교'},
      'tags': ['약속을 잘 지켜요'],
      'comment': null,
      'created_at': '2026-09-28T05:00:00+00:00',
    });

    expect(review.id, 'r1');
    expect(review.nickname, '달빛');
    expect(review.university, '테스트대학교');
    expect(review.avatarUrl, isNull);
    expect(review.tags, ['약속을 잘 지켜요']);
    expect(review.comment, isNull);
    expect(review.createdAt, DateTime.utc(2026, 9, 28, 5));
  });

  test('reviewer 아바타 · 한마디가 있으면 그대로 읽는다', () {
    final review = FriendReview.fromJson({
      'id': 'r2',
      'reviewer': {
        'nickname': '여우비',
        'avatar_url': 'https://cdn.test/a.png',
        'university': '테스트대학교',
      },
      'tags': ['성실해요', '다정해요'],
      'comment': '믿음직해요',
      'created_at': '2026-09-27T05:00:00+00:00',
    });

    expect(review.avatarUrl, 'https://cdn.test/a.png');
    expect(review.tags, ['성실해요', '다정해요']);
    expect(review.comment, '믿음직해요');
  });

  test('ReviewTarget.fromJson 은 20b 머리에 쓸 필드를 읽는다', () {
    final target = ReviewTarget.fromJson({
      'profile_id': 'p2',
      'nickname': '달빛',
      'avatar_url': null,
    });

    expect(target.profileId, 'p2');
    expect(target.nickname, '달빛');
    expect(target.avatarUrl, isNull);
  });

  test('리뷰 신고 대상은 target_type friend_review 로 간다', () {
    expect(const ReportTarget.friendReview('r1').toJson(), {'target_type': 'friend_review', 'target_id': 'r1'});
  });

  test('태그 목록은 서버 TAGS 와 같은 12종 · 외모 태그 없음', () {
    expect(friendReviewTags, hasLength(12));
    expect(friendReviewTags.first, '약속을 잘 지켜요');
    expect(friendReviewTags.last, '리액션이 좋아요');
    expect(friendReviewMaxTags, 3);
    expect(friendReviewCommentMaxLength, 100);
  });
}
