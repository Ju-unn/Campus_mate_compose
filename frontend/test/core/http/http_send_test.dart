import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

class MockUser extends Mock implements User {}

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

  // POST /school-email/verify 409 — 문구가 아니라 기계용 `provider` 로 가른다(backend school_email/router.py).
  test('409 에 provider 가 있으면 SchoolEmailTakenFailure 로 수단을 담는다', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'detail': '이 메일은 구글로 가입돼 있어요', 'provider': 'google'}),
        409,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final result = await sendHttpRequest(client, buildRequest());

    final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
    expect(failure, isA<SchoolEmailTakenFailure>());
    expect(failure!.toDisplayMessage(), '이 메일은 구글로 가입돼 있어요');
    expect((failure as SchoolEmailTakenFailure).toHintMessage(), '구글 계정으로 로그인해 주세요');
  });

  test('409 가 아니면 provider 칸이 있어도 ServerRejectedFailure 그대로', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'detail': '거절', 'provider': 'kakao'}),
        403,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<ServerRejectedFailure>());
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

  test('502·503 은 서버가 잠깐 못 받는 것이라 다시 시도하라는 ServerUnavailableFailure', () async {
    for (final status in [502, 503]) {
      final client = MockClient((request) async => http.Response('<html>$status</html>', status));

      final result = await sendHttpRequest(client, buildRequest());

      expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<ServerUnavailableFailure>());
    }
  });

  test('그 밖의 5xx 는 서버 내부 사정을 노출하지 않고 UnknownFailure', () async {
    final client = MockClient((request) async => http.Response('<html>500</html>', 500));

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });

  group('계정 상태 헤더(X-Account-Status, 조각 6 A4)', () {
    http.Response rejected(int status, String detail, {String? accountStatus}) {
      return http.Response(
        jsonEncode({'detail': detail}),
        status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'x-account-status': ?accountStatus,
        },
      );
    }

    test('403 with X-Account-Status suspended → SuspendedFailure', () async {
      final client = MockClient((request) async => rejected(403, '이용이 제한된 계정이에요', accountStatus: 'suspended'));

      final result = await sendHttpRequest(client, buildRequest());

      final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
      expect(failure, isA<SuspendedFailure>());
      expect(failure!.toDisplayMessage(), '이용이 제한된 계정이에요');
    });

    test('401 with X-Account-Status withdrawn → WithdrawnFailure', () async {
      final client = MockClient((request) async => rejected(401, '탈퇴한 계정이에요', accountStatus: 'withdrawn'));

      final result = await sendHttpRequest(client, buildRequest());

      final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
      expect(failure, isA<WithdrawnFailure>());
      expect(failure!.toDisplayMessage(), '탈퇴한 계정이에요');
    });

    test('401 without the header → SessionRejectedFailure (A11)', () async {
      // 서버가 이 로그인을 받지 않는다(계정 삭제 · 세션 끊김 · 토큰 만료). 문구는 서버 401 과 같다.
      final client = MockClient((request) async => rejected(401, '세션이 만료됐어요, 다시 로그인해 주세요'));

      final result = await sendHttpRequest(client, buildRequest());

      final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
      expect(failure, isA<SessionRejectedFailure>());
      expect(failure!.toDisplayMessage(), '세션이 만료됐어요, 다시 로그인해 주세요');
    });

    test('403 without the header keeps ServerRejectedFailure(detail)', () async {
      // 학생증·학과 관문도 403 이다(Ruling 8) — 헤더가 없으면 정지로 읽지 않는다.
      final client = MockClient((request) async => rejected(403, '학생 인증을 먼저 마쳐 주세요'));

      final result = await sendHttpRequest(client, buildRequest());

      final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
      expect(failure, isA<ServerRejectedFailure>());
      expect(failure!.toDisplayMessage(), '학생 인증을 먼저 마쳐 주세요');
    });

    test('모르는 헤더 값은 계정 상태로 읽지 않는다', () async {
      final client = MockClient((request) async => rejected(403, '거절', accountStatus: 'paused'));

      final result = await sendHttpRequest(client, buildRequest());

      expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<ServerRejectedFailure>());
    });
  });

  test('네트워크 연결 자체가 실패하면 예외가 새지 않고 NetworkFailure', () async {
    final client = MockClient((request) async => throw Exception('연결 실패'));

    final result = await sendHttpRequest(client, buildRequest());

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<NetworkFailure>());
  });

  test('세션이 있으면 토큰을 붙여 보낸다', () async {
    final auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    String? sentHeader;
    final client = MockClient((request) async {
      sentHeader = request.headers['Authorization'];
      return http.Response('ok', 200);
    });

    final result = await sendAuthorizedRequest(
      client,
      auth,
      (accessToken) => buildRequest()..headers['Authorization'] = 'Bearer $accessToken',
    );

    expect(sentHeader, 'Bearer token-abc');
    expect(result.when(onSuccess: (response) => response.body, onFailure: (_) => null), 'ok');
  });

  test('세션이 없으면 요청을 만들지도 않고 SessionExpiredFailure', () async {
    final auth = MockGoTrueClient();
    when(() => auth.currentSession).thenReturn(null);
    var built = false;
    final client = MockClient((request) async => http.Response('ok', 200));

    final result = await sendAuthorizedRequest(client, auth, (accessToken) {
      built = true;
      return buildRequest();
    });

    expect(built, isFalse);
    final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
    expect(failure, isA<SessionExpiredFailure>());
    // 원래 로그인 상태가 아니다 — 로그인 화면으로 보내는 신호(SessionRejectedFailure)가 아니다.
    expect(failure, isNot(isA<SessionRejectedFailure>()));
  });

  group('서버 401 이면 토큰을 새로 받아 한 번만 다시 보낸다(A11 · E-EDGE-09)', () {
    late MockGoTrueClient auth;
    late List<String?> sentTokens;

    Session sessionWith(String token) {
      final session = MockSession();
      when(() => session.accessToken).thenReturn(token);
      when(() => session.user).thenReturn(MockUser());
      return session;
    }

    http.Response unauthorized() => http.Response(
      jsonEncode({'detail': '세션이 만료됐어요, 다시 로그인해 주세요'}),
      401,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    Future<Failure?> send(http.Response Function(String? token) respond) async {
      final client = MockClient((request) async {
        final token = request.headers['Authorization'];
        sentTokens.add(token);
        return respond(token);
      });
      final result = await sendAuthorizedRequest(
        client,
        auth,
        (accessToken) => buildRequest()..headers['Authorization'] = 'Bearer $accessToken',
      );
      return result.when(onSuccess: (_) => null, onFailure: (f) => f);
    }

    setUp(() {
      auth = MockGoTrueClient();
      sentTokens = [];
      final old = sessionWith('old');
      when(() => auth.currentSession).thenReturn(old);
    });

    test('들고 있던 토큰만 만료였다면 새 토큰으로 다시 보내 성공한다', () async {
      final fresh = sessionWith('new');
      when(() => auth.refreshSession()).thenAnswer((_) async => AuthResponse(session: fresh));

      final failure = await send((token) => token == 'Bearer new' ? http.Response('ok', 200) : unauthorized());

      expect(failure, isNull);
      expect(sentTokens, ['Bearer old', 'Bearer new']);
    });

    test('토큰을 새로 받지 못하면 SessionRejectedFailure, 다시 보내지 않는다', () async {
      when(() => auth.refreshSession()).thenThrow(const AuthException('Invalid Refresh Token'));

      final failure = await send((_) => unauthorized());

      expect(failure, isA<SessionRejectedFailure>());
      expect(sentTokens, ['Bearer old']);
    });

    test('새 토큰으로도 401 이면 SessionRejectedFailure, 갱신은 한 번뿐', () async {
      final fresh = sessionWith('new');
      when(() => auth.refreshSession()).thenAnswer((_) async => AuthResponse(session: fresh));

      final failure = await send((_) => unauthorized());

      expect(failure, isA<SessionRejectedFailure>());
      expect(sentTokens, ['Bearer old', 'Bearer new']);
      verify(() => auth.refreshSession()).called(1);
    });

    test('갱신이 네트워크로 실패하면 로그아웃 신호가 아니라 NetworkFailure', () async {
      when(() => auth.refreshSession()).thenThrow(AuthRetryableFetchException());

      final failure = await send((_) => unauthorized());

      expect(failure, isA<NetworkFailure>());
    });

    test('401 이 아니면 갱신하지 않는다', () async {
      final failure = await send(
        (_) => http.Response(
          jsonEncode({'detail': '학생 인증을 먼저 마쳐 주세요'}),
          403,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );

      expect(failure, isA<ServerRejectedFailure>());
      verifyNever(() => auth.refreshSession());
    });
  });
}
