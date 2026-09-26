import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/model/http_home_repository.dart';
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

  HttpHomeRepository buildRepository(http.Client client) =>
      HttpHomeRepository(ApiClient('https://api.test', client, auth));

  http.Response jsonResponse(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  test('GET /home/summary 의 다섯 값을 HomeSummary 로 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/home/summary');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return jsonResponse({
        'delivered_cards': 12,
        'signups': 3,
        'conversations_started': 0,
        'campuses': ['가람대', '새솔대'],
        'profile_completion_percent': 70,
      });
    });

    final result = await buildRepository(client).fetchSummary();

    final summary = result.when<HomeSummary?>(onSuccess: (s) => s, onFailure: (_) => null)!;
    expect(summary.deliveredCards, 12);
    expect(summary.signups, 3);
    expect(summary.conversationsStarted, 0);
    expect(summary.campuses, ['가람대', '새솔대']);
    expect(summary.profileCompletionPercent, 70);
  });

  test('서버에 아직 없는 사람 칸·리뷰 값은 목값으로 채운다(사용자 결정 2026-09-26)', () async {
    final client = MockClient((_) async => jsonResponse({
          'delivered_cards': 0,
          'signups': 0,
          'conversations_started': 0,
          'campuses': <String>[],
          'profile_completion_percent': 0,
        }));

    final result = await buildRepository(client).fetchSummary();

    final summary = result.when<HomeSummary?>(onSuccess: (s) => s, onFailure: (_) => null)!;
    // pen `b9Rask` · `Ch4h6` 과 같은 그림 두 장, review-strip `L7wKi` 의 4.8 · 143.
    expect(summary.presentPeopleImages, ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png']);
    expect(summary.reviewRating, 4.8);
    expect(summary.reviewCount, 143);
  });

  test('서버 오류면 실패를 돌려준다', () async {
    final client = MockClient((_) async => jsonResponse({'detail': 'boom'}, 500));

    final result = await buildRepository(client).fetchSummary();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<Failure>());
  });

  test('약속과 다른 모양이면 실패를 돌려준다', () async {
    final client = MockClient((_) async => jsonResponse({'delivered_cards': '12'}));

    final result = await buildRepository(client).fetchSummary();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
