import 'dart:convert';

import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/http_card_repository.dart';
import 'package:flutter/foundation.dart';
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
    return HttpCardRepository(ApiClient('https://api.test', client, auth));
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
    // `+09:00` 을 그대로 두면 UTC DateTime 이라 화면이 7시를 22시로 읽는다 — 기기 시간대로 온다.
    expect(today.nextIssueAt, DateTime.parse('2026-09-24T07:00:00+09:00').toLocal());
    expect(today.nextIssueAt!.isUtc, isFalse);
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

  test('아이폰에서 등록한 토큰은 ios 로 보낸다', () async {
    // 'android' 가 박혀 있으면 device_platform enum 의 ios 가 영영 쓰이지 않는다.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse({'ok': true});
    });

    await buildRepository(client).registerPushToken('tok-1');

    expect(sent['platform'], 'ios');
  });

  test('안드로이드·아이폰이 아니면 토큰을 아예 보내지 않는다', () async {
    // 예전에는 웹·데스크톱이 전부 android 로 떨어졌다(조각 4 리뷰 권고 5번).
    // device_platform enum 에 없는 값을 보내느니 요청 자체를 하지 않는다.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return jsonResponse({'ok': true});
    });

    final result = await buildRepository(client).registerPushToken('tok-1');

    expect(called, isFalse);
    // 보낼 것이 없을 뿐 실패한 것은 아니다.
    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });

  test('학생증·프로필 사진은 같은 multipart 통로를 쓴다', () async {
    // 권고 4번: Authorization 을 저장소가 각자 달던 것을 ApiClient 로 모았다.
    late http.BaseRequest seen;
    final client = MockClient((request) async {
      seen = request;
      return jsonResponse({'ok': true});
    });

    await ApiClient('https://api.test', client, auth)
        .sendMultipart('/profile-onboarding/photos', {'position': '0'}, 'pubspec.yaml');

    expect(seen.headers['Authorization'], 'Bearer token-abc');
    expect(seen.url.toString(), 'https://api.test/profile-onboarding/photos');
  });
}
