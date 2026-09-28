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
  late List<Failure> observed;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    observed = [];
  });

  ApiClient build(http.Client client) {
    return ApiClient('https://api.test', client, auth, onFailure: observed.add);
  }

  test('every failed request is handed to onFailure', () async {
    // send · sendRequest · sendMultipart 가 모두 sendRequest 한 곳을 지난다 — 둘로 확인한다.
    final api = build(MockClient((request) async => http.Response('', 500)));

    await api.send('GET', '/a', (_) {});
    await api.sendRequest((token) => http.Request('GET', api.uri('/b')));

    expect(observed, hasLength(2));
    expect(observed, everyElement(isA<UnknownFailure>()));
  });

  test('세션이 없어 보내지 못한 실패도 넘긴다', () async {
    when(() => auth.currentSession).thenReturn(null);
    final api = build(MockClient((request) async => http.Response('{}', 200)));

    await api.send('GET', '/a', (_) {});

    expect(observed.single, isA<SessionExpiredFailure>());
  });

  test('성공한 요청은 넘기지 않는다', () async {
    final api = build(MockClient((request) async => http.Response('{}', 200)));

    await api.send('GET', '/a', (_) {});

    expect(observed, isEmpty);
  });

  test('onFailure 가 없어도 실패를 그대로 돌려준다', () async {
    final api = ApiClient('https://api.test', MockClient((request) async => http.Response('', 500)), auth);

    final result = await api.send('GET', '/a', (_) {});

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
