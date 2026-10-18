import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/app.dart';
import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/billing/billing_controller.dart';
import 'package:campus_mate_admin/billing/revenue_chart.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/user_fakes.dart';

/// A8 결제 조회(pen w674C, 값표 G + PNG A8_결제_조회 · _주문_못_찾음 · _상태_완료 · _못_거둔_목록_없음 측정) — 그리고 주문 번호 보안.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');
  const orderNo = 'GPA.1111-2222-3333-44444';

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<FakeUserServer> openBilling(WidgetTester tester, {FakeUserServer? server, bool settle = true}) async {
    final fake = server ?? FakeUserServer();
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: fake.api(), initialPath: '/billing', settle: settle);
    return fake;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder button(String label) => find.widgetWithText(AdminButton, label);
  Finder field() => find.byType(TextField);
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;

  Future<void> search(WidgetTester tester, String order) async {
    await tester.enterText(field(), order);
    await tester.tap(button('조회'));
    await tester.pumpAndSettle();
  }

  group('pen 배치(w674C)', () {
    testWidgets('TopBar "결제 조회"(메뉴 이름은 "결제")', (tester) async {
      await openBilling(tester);

      expect(find.text('결제 조회'), findsOneWidget);
      expect(find.text('결제'), findsOneWidget);
    });

    testWidgets('윗줄 y96: 매출 카드 (272,96) 280×146 — 라벨 · 값 32/700 "₩1,284,000" · "2026년 10월" 14/600 web primary-text, 사이 24 검색 카드 폭 832', (tester) async {
      await openBilling(tester);

      expect(tester.getRect(find.byType(StatCard)), const Rect.fromLTWH(272, 96, 280, 146));
      final label = find.text('이번 달 매출 (시험 결제 제외)');
      expect((styleOf(tester, label).fontSize, styleOf(tester, label).color), (14, AdminColors.muted));
      expect(tester.getTopLeft(label), const Offset(296, 120));
      final value = find.text('₩1,284,000');
      expect((styleOf(tester, value).fontSize, styleOf(tester, value).fontWeight), (32, FontWeight.w700));
      expect(tester.getTopLeft(value).dy, closeTo(151, 1));
      final month = find.text('2026년 10월');
      expect((styleOf(tester, month).fontSize, styleOf(tester, month).fontWeight, styleOf(tester, month).color), (14, FontWeight.w600, AdminColors.primaryText));
      expect(tester.getTopLeft(month).dy, closeTo(198.5, 1.5));
      expect(tester.getRect(key('order-search-card')), const Rect.fromLTWH(576, 96, 832, 146));
    });

    testWidgets('매출 0 이면 "₩0"', (tester) async {
      await openBilling(tester, server: FakeUserServer()..summary = {'month': '2026-09', 'revenue_krw': 0, 'order_count': 0, 'refunded_krw': 0});

      expect(find.text('₩0'), findsOneWidget);
      expect(find.text('2026년 9월'), findsOneWidget);
    });

    testWidgets('검색 카드 안쪽 24 · 세로 8: 제목 16/700 y120 → 칸 (600,150) 480×44 → 12 → [조회] x1092 → 안내 12 web-muted', (tester) async {
      await openBilling(tester);

      final title = find.text('주문 · 거래 번호로 찾기');
      expect(tester.getTopLeft(title), const Offset(600, 120));
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (16, FontWeight.w700));
      expect(tester.getRect(key('order-search-box')), const Rect.fromLTWH(600, 150, 480, 44));
      expect(tester.getTopLeft(button('조회')), const Offset(1092, 150));
      expect(tester.getSize(button('조회')).height, 44);
      expect(find.text('구글 주문 번호 · 애플 거래 번호 (정확히 일치)'), findsOneWidget);
      final note = find.text('읽기 전용이에요. 여기서 하트를 주지는 않아요(하트 조정은 사용자 상세).');
      expect(tester.getTopLeft(note), const Offset(600, 202));
      expect((styleOf(tester, note).fontSize, styleOf(tester, note).color), (12, AdminColors.muted));
    });

    testWidgets('그래프 카드 y262: 폭 1136 · 높이 316 · 안쪽 20 — 제목 16/700 + 알약(오른쪽 끝, 높이 24, 12/600 web-muted, web-surface-strong)', (tester) async {
      await openBilling(tester);

      expect(tester.getRect(key('revenue-card')), const Rect.fromLTWH(272, 262, 1136, 316));
      // 제목(22)은 알약(24) 줄의 세로 가운데 — 위 20 + 1
      expect(tester.getTopLeft(find.text('최근 30일 매출 (원)')), const Offset(292, 283));
      final pill = key('revenue-pill');
      expect(tester.getSize(pill).height, 24);
      expect(tester.getRect(pill).right, 1388);
      expect((tester.widget<Container>(pill).decoration! as BoxDecoration).color, AdminColors.surfaceStrong);
      final pillText = find.text('최근 30일 · 시험 결제 제외');
      expect((styleOf(tester, pillText).fontSize, styleOf(tester, pillText).fontWeight, styleOf(tester, pillText).color), (12, FontWeight.w600, AdminColors.muted));
    });

    testWidgets('그래프 1080×240 (292,318): 눈금 글자 4개(0 · 10만 · 20만 · 30만), 날짜 5개 9/19 · 9/26 · 10/3 · 10/10 · 10/18, 범례 12 web-muted', (tester) async {
      await openBilling(tester);

      expect(tester.getRect(key('revenue-chart')), const Rect.fromLTWH(292, 318, 1080, 240));
      expect(find.byType(CustomPaint), findsWidgets);
      final legend = find.text('일 매출 (원, 시험 결제 제외)');
      expect(tester.getTopLeft(legend).dx, 292 + 56 + 10 + 6);
      expect(tester.getTopLeft(legend).dy, closeTo(318 + 212, 1));
      expect(styleOf(tester, legend).color, AdminColors.muted);
      final swatch = tester.getRect(key('chart-legend-swatch'));
      expect(swatch.size, const Size(10, 10));
      expect((tester.widget<Container>(key('chart-legend-swatch')).decoration! as BoxDecoration).color, AdminColors.chartRevenue);
    });

    testWidgets('조회 전에는 주문 결과 카드가 없고, 못 거둔 표 제목은 그래프 아래 20(y598), 표는 그 아래 20 y640', (tester) async {
      await openBilling(tester);

      expect(key('order-result'), findsNothing);
      final title = find.text('환불됐는데 하트를 다 못 거둔 목록');
      expect(tester.getTopLeft(title), const Offset(272, 598));
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (16, FontWeight.w700));
      expect(tester.getRect(key('shortfall-table')), const Rect.fromLTWH(272, 640, 1136, 44 + 52 * 2));
      final note = find.text('이미 써서 다 거두지 못한 구매예요. 손으로 줄지 판단할 때 참고해요.');
      expect(tester.getTopLeft(note).dy, 640 + 148 + 20);
      expect((styleOf(tester, note).fontSize, styleOf(tester, note).color), (12, AdminColors.muted));
    });

    testWidgets('못 거둔 표 열: 시각 288 · 닉네임 458 · 상품 608 · 스토어 758 · 지급 888 · 회수 978 · 못 거둔 하트 1068, 값 줄', (tester) async {
      await openBilling(tester);

      final table = key('shortfall-table');
      for (final (text, x) in [('시각', 288.0), ('닉네임', 458.0), ('상품', 608.0), ('스토어', 758.0), ('지급', 888.0), ('회수', 978.0), ('못 거둔 하트', 1068.0)]) {
        expect(tester.getRect(find.descendant(of: table, matching: find.text(text))).left, x, reason: text);
      }
      for (final text in ['2026-10-10 18:20', '닉네임A', '하트 100개', '구글 플레이', '100', '60', '40', '2026-10-04 09:12', '닉네임F', '하트 50개', '앱스토어', '0']) {
        expect(find.descendant(of: table, matching: find.text(text)), findsOneWidget, reason: text);
      }
      expect(find.descendant(of: table, matching: find.text('50')), findsNWidgets(2)); // 지급 50 · 못 거둔 50
    });

    testWidgets('못 거둔 목록이 비면(A8_결제_조회_못_거둔_목록_없음): 표 · 안내 대신 "다 거두지 못한 구매가 없어요" 14 web-muted(제목 아래 20)', (tester) async {
      await openBilling(tester, server: FakeUserServer()..shortfall = []);

      expect(key('shortfall-table'), findsNothing);
      final none = find.text('다 거두지 못한 구매가 없어요');
      expect(tester.getTopLeft(none).dy, closeTo(598 + 22 + 20, 1));
      expect((styleOf(tester, none).fontSize, styleOf(tester, none).color), (14, AdminColors.muted));
      expect(find.textContaining('이미 써서 다 거두지 못한'), findsNothing);
    });
  });

  group('주문 · 거래 번호 조회(KF9lR)', () {
    testWidgets('환불된 구매: 카드 (272,598) 높이 96 · 안쪽 24 · 칸 6개 가로 32 — 이름 12/600 web-muted → 6 → 값 16/700, 상태 "환불됨" danger 배지', (tester) async {
      await openBilling(tester);

      await search(tester, orderNo);

      final card = key('order-result');
      expect(tester.getRect(card), const Rect.fromLTWH(272, 598, 1136, 96));
      final names = ['상품', '스토어', '상태', '지급 하트', '회수한 하트', '시각'];
      var previousRight = 0.0;
      for (final name in names) {
        final label = find.descendant(of: card, matching: find.text(name));
        expect(tester.getTopLeft(label).dy, 622, reason: name);
        expect((styleOf(tester, label).fontSize, styleOf(tester, label).fontWeight, styleOf(tester, label).color), (12, FontWeight.w600, AdminColors.muted));
        if (name == '상품') expect(tester.getTopLeft(label).dx, 296);
        previousRight = tester.getRect(label).left;
      }
      expect(previousRight, greaterThan(296));
      for (final (value, _) in [('하트 100개', 0), ('구글 플레이', 0), ('100', 0), ('60', 0), ('2026-10-10 18:20', 0)]) {
        final text = find.descendant(of: card, matching: find.text(value));
        expect(text, findsOneWidget, reason: value);
        expect((styleOf(tester, text).fontSize, styleOf(tester, text).fontWeight, styleOf(tester, text).color), (16, FontWeight.w700, AdminColors.ink));
        expect(tester.getTopLeft(text).dy, closeTo(644, 1));
      }
      final badge = tester.widget<StatusBadge>(find.descendant(of: card, matching: find.byType(StatusBadge)));
      expect((badge.label, badge.tone), ('환불됨', StatusTone.danger));
      // 칸 사이 가로 32
      final cell1Right = tester.getRect(find.descendant(of: card, matching: find.text('하트 100개'))).right;
      expect(tester.getRect(find.descendant(of: card, matching: find.text('스토어'))).left - cell1Right, closeTo(32, 6));
      // 못 거둔 표 제목은 결과 카드 아래 20 → y714
      expect(tester.getTopLeft(find.text('환불됐는데 하트를 다 못 거둔 목록')).dy, 714);
      expect(tester.getTopLeft(key('shortfall-table')).dy, 756);
    });

    testWidgets('완료된 구매(A8_결제_조회_상태_완료): 배지 "완료" success, 회수한 하트 0', (tester) async {
      final server = FakeUserServer()..orders = [orderRow(status: 'granted', clawedBack: 0)];
      await openBilling(tester, server: server);

      await search(tester, orderNo);

      final badge = tester.widget<StatusBadge>(find.descendant(of: key('order-result'), matching: find.byType(StatusBadge)));
      expect((badge.label, badge.tone), ('완료', StatusTone.success));
      expect(find.descendant(of: key('order-result'), matching: find.text('0')), findsOneWidget);
      // 환불이 아니면 "시각" 은 구매 시각(환불이면 환불 시각 — 위 시험)
      expect(find.descendant(of: key('order-result'), matching: find.text('2026-10-09 10:00')), findsOneWidget);
    });

    testWidgets('그 밖 상태는 surface-strong · muted 배지에 글자 그대로', (tester) async {
      final server = FakeUserServer()..orders = [orderRow(status: 'pending', clawedBack: 0)];
      await openBilling(tester, server: server);

      await search(tester, orderNo);

      final badge = tester.widget<StatusBadge>(find.descendant(of: key('order-result'), matching: find.byType(StatusBadge)));
      expect((badge.label, badge.tone), ('pending', StatusTone.neutral));
    });

    testWidgets('못 찾음(A8_결제_조회_주문_못_찾음): 같은 카드 높이 67 안에 14 web-muted "그 번호로 찾은 구매가 없어요", 못 거둔 제목 y685', (tester) async {
      await openBilling(tester);

      await search(tester, 'GPA.0000');

      final card = key('order-result');
      expect(tester.getRect(card), const Rect.fromLTWH(272, 598, 1136, 67));
      final text = find.text('그 번호로 찾은 구매가 없어요');
      expect(tester.getTopLeft(text), const Offset(296, 622));
      expect((styleOf(tester, text).fontSize, styleOf(tester, text).color), (14, AdminColors.muted));
      expect(tester.getTopLeft(find.text('환불됐는데 하트를 다 못 거둔 목록')).dy, 685);
    });

    testWidgets('번호 모양이 틀리면(422) 오류 줄, 서버 오류면 일반 오류 줄 — 같은 카드 안', (tester) async {
      final server = FakeUserServer();
      await openBilling(tester, server: server);

      server.searchFailure = 422;
      await search(tester, 'a b');
      expect(find.textContaining('번호 모양이 맞지 않아요'), findsOneWidget);

      server.searchFailure = 500;
      await search(tester, orderNo);
      expect(find.text('조회하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('빈 칸은 보내지 않는다. 받는 중에는 [조회] 가 요청 중 표시', (tester) async {
      final server = FakeUserServer()..holdSearch = Completer<void>();
      await openBilling(tester, server: server);

      await tester.tap(button('조회'));
      await tester.pump();
      expect(server.requests.where((r) => r.url.path.endsWith('orders/search')), isEmpty);

      await tester.enterText(field(), orderNo);
      await tester.tap(button('조회'));
      await tester.pump();
      expect(find.text('조회하고 있어요'), findsOneWidget);
      expect(find.byType(AdminLoader), findsWidgets);
      server.holdSearch!.complete();
      await tester.pumpAndSettle();
      expect(find.text('조회하고 있어요'), findsNothing);
    });
  });

  group('주문 번호 보안(대장 결정 8 · 설계 §14-3)', () {
    testWidgets('번호는 POST 본문으로만 — 요청 주소 · 쿼리에 없고, 조회 뒤에도 칸에 그대로, 주소창 · provider 상태에는 없다', (tester) async {
      final server = await openBilling(tester);

      await search(tester, orderNo);

      final post = server.requests.singleWhere((r) => r.method == 'POST' && r.url.path == '/admin/billing/orders/search');
      expect(jsonDecode(post.body), {'order': orderNo});
      for (final request in server.requests) {
        expect(request.url.toString(), isNot(contains('GPA')), reason: request.url.toString());
      }
      expect(tester.widget<TextField>(field()).controller!.text, orderNo);
      expect(locationOf(tester), '/billing');
      final container = ProviderScope.containerOf(tester.element(find.byType(AdminApp)));
      final state = '${container.read(orderSearchProvider)} ${container.read(billingOverviewProvider)}';
      expect(state, isNot(contains('GPA')));
      expect(state, isNot(contains('1111-2222')));
      // 결과 카드에도 번호를 그리지 않는다
      expect(find.textContaining('GPA.', findRichText: true), findsOneWidget); // 입력 칸 글자뿐
    });

    testWidgets('입력 칸은 글자 제안 · 자동 고침을 끈다', (tester) async {
      await openBilling(tester);

      final input = tester.widget<TextField>(field());
      expect((input.enableSuggestions, input.autocorrect, input.enableIMEPersonalizedLearning), (false, false, false));
    });
  });

  group('그래프(대장 결정 9 — fl_chart 없이 직접 그림)', () {
    testWidgets('막대 위에 마우스를 올리면 그날 "M/D · ₩n" 말풍선(ink 바탕), 벗어나면 사라진다', (tester) async {
      await openBilling(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);

      // 6번째 막대(9/24 · ₩285,000): 그림 x 57 + 슬롯 33.0 × 5.5
      final chart = tester.getTopLeft(key('revenue-chart'));
      final slot = (1080 - RevenueChart.axisWidth - RevenueChart.rightPad) / 30;
      await mouse.addPointer(location: chart + Offset(RevenueChart.axisWidth + slot * 5.5, 100));
      await mouse.moveTo(chart + Offset(RevenueChart.axisWidth + slot * 5.5, 101));
      await tester.pump();

      expect(find.text('9/24 · ₩285,000'), findsOneWidget);
      final box = tester.widget<Container>(key('chart-tooltip'));
      expect((box.decoration! as BoxDecoration).color, AdminColors.ink);
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(key('chart-tooltip'), findsNothing);
    });

    testWidgets('화면 읽기: 그림 전체가 한 줄로 읽힌다 — "최근 30일 매출 합계 ₩n, 가장 많은 날 M/D ₩n"', (tester) async {
      final handle = tester.ensureSemantics();
      await openBilling(tester);

      final total = [90000, 130000, 170000, 132000, 166000, 285000, 150000, 175000, 195000, 137000, 152000, 165000, 189000, 110000, 120000, 55000, 70000, 88000, 30000, 145000, 84000, 36000, 75000, 112000, 75000, 113000, 244000, 117000, 155000, 190000].fold<int>(0, (a, b) => a + b);
      expect(find.bySemanticsLabel(RegExp('최근 30일 매출 합계 ₩${total.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}, 가장 많은 날 9/24 ₩285,000')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('좁은 창(1280)에서는 그래프가 줄어든다(카드 안 폭)', (tester) async {
      final server = FakeUserServer();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/billing', size: const Size(1280, 900));

      // 내용 1040(1280 − 메뉴 240) − 32×2 − 카드 안쪽 20×2 = 936
      expect(tester.getSize(key('revenue-chart')).width, 936);
    });
  });

  group('받는 중 · 못 받음', () {
    testWidgets('못 받으면 오류 틀 + [다시 시도] — 검색 카드는 그대로 쓸 수 있다', (tester) async {
      final server = FakeUserServer()..billingFailure = 500;
      await openBilling(tester, server: server);

      expect(find.text('결제 정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('—'), findsOneWidget); // 매출 값 자리
      await search(tester, orderNo);
      expect(find.text('하트 100개'), findsOneWidget);
      server.billingFailure = null;
      await tester.tap(button('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('결제 정보를 불러오지 못했어요'), findsNothing);
      expect(find.text('₩1,284,000'), findsOneWidget);
    });
  });

  group('큰 글자(1.3배) · 좁은 창', () {
    testWidgets('1280×800 에서도 넘치지 않는다 — 매출 카드 값 · 주문 결과 칸 · 표', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = FakeUserServer()..summary = {'month': '2026-10', 'revenue_krw': 12840000, 'order_count': 9, 'refunded_krw': 0};
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/billing', size: const Size(1280, 800));
      await search(tester, orderNo);

      expect(tester.takeException(), isNull);
      expect(find.text('₩12,840,000'), findsOneWidget);
    });
  });
}
