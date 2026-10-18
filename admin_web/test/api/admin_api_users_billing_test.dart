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
    test('listUsers: q 가 없으면 쿼리 없이 GET /admin/users, 있으면 q 만 붙는다', () async {
      final api = apiWith((_) => json(200, {'items': [userRow('u1')]}));

      final all = await api.listUsers();
      await api.listUsers(q: '닉네임A');

      expect(requests[0].method, 'GET');
      expect(requests[0].url.path, '/admin/users');
      expect(requests[0].url.queryParameters, isEmpty);
      expect(requests[1].url.queryParameters, {'q': '닉네임A'});
      expect(all.single.id, 'u1');
      expect(all.single.nickname, '닉네임A');
      expect(all.single.university, '서울대학교');
      expect(all.single.status, 'active');
      expect(all.single.reportCount, 0);
    });

    test('가입 중인 사람은 닉네임 · 학교가 null 이어도 읽는다', () async {
      final api = apiWith((_) => json(200, {'items': [userRow('u1', nickname: null, university: null, status: 'pending')]}));

      final users = await api.listUsers();

      expect(users.single.nickname, isNull);
      expect(users.single.university, isNull);
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
      final api = apiWith((_) => json(200, userDetailJson('u1')));

      final detail = await api.getUser('u1');

      expect(requests.single.url.path, '/admin/users/u1');
      expect(detail.summary.nickname, '닉네임A');
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
          _ => json(200, {'items': [shortfallRow()]}),
        };
      });

      final summary = await api.billingSummary();
      final days = await api.billingDaily();
      final short = await api.billingShortfall();

      expect(requests[1].url.queryParameters, {'days': '30'});
      expect(summary.month, '2026-10');
      expect(summary.revenueKrw, 1284000);
      expect(days.map((d) => (d.date, d.revenueKrw)), [('2026-10-17', 30000), ('2026-10-18', 0)]);
      expect(short.single.purchaseId, 'pu1');
      expect(short.single.nickname, '닉네임A');
      expect(short.single.shortfallHearts, 40);
      expect(short.single.productName, '하트 100개');
      expect(short.single.refundedAt, DateTime.utc(2026, 10, 10, 9, 20));
    });
  });
}
