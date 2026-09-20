import 'dart:convert';

import 'package:campus_mate/auth/model/http_send.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Request buildRequest() {
    return http.Request('GET', Uri.parse('https://api.test/ping'));
  }

  test('2xx 응답이면 Success 로 response 를 그대로 담는다', () async {
    final client = MockClient((request) async => http.Response('ok', 200));

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (response) => response.body, onFailure: (_) => null), 'ok');
  });

  test('429 면 RateLimitedFailure', () async {
    final client = MockClient((request) async => http.Response('', 429));

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<RateLimitedFailure>());
  });

  test('4xx 에 detail 이 있으면 ServerRejectedFailure 에 서버 메시지를 담는다', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'detail': '이미 검토 중이에요'}),
        409,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final result = await sendHttpRequest(client, buildRequest());

    final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
    expect(failure, isA<ServerRejectedFailure>());
    expect(failure!.toDisplayMessage(), '이미 검토 중이에요');
  });

  test('FastAPI 422 처럼 detail 이 리스트면 앱이 죽지 않고 UnknownFailure', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'detail': [
            {'loc': ['body', 'real_name'], 'msg': 'field required', 'type': 'value_error.missing'},
          ],
        }),
        422,
      );
    });

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });

  test('4xx 에 detail 이 없으면 문구를 새로 짓지 않고 UnknownFailure', () async {
    final client = MockClient((request) async => http.Response(jsonEncode({}), 400));

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });

  test('500 이상이면 서버 내부 사정을 노출하지 않고 UnknownFailure', () async {
    final client = MockClient((request) async => http.Response('<html>502</html>', 502));

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });

  test('네트워크 연결 자체가 실패하면 예외가 새지 않고 NetworkFailure', () async {
    final client = MockClient((request) async => throw Exception('연결 실패'));

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
  });
}
