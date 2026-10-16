import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/home/model/home_people.dart';
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

  test('리뷰 띠 값은 서버의 실제 스토어 평점 · 평가 수(store_rating · store_rating_count)를 그대로 읽는다', () async {
    final client = MockClient((_) async => jsonResponse({
          'delivered_cards': 0,
          'signups': 0,
          'conversations_started': 0,
          'campuses': <String>[],
          'profile_completion_percent': 0,
          'store_rating': 4.3,
          'store_rating_count': 27,
        }));

    final result = await buildRepository(client).fetchSummary();

    final summary = result.when<HomeSummary?>(onSuccess: (s) => s, onFailure: (_) => null)!;
    expect(summary.reviewRating, 4.3);
    expect(summary.reviewCount, 27);
  });

  test('평점이 정수 JSON(5)이어도 소수로 읽는다', () async {
    final client = MockClient((_) async => jsonResponse({
          'delivered_cards': 0,
          'signups': 0,
          'conversations_started': 0,
          'campuses': <String>[],
          'profile_completion_percent': 0,
          'store_rating': 5,
          'store_rating_count': 1,
        }));

    final result = await buildRepository(client).fetchSummary();

    final summary = result.when<HomeSummary?>(onSuccess: (s) => s, onFailure: (_) => null)!;
    expect(summary.reviewRating, 5.0);
    expect(summary.reviewCount, 1);
  });

  test('옛 서버(리뷰 칸 없음)면 0 · 0 이다 — 지어낸 값을 채우지 않고, 화면은 띠를 숨긴다', () async {
    final client = MockClient((_) async => jsonResponse({
          'delivered_cards': 0,
          'signups': 0,
          'conversations_started': 0,
          'campuses': <String>[],
          'profile_completion_percent': 0,
        }));

    final result = await buildRepository(client).fetchSummary();

    final summary = result.when<HomeSummary?>(onSuccess: (s) => s, onFailure: (_) => null)!;
    expect(summary.reviewRating, 0);
    expect(summary.reviewCount, 0);
  });

  test('cohort 가 null 이면 대기 없음이다(이미 열린 학교)', () async {
    final client = MockClient((_) async => jsonResponse({
          'delivered_cards': 0,
          'signups': 0,
          'conversations_started': 0,
          'campuses': <String>[],
          'profile_completion_percent': 60,
          'cohort': null,
        }));

    final result = await buildRepository(client).fetchSummary();

    final summary = result.when<HomeSummary?>(onSuccess: (s) => s, onFailure: (_) => null)!;
    expect(summary.cohort, isNull);
  });

  test('cohort 가 있으면 첫 카드 시각(기기 시간대)과 모집 인원을 읽는다', () async {
    final client = MockClient((_) async => jsonResponse({
          'delivered_cards': 0,
          'signups': 0,
          'conversations_started': 0,
          'campuses': <String>[],
          'profile_completion_percent': 60,
          // 서울 월요일 07:00 = UTC 일요일 22:00. PostgREST 는 +00:00 으로 준다.
          'cohort': {'first_card_at': '2099-01-04T22:00:00+00:00', 'recruit_count': 87},
        }));

    final result = await buildRepository(client).fetchSummary();

    final cohort = result.when<HomeSummary?>(onSuccess: (s) => s, onFailure: (_) => null)!.cohort!;
    expect(cohort.firstCardAt.toUtc(), DateTime.utc(2099, 1, 4, 22));
    expect(cohort.firstCardAt.isUtc, isFalse, reason: '화면은 기기 시간대의 달력 날짜로 D-숫자를 센다');
    expect(cohort.recruitCount, 87);
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

  group('GET /home/people — 레일 사람 칸(요약과 따로 읽는다)', () {
    test('서버가 흐린 그림 base64 목록을 주면 풀어서 돌려준다', () async {
      final image = [0xFF, 0xD8, 0xFF, 0xE0];
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://api.test/home/people');
        expect(request.headers['Authorization'], 'Bearer token-abc');
        return jsonResponse({
          'people': [base64Encode(image)],
        });
      });

      final result = await buildRepository(client).fetchPeople();

      final people = result.when<HomePeople?>(onSuccess: (p) => p, onFailure: (_) => null)!;
      expect(people.map((bytes) => bytes.toList()), [image]);
    });

    test('후보가 모자라 빈 목록이면 비어 있는 성공이다', () async {
      final client = MockClient((_) async => jsonResponse({'people': <String>[]}));

      final result = await buildRepository(client).fetchPeople();

      expect(result.when(onSuccess: (p) => p.isEmpty, onFailure: (_) => null), isTrue);
    });

    test('서버 오류면 실패를 돌려준다', () async {
      final client = MockClient((_) async => jsonResponse({'detail': 'boom'}, 500));

      final result = await buildRepository(client).fetchPeople();

      expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<Failure>());
    });

    test('약속과 다른 모양이면 실패를 돌려준다', () async {
      final client = MockClient((_) async => jsonResponse({'people': 'oops'}));

      final result = await buildRepository(client).fetchPeople();

      expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
    });
  });
}
