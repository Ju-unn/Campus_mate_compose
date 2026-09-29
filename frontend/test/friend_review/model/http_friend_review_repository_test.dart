import 'dart:convert';

import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/friend_review/model/http_friend_review_repository.dart';
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

  HttpFriendReviewRepository buildRepository(http.Client client) {
    return HttpFriendReviewRepository(ApiClient('https://api.test', client, auth));
  }

  http.Response jsonResponse(Object body, [int status = 200]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// 요청 하나를 붙잡아 두고 [response] 를 돌려주는 가짜 서버.
  (MockClient, List<http.Request>) recording(http.Response response) {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return response;
    });
    return (client, seen);
  }

  Map<String, dynamic> reviewJson() => {
        'id': 'r1',
        'reviewer': {'nickname': '달빛', 'avatar_url': null, 'university': '테스트대학교'},
        'tags': ['성실해요'],
        'comment': null,
        'created_at': '2026-09-28T05:00:00+00:00',
      };

  test('create 는 POST /friend-reviews 에 다듬은 한마디를 싣고, 빈 한마디는 null', () async {
    final (client, seen) = recording(jsonResponse({'id': 'r1'}, 201));

    await buildRepository(client)
        .create(revieweeId: 'p2', tags: ['성실해요'], comment: '  좋아요 ');

    final request = seen.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.test/friend-reviews');
    expect(jsonDecode(request.body), {
      'reviewee_id': 'p2',
      'tags': ['성실해요'],
      'comment': '좋아요',
    });

    final (blankClient, blankSeen) = recording(jsonResponse({'id': 'r1'}, 201));
    await buildRepository(blankClient)
        .create(revieweeId: 'p2', tags: ['성실해요'], comment: '   ');
    expect(jsonDecode(blankSeen.single.body)['comment'], isNull);
  });

  test('fetchAbout 은 GET /friend-reviews/about/{id} 의 reviews 를 읽는다', () async {
    final (client, seen) = recording(jsonResponse({
      'reviews': [reviewJson()],
    }));

    final result = await buildRepository(client).fetchAbout('p2');

    expect(seen.single.method, 'GET');
    expect(seen.single.url.toString(), 'https://api.test/friend-reviews/about/p2');
    final reviews = result.when(onSuccess: (value) => value, onFailure: (_) => null)!;
    expect(reviews, hasLength(1));
    expect(reviews.single.nickname, '달빛');
  });

  test('fetchReceived 는 GET /friend-reviews/received', () async {
    final (client, seen) = recording(jsonResponse({
      'reviews': [reviewJson()],
    }));

    final result = await buildRepository(client).fetchReceived();

    expect(seen.single.method, 'GET');
    expect(seen.single.url.toString(), 'https://api.test/friend-reviews/received');
    final reviews = result.when(onSuccess: (value) => value, onFailure: (_) => null)!;
    expect(reviews, hasLength(1));
  });

  test('fetchTarget 은 GET /friend-reviews/targets/{id}', () async {
    final (client, seen) = recording(jsonResponse({
      'profile_id': 'p2',
      'nickname': '달빛',
      'avatar_url': null,
    }));

    final result = await buildRepository(client).fetchTarget('p2');

    expect(seen.single.method, 'GET');
    expect(seen.single.url.toString(), 'https://api.test/friend-reviews/targets/p2');
    final target = result.when(onSuccess: (value) => value, onFailure: (_) => null)!;
    expect(target.profileId, 'p2');
    expect(target.nickname, '달빛');
  });
}
