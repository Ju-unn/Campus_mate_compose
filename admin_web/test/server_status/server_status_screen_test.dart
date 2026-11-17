import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/platform/confirm_store.dart';
import 'package:campus_mate_admin/app.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/shell/nav_badges.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/count_badge.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../helpers/fakes.dart';
import '../helpers/server_status_fakes.dart';

/// A11 서버 상태(pen YAdMU · 이상 없음 siTuo). 값은 .superpowers/sdd/2026-11-17-admin-server-status/pen-values.md.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  late Map<String, String> stored;
  late List<String> opened;

  Future<FakeStatusServer> open(WidgetTester tester, {FakeStatusServer? server, bool settle = true, Map<String, String>? store, ConfirmStore? confirmStore, FakeAdminAuth? auth}) async {
    final fake = server ?? FakeStatusServer();
    stored = store ?? {};
    opened = [];
    await pumpAdminApp(
      tester,
      auth: auth ?? FakeAdminAuth(mfa: aal2),
      api: fake.api(),
      initialPath: '/server-status',
      settle: settle,
      overrides: [
        confirmStoreProvider.overrideWithValue(confirmStore ?? memoryStore(stored)),
        linkOpenerProvider.overrideWithValue(opened.add),
      ],
    );
    return fake;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder serverBadgeText() => find.descendant(of: key('nav-serverStatus'), matching: find.descendant(of: find.byType(CountBadge), matching: find.byType(Text)));
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;

  testWidgets('renders cards and anomalies', (tester) async {
    await open(tester);

    expect(find.text('서버 상태'), findsWidgets); // TopBar 제목 + 메뉴
    expect(find.text('마지막 갱신 22:41'), findsOneWidget);
    for (final (label, value, footer) in [
      ('요청 수', '42/분', '최근 15분 평균'),
      ('오류 비율', '0.2%', '최근 15분 · 5% 넘으면 이상'),
      ('응답 속도', '0.16초', '100건 중 95번째 1.2초'),
      ('켜진 서버', '1대', '지금 일하는 서버'),
    ]) {
      final card = find.widgetWithText(StatCard, label);
      expect(find.descendant(of: card, matching: find.text(value)), findsOneWidget, reason: label);
      expect(find.descendant(of: card, matching: find.text(footer)), findsOneWidget, reason: label);
    }
    expect(find.text('이상 목록'), findsOneWidget);
    expect(find.text('확인하면 왼쪽 메뉴의 숫자가 사라져요'), findsOneWidget);
    expect(find.text('오류 비율 6% (5분)'), findsOneWidget);
    expect(find.text('응답이 느려요 (보통 1.5초)'), findsOneWidget);
    expect(find.text('서버 오류 3건 (5분)'), findsOneWidget);
    expect([for (final t in ['21:35', '21:00', '20:05']) tester.getTopLeft(find.text(t).first).dy], orderedEquals([
      tester.getTopLeft(find.text('오류 비율 6% (5분)')).dy,
      tester.getTopLeft(find.text('응답이 느려요 (보통 1.5초)')).dy,
      tester.getTopLeft(find.text('서버 오류 3건 (5분)')).dy,
    ]));
    expect(find.text('요청 수 (5분마다)'), findsOneWidget);
    expect(find.text('서버 오류 (5분마다)'), findsOneWidget);
    expect(find.text('최근 3시간'), findsNWidgets(2));
    expect(find.text('이상 기준 3건'), findsOneWidget);
    expect(find.text('앱 꺼짐은 Firebase Crashlytics 에서 보기 →'), findsOneWidget);
    expect(serverBadgeText(), findsOneWidget);
  });

  testWidgets('pen 배치(YAdMU): 패널 (272,96) 1136×146 → 20 → 카드 4장 272×146 사이 16 → 20 → 그래프 카드 560×316 → 20 → 링크', (tester) async {
    // pen 처럼 이상 2줄
    await open(tester, server: FakeStatusServer()..status = serverStatusJson(anomalies: defaultAnomalies().take(2).toList()));

    expect(tester.getRect(key('anomaly-panel')), const Rect.fromLTWH(272, 96, 1136, 146));
    final cards = find.byType(StatCard);
    expect(cards, findsNWidgets(4));
    expect([for (var i = 0; i < 4; i++) tester.getRect(cards.at(i))], const [
      Rect.fromLTWH(272, 262, 272, 146),
      Rect.fromLTWH(560, 262, 272, 146),
      Rect.fromLTWH(848, 262, 272, 146),
      Rect.fromLTWH(1136, 262, 272, 146),
    ]);
    expect(tester.getRect(key('requests-card')), const Rect.fromLTWH(272, 428, 560, 316));
    expect(tester.getRect(key('errors-card')), const Rect.fromLTWH(848, 428, 560, 316));
    expect(tester.getSize(key('chart-requests')), const Size(520, 240));
    expect(tester.getTopLeft(find.text('앱 꺼짐은 Firebase Crashlytics 에서 보기 →')), const Offset(272, 764));
    final link = styleOf(tester, find.text('앱 꺼짐은 Firebase Crashlytics 에서 보기 →'));
    expect((link.fontSize, link.fontWeight, link.color), (12, FontWeight.w600, AdminColors.primaryText));
  });

  testWidgets('pen 값: 패널 머리(경고 20 danger · 제목 16/700 · 안내 12 muted · [확인] 36) · 이상 줄(점 8 · 시각 14/600 muted 폭 44 · 설명 14 ink, 줄 사이 12)', (tester) async {
    await open(tester);

    final panel = tester.getRect(key('anomaly-panel'));
    final icon = tester.widget<Icon>(find.byIcon(LucideIcons.triangleAlert));
    expect((icon.size, icon.color), (20, AdminColors.danger));
    expect(tester.getTopLeft(find.byIcon(LucideIcons.triangleAlert)) - panel.topLeft, const Offset(20, 30));
    final title = styleOf(tester, find.text('이상 목록'));
    expect((title.fontSize, title.fontWeight, title.color), (16, FontWeight.w700, AdminColors.ink));
    expect(tester.getTopLeft(find.text('이상 목록')) - panel.topLeft, const Offset(52, 20));
    expect(tester.getTopLeft(find.text('확인하면 왼쪽 메뉴의 숫자가 사라져요')) - panel.topLeft, const Offset(52, 44));
    final confirm = tester.getRect(find.widgetWithText(AdminButton, '확인'));
    expect(confirm.height, 36);
    expect(panel.right - confirm.right, 20);
    expect(confirm.top - panel.top, 22);
    expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '확인')).variant, AdminButtonVariant.primary);

    final time = find.text('21:35');
    expect(tester.getRect(time), Rect.fromLTWH(panel.left + 40, panel.top + 76, 44, 19));
    expect((styleOf(tester, time).fontSize, styleOf(tester, time).fontWeight, styleOf(tester, time).color), (14, FontWeight.w600, AdminColors.muted));
    final message = find.text('오류 비율 6% (5분)');
    expect(tester.getTopLeft(message), Offset(panel.left + 96, panel.top + 76));
    expect((styleOf(tester, message).fontSize, styleOf(tester, message).color), (14, AdminColors.ink));
    // "21:00" 은 그래프 눈금에도 있다 — 화면 위쪽(패널)의 것
    expect(tester.getTopLeft(find.text('21:00').first).dy - tester.getTopLeft(time).dy, 31);
    final dot = tester.getRect(key('anomaly-dot-0'));
    expect(dot, Rect.fromLTWH(panel.left + 20, panel.top + 82, 8, 8));
  });

  testWidgets('TopBar: 제목 → 마지막 갱신 14 muted → 12 → [새로고침] 보조 36 → 16 → 관리자 메일', (tester) async {
    await open(tester);

    final updated = find.text('마지막 갱신 22:41');
    expect((styleOf(tester, updated).fontSize, styleOf(tester, updated).color), (14, AdminColors.muted));
    final refresh = tester.getRect(find.widgetWithText(AdminButton, '새로고침'));
    expect(refresh.height, 36);
    expect(refresh.left - tester.getRect(updated).right, 12);
    expect(tester.getTopLeft(find.text('admin@example.com')).dx - refresh.right, 16);
    expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '새로고침')).variant, AdminButtonVariant.secondary);
  });

  testWidgets('confirm clears server badge', (tester) async {
    await open(tester);
    expect(tester.widget<Text>(serverBadgeText()).data, '3');

    await tester.tap(find.widgetWithText(AdminButton, '확인'));
    await tester.pumpAndSettle();

    expect(serverBadgeText(), findsNothing);
    expect((jsonDecode(stored[ConfirmStore.key]!) as List).toSet(), {for (final row in defaultAnomalies()) anomalyKeyOf(row)});
    // 확인한 줄은 흐리게(설명 web-muted · 점 web-disabled) — 목록에는 남는다
    expect(styleOf(tester, find.text('오류 비율 6% (5분)')).color, AdminColors.muted);
  });

  testWidgets('22:40 칸 이상을 확인한 뒤 같은 칸에 새 종류가 생기면 배지 1 — 확인한 줄만 흐리게', (tester) async {
    final at = DateTime.utc(2026, 11, 17, 13, 40); // 22:40 한국, 아직 진행 중인 칸
    final errors = anomalyRow(at, 'errors', 3);
    final server = FakeStatusServer()..status = serverStatusJson(anomalies: [errors]);
    await open(tester, server: server);

    await tester.tap(find.widgetWithText(AdminButton, '확인'));
    await tester.pumpAndSettle();
    expect(serverBadgeText(), findsNothing);

    server.status = serverStatusJson(anomalies: [anomalyRow(at, 'error_rate', 0.08), errors]);
    await tester.tap(find.widgetWithText(AdminButton, '새로고침'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(serverBadgeText()).data, '1');
    expect(styleOf(tester, find.text('오류 비율 8% (5분)')).color, AdminColors.ink);
    expect(styleOf(tester, find.text('서버 오류 3건 (5분)')).color, AdminColors.muted);
  });

  testWidgets('확인할 때 지금 창(3시간) 밖 열쇠는 버리고, 창 안의 앞 열쇠는 남긴다', (tester) async {
    final old = '${DateTime.utc(2026, 11, 17, 5).toIso8601String()}|errors'; // 창 시작(10:45 UTC)보다 앞
    final kept = '${DateTime.utc(2026, 11, 17, 11, 30).toIso8601String()}|slow'; // 창 안, 지금 목록엔 없음
    await open(tester, store: {ConfirmStore.key: jsonEncode([old, kept, 'garbage'])});

    await tester.tap(find.widgetWithText(AdminButton, '확인'));
    await tester.pumpAndSettle();

    expect((jsonDecode(stored[ConfirmStore.key]!) as List).toSet(), {kept, for (final row in defaultAnomalies()) anomalyKeyOf(row)});
  });

  testWidgets('저장소가 던져도 [확인]은 깨지지 않고 이 창에서는 배지가 사라진다', (tester) async {
    await open(tester, confirmStore: throwingStore());
    expect(tester.widget<Text>(serverBadgeText()).data, '3');

    await tester.tap(find.widgetWithText(AdminButton, '확인'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(serverBadgeText(), findsNothing);
  });

  testWidgets('로그아웃하면 서버 상태 · 대기 건수 · 확인 상태를 비우고, 다시 들어오면 새로 읽는다', (tester) async {
    final auth = FakeAdminAuth(mfa: aal2);
    final server = FakeStatusServer()..counts = {'heart_tasks': 4, 'graduates': 0, 'reports': 0, 'inquiries': 0};
    await open(tester, server: server, auth: auth);
    expect(tester.widget<Text>(serverBadgeText()).data, '3');

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(AdminApp)));
    expect(container.read(serverStatusProvider).status, isNull);
    expect(container.read(pendingCountsProvider).value, isNull);
    expect(find.byType(CountBadge), findsNothing);

    // 다른 관리자가 같은 브라우저로 들어온다 — 이상 없음 · 대기 0
    server
      ..status = serverStatusJson(anomalies: [])
      ..counts = {'heart_tasks': 0, 'graduates': 0, 'reports': 0, 'inquiries': 0};
    auth.session = true;
    auth.emitChange();
    await tester.pumpAndSettle();

    expect(server.calls('/admin/server-status'), 2);
    expect(server.calls('/admin/pending-counts'), greaterThanOrEqualTo(2));
    expect(find.descendant(of: find.byType(CountBadge), matching: find.byType(Text)), findsNothing);
  });

  testWidgets('refresh button reloads both', (tester) async {
    final server = await open(tester);
    expect((server.calls('/admin/server-status'), server.calls('/admin/pending-counts')), (1, 1));

    server.status = serverStatusJson(anomalies: []);
    await tester.tap(find.widgetWithText(AdminButton, '새로고침'));
    await tester.pumpAndSettle();

    expect((server.calls('/admin/server-status'), server.calls('/admin/pending-counts')), (2, 2));
    expect(find.text('최근 3시간 이상 없음'), findsOneWidget);
  });

  testWidgets('새로고침 중에는 숫자를 그대로 두고 [새로고침] 이 도는 아이콘으로 막힌다', (tester) async {
    final server = await open(tester);
    server.holdStatus = Completer<void>();

    await tester.tap(find.widgetWithText(AdminButton, '새로고침'));
    await tester.pump();

    expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '새로고침')).loading, isTrue);
    expect(find.text('42/분'), findsOneWidget);
    await tester.tap(find.widgetWithText(AdminButton, '새로고침'));
    await tester.pump();
    expect(server.calls('/admin/server-status'), 2, reason: '도는 동안 다시 눌러도 한 번만');

    server.holdStatus!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<AdminButton>(find.widgetWithText(AdminButton, '새로고침')).loading, isFalse);
  });

  testWidgets('server status error shows retry', (tester) async {
    final server = FakeStatusServer()..statusFailure = 503;
    await open(tester, server: server);

    expect(find.text('서버 상태를 불러오지 못했어요'), findsOneWidget);
    expect(find.widgetWithText(AdminButton, '다시 시도'), findsOneWidget);
    expect(serverBadgeText(), findsNothing);
    expect(find.textContaining('마지막 갱신'), findsNothing);

    server.statusFailure = null;
    await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('42/분'), findsOneWidget);
  });

  testWidgets('처음 불러오는 중에는 불러오는 중 줄', (tester) async {
    final server = FakeStatusServer()..holdStatus = Completer<void>();
    await open(tester, server: server, settle: false);
    await tester.pump();
    await tester.pump();

    expect(find.text('서버 상태를 불러오고 있어요'), findsOneWidget);
    server.holdStatus!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('empty window shows no-anomaly text', (tester) async {
    final server = FakeStatusServer()..status = serverStatusJson(anomalies: []);
    await open(tester, server: server);

    expect(find.text('최근 3시간 이상 없음'), findsOneWidget);
    expect(find.widgetWithText(AdminButton, '확인'), findsNothing);
    final icon = tester.widget<Icon>(find.byIcon(LucideIcons.circleCheck));
    expect((icon.size, icon.color), (20, AdminColors.success));
    expect(tester.getSize(key('anomaly-panel')).height, 97); // pen JByhz
  });

  testWidgets('이상이 10줄 넘으면 최신 10줄 + "외 N건"', (tester) async {
    final rows = [for (var i = 0; i < 12; i++) anomalyRow(DateTime.utc(2026, 11, 17, 13, 40).subtract(Duration(minutes: 5 * i)), 'errors', 3 + i)];
    final server = FakeStatusServer()..status = serverStatusJson(anomalies: rows);
    await open(tester, server: server);

    expect(find.textContaining('(5분)'), findsNWidgets(10));
    expect(find.text('서버 오류 3건 (5분)'), findsOneWidget); // 최신
    expect(find.text('서버 오류 14건 (5분)'), findsNothing);
    expect(find.text('외 2건'), findsOneWidget);
  });

  testWidgets('그래프: 30분마다 HH:mm 눈금, 요청 수는 범례 없음', (tester) async {
    await open(tester);

    for (final label in ['20:00', '20:30', '21:00', '21:30', '22:00', '22:30']) {
      expect(find.descendant(of: key('chart-requests'), matching: find.text(label)), findsOneWidget, reason: label);
      expect(find.descendant(of: key('chart-errors'), matching: find.text(label)), findsOneWidget, reason: label);
    }
    expect(find.descendant(of: key('chart-requests'), matching: find.text('300')), findsOneWidget);
    expect(find.descendant(of: key('chart-errors'), matching: find.text('10')), findsOneWidget);
    expect(find.descendant(of: key('chart-requests'), matching: find.text('이상 기준 3건')), findsNothing);
    // pen 첫 눈금 "20:00" 은 넷째 칸 가운데(x 75+14.5 → 칸 3 가운데 44 + 460/36 × 3.5)
    final chart = tester.getTopLeft(key('chart-requests'));
    expect(tester.getCenter(find.descendant(of: key('chart-requests'), matching: find.text('20:00'))).dx - chart.dx, closeTo(44 + 460 / 36 * 3.5, 0.5));
  });

  testWidgets('큰 글자(1.3배) · 좁은 창 1280×800 에서도 넘치지 않는다 — TopBar · 패널 · 카드 · 메뉴 배지', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final server = FakeStatusServer()..counts = {'heart_tasks': 120, 'graduates': 1, 'reports': 3, 'inquiries': 1};
    stored = {};
    await pumpAdminApp(
      tester,
      auth: FakeAdminAuth(mfa: aal2),
      api: server.api(),
      initialPath: '/server-status',
      size: const Size(1280, 800),
      overrides: [confirmStoreProvider.overrideWithValue(memoryStore(stored))],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('42/분'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('Crashlytics 링크는 콘솔 첫 화면을 새로 연다(프로젝트 경로 없음)', (tester) async {
    await open(tester);

    await tester.tap(find.text('앱 꺼짐은 Firebase Crashlytics 에서 보기 →'));
    await tester.pump();

    expect(opened, ['https://console.firebase.google.com/']);
  });
}
