import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/referral/model/http_referral_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

/// 서버 계약(backend/app/referral/router.py): POST /referral/redeem `{"code"}` → `{"referrer_id"}`,
/// GET /referral/my-code → `{"code"}`.
void main() {
  late MockGoTrueClient auth;
  late List<http.Request> requests;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    requests = [];
  });

  HttpReferralRepository repositoryAnswering(Object body, {int status = 200}) {
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return HttpReferralRepository(ApiClient('https://api.test', client, auth));
  }

  String? valueOf(Result<String> result) => result.when(onSuccess: (value) => value, onFailure: (_) => null);

  test('코드 입력은 POST /referral/redeem 에 code 를 싣고 referrer_id 를 돌려준다', () async {
    final repository = repositoryAnswering({'referrer_id': '22222222-2222-2222-2222-222222222222'});

    final result = await repository.redeem('K7QMX2');

    expect(valueOf(result), '22222222-2222-2222-2222-222222222222');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/referral/redeem');
    expect(jsonDecode(requests.single.body), {'code': 'K7QMX2'});
  });

  test('서버가 409 문구를 주면 그 문구로 실패한다', () async {
    final repository = repositoryAnswering({'detail': '추천 코드는 한 번만 입력할 수 있어요'}, status: 409);

    final result = await repository.redeem('K7QMX2');

    expect(
      result.when(onSuccess: (_) => null, onFailure: (failure) => failure.toDisplayMessage()),
      '추천 코드는 한 번만 입력할 수 있어요',
    );
  });

  test('내 코드는 GET /referral/my-code 의 code 다', () async {
    final repository = repositoryAnswering({'code': 'K7QMX2'});

    final result = await repository.myCode();

    expect(valueOf(result), 'K7QMX2');
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/referral/my-code');
  });
}
