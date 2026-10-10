import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/notifications/model/app_notification.dart';
import 'package:campus_mate/notifications/model/http_notifications_repository.dart';
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

  HttpNotificationsRepository build(http.Client client) =>
      HttpNotificationsRepository(ApiClient('https://api.test', client, auth));

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> item(String id, {String kind = 'card_arrived', bool read = false, Object? data}) => {
        'id': id,
        'kind': kind,
        'title': '제목 $id',
        'body': '본문 $id',
        'data': data ?? {'route': 'daily_card'},
        'created_at': '2026-10-10T09:00:00+09:00',
        'read': read,
      };

  NotificationsPage pageOf(Result<NotificationsPage> result) => result.when<NotificationsPage?>(onSuccess: (p) => p, onFailure: (_) => null)!;

  group('GET /notifications', () {
    test('첫 쪽은 limit 만 보내고 items · unread_count · next_before 를 읽는다', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/notifications');
        expect(request.url.queryParameters, {'limit': '30'});
        expect(request.headers['Authorization'], 'Bearer token-abc');
        return json({
          'items': [item('a'), item('b', kind: 'match_made', read: true)],
          'unread_count': 4,
          'next_before': '2026-10-09T09:00:00+09:00',
        });
      });

      final page = pageOf(await build(client).fetchPage());

      expect(page.items.map((n) => n.id), ['a', 'b']);
      expect(page.items[1].kind, NotificationKind.matchMade);
      expect(page.items[1].read, isTrue);
      expect(page.items[0].title, '제목 a');
      expect(page.items[0].body, '본문 a');
      expect(page.items[0].data['route'], 'daily_card');
      expect(page.unreadCount, 4);
      expect(page.nextBefore, '2026-10-09T09:00:00+09:00');
    });

    test('before 를 주면 그대로 쿼리에 싣는다(+ 는 %2B 로 인코딩된다)', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['before'], '2026-10-09T09:00:00+09:00');
        expect(request.url.query, contains('%2B09%3A00'));
        return json({'items': <Object>[], 'unread_count': 0, 'next_before': null});
      });

      final page = pageOf(await build(client).fetchPage(limit: 30, before: '2026-10-09T09:00:00+09:00'));

      expect(page.items, isEmpty);
      expect(page.nextBefore, isNull);
    });

    test('created_at 은 시각 그대로(기기 시간대 DateTime) 읽는다', () async {
      final client = MockClient((_) async => json({'items': [item('a')], 'unread_count': 1, 'next_before': null}));

      final page = pageOf(await build(client).fetchPage());

      expect(page.items.single.createdAt.toUtc(), DateTime.utc(2026, 10, 10));
    });

    test('모르는 kind 는 other 로, data 가 비어도 빈 맵으로 읽는다', () async {
      final client = MockClient((_) async => json({
            'items': [
              {...item('a', kind: 'something_new'), 'data': null},
            ],
            'unread_count': 0,
            'next_before': null,
          }));

      final n = pageOf(await build(client).fetchPage()).items.single;

      expect(n.kind, NotificationKind.other);
      expect(n.data, isEmpty);
    });

    test('서버가 실패하면 Failure 로 돌려준다', () async {
      final client = MockClient((_) async => http.Response('', 500));

      final result = await build(client).fetchPage();

      expect(result.when<bool>(onSuccess: (_) => false, onFailure: (_) => true), isTrue);
    });
  });

  test('GET /notifications/unread-count 는 unread_count 를 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/notifications/unread-count');
      return json({'unread_count': 7});
    });

    final result = await build(client).fetchUnreadCount();

    expect(result.when<int>(onSuccess: (n) => n, onFailure: (_) => -1), 7);
  });

  test('POST /notifications/{id}/read', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/notifications/n-1/read');
      return json({});
    });

    final result = await build(client).markRead('n-1');

    expect(result.when<bool>(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });

  test('POST /notifications/read-all', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/notifications/read-all');
      return json({});
    });

    final result = await build(client).markAllRead();

    expect(result.when<bool>(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });
}
