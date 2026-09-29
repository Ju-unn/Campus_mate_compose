import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:campus_mate/consent/model/http_consent_repository.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

/// 서버 계약(backend/app/consents/router.py): POST /me/consents `{"agreed": [...], "marketing": bool}` → `{"ok": true}`.
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

  HttpConsentRepository repositoryAnswering(Object body, {int status = 200}) {
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    return HttpConsentRepository(ApiClient('https://api.test', client, auth));
  }

  test('필수 항목의 전선 이름과 마케팅 여부를 따로 싣는다', () async {
    final repository = repositoryAnswering({'ok': true});

    final result = await repository.submit(agreed: ConsentItem.values.toSet());

    expect(result, isA<Success<void>>());
    expect(requests.single.method, 'POST');
    expect(requests.single.url.toString(), 'https://api.test/me/consents');
    expect(jsonDecode(requests.single.body), {
      'agreed': ['terms', 'privacy', 'sensitive_religion', 'overseas_transfer'],
      'marketing': true,
    });
  });

  test('마케팅을 안 켰으면 marketing 은 false 다', () async {
    final repository = repositoryAnswering({'ok': true});

    await repository.submit(agreed: {...ConsentItem.values}..remove(ConsentItem.marketing));

    expect((jsonDecode(requests.single.body) as Map)['marketing'], isFalse);
  });

  test('서버가 거절하면 실패로 돌려준다', () async {
    final repository = repositoryAnswering({'detail': '필수 항목에 모두 동의해 주세요'}, status: 400);

    final result = await repository.submit(agreed: {ConsentItem.terms});

    expect(result.when(onSuccess: (_) => null, onFailure: (failure) => failure), isA<Failure>());
  });
}
