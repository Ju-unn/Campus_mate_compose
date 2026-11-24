import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, dynamic> _pollPart = {
  'option_a_label': '찬성',
  'option_b_label': '반대',
  'a_count': 2,
  'b_count': 1,
  'my_choice': 'b',
};

Map<String, dynamic> _item({String kind = 'poll', String category = 'love', Map<String, dynamic>? poll = _pollPart}) => {
      'id': 'i1',
      'kind': kind,
      'category': category,
      'text': '첫 데이트 더치페이',
      'created_at': '2026-11-24T05:00:00+00:00',
      'is_mine': true,
      'comment_count': 4,
      'poll': poll,
    };

void main() {
  group('CommunityItem.fromJson', () {
    test('투표 줄은 poll 칸을 기존 Poll 로 읽고, 질문은 text 다', () {
      final item = CommunityItem.fromJson(_item());

      expect(item.kind, CommunityKind.poll);
      expect(item.category, CommunityCategory.love);
      expect(item.id, 'i1');
      expect(item.text, '첫 데이트 더치페이');
      expect(item.isMine, isTrue);
      expect(item.commentCount, 4);
      expect(item.createdAt.isUtc, isFalse);
      final poll = item.poll!;
      expect(poll.id, 'i1');
      expect(poll.question, '첫 데이트 더치페이');
      expect(poll.myChoice, PollChoice.b);
      expect(poll.total, 3);
      expect(poll.isMine, isTrue);
      expect(poll.commentCount, 4);
    });

    test('게시물 줄은 poll 이 null 이다', () {
      final item = CommunityItem.fromJson(_item(kind: 'post', category: 'career', poll: null));

      expect(item.kind, CommunityKind.post);
      expect(item.poll, isNull);
      expect(item.category, CommunityCategory.career);
      expect(item.text, '첫 데이트 더치페이');
      expect(item.commentCount, 4);
      expect(item.isMine, isTrue);
    });
  });

  test('withCommentCount 는 댓글 수만 바꾸고, 투표면 안의 Poll 숫자도 같이 맞춘다', () {
    final poll = CommunityItem.fromJson(_item()).withCommentCount(9);
    final post = CommunityItem.fromJson(_item(kind: 'post', poll: null)).withCommentCount(9);

    expect(poll.commentCount, 9);
    expect(poll.poll!.commentCount, 9);
    expect(poll.category, CommunityCategory.love);
    expect(post.commentCount, 9);
    expect(post.poll, isNull);
    expect(post.text, '첫 데이트 더치페이');
  });

  test('withVote 는 투표 응답(옛 카드 모양, 카테고리 없음)을 받아 카테고리는 지키고 투표 칸을 바꾼다', () {
    final item = CommunityItem.fromJson(_item());
    final voted = Poll(
      id: 'i1',
      question: '첫 데이트 더치페이',
      optionA: '찬성',
      optionB: '반대',
      createdAt: item.createdAt,
      aCount: 3,
      bCount: 1,
      myChoice: PollChoice.a,
      isMine: true,
      commentCount: 5,
    );

    final next = item.withVote(voted);

    expect(next.category, CommunityCategory.love);
    expect(next.poll!.myChoice, PollChoice.a);
    expect(next.poll!.total, 4);
    expect(next.commentCount, 5);
  });

  group('CommunityKind — 앱 검사는 미리 보여 주기만, 기준은 서버', () {
    test('글자 상한: 투표 질문 80 · 게시물 본문 500 (서버 · DB 와 같다)', () {
      expect(CommunityKind.poll.maxLength, 80);
      expect(CommunityKind.post.maxLength, 500);
    });

    test('앞뒤 공백을 깎고 코드 포인트로 잰다', () {
      expect(CommunityKind.post.accepts('${'가' * 500}  '), isTrue);
      expect(CommunityKind.post.accepts('가' * 501), isFalse);
      // 👍🏻 = 코드 포인트 2개(서버 len 과 같다)
      expect(CommunityKind.poll.accepts('👍🏻' * 40), isTrue);
      expect(CommunityKind.poll.accepts('${'👍🏻' * 40}a'), isFalse);
    });

    test('빈 글 · 공백뿐 · 0폭 문자뿐이면 받지 않는다(서버 visible 과 같은 목록)', () {
      for (final blank in ['', '   ', '\n\t', '​‌‍⁠﻿', ' ​ ']) {
        expect(CommunityKind.post.accepts(blank), isFalse, reason: blank.runes.toString());
      }
      expect(CommunityKind.post.accepts('​가'), isTrue);
    });
  });
}
