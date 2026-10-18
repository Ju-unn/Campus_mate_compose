import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;

  AdminApi apiWith(http.Response Function(http.Request) respond, {String? token = 'tok'}) {
    requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
    return AdminApi('https://api.test/', client, () => token);
  }

  http.Response json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  test('로그인 토큰을 Bearer 로 달고 JSON 으로 주고받는다', () async {
    final api = apiWith((_) => json(200, {'nickname': '운영자'}));

    final response = await api.send('POST', '/admin/x', body: {'reason': '확인'});

    final request = requests.single;
    expect(request.url.toString(), 'https://api.test/admin/x');
    expect(request.headers['Authorization'], 'Bearer tok');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(request.body), {'reason': '확인'});
    expect(response.isSuccess, isTrue);
    expect(response.body, {'nickname': '운영자'});
  });

  test('me 는 GET /admin/me 를 부른다', () async {
    final api = apiWith((_) => json(200, {}));

    await api.me();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/admin/me');
  });

  test('403 본문의 detail 문자열을 이유로 읽는다(D0 확정 모양)', () async {
    final api = apiWith((_) => json(403, {'detail': AdminReason.notAdmin}));

    final response = await api.me();

    expect(response.statusCode, 403);
    expect(response.reason, AdminReason.notAdmin);
    expect(response.isSuccess, isFalse);
  });

  test('JSON 이 아닌 본문(게이트웨이 오류 페이지)도 예외 없이 상태코드만 돌려준다', () async {
    final api = apiWith((_) => http.Response('<html>bad gateway</html>', 502));

    final response = await api.me();

    expect(response.statusCode, 502);
    expect(response.body, isNull);
    expect(response.reason, isNull);
  });

  test('연결이 안 되면 상태코드 없이 돌려준다', () async {
    final api = apiWith((_) => throw http.ClientException('offline'));

    final response = await api.me();

    expect(response.statusCode, isNull);
    expect(response.isSuccess, isFalse);
  });

  group('인증샷 검수', () {
    Map<String, Object?> row(String id, [String task = 'everytime_post']) => {
      'id': id,
      'task': task,
      'status': 'submitted',
      'reject_reason': null,
      'reward_hearts': 40,
      'created_at': '2026-10-18T05:08:00+00:00',
      'reviewed_at': null,
      'profile': {'id': 'p', 'nickname': '하늘', 'university': '테스트대학교'},
    };

    test('목록: GET /admin/heart-tasks — 전체면 task 없이, 항목을 고르면 task 를 단다', () async {
      final api = apiWith((_) => json(200, {'items': [row('s1'), row('s2', 'kakao_share')]}));

      final all = await api.listHeartTasks();
      await api.listHeartTasks(task: HeartTaskKind.kakaoShare);

      expect(all.map((i) => i.id), ['s1', 's2']);
      expect(requests.map((r) => '${r.method} ${r.url}'), [
        'GET https://api.test/admin/heart-tasks',
        'GET https://api.test/admin/heart-tasks?task=kakao_share',
      ]);
    });

    test('한 건: GET /admin/heart-tasks/{id} 로 사진 · 지난 제출을 받는다', () async {
      final api = apiWith((_) => json(200, {...row('s1'), 'photo_url': 'https://storage.test/a.jpg', 'previous': <Object?>[]}));

      final detail = await api.getHeartTask('s1');

      expect(requests.single.url.path, '/admin/heart-tasks/s1');
      expect(detail.photoUrl, 'https://storage.test/a.jpg');
    });

    test('승인은 본문 없이, 반려는 사유 하나를 POST 한다', () async {
      final api = apiWith((_) => json(200, {...row('s1'), 'photo_url': null, 'previous': <Object?>[]}));

      await api.approveHeartTask('s1');
      await api.rejectHeartTask('s1', HeartTaskRejectReason.notVerified);

      expect(requests.map((r) => (r.method, r.url.path)), [
        ('POST', '/admin/heart-tasks/s1/approve'),
        ('POST', '/admin/heart-tasks/s1/reject'),
      ]);
      expect(requests.first.body, isEmpty);
      expect(jsonDecode(requests.last.body), {'reason': 'not_verified'});
    });

    test('제출 번호에 / · . · % 가 있으면(..%2Fme 등) 요청을 보내지 않고 실패 — 다른 관리자 API 를 부르지 못한다', () async {
      final api = apiWith((_) => json(200, {}));

      for (final id in ['../me', '..%2Fme', 'a/b', '%2e%2e', 'x y', '']) {
        await expectLater(api.getHeartTask(id), throwsA(isA<AdminApiFailure>()), reason: id);
        await expectLater(api.approveHeartTask(id), throwsA(isA<AdminApiFailure>()), reason: id);
        await expectLater(api.rejectHeartTask(id, HeartTaskRejectReason.reused), throwsA(isA<AdminApiFailure>()), reason: id);
      }
      expect(requests, isEmpty);
    });

    test('409 already_reviewed 는 AlreadyReviewed 예외', () async {
      final api = apiWith((_) => json(409, {'detail': 'already_reviewed'}));

      await expectLater(api.approveHeartTask('s1'), throwsA(isA<AlreadyReviewed>()));
      await expectLater(api.rejectHeartTask('s1', HeartTaskRejectReason.reused), throwsA(isA<AlreadyReviewed>()));
    });

    test('그 밖의 실패(404 · 연결 실패 · 모양이 틀린 본문)는 AdminApiFailure — 상태코드를 싣는다', () async {
      await expectLater(
        apiWith((_) => json(404, {'detail': 'not_found'})).getHeartTask('x'),
        throwsA(isA<AdminApiFailure>().having((e) => e.statusCode, 'statusCode', 404)),
      );
      await expectLater(
        apiWith((_) => throw http.ClientException('offline')).listHeartTasks(),
        throwsA(isA<AdminApiFailure>().having((e) => e.statusCode, 'statusCode', isNull)),
      );
      await expectLater(
        apiWith((_) => json(200, {'rows': <Object?>[]})).listHeartTasks(),
        throwsA(isA<AdminApiFailure>().having((e) => e.statusCode, 'statusCode', 200)),
      );
      await expectLater(
        apiWith((_) => json(500, {})).approveHeartTask('s1'),
        throwsA(isA<AdminApiFailure>().having((e) => e is AlreadyReviewed, 'is AlreadyReviewed', isFalse)),
      );
    });
  });

  test('세션이 없으면 요청을 보내지 않고 401 로 돌려준다', () async {
    final api = apiWith((_) => json(200, {}), token: null);

    final response = await api.me();

    expect(requests, isEmpty);
    expect(response.statusCode, 401);
  });
}
