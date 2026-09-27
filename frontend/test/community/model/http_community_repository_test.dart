import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/http_community_repository.dart';
import 'package:campus_mate/community/model/poll.dart';
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

  test('첫 쪽은 쿼리 없이, 다음 쪽은 맨 아래 글의 시각(UTC)과 id 로 부른다', () async {
    final urls = <String>[];
    final repository = buildRepository(MockClient((request) async {
      urls.add(request.url.toString());
      return jsonResponse({'polls': [], 'has_more': false});
    }));

    await repository.fetchPolls();
    await repository.fetchPolls(before: DateTime.utc(2026, 9, 27, 5), beforeId: 'p9');

    expect(urls[0], 'https://api.test/community/polls');
    expect(Uri.parse(urls[1]).queryParameters, {'before': '2026-09-27T05:00:00.000Z', 'before_id': 'p9'});
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

  test('삭제는 204 빈 본문도 성공으로 읽는다', () async {
    final repository = buildRepository(MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/community/polls/p1');
      return http.Response('', 204);
    }));

    final result = await repository.deletePoll('p1');

    expect(result, isA<Success<void>>());
  });
}
