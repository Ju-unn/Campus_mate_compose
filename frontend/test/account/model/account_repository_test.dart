import 'dart:convert';

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

void main() {
  late MockGoTrueClient auth;
  late List<http.Request> seen;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    seen = [];
  });

  HttpAccountRepository repositoryReturning(http.Response response) {
    final client = MockClient((request) async {
      seen.add(request);
      return response;
    });
    return HttpAccountRepository(ApiClient('https://api.test', client, auth));
  }

  http.Response json(Object body, [int status = 200, Map<String, String> headers = const {}]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
    );
  }

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
