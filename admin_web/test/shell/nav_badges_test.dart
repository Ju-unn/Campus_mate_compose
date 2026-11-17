import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/platform/confirm_store.dart';
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/shell/nav_badges.dart';
import 'package:campus_mate_admin/widgets/count_badge.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/server_status_fakes.dart';

/// 왼쪽 메뉴 빨간 숫자(pen QtFLt · BQyo6): 서버 상태 = 확인 뒤 새 이상 수, 인증샷 검수 · 졸업생 · 신고 · 문의 = 대기 건수.
/// 숫자는 셸이 뜰 때 한 번 + 새로고침 때만(서버 상태), 대기 건수는 메뉴 이동 때도 — 시계로 다시 부르지 않는다.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  Future<FakeStatusServer> open(WidgetTester tester, {FakeStatusServer? server, ConfirmStore? store}) async {
    final fake = server ?? FakeStatusServer();
    await pumpAdminApp(
      tester,
      auth: FakeAdminAuth(mfa: aal2),
      api: fake.api(),
      overrides: [confirmStoreProvider.overrideWithValue(store ?? memoryStore({}))],
    );
    return fake;
  }

  /// pumpAndSettle 대신 정해진 횟수만 그린다 — 관문 ↔ 배지 읽기가 반복되면 무한히 기다리지 않고 바로 FAIL(fix round 1).
  Future<void> pumpBounded(WidgetTester tester, FakeStatusServer server) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(server.calls('/admin/server-status'), lessThanOrEqualTo(3), reason: '서버 상태를 반복해 부른다(관문 ↔ 배지 반복)');
    }
  }

  /// 그 메뉴 칸 안에 보이는 배지 글자(없으면 null)
  String? badgeOf(WidgetTester tester, AdminSection section) {
    final badge = find.descendant(of: find.byKey(ValueKey('nav-${section.name}')), matching: find.descendant(of: find.byType(CountBadge), matching: find.byType(Text)));
    if (badge.evaluate().isEmpty) return null;
    return tester.widget<Text>(badge).data;
  }

  testWidgets('server badge counts only unseen anomalies', (tester) async {
    // 이상 3줄 중 앞서 본(열쇠가 저장된) 2줄은 빼고 1
    final seen = [for (final row in defaultAnomalies().skip(1)) anomalyKeyOf(row)];
    await open(tester, store: memoryStore({ConfirmStore.key: jsonEncode(seen)}));

    expect(badgeOf(tester, AdminSection.serverStatus), '1');
  });

  testWidgets('저장된 값이 깨졌으면(JSON 아님 · 배열 아님) 아무것도 안 본 것으로', (tester) async {
    await open(tester, store: memoryStore({ConfirmStore.key: '{not json'}));
    expect(badgeOf(tester, AdminSection.serverStatus), '3');
  });

  testWidgets('확인한 적 없으면 이상 전부를 센다', (tester) async {
    await open(tester);

    expect(badgeOf(tester, AdminSection.serverStatus), '3');
  });

  testWidgets('confirm store survives storage errors', (tester) async {
    await open(tester, store: throwingStore());

    expect(tester.takeException(), isNull);
    expect(badgeOf(tester, AdminSection.serverStatus), '3');
    expect(find.text('오늘 처리할 일'), findsOneWidget); // 홈은 그대로 뜬다
  });

  testWidgets('pending counts map to sections', (tester) async {
    final server = FakeStatusServer()..counts = {'heart_tasks': 2, 'graduates': 1, 'reports': 3, 'inquiries': 1};
    await open(tester, server: server);

    expect(badgeOf(tester, AdminSection.heartTasks), '2');
    expect(badgeOf(tester, AdminSection.graduates), '1');
    expect(badgeOf(tester, AdminSection.reports), '3');
    expect(badgeOf(tester, AdminSection.inquiries), '1');
    for (final section in [AdminSection.home, AdminSection.matching, AdminSection.users, AdminSection.billing, AdminSection.unknownDomains, AdminSection.actions]) {
      expect(badgeOf(tester, section), isNull, reason: section.name);
    }
  });

  testWidgets('대기 건수 0 · 이상 0 이면 배지가 없다', (tester) async {
    final server = FakeStatusServer()..status = serverStatusJson(anomalies: []);
    await open(tester, server: server);

    expect(find.descendant(of: find.byType(CountBadge), matching: find.byType(Text)), findsNothing);
  });

  testWidgets('읽기 실패면 배지를 숨긴다(서버 상태 503 · 대기 건수 연결 실패)', (tester) async {
    final server = FakeStatusServer()
      ..statusFailure = 503
      ..countsFailure = 0;
    await open(tester, server: server);

    expect(find.descendant(of: find.byType(CountBadge), matching: find.byType(Text)), findsNothing);
    expect(find.text('오늘 처리할 일'), findsOneWidget);
  });

  testWidgets('navigating refreshes pending counts', (tester) async {
    final server = await open(tester);
    expect(server.calls('/admin/pending-counts'), 1);
    expect(server.calls('/admin/server-status'), 1);

    server.counts = {'heart_tasks': 5, 'graduates': 0, 'reports': 0, 'inquiries': 0};
    await tester.tap(find.byKey(const ValueKey('nav-reports')));
    await tester.pumpAndSettle();

    expect(server.calls('/admin/pending-counts'), 2);
    expect(badgeOf(tester, AdminSection.heartTasks), '5');
    expect(server.calls('/admin/server-status'), 1, reason: '서버 숫자는 메뉴 이동으로 다시 부르지 않는다');
  });

  testWidgets('no timer', (tester) async {
    final server = await open(tester);

    await tester.pump(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 30));

    expect(server.calls('/admin/pending-counts'), 1);
    expect(server.calls('/admin/server-status'), 1);
  });

  testWidgets('pen 배치: 배지는 메뉴 칸 맨 오른쪽(칸 오른쪽 12 안), 세로 가운데', (tester) async {
    final server = FakeStatusServer()..counts = {'heart_tasks': 2, 'graduates': 0, 'reports': 0, 'inquiries': 0};
    await open(tester, server: server);

    final item = tester.getRect(find.byKey(const ValueKey('nav-heartTasks')));
    final badge = tester.getRect(find.descendant(of: find.byKey(const ValueKey('nav-heartTasks')), matching: find.byType(CountBadge)));
    expect(item.right - badge.right, 12);
    expect(badge.center.dy, item.center.dy);
  });

  testWidgets('셸의 서버 상태가 403 이고 관문 확인(me)은 200 이면 관문만 다시 보고, 서버 상태는 다시 부르지 않는다(반복 없음)', (tester) async {
    final auth = FakeAdminAuth(mfa: aal2);
    final server = FakeStatusServer()
      ..statusFailure = 403
      ..maxStatusCalls = 3;
    await pumpAdminApp(tester, auth: auth, api: server.api(), overrides: [confirmStoreProvider.overrideWithValue(memoryStore({}))], settle: false);
    await pumpBounded(tester, server);

    expect(server.calls('/admin/server-status'), 1);
    expect(server.calls('/admin/me'), 2, reason: '403 이 관문을 한 번 다시 보게 한다');
    expect(auth.calls, isNot(contains('signOut')));
    expect(find.text('오늘 처리할 일'), findsOneWidget);
  });

  testWidgets('셸의 서버 상태가 401 이고 다음 관문 확인도 401 이면 로그아웃된다', (tester) async {
    final auth = FakeAdminAuth(mfa: aal2);
    final server = FakeStatusServer()
      ..statusFailure = 401
      ..laterMeStatus = 401
      ..maxStatusCalls = 3;
    await pumpAdminApp(tester, auth: auth, api: server.api(), overrides: [confirmStoreProvider.overrideWithValue(memoryStore({}))], settle: false);
    await pumpBounded(tester, server);

    expect(auth.calls, contains('signOut'));
    expect(auth.session, isFalse);
  });

  test('navBadgeCount: 서버 상태 · 대기 건수 메뉴 말고는 0', () {
    expect(navBadgeCount(AdminSection.home, serverNew: 4, pending: null), 0);
    expect(navBadgeCount(AdminSection.serverStatus, serverNew: 4, pending: null), 4);
    expect(navBadgeCount(AdminSection.reports, serverNew: 4, pending: null), 0);
  });
}
