import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/http_card_repository.dart';
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

  HttpCardRepository buildRepository(http.Client client) {
    return HttpCardRepository('https://api.test', client, auth);
  }

  http.Response jsonResponse(Object body) {
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  test('오늘의 카드를 프로필까지 붙여 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.test/cards/today');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return jsonResponse({
        'cards': [
          {
            'card_id': 'card-1',
            'source': 'daily',
            'expires_at': '2026-09-24T07:00:00+09:00',
            'profile': {
              'profile_id': 't1',
              'nickname': '여우비',
              'age': 23,
              'university': '테스트대학교',
              'major': '컴퓨터공학과',
              'avatar_url': 'https://cdn.test/a.png',
            },
          },
        ],
        'next_issue_at': '2026-09-24T07:00:00+09:00',
        'locked_card_available': true,
        'candidate_pool_empty': false,
      });
    });

    final result = await buildRepository(client).fetchToday();

    final today = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(today!.cards.single.profile.nameWithAge, '여우비, 23');
    expect(today.cards.single.profile.schoolLine, '테스트대학교 · 컴퓨터공학과');
    expect(today.nextIssueAt, DateTime.parse('2026-09-24T07:00:00+09:00'));
  });

  test('카드가 하나도 없고 후보 풀도 비었으면 그 사실이 그대로 올라온다', () async {
    final client = MockClient((request) async => jsonResponse({
          'cards': <Object>[],
          'next_issue_at': null,
          'locked_card_available': false,
          'candidate_pool_empty': true,
        }));

    final result = await buildRepository(client).fetchToday();

    final today = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(today!.cards, isEmpty);
    expect(today.candidatePoolEmpty, isTrue);
  });

  test('결정은 decision 값을 그대로 보낸다', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return jsonResponse({'ok': true});
    });

    await buildRepository(client).decide('card-1', CardDecision.reject);

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://api.test/cards/card-1/decision');
    expect(jsonDecode(sent.body), {'decision': 'reject'});
  });

  test('수락함 응답이 매칭으로 이어지면 match_id 가 올라온다', () async {
    final client = MockClient((request) async => jsonResponse({'matched': true, 'match_id': 'm-1'}));

    final result = await buildRepository(client).respondToAcceptance('card-1', CardDecision.accept);

    final outcome = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(outcome!.matched, isTrue);
    expect(outcome.matchId, 'm-1');
  });

  test('기한이 지난 수락(410)은 서버 문구를 그대로 보여준다', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({'detail': '기한이 지났어요'}),
          410,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));

    final result = await buildRepository(client).respondToAcceptance('card-1', CardDecision.accept);

    expect(
      result.when(onSuccess: (_) => null, onFailure: (f) => f.toDisplayMessage()),
      '기한이 지났어요',
    );
  });

  test('연결이 끊겨도 예외가 새지 않고 NetworkFailure 로 돌아온다', () async {
    final client = MockClient((request) async => throw Exception('연결 실패'));

    final result = await buildRepository(client).fetchToday();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
  });
}
