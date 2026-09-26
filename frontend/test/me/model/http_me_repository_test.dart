import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/me/model/http_me_repository.dart';
import 'package:campus_mate/me/model/my_profile.dart';
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

  HttpMeRepository buildRepository(http.Client client) => HttpMeRepository(ApiClient('https://api.test', client, auth));

  http.Response jsonResponse(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  MyProfile? profileOf(Result<MyProfile> result) => result.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);

  test('GET /me/profile 의 값을 MyProfile 로 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/me/profile');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return jsonResponse({
        'nickname': '여우',
        'age': 23,
        'university': '가나대학교',
        'major': '경영학과',
        'height_cm': 178,
        'mbti': 'ENFP',
        'avatar_url': 'https://img.test/avatar.png',
        'photo_urls': ['https://img.test/1.png', 'https://img.test/2.png'],
        'preferred_age_min': 22,
        'preferred_age_max': 27,
        'preferred_height_min': 165,
        'preferred_height_max': 180,
        'bio': '주말엔 산책해요.',
      });
    });

    final profile = profileOf(await buildRepository(client).fetchProfile())!;

    expect(profile.nickname, '여우');
    expect(profile.age, 23);
    expect(profile.university, '가나대학교');
    expect(profile.major, '경영학과');
    expect(profile.heightCm, 178);
    expect(profile.mbti, 'ENFP');
    expect(profile.avatarUrl, 'https://img.test/avatar.png');
    expect(profile.photoUrls, ['https://img.test/1.png', 'https://img.test/2.png']);
    expect(profile.preferredAgeMin, 22);
    expect(profile.preferredAgeMax, 27);
    expect(profile.preferredHeightMin, 165);
    expect(profile.preferredHeightMax, 180);
    expect(profile.bio, '주말엔 산책해요.');
  });

  test('null 일 수 있는 값이 비어 오면 null 로 읽는다', () async {
    final client = MockClient((_) async => jsonResponse({
          'nickname': '여우',
          'age': null,
          'university': '가나대학교',
          'major': null,
          'height_cm': null,
          'mbti': null,
          'avatar_url': null,
          'photo_urls': <String>[],
          'preferred_age_min': null,
          'preferred_age_max': null,
          'preferred_height_min': null,
          'preferred_height_max': null,
          'bio': null,
        }));

    final profile = profileOf(await buildRepository(client).fetchProfile())!;

    expect(profile.nickname, '여우');
    expect(profile.university, '가나대학교');
    expect(
      [
        profile.age,
        profile.major,
        profile.heightCm,
        profile.mbti,
        profile.avatarUrl,
        profile.preferredAgeMin,
        profile.preferredAgeMax,
        profile.preferredHeightMin,
        profile.preferredHeightMax,
        profile.bio,
      ],
      everyElement(isNull),
    );
    expect(profile.photoUrls, isEmpty);
  });

  test('서버 오류면 실패를 돌려준다', () async {
    final client = MockClient((_) async => jsonResponse({'detail': 'boom'}, 500));

    final result = await buildRepository(client).fetchProfile();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<Failure>());
  });

  test('약속과 다른 모양이면 실패를 돌려준다', () async {
    final client = MockClient((_) async => jsonResponse({'nickname': 3}));

    final result = await buildRepository(client).fetchProfile();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
