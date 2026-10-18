import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
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

  group('신고 검수(D2 · A4)', () {
    Map<String, Object?> summary(String id, [String type = 'message']) => {
      'id': id,
      'target_type': type,
      'target_id': 'c-$id',
      'reason': 'abuse',
      'reason_note': null,
      'status': 'open',
      'created_at': '2026-10-18T02:20:00+00:00',
      'resolved_at': null,
      'target_profile': {'id': 'p1', 'nickname': '하늘', 'university': '테스트대학교', 'status': 'active', 'auto_hidden_at': null},
    };
    Map<String, Object?> detail(String id) => {
      ...summary(id),
      'snapshot': {'message_id': 'm', 'match_id': 'room', 'body': '글', 'created_at': '2026-10-18T02:00:00+00:00'},
      'content_status': null,
      'open_reporters': 1,
      'other_reports': <Object?>[],
    };

    test('목록: GET /admin/reports?status= — 종류를 고르면 type 을 단다', () async {
      final api = apiWith((_) => json(200, {'items': [summary('r1'), summary('r2', 'poll')]}));

      final open = await api.listReports();
      await api.listReports(status: ReportStatus.dismissed, type: ReportTargetType.friendReview);

      expect(open.map((i) => i.id), ['r1', 'r2']);
      expect(requests.map((r) => '${r.method} ${r.url}'), [
        'GET https://api.test/admin/reports?status=open',
        'GET https://api.test/admin/reports?status=dismissed&type=friend_review',
      ]);
    });

    test('한 건: GET /admin/reports/{id}', () async {
      final api = apiWith((_) => json(200, detail('r1')));

      final got = await api.getReport('r1');

      expect(requests.single.url.path, '/admin/reports/r1');
      expect(got.openReporters, 1);
    });

    test('닫기: POST /resolve {outcome, note, same_target} — 메모는 앞뒤 공백만 떼고, 비면 null', () async {
      final api = apiWith((_) => json(200, detail('r1')));

      await api.resolveReport('r1', ReportStatus.actioned, note: '  사진 확인  ', sameTarget: true, seenReportIds: ['o1', 'o2']);
      await api.resolveReport('r1', ReportStatus.dismissed, note: '   ');

      expect(requests.map((r) => r.url.path), everyElement('/admin/reports/r1/resolve'));
      expect(jsonDecode(requests.first.body), {
        'outcome': 'actioned',
        'note': '사진 확인',
        'same_target': true,
        'seen_report_ids': ['o1', 'o2'],
      });
      // 함께 닫기가 아니면 본 신고 목록은 보내지 않는다(서버는 이 신고 한 건만 닫는다)
      expect(jsonDecode(requests.last.body), {'outcome': 'dismissed', 'note': null, 'same_target': false});
    });

    test('함께 닫기인데 본 신고 목록을 안 주면 빈 목록([])을 보낸다 — 서버가 422 로 돌리는 "칸 없음" 이 되지 않게(이 신고만 닫힌다)', () async {
      final api = apiWith((_) => json(200, detail('r1')));

      await api.resolveReport('r1', ReportStatus.actioned, sameTarget: true);

      expect(jsonDecode(requests.single.body), {'outcome': 'actioned', 'note': null, 'same_target': true, 'seen_report_ids': <Object?>[]});
    });

    test('채팅 앞뒤: POST /chat-context {reason} → 줄 목록(글자는 그대로, 앞뒤 공백만 뗌)', () async {
      final api = apiWith(
        (_) => json(200, {
          'messages': [
            {'id': 'm1', 'kind': 'text', 'body': '<b>안녕</b>', 'created_at': '2026-10-18T02:00:00+00:00', 'from_target': true, 'reported': false},
          ],
        }),
      );

      final lines = await api.chatContext('r1', ' 신고 확인 ');

      expect(requests.single.url.path, '/admin/reports/r1/chat-context');
      expect(jsonDecode(requests.single.body), {'reason': '신고 확인'});
      expect(lines.single.body, '<b>안녕</b>');
    });

    test('사람 조치: POST /admin/profiles/{id}/suspend · unsuspend · unhide {reason}', () async {
      final api = apiWith((_) => json(200, {'id': 'p1', 'status': 'suspended'}));

      for (final action in ProfileAction.values) {
        await api.actOnProfile('p1', action, '사유', seenReportIds: ['r1', 'o1']);
      }

      expect(requests.map((r) => r.url.path), [
        '/admin/profiles/p1/suspend',
        '/admin/profiles/p1/unsuspend',
        '/admin/profiles/p1/unhide',
      ]);
      // 본 신고 목록은 가림 해제만 보낸다 — 정지 · 정지 해제 함수는 그 칸을 쓰지 않는다
      expect(requests.map((r) => jsonDecode(r.body)), [
        {'reason': '사유'},
        {'reason': '사유'},
        {'reason': '사유', 'seen_report_ids': ['r1', 'o1']},
      ]);
    });

    test('가림 해제인데 본 신고 목록을 안 주면 빈 목록([])을 보낸다', () async {
      final api = apiWith((_) => json(200, {'id': 'p1'}));

      await api.actOnProfile('p1', ProfileAction.unhide, '사유');

      expect(jsonDecode(requests.single.body), {'reason': '사유', 'seen_report_ids': <Object?>[]});
    });

    test('서버가 422 seen_reports_required 로 돌리면 일반 실패다(AdminApiFailure 422)', () async {
      final api = apiWith((_) => json(422, {'detail': 'seen_reports_required'}));

      await expectLater(
        api.resolveReport('r1', ReportStatus.dismissed, sameTarget: true, seenReportIds: const []),
        throwsA(isA<AdminApiFailure>().having((f) => f.statusCode, 'statusCode', 422)),
      );
    });

    test('글 가림: POST /admin/content/polls|friend-reviews/{id}/blind|unblind {reason}', () async {
      final api = apiWith((_) => json(200, {'id': 'c', 'status': 'blinded'}));

      await api.setContentStatus(ReportTargetType.poll, 'c1', blind: true, reason: '사유');
      await api.setContentStatus(ReportTargetType.friendReview, 'c2', blind: false, reason: '사유');

      expect(requests.map((r) => r.url.path), ['/admin/content/polls/c1/blind', '/admin/content/friend-reviews/c2/unblind']);
    });

    test('번호에 / · . · % 가 있으면 요청을 보내지 않고 실패 — 다른 관리자 API 를 부르지 못한다', () async {
      final api = apiWith((_) => json(200, {}));

      for (final id in ['../me', '..%2Fme', 'a/b', '%2e%2e', 'x y', '']) {
        await expectLater(api.getReport(id), throwsA(isA<AdminApiFailure>()), reason: id);
        await expectLater(api.resolveReport(id, ReportStatus.actioned), throwsA(isA<AdminApiFailure>()), reason: id);
        await expectLater(api.chatContext(id, '사유'), throwsA(isA<AdminApiFailure>()), reason: id);
        await expectLater(api.actOnProfile(id, ProfileAction.suspend, '사유'), throwsA(isA<AdminApiFailure>()), reason: id);
        await expectLater(
          api.setContentStatus(ReportTargetType.poll, id, blind: true, reason: '사유'),
          throwsA(isA<AdminApiFailure>()),
          reason: id,
        );
      }
      expect(requests, isEmpty);
    });

    test('409 already_done 은 이미 처리됨(AlreadyReviewed) 예외', () async {
      final api = apiWith((_) => json(409, {'detail': 'already_done'}));

      await expectLater(api.resolveReport('r1', ReportStatus.actioned), throwsA(isA<AlreadyReviewed>()));
      await expectLater(api.actOnProfile('p1', ProfileAction.unhide, '사유'), throwsA(isA<AlreadyReviewed>()));
    });
  });

  test('세션이 없으면 요청을 보내지 않고 401 로 돌려준다', () async {
    final api = apiWith((_) => json(200, {}), token: null);

    final response = await api.me();

    expect(requests, isEmpty);
    expect(response.statusCode, 401);
  });
}
