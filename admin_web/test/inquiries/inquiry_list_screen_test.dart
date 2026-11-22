import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/inquiry_fakes.dart';

/// 문의 목록(`/inquiries`) — 신고 목록(A4)과 같은 틀: 필터 칩 줄 → 표 → 안내. pen 에 문의 화면은 아직 없다.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  List<Map<String, Object?>> rows() => [
    inquiryRow(inquiryA, createdAt: '2026-11-10T01:00:00+00:00', body: '앱이 멈춰요'),
    inquiryRow(inquiryB, createdAt: '2026-11-10T02:00:00+00:00', reason: 'payment', body: '하트가 안 들어왔어요', status: 'answered', answeredAt: '2026-11-10T03:00:00+00:00'),
    inquiryRow(inquiryC, createdAt: '2026-11-10T03:00:00+00:00', reason: 'account', body: '인증이 안 돼요\n두 번째 줄', status: 'in_progress', profile: null),
  ];

  Future<FakeInquiryServer> open(WidgetTester tester, {FakeInquiryServer? server, String path = '/inquiries', bool settle = true}) async {
    final fake = server ?? FakeInquiryServer(rows: rows());
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: fake.api(), initialPath: path, settle: settle);
    return fake;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder chip(String label) => find.widgetWithText(AdminChip, label);

  testWidgets('사이드 메뉴 "문의"를 누르면 /inquiries, TopBar 도 "문의"', (tester) async {
    await open(tester, path: '/');

    await tester.tap(key('nav-inquiries'));
    await tester.pumpAndSettle();

    expect(locationOf(tester), '/inquiries');
    expect(find.text('문의'), findsNWidgets(2)); // 메뉴 + TopBar
  });

  testWidgets('처음에는 "새 문의"만 받는다(요청 status=new) — 표에는 그 줄만', (tester) async {
    final server = await open(tester);

    expect(server.lists.single.url.queryParameters, {'status': 'new', 'page': '1', 'size': '20'});
    expect(key('inquiry-row-$inquiryA'), findsOneWidget);
    expect(key('inquiry-row-$inquiryB'), findsNothing);
  });

  testWidgets('칩 전체 · 새 문의 · 처리 중 · 답변 완료 — 고르면 그 상태로 다시 받는다', (tester) async {
    final server = await open(tester);

    await tester.tap(chip('전체'));
    await tester.pumpAndSettle();
    expect(server.lists.last.url.queryParameters, {'page': '1', 'size': '20'});
    expect([for (final id in [inquiryA, inquiryB, inquiryC]) key('inquiry-row-$id').evaluate().length], [1, 1, 1]);

    await tester.tap(chip('답변 완료'));
    await tester.pumpAndSettle();
    expect(server.lists.last.url.queryParameters, {'status': 'answered', 'page': '1', 'size': '20'});
    expect(key('inquiry-row-$inquiryB'), findsOneWidget);
    expect(key('inquiry-row-$inquiryA'), findsNothing);

    await tester.tap(chip('처리 중'));
    await tester.pumpAndSettle();
    expect(server.lists.last.url.queryParameters, {'status': 'in_progress', 'page': '1', 'size': '20'});
    expect(key('inquiry-row-$inquiryC'), findsOneWidget);
  });

  testWidgets('표 머리 · 칸: 접수 시각(한국 시간) · 사유 · 보낸 사람 · 상태 · 내용 첫 줄', (tester) async {
    await open(tester);
    await tester.tap(chip('전체'));
    await tester.pumpAndSettle();

    final table = key('inquiry-table');
    for (final head in ['접수 시각', '사유', '보낸 사람', '상태', '내용']) {
      expect(find.descendant(of: table, matching: find.text(head)), findsOneWidget, reason: head);
    }
    // 최근 순: C(03:00Z) → B → A
    final ys = [for (final id in [inquiryC, inquiryB, inquiryA]) tester.getTopLeft(key('inquiry-row-$id')).dy];
    expect(ys, [...ys]..sort());
    final a = key('inquiry-row-$inquiryA');
    for (final text in ['2026-11-10 10:00', '앱 오류', '하늘 · 테스트대학교', '새 문의', '앱이 멈춰요']) {
      expect(find.descendant(of: a, matching: find.text(text)), findsOneWidget, reason: text);
    }
    final c = key('inquiry-row-$inquiryC');
    expect(find.descendant(of: c, matching: find.text('탈퇴한 사용자')), findsOneWidget);
    expect(find.descendant(of: c, matching: find.text('계정·인증')), findsOneWidget);
    expect(find.descendant(of: c, matching: find.text('인증이 안 돼요')), findsOneWidget); // 첫 줄만
    expect(find.textContaining('두 번째 줄'), findsNothing);
  });

  List<Map<String, Object?>> many(int count) => [
        for (var i = 1; i <= count; i++) inquiryRow('q$i', createdAt: '2026-11-10T10:${60 - i}:00+00:00'), // q1 이 가장 최근
      ];

  testWidgets('번호 쪽: 표 아래 전체 건수, 2를 누르면 같은 필터로 page=2 를 받아 그 쪽만 그린다', (tester) async {
    final server = await open(tester, server: FakeInquiryServer(rows: many(21)));

    expect(find.text('전체 21건'), findsOneWidget);
    expect(key('inquiry-row-q21'), findsNothing);
    await tester.ensureVisible(key('pager-page-2'));
    await tester.tap(key('pager-page-2'));
    await tester.pumpAndSettle();

    expect(server.lists.last.url.queryParameters, {'status': 'new', 'page': '2', 'size': '20'});
    expect(key('inquiry-row-q21'), findsOneWidget);
    expect(key('inquiry-row-q1'), findsNothing);
    expect(find.text('더 보기'), findsNothing);
  });

  testWidgets('2쪽에서 필터를 바꾸면 1쪽부터, 쪽 받기가 실패하면 오류 + 다시 시도는 그 쪽을 다시', (tester) async {
    final server = await open(tester, server: FakeInquiryServer(rows: many(21)));
    await tester.ensureVisible(key('pager-page-2'));
    await tester.tap(key('pager-page-2'));
    await tester.pumpAndSettle();

    await tester.tap(chip('전체'));
    await tester.pumpAndSettle();
    expect(server.lists.last.url.queryParameters, {'page': '1', 'size': '20'});

    server.listFailure = 500;
    await tester.ensureVisible(key('pager-page-2'));
    await tester.tap(key('pager-page-2'));
    await tester.pumpAndSettle();
    expect(find.text('문의를 불러오지 못했어요'), findsOneWidget);
    server.listFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(server.lists.last.url.queryParameters, {'page': '2', 'size': '20'});
    expect(key('inquiry-row-q21'), findsOneWidget);
  });

  testWidgets('받는 중: 안내 글자 / 못 받음: 오류 + 다시 시도 → 성공하면 표', (tester) async {
    final server = FakeInquiryServer(rows: rows())..listFailure = 500;
    await open(tester, server: server, settle: false);
    await tester.pump();
    expect(find.text('문의를 불러오고 있어요'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('문의를 불러오지 못했어요'), findsOneWidget);
    server.listFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('문의를 불러오지 못했어요'), findsNothing);
    expect(key('inquiry-row-$inquiryA'), findsOneWidget);
  });

  testWidgets('연결이 끊겨도(statusCode 없음) 같은 오류 화면', (tester) async {
    await open(tester, server: FakeInquiryServer(rows: rows())..listFailure = 0);

    expect(find.text('문의를 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('빈 목록: 새 문의만 볼 때와 다른 상태를 볼 때 글이 다르다', (tester) async {
    await open(tester, server: FakeInquiryServer());

    expect(find.text('새 문의가 없어요'), findsOneWidget);
    await tester.tap(chip('답변 완료'));
    await tester.pumpAndSettle();
    expect(find.text('조건에 맞는 문의가 없어요'), findsOneWidget);
  });

  testWidgets('줄을 누르면 /inquiries/{id} 상세로', (tester) async {
    await open(tester);

    await tester.tap(key('inquiry-row-$inquiryA'));
    await tester.pumpAndSettle();

    expect(locationOf(tester), '/inquiries/$inquiryA');
    expect(find.text('문의 상세'), findsOneWidget); // TopBar
  });

  testWidgets('상세에서 "← 문의 목록"으로 돌아오면 고른 필터가 남아 있다', (tester) async {
    final server = await open(tester);
    await tester.tap(chip('전체'));
    await tester.pumpAndSettle();
    await tester.tap(key('inquiry-row-$inquiryB'));
    await tester.pumpAndSettle();

    await tester.tap(key('inquiry-back'));
    await tester.pumpAndSettle();

    expect(locationOf(tester), '/inquiries');
    expect(server.lists.last.url.queryParameters, {'page': '1', 'size': '20'});
    expect(key('inquiry-row-$inquiryB'), findsOneWidget);
  });
}
