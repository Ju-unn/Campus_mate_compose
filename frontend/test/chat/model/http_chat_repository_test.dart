import 'dart:convert';

import 'package:campus_mate/chat/model/http_chat_repository.dart';
import 'package:campus_mate/chat/model/message.dart';
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

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpChatRepository buildRepository(http.Client client) {
    return HttpChatRepository(ApiClient('https://api.test', client, auth));
  }

  http.Response jsonResponse(Object body, [int status = 200]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  test('대화 목록을 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.test/chat/conversations');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return jsonResponse({
        'conversations': [
          {
            'match_id': 'm1',
            'partner': {'profile_id': 'p2', 'nickname': '여우비', 'avatar_url': null},
            'last_message': '내일 시간 괜찮으세요?',
            'last_message_kind': 'text',
            'last_message_at': '2026-09-22T14:14:00+09:00',
            'unread_count': 2,
            'trust_passed': false,
            'my_trust_response': null,
            'remaining_seconds': 3600,
          },
        ],
      });
    });

    final result = await buildRepository(client).fetchConversations();

    final conversations = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(conversations!.single.partner.nickname, '여우비');
    expect(conversations.single.unreadCount, 2);
    expect(conversations.single.hasAccepted, isFalse);
  });

  test('첫 페이지에는 커서를 붙이지 않는다', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return jsonResponse({'messages': [], 'has_more': false});
    });

    await buildRepository(client).fetchMessages('m1');

    expect(seen.path, '/chat/matches/m1/messages');
    expect(seen.queryParameters['limit'], '50');
    expect(seen.queryParameters.containsKey('before'), isFalse);
    expect(seen.queryParameters.containsKey('before_id'), isFalse);
  });

  test('더 불러올 때는 시각과 id 를 함께 보낸다', () async {
    late Uri seen;
    final client = MockClient((request) async {
      seen = request.url;
      return jsonResponse({'messages': [], 'has_more': false});
    });

    await buildRepository(client).fetchMessages(
      'm1',
      before: DateTime.utc(2026, 9, 22, 5),
      beforeId: 'msg-9',
    );

    // 시각만 보내면 같은 시각에 들어간 두 줄 중 하나가 페이지 경계에서 빠진다.
    expect(seen.queryParameters['before'], '2026-09-22T05:00:00.000Z');
    expect(seen.queryParameters['before_id'], 'msg-9');
  });

  test('메시지 목록은 오래된 것부터 담아 준다', () async {
    final client = MockClient((request) async {
      // 서버는 최신순으로 준다.
      return jsonResponse({
        'messages': [
          {
            'id': 'm2', 'sender_id': 'p1', 'kind': 'text', 'body': '두 번째',
            'created_at': '2026-09-22T14:20:00+09:00',
          },
          {
            'id': 'm1', 'sender_id': 'p2', 'kind': 'text', 'body': '첫 번째',
            'created_at': '2026-09-22T14:10:00+09:00',
          },
        ],
        'has_more': true,
      });
    });

    final result = await buildRepository(client).fetchMessages('m1');

    final page = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(page!.messages.map((m) => m.body), ['첫 번째', '두 번째']);
    expect(page.hasMore, isTrue);
  });

  test('모르는 종류의 줄은 건너뛰고 나머지를 보여준다', () async {
    final client = MockClient((request) async {
      return jsonResponse({
        'messages': [
          {
            'id': 'm2', 'sender_id': 'p1', 'kind': 'sticker', 'body': '??',
            'created_at': '2026-09-22T14:20:00+09:00',
          },
          {
            'id': 'm1', 'sender_id': 'p2', 'kind': 'text', 'body': '안녕하세요',
            'created_at': '2026-09-22T14:10:00+09:00',
          },
        ],
        'has_more': false,
      });
    });

    final result = await buildRepository(client).fetchMessages('m1');

    // 한 줄 때문에 대화 전체가 안 보이면 그게 더 큰 사고다.
    final page = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(page!.messages.map((m) => m.body), ['안녕하세요']);
  });

  test('보낸 줄을 그대로 돌려받는다', () async {
    late String body;
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.test/chat/matches/m1/messages');
      body = request.body;
      return jsonResponse({
        'message': {
          'id': 'm9', 'sender_id': 'p1', 'kind': 'text', 'body': '안녕하세요',
          'created_at': '2026-09-22T14:30:00+09:00',
        },
      }, 201);
    });

    final result = await buildRepository(client).sendMessage('m1', '안녕하세요');

    expect(jsonDecode(body), {'body': '안녕하세요'});
    expect(result.when(onSuccess: (m) => m?.kind, onFailure: (_) => null), MessageKind.text);
  });

  test('신뢰 확인 수락은 바디 없이 보낸다', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return jsonResponse({'passed': true, 'kakao_id': 'fox_rain'});
    });

    final result = await buildRepository(client).acceptTrust('m1');

    // 결정 11 로 고를 것이 없어졌다 — 바디가 붙으면 그 자체가 설계 착오다.
    expect(seen.body, isEmpty);
    expect(result.when(onSuccess: (o) => o.kakaoId, onFailure: (_) => null), 'fox_rain');
  });

  test('409 는 서버가 준 문구를 그대로 실어 온다', () async {
    final client = MockClient((request) async => jsonResponse({'detail': '이미 나간 대화예요'}, 409));

    final result = await buildRepository(client).leave('m1');

    final failure = result.when(onSuccess: (_) => null, onFailure: (value) => value);
    expect(failure, isA<ServerRejectedFailure>());
    expect(failure!.toDisplayMessage(), '이미 나간 대화예요');
  });

  test('통과 전에는 방 응답에 카카오톡 아이디가 없다', () async {
    final client = MockClient((request) async {
      return jsonResponse({
        'match_id': 'm1',
        'created_at': '2026-09-22T10:00:00+09:00',
        'chat_closed_at': null,
        'my_last_read_at': null,
        'partner': {'profile_id': 'p2', 'nickname': '여우비', 'avatar_url': null},
        'gate': {
          'my_response': null,
          'passed': false,
          'partner_left': false,
          'deadline_at': '2026-09-24T10:00:00+09:00',
          'remaining_seconds': 172800,
        },
      });
    });

    final result = await buildRepository(client).fetchRoom('m1');

    final room = result.when(onSuccess: (value) => value, onFailure: (_) => null);
    expect(room!.kakaoId, isNull);
    expect(room.photoUrls, isEmpty);
    expect(room.gate.accepted, isFalse);
  });
}
