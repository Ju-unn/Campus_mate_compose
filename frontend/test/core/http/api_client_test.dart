import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/analytics/handled_api_error.dart';
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

  group('앱이 버틴 오류 알림(오류 수집)', () {
    test('send · sendRequest 가 지나는 5xx · 연결 실패를 onHandledError 로 알린다', () async {
      final handled = <HandledApiError>[];
      final api = ApiClient(
        'https://api.test',
        MockClient((request) async => request.url.path == '/b' ? throw http.ClientException('끊김') : http.Response('', 500)),
        auth,
        onHandledError: handled.add,
      );

      await api.send('GET', '/cards/3f2a9c1e-7b4d-4e8a-9c21-5d6e7f8a9b0c/accept', (_) {});
      await api.sendRequest((token) => http.Request('GET', api.uri('/b')));

      expect(handled.map((e) => e.toString()), [
        'HandledApiError(kind: ServerError, status: 500, route: /cards/:id/accept)',
        'HandledApiError(kind: ClientException, status: -, route: /b)',
      ]);
    });

    test('4xx 와 성공은 알리지 않는다', () async {
      final handled = <HandledApiError>[];
      final statuses = [200, 404, 422];
      final api = ApiClient(
        'https://api.test',
        MockClient((request) async => http.Response('{"detail":"x"}', statuses.removeAt(0))),
        auth,
        onHandledError: handled.add,
      );

      for (var i = 0; i < 3; i++) {
        await api.send('GET', '/a', (_) {});
      }

      expect(handled, isEmpty);
    });
  });

  test('onFailure 가 없어도 실패를 그대로 돌려준다', () async {
    final api = ApiClient('https://api.test', MockClient((request) async => http.Response('', 500)), auth);

    final result = await api.send('GET', '/a', (_) {});

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
