import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/reports/report_item.dart' show ProfileAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/user_fakes.dart';

/// W3 서버 계약(D3 계획서 표 · backend/app/admin/{users,user_actions,billing}.py) — 경로 · 본문 · 응답 필드 이름.
void main() {
  late List<http.Request> requests;

  AdminApi apiWith(http.Response Function(http.Request) respond) {
    requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
    return AdminApi('https://api.test', client, () => 'tok');
  }

  http.Response json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  group('사용자 찾기', () {
    test('listUsers: q 가 없으면 쪽만, 있으면 q 도 붙는다', () async {
      final api = apiWith((_) => json(200, {'items': [userRow('u1')], 'total': 1, 'page': 1, 'size': 20}));

      final all = await api.listUsers();
      await api.listUsers(q: '닉네임A');

      expect(requests[0].method, 'GET');
      expect(requests[0].url.path, '/admin/users');
      expect(requests[0].url.queryParameters, {'page': '1', 'size': '20'});
      expect(requests[1].url.queryParameters, {'q': '닉네임A', 'page': '1', 'size': '20'});
      expect(all.items.single.id, 'u1');
      expect(all.items.single.nickname, '닉네임A');
      expect(all.items.single.university, '서울대학교');
      expect(all.items.single.status, 'active');
      expect(all.items.single.reportCount, 0);
      expect((all.items.single.gender, all.items.single.acquisitionChannel), ('male', null));
    });

    test('가입 중인 사람은 닉네임 · 학교 · 성별이 null 이어도 읽는다', () async {
      final api = apiWith(
        (_) => json(200, {
          'items': [userRow('u1', nickname: null, university: null, status: 'pending', gender: null, channel: 'friend')],
          'total': 1,
        }),
      );

      final users = await api.listUsers();

      expect(users.items.single.nickname, isNull);
      expect(users.items.single.university, isNull);
      expect((users.items.single.gender, users.items.single.acquisitionChannel), (null, 'friend'));
    });

    test('성별 · 들어온 경로 칸이 없는 옛 서버 응답도 읽는다(관리자 웹이 서버보다 먼저 나갈 때)', () async {
      final api = apiWith(
        (_) => json(200, {
          'items': [
            {'id': 'u1', 'nickname': '닉네임A', 'university': null, 'status': 'active', 'created_at': '2026-09-30T03:00:00+00:00', 'report_count': 0},
          ],
          'total': 1,
        }),
      );

      final users = await api.listUsers();

      expect((users.items.single.gender, users.items.single.acquisitionChannel), (null, null));
    });

    test('userTotals: GET /admin/users/totals → 성별 · 들어온 경로 인원(쿼리 없음)', () async {
      final api = apiWith((_) => json(200, userTotalsJson()));

      final totals = await api.userTotals();

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/admin/users/totals');
      expect(requests.single.url.query, isEmpty);
      expect(totals.gender, {'male': 12, 'female': 9, 'none': 3});
      expect(totals.channels, {'everytime': 5, 'instagram': 4, 'friend': 3, 'community': 1, 'other': 2, 'none': 9});
    });

    test('userTotals: 모양이 틀리면(개수가 정수가 아님 · 칸 없음) 실패로 다룬다', () async {
      for (final body in [
        {'gender': {'male': '12'}, 'acquisition_channel': <String, Object?>{}},
        {'gender': <String, Object?>{}},
      ]) {
        final api = apiWith((_) => json(200, body));
        await expectLater(api.userTotals(), throwsA(isA<AdminApiFailure>()), reason: '$body');
      }
    });

    test('학교 메일 찾기는 POST 본문으로만 — 주소 · 쿼리에 메일이 없다', () async {
      final api = apiWith((_) => json(200, {'items': <Object?>[]}));

      final found = await api.searchUsersBySchoolEmail('alice.test@campus.ac.kr');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/admin/users/search');
      expect(jsonDecode(request.body), {'school_email': 'alice.test@campus.ac.kr'});
      expect(request.url.toString(), isNot(contains('alice')));
      expect(request.url.toString(), isNot(contains('@')));
      expect(request.url.query, isEmpty);
      expect(found, isEmpty);
    });
  });

  group('사용자 상세', () {
    test('getUser: 필드 이름 그대로 읽는다(UserDetail)', () async {
      final api = apiWith((_) => json(200, userDetailJson('u1', channel: 'other', note: '학교 게시판')));

      final detail = await api.getUser('u1');

      expect(requests.single.url.path, '/admin/users/u1');
      expect(detail.summary.nickname, '닉네임A');
      expect((detail.summary.gender, detail.summary.acquisitionChannel, detail.acquisitionNote), ('male', 'other', '학교 게시판'));
      expect(detail.lastActiveAt, DateTime.utc(2026, 10, 18, 5, 20));
      expect(detail.avatarUrl, isNull);
      expect(detail.loginProviders, ['kakao']);
      expect(detail.heartBalance, 120);
      expect(detail.contactBlockCount, 14);
      expect(detail.hearts.map((h) => (h.amount, h.balanceAfter, h.reason)), [(40, 120, 'free_task'), (-30, 80, 'extra_card')]);
      expect(detail.purchases.first.grantedHearts, 100);
      expect(detail.purchases.first.productName, '하트 100개');
      expect(detail.purchases.first.store, 'play_store');
      expect(detail.purchases.first.status, 'granted');
      expect(detail.notes.first.text, '결제 문의, 영수증 확인함');
    });

    test('login_providers 가 null(조회 실패)이어도 읽는다', () async {
      final api = apiWith((_) => json(200, userDetailJson('u1', providers: null)));

      expect((await api.getUser('u1')).loginProviders, isNull);
    });

    test('경로에 들어가는 사용자 번호는 영숫자 · 하이픈만 — "../me" 는 보내지 않고 404', () async {
      final api = apiWith((_) => json(200, userDetailJson('u1')));

      await expectLater(api.getUser('../me'), throwsA(isA<AdminApiFailure>().having((e) => e.statusCode, 'status', 404)));
      await expectLater(api.adjustHearts('a/b', 5, '확인'), throwsA(isA<AdminApiFailure>()));
      await expectLater(api.addUserNote('..', '메모'), throwsA(isA<AdminApiFailure>()));
      expect(requests, isEmpty);
    });

    test('메모는 POST /notes {text}', () async {
      final api = apiWith((_) => json(200, {'saved': true}));

      await api.addUserNote('u1', ' 영수증 확인 ');

      expect(requests.single.url.path, '/admin/users/u1/notes');
      expect(jsonDecode(requests.single.body), {'text': '영수증 확인'});
    });

    test('하트 조정은 POST /hearts {amount, reason}, 부호 그대로 정수로', () async {
      final api = apiWith((_) => json(200, {'id': 'u1', 'amount': -30, 'heart_balance': 90, 'action_id': 'a1'}));

      await api.adjustHearts('u1', -30, ' 결제 오류 정정 ');

      expect(requests.single.url.path, '/admin/users/u1/hearts');
      expect(jsonDecode(requests.single.body), {'amount': -30, 'reason': '결제 오류 정정'});
    });

    test('409 의 이유(insufficient_hearts · account_withdrawn)를 실패에 담아 준다', () async {
      final api = apiWith((_) => json(409, {'detail': 'insufficient_hearts'}));

      await expectLater(
        api.adjustHearts('u1', -999, '확인'),
        throwsA(isA<AdminApiFailure>().having((e) => e.statusCode, 'status', 409).having((e) => e.reason, 'reason', 'insufficient_hearts')),
      );
    });

    test('열람은 POST /private {reason} → phone_number · kakao_id(없으면 null)', () async {
      final api = apiWith((_) => json(200, {'phone_number': '010-1234-5678', 'kakao_id': null}));

      final contact = await api.viewPrivate('u1', ' 문의 응대 ');

      expect(requests.single.url.path, '/admin/users/u1/private');
      expect(jsonDecode(requests.single.body), {'reason': '문의 응대'});
      expect(contact.phoneNumber, '010-1234-5678');
      expect(contact.kakaoId, isNull);
    });

    test('탈퇴 대행은 POST /close-account {reason, verified_by} → cleanup 결과', () async {
      final api = apiWith(
        (_) => json(200, {
          'id': 'u1',
          'was_status': 'active',
          'status': 'withdrawn',
          'rejoin_blocked': 'two_months',
          'cleanup': {'push_tokens': 'ok', 'student_id_files': 'ok', 'kakao_unlink': 'failed'},
          'not_done': ['apple_revoke', 'logout_everywhere'],
        }),
      );

      final result = await api.closeAccount('u1', reason: ' 본인 탈퇴 요청 ', verifiedBy: ' 답장 확인 ');

      expect(requests.single.url.path, '/admin/users/u1/close-account');
      expect(jsonDecode(requests.single.body), {'reason': '본인 탈퇴 요청', 'verified_by': '답장 확인'});
      expect(result.kakaoUnlinkFailed, isTrue);
      expect(result.otherCleanupFailed, isFalse);
    });

    test('정지 · 해제는 D2 경로 /admin/profiles/{id}/suspend · unsuspend 를 쓴다', () async {
      final api = apiWith((_) => json(200, {'id': 'u1'}));

      await api.actOnProfile('u1', ProfileAction.suspend, '확인');
      await api.actOnProfile('u1', ProfileAction.unsuspend, '확인');

      expect(requests.map((r) => r.url.path), ['/admin/profiles/u1/suspend', '/admin/profiles/u1/unsuspend']);
    });
  });

  group('결제 조회', () {
    test('주문 번호는 POST 본문으로만 — 주소에 번호가 없고, 응답의 번호 칸은 읽지 않는다', () async {
      final api = apiWith((_) => json(200, {'items': [orderRow(storeOrderId: 'GPA.1111-2222-3333-44444')]}));

      final orders = await api.findOrders('GPA.1111-2222-3333-44444');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/admin/billing/orders/search');
      expect(jsonDecode(request.body), {'order': 'GPA.1111-2222-3333-44444'});
      expect(request.url.toString(), isNot(contains('GPA')));
      final order = orders.single;
      expect(order.productName, '하트 100개');
      expect(order.grantedHearts, 100);
      expect(order.clawedBackHearts, 60);
      expect(order.store, 'play_store');
      expect(order.status, 'refunded');
      expect(order.purchasedAt, DateTime.utc(2026, 10, 9, 1));
      expect(order.refundedAt, DateTime.utc(2026, 10, 10, 9, 20));
      expect(order.toString(), isNot(contains('GPA')));
    });

    test('요약 · 일별 · 못 거둔 목록 경로와 필드', () async {
      final api = apiWith((request) {
        return switch (request.url.path) {
          '/admin/billing/summary' => json(200, {'month': '2026-10', 'revenue_krw': 1284000, 'order_count': 9, 'refunded_krw': 0}),
          '/admin/billing/daily' => json(200, {'days': [dayRow('2026-10-17', 30000), dayRow('2026-10-18', 0)]}),
          _ => json(200, {'items': [shortfallRow()], 'total': 1, 'page': 1, 'size': 20}),
        };
      });

      final summary = await api.billingSummary();
      final days = await api.billingDaily();
      final short = await api.billingShortfall();

      expect(requests[1].url.queryParameters, {'days': '30'});
      expect(summary.month, '2026-10');
      expect(summary.revenueKrw, 1284000);
      expect(days.map((d) => (d.date, d.revenueKrw)), [('2026-10-17', 30000), ('2026-10-18', 0)]);
      expect(short.items.single.purchaseId, 'pu1');
      expect(short.items.single.nickname, '닉네임A');
      expect(short.items.single.shortfallHearts, 40);
      expect(short.items.single.productName, '하트 100개');
      expect(short.items.single.refundedAt, DateTime.utc(2026, 10, 10, 9, 20));
    });

    test('환불이 잦은 계정: 경로 frequent-returns(금지어 refund 없음) · 쪽만 · 줄 차례 그대로', () async {
      final api = apiWith((request) => json(200, {'items': [returnedRow(), returnedRow(id: 'u7', nickname: null, count: 1)], 'total': 2, 'page': 1, 'size': 20}));

      final rows = await api.billingReturnedAccounts();

      expect(requests.single.url.path, '/admin/billing/frequent-returns');
      expect(requests.single.url.queryParameters, {'page': '1', 'size': '20'});
      expect(rows.items.map((r) => (r.profileId, r.nickname, r.refundCount)), [('u1', '닉네임A', 3), ('u7', null, 1)]);
    });

    test('환불이 잦은 계정 응답 모양이 틀리면 실패로 다룬다', () async {
      final api = apiWith((request) => json(200, {'rows': []}));

      await expectLater(api.billingReturnedAccounts(), throwsA(isA<AdminApiFailure>()));
    });
  });
}
