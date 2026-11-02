import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/core/app_update/app_version.dart';
import 'package:campus_mate/core/app_update/app_version_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AppVersionRepository repositoryAnswering(http.Response Function(http.Request request) answer) {
  return AppVersionRepository('https://api.test', MockClient((request) async => answer(request)));
}

http.Response json(Object? body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('로그인 전에도 부르므로 인증 헤더 없이 GET /app/version 을 보낸다', () async {
    late http.Request sent;
    final repository = repositoryAnswering((request) {
      sent = request;
      return json({'min_version': '1.0.1'});
    });

    await repository.fetchMinimum();

    expect(sent.method, 'GET');
    expect(sent.url.toString(), 'https://api.test/app/version');
    expect(sent.headers.containsKey('Authorization'), isFalse);
  });

  test('200 이고 최소 버전이 있으면 그 버전을 준다', () async {
    final repository = repositoryAnswering((_) => json({'min_version': '1.0.1'}));

    expect(await repository.fetchMinimum(), AppVersion.tryParse('1.0.1'));
  });

  test('최소 버전이 null 이면 null — 아무도 막지 않는다', () async {
    final repository = repositoryAnswering((_) => json({'min_version': null}));

    expect(await repository.fetchMinimum(), isNull);
  });

  test('서버가 오류(500) 로 답하면 null — 장애 때 앱이 잠기지 않게', () async {
    final repository = repositoryAnswering((_) => http.Response('boom', 500));

    expect(await repository.fetchMinimum(), isNull);
  });

  test('404 처럼 이 경로를 모르는 서버(옛 서버)여도 null', () async {
    final repository = repositoryAnswering((_) => http.Response('{"detail":"Not Found"}', 404));

    expect(await repository.fetchMinimum(), isNull);
  });

  test('연결이 안 되면 null', () async {
    final repository = AppVersionRepository(
      'https://api.test',
      MockClient((_) async => throw http.ClientException('offline')),
    );

    expect(await repository.fetchMinimum(), isNull);
  });

  test('이상한 응답은 모두 null — 모양이 달라도 앱이 죽지 않는다', () async {
    final strange = <http.Response>[
      http.Response('', 200),
      http.Response('<html>gateway</html>', 200),
      json(<Object?>[]),
      json('1.0.1'),
      json(<String, Object?>{}),
      json({'min_version': 5}),
      json({'min_version': 'banana'}),
      json({'min_version': '1.0'}),
      json({'min_version': ''}),
    ];
    for (final response in strange) {
      final repository = repositoryAnswering((_) => response);

      expect(await repository.fetchMinimum(), isNull, reason: response.body);
    }
  });

  // testWidgets 의 가짜 시계로 3초를 건너뛴다(fake_async 를 따로 들이지 않는다).
  testWidgets('3초 안에 답이 없으면 null — 기다리다 앱이 멈추지 않게', (tester) async {
    final repository = AppVersionRepository(
      'https://api.test',
      MockClient((_) => Completer<http.Response>().future),
    );
    AppVersion? result = AppVersion.tryParse('9.9.9');
    var finished = false;
    unawaited(repository.fetchMinimum().then((value) {
      result = value;
      finished = true;
    }));

    await tester.pump(const Duration(milliseconds: 2900));
    expect(finished, isFalse, reason: '3초가 되기 전에는 기다린다');
    await tester.pump(const Duration(milliseconds: 200));

    expect(finished, isTrue);
    expect(result, isNull);
  });
}
