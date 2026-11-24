import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/repository/http_community_repository.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockGoTrueClient auth;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpCommunityRepository buildRepository(http.Client client) =>
      HttpCommunityRepository(ApiClient('https://api.test', client, auth));

  http.Response jsonResponse(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> itemJson(String id, {Map<String, dynamic>? poll}) => {
        'id': id, 'kind': poll == null ? 'post' : 'poll', 'category': 'career', 'text': '취업 준비 어떻게 해요?',
        'created_at': '2026-11-24T05:00:00+00:00', 'is_mine': false, 'comment_count': 2, 'poll': poll,
      };

  test('피드 첫 쪽은 GET /community/feed 쿼리 없이, 다음 쪽은 맨 아래 글의 시각(UTC)과 id 로 부른다', () async {
    final urls = <String>[];
    final repository = buildRepository(MockClient((request) async {
      urls.add(request.url.toString());
      return jsonResponse({'items': [], 'has_more': false});
    }));

    await repository.fetchFeed();
    await repository.fetchFeed(before: (createdAt: DateTime.utc(2026, 9, 27, 5), id: 'p9'));

    expect(urls[0], 'https://api.test/community/feed');
    expect(Uri.parse(urls[1]).path, '/community/feed');
    expect(Uri.parse(urls[1]).queryParameters, {'before': '2026-09-27T05:00:00.000Z', 'before_id': 'p9'});
  });

  test('전체 말고 다른 탭은 tab 을 서버 값으로 보내고(카테고리 탭 포함), 다음 쪽이면 커서도 같이 보낸다', () async {
    final urls = <Uri>[];
    final repository = buildRepository(MockClient((request) async {
      urls.add(request.url);
      return jsonResponse({'items': [], 'has_more': false});
    }));

    await repository.fetchFeed(tab: CommunityFeedTab.all);
    await repository.fetchFeed(tab: CommunityFeedTab.popular);
    await repository.fetchFeed(tab: CommunityFeedTab.love);
    await repository.fetchFeed(tab: CommunityFeedTab.voted, before: (createdAt: DateTime.utc(2026, 9, 27, 5), id: 'p9'));

    // 전체는 쿼리가 없다 — 서버 기본값이 all 이다.
    expect(urls[0].toString(), 'https://api.test/community/feed');
    expect(urls[1].queryParameters, {'tab': 'popular'});
    expect(urls[2].queryParameters, {'tab': 'love'});
    expect(urls[3].queryParameters, {'tab': 'voted', 'before': '2026-09-27T05:00:00.000Z', 'before_id': 'p9'});
  });

  test('피드는 투표 · 게시물이 섞인 items 와 has_more 를 읽는다', () async {
    final repository = buildRepository(MockClient((request) async => jsonResponse({
          'items': [
            itemJson('i1'),
            itemJson('i2', poll: {'option_a_label': '찬성', 'option_b_label': '반대', 'a_count': 1, 'b_count': 0, 'my_choice': null}),
          ],
          'has_more': true,
        })));

    final result = await repository.fetchFeed();

    result.when(
      onSuccess: (page) {
        expect([for (final item in page.items) item.kind], [CommunityKind.post, CommunityKind.poll]);
        expect(page.items.first.category, CommunityCategory.career);
        expect(page.hasMore, isTrue);
      },
      onFailure: (failure) => fail('$failure'),
    );
  });

  test('게시물 id 로 열면(댓글 푸시 route "poll" 도 같은 상세) GET /community/items/{id} 가 게시물을 담는다 — kind post · poll null', () async {
    final repository = buildRepository(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/community/items/i1');
      return jsonResponse({'item': itemJson('i1')});
    }));

    final result = await repository.fetchItem('i1');

    result.when(
      onSuccess: (item) {
        expect(item.kind, CommunityKind.post);
        expect(item.poll, isNull);
        expect(item.id, 'i1');
        expect(item.text, '취업 준비 어떻게 해요?');
        expect(item.category, CommunityCategory.career);
        expect(item.commentCount, 2);
      },
      onFailure: (failure) => fail('$failure'),
    );
  });

  test('투표 id 로 열면 같은 길이 투표 칸(poll)을 담는다', () async {
    final repository = buildRepository(MockClient((request) async => jsonResponse({
          'item': itemJson('i2', poll: {'option_a_label': '짜장', 'option_b_label': '짬뽕', 'a_count': 3, 'b_count': 1, 'my_choice': 'a'}),
        })));

    final result = await repository.fetchItem('i2');

    result.when(
      onSuccess: (item) {
        expect(item.kind, CommunityKind.poll);
        expect(item.poll!.optionA, '짜장');
        expect(item.poll!.myChoice, PollChoice.a);
      },
      onFailure: (failure) => fail('$failure'),
    );
  });

  test('없는 · 가려진 글(404)이면 서버 문구를 실은 실패다', () async {
    final repository = buildRepository(MockClient((request) async => jsonResponse({'detail': '글을 찾을 수 없어요'}, 404)));

    final result = await repository.fetchItem('i1');

    result.when(
      onSuccess: (_) => fail('성공하면 안 된다'),
      onFailure: (failure) => expect((failure as ServerRejectedFailure).serverMessage, '글을 찾을 수 없어요'),
    );
  });

  test('투표 올리기는 POST /community/polls 에 카테고리를 같이 싣는다', () async {
    final repository = buildRepository(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/community/polls');
      expect(jsonDecode(request.body),
          {'question': '짜장 vs 짬뽕', 'option_a_label': '짜장', 'option_b_label': '짬뽕', 'category': 'love'});
      return jsonResponse({'id': 'p1'}, 201);
    }));

    final result = await repository.createPoll(
        category: CommunityCategory.love, question: '짜장 vs 짬뽕', optionA: '짜장', optionB: '짬뽕');

    expect(result, isA<Success<void>>());
  });

  test('게시물 올리기는 POST /community/posts {category, body}', () async {
    final repository = buildRepository(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/community/posts');
      expect(jsonDecode(request.body), {'category': 'career', 'body': '면접 팁 있나요'});
      return jsonResponse({'id': 'i1'}, 201);
    }));

    final result = await repository.createPost(category: CommunityCategory.career, body: '면접 팁 있나요');

    expect(result, isA<Success<void>>());
  });

  test('하루 10개를 넘으면 429 와 서버 문구를 실패로 돌려준다', () async {
    final repository = buildRepository(
        MockClient((request) async => jsonResponse({'detail': '오늘은 글을 더 올릴 수 없어요'}, 429)));

    final result = await repository.createPost(category: CommunityCategory.free, body: '안녕');

    result.when(
      onSuccess: (_) => fail('성공하면 안 된다'),
      onFailure: (failure) => expect((failure as RateLimitedFailure).serverMessage, '오늘은 글을 더 올릴 수 없어요'),
    );
  });

  test('투표는 choice 를 보내고 새 글과 보상 여부를 읽는다', () async {
    final repository = buildRepository(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/community/polls/p1/votes');
      expect(jsonDecode(request.body), {'choice': 'a'});
      return jsonResponse({
        'poll': {
          'id': 'p1', 'question': 'q', 'option_a_label': '찬성', 'option_b_label': '반대',
          'created_at': '2026-09-27T05:00:00+00:00', 'a_count': 1, 'b_count': 0, 'my_choice': 'a', 'is_mine': false,
        },
        'rewarded': true,
      });
    }));

    final outcome = await repository.vote('p1', PollChoice.a);

    outcome.when(
      onSuccess: (value) {
        expect(value.rewarded, isTrue);
        expect(value.poll.myChoice, PollChoice.a);
      },
      onFailure: (failure) => fail('$failure'),
    );
  });

  test('글 삭제는 DELETE /community/items/{id}, 204 빈 본문도 성공으로 읽는다', () async {
    final repository = buildRepository(MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/community/items/p1');
      return http.Response('', 204);
    }));

    final result = await repository.deleteItem('p1');

    expect(result, isA<Success<void>>());
  });
  group('댓글', () {
    Map<String, dynamic> commentJson(String id) => {
          'id': id, 'body': '안녕', 'created_at': '2026-11-10T05:00:00+00:00',
          'alias_no': 1, 'is_post_author': false, 'is_mine': false, 'can_delete': false,
        };

    test('첫 쪽은 쿼리 없이, 더 보기는 마지막 댓글의 시각(UTC)과 id 를 after · after_id 로 보낸다', () async {
      final urls = <Uri>[];
      final repository = buildRepository(MockClient((request) async {
        urls.add(request.url);
        return jsonResponse({'items': [commentJson('c1')], 'has_more': true});
      }));

      final first = await repository.fetchComments('p1');
      await repository.fetchComments('p1', after: (createdAt: DateTime.utc(2026, 11, 10, 5), id: 'c9'));

      expect(urls[0].toString(), 'https://api.test/community/items/p1/comments');
      expect(urls[1].queryParameters, {'after': '2026-11-10T05:00:00.000Z', 'after_id': 'c9'});
      first.when(
        onSuccess: (page) {
          expect(page.items.single.id, 'c1');
          expect(page.hasMore, isTrue);
        },
        onFailure: (failure) => fail('$failure'),
      );
    });

    test('쓰기는 body 를 POST 하고 201 한 줄을 읽는다', () async {
      final repository = buildRepository(MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/community/items/p1/comments');
        expect(jsonDecode(request.body), {'body': '안녕'});
        return jsonResponse(commentJson('c7'), 201);
      }));

      final result = await repository.addComment('p1', '안녕');

      result.when(onSuccess: (comment) => expect(comment.id, 'c7'), onFailure: (failure) => fail('$failure'));
    });

    test('하루 50개를 넘으면 429 와 서버 문구를 실패로 돌려준다', () async {
      final repository = buildRepository(MockClient(
        (request) async => jsonResponse({'detail': '오늘은 댓글을 더 달 수 없어요'}, 429),
      ));

      final result = await repository.addComment('p1', '안녕');

      result.when(
        onSuccess: (_) => fail('성공하면 안 된다'),
        onFailure: (failure) => expect((failure as RateLimitedFailure).serverMessage, '오늘은 댓글을 더 달 수 없어요'),
      );
    });

    test('삭제는 DELETE /community/comments/{id}, 204 빈 본문도 성공이다', () async {
      final repository = buildRepository(MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/community/comments/c1');
        return http.Response('', 204);
      }));

      expect(await repository.deleteComment('c1'), isA<Success<void>>());
    });
  });
}
