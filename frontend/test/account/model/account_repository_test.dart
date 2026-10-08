import 'dart:convert';

import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

class MockUser extends Mock implements User {}

void main() {
  late MockGoTrueClient auth;
  late List<http.Request> seen;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    final user = MockUser();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    when(() => user.appMetadata).thenReturn({'provider': 'kakao'});
    when(() => auth.currentUser).thenReturn(user);
    seen = [];
  });

  HttpAccountRepository repositoryReturning(http.Response response) {
    final client = MockClient((request) async {
      seen.add(request);
      return response;
    });
    return HttpAccountRepository(ApiClient('https://api.test', client, auth), auth);
  }

  http.Response json(Object body, [int status = 200, Map<String, String> headers = const {}]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
    );
  }

  test('GET /account 값과 세션의 로그인 수단을 AccountInfo 로 읽는다', () async {
    final result = await repositoryReturning(json({
      'real_name': '홍길동', 'birth_year': 2003, 'university': '서울대학교',
      'joined_at': '2026-09-01T10:00:00+00:00', 'kakao_id': 'fox_rain',
    })).fetchAccount();
    final info = result.when<AccountInfo?>(onSuccess: (i) => i, onFailure: (_) => null)!;

    expect(seen.single.method, 'GET');
    expect(seen.single.url.toString(), 'https://api.test/account');
    expect(info.loginProvider, 'kakao');
    expect(info.realName, '홍길동');
    expect(info.birthYear, 2003);
    expect(info.university, '서울대학교');
    expect(info.joinedAt, DateTime.utc(2026, 9, 1, 10));
    expect(info.kakaoId, 'fox_rain');
  });

  // 소셜 로그인 뒤 user.email 은 개인 메일이거나(구글) 비어 있다(카카오) — 16e 는 이메일을 보이지 않는다(지시문 13 A-7).
  test('로그인 수단을 못 읽으면 null', () async {
    final user = MockUser();
    when(() => user.appMetadata).thenReturn(<String, dynamic>{});
    when(() => auth.currentUser).thenReturn(user);

    final result = await repositoryReturning(json({
      'real_name': null, 'birth_year': null, 'university': '서울대학교',
      'joined_at': '2026-09-01T10:00:00+00:00', 'kakao_id': null,
    })).fetchAccount();

    expect(result.when<AccountInfo?>(onSuccess: (i) => i, onFailure: (_) => null)!.loginProvider, isNull);
  });

  test('빈 칸은 null 로 받는다', () async {
    final result = await repositoryReturning(json({
      'real_name': null, 'birth_year': null, 'university': '서울대학교',
      'joined_at': '2026-09-01T10:00:00+00:00', 'kakao_id': null,
    })).fetchAccount();
    final info = result.when<AccountInfo?>(onSuccess: (i) => i, onFailure: (_) => null)!;

    expect(info.realName, isNull);
    expect(info.birthYear, isNull);
    expect(info.kakaoId, isNull);
  });

  test('502 는 Failure 로 돌려준다', () async {
    final result = await repositoryReturning(json({'detail': 'bad gateway'}, 502)).fetchAccount();

    expect(result.when<Failure?>(onSuccess: (_) => null, onFailure: (f) => f), isA<ServerUnavailableFailure>());
  });

  test('탈퇴는 POST /account/withdraw 이고 {ok:true} 면 성공이다', () async {
    final result = await repositoryReturning(json({'ok': true})).withdraw();

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/account/withdraw');
    expect(seen.single.headers['Authorization'], 'Bearer token-abc');
    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });

  test('이미 탈퇴한 계정이면 WithdrawnFailure 를 그대로 돌려준다(성공 판단은 ViewModel 몫)', () async {
    final result = await repositoryReturning(
      json({'detail': '탈퇴한 계정이에요'}, 401, {'x-account-status': 'withdrawn'}),
    ).withdraw();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<WithdrawnFailure>());
  });

  test('카카오톡 아이디는 GET /account/kakao-id 의 kakao_id 다', () async {
    final result = await repositoryReturning(json({'kakao_id': 'hong_gildong'})).fetchKakaoId();

    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/account/kakao-id');
    expect(result.when(onSuccess: (id) => id, onFailure: (_) => 'failed'), 'hong_gildong');
  });

  test('저장된 아이디가 없으면 null 이다', () async {
    final result = await repositoryReturning(json({'kakao_id': null})).fetchKakaoId();

    expect(result.when(onSuccess: (id) => id, onFailure: (_) => 'failed'), isNull);
  });

  test('실패는 그대로 돌려준다', () async {
    final result = await repositoryReturning(http.Response('', 500)).fetchKakaoId();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
