import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../helpers/fakes.dart';
import '../helpers/stats_fakes.dart';

/// A2 홈(pen kud26, 1440×1400 — 값표 w4_pen_values + PNG A2_홈 측정). 서버 계약은 D4(stats · health).
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<FakeStatsServer> openHome(WidgetTester tester, {FakeStatsServer? server, bool settle = true}) async {
    final fake = server ?? FakeStatsServer();
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: fake.api(), size: const Size(1440, 1400), settle: settle);
    return fake;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;

  group('pen 배치(kud26)', () {
    testWidgets('TopBar "홈" · 인사말 "오늘 처리할 일" (272,96) 20/700 ink', (tester) async {
      await openHome(tester);

      final greeting = find.text('오늘 처리할 일');
      expect(tester.getTopLeft(greeting), const Offset(272, 96));
      expect((styleOf(tester, greeting).fontSize, styleOf(tester, greeting).fontWeight, styleOf(tester, greeting).color), (20, FontWeight.w700, AdminColors.ink));
    });

    testWidgets('통계 카드 3장 y147: 280×146, 사이 24 — 검수 대기 12 · 열린 신고 5 · 오늘 가입 38, 링크 14/600 primary-text', (tester) async {
      await openHome(tester);

      final cards = find.byType(StatCard);
      expect(cards, findsNWidgets(3));
      expect([for (var i = 0; i < 3; i++) tester.getRect(cards.at(i))], const [
        Rect.fromLTWH(272, 147, 280, 146),
        Rect.fromLTWH(576, 147, 280, 146),
        Rect.fromLTWH(880, 147, 280, 146),
      ]);
      expect(tester.getTopLeft(find.text('검수 대기')), const Offset(296, 171));
      for (final (label, value) in [('검수 대기', '12'), ('열린 신고', '5'), ('오늘 가입', '38')]) {
        final card = find.widgetWithText(StatCard, label);
        expect(find.descendant(of: card, matching: find.text(value)), findsOneWidget, reason: label);
      }
      final value = find.text('12');
      expect((styleOf(tester, value).fontSize, styleOf(tester, value).fontWeight), (32, FontWeight.w700));
      expect(tester.getTopLeft(value).dy, closeTo(202, 1));
      final link = find.text('사용자 보기 →');
      expect((styleOf(tester, link).fontSize, styleOf(tester, link).fontWeight, styleOf(tester, link).color), (14, FontWeight.w600, AdminColors.primaryText));
      expect(tester.getTopLeft(link).dy, closeTo(248, 1));
      expect(find.text('열기 →'), findsNWidgets(2));
    });

    testWidgets('차트 카드: 줄 1 y317 — 가입 추이 (272,317) · 접수량 (848,317) 560×316 사이 16, 줄 2 y657 — 학교별 활성 인원', (tester) async {
      await openHome(tester);

      expect(tester.getRect(key('signup-card')), const Rect.fromLTWH(272, 317, 560, 316));
      expect(tester.getRect(key('intake-card')), const Rect.fromLTWH(848, 317, 560, 316));
      expect(tester.getRect(key('schools-card')), const Rect.fromLTWH(272, 657, 560, 316));
      expect(find.text('가입 추이'), findsOneWidget);
      expect(find.text('접수량'), findsOneWidget);
      expect(find.text('학교별 활성 인원'), findsOneWidget);
      expect([find.text('최근 30일'), find.text('최근 14일'), find.text('현재')].map((f) => f.evaluate().length), [1, 1, 1]);
    });

    testWidgets('그래프 520×240: 가입 추이 (292,373) · 접수량 (868,373) · 학교별 (292,713)', (tester) async {
      await openHome(tester);

      expect(tester.getRect(key('chart-signups')), const Rect.fromLTWH(292, 373, 520, 240));
      expect(tester.getRect(key('chart-intake')), const Rect.fromLTWH(868, 373, 520, 240));
      expect(tester.getRect(key('chart-schools')), const Rect.fromLTWH(292, 713, 520, 240));
    });

    testWidgets('접수량 막대는 같은 30일 응답의 마지막 14일(10/5 ~ 10/18)', (tester) async {
      await openHome(tester);

      for (final date in ['10/5', '10/9', '10/13']) {
        expect(find.descendant(of: key('chart-intake'), matching: find.text(date)), findsOneWidget, reason: date);
      }
      expect(find.descendant(of: key('chart-intake'), matching: find.text('9/19')), findsNothing);
      // 가입 추이는 30일 전체
      expect(find.descendant(of: key('chart-signups'), matching: find.text('9/19')), findsOneWidget);
    });

    testWidgets('학교별 현황: 제목 (848,657) 16/700 → 표 (848,691) 560 × (44 + 52 × 학교 수), 열 학교 170 · 카드 오픈 시각 180 · 남 활성 100 · 여 활성 100', (tester) async {
      await openHome(tester);

      final title = find.text('학교별 현황');
      expect(tester.getTopLeft(title), const Offset(848, 657));
      expect((styleOf(tester, title).fontSize, styleOf(tester, title).fontWeight), (16, FontWeight.w700));
      expect(tester.getRect(key('school-table')), const Rect.fromLTWH(848, 691, 560, 44 + 52 * 5));
      final table = key('school-table');
      expect([for (final head in ['학교', '카드 오픈 시각', '남 활성', '여 활성']) tester.getTopLeft(find.descendant(of: table, matching: find.text(head))).dx], [864, 1034, 1214, 1314]);
      // 카드 오픈 시각은 한국 시각 그대로(UTC 22:00 → 다음 날 07:00)
      expect(find.descendant(of: table, matching: find.text('서울대학교')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('2026-11-02 07:00')), findsNWidgets(2));
      expect(find.descendant(of: table, matching: find.text('2026-11-09 07:00')), findsNWidgets(3));
      expect(find.descendant(of: table, matching: find.text('62')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('58')), findsOneWidget);
    });

    testWidgets('운영 상태판: 카드 520×332 · 안쪽 24 · 줄 높이 44 사이 4 — 제목 16/700, 줄 다섯, 아래 12 muted 안내 (pen y997 은 표가 학교 3곳일 때, 5곳이면 줄 2 가 표 높이로 늘어 y1019)', (tester) async {
      await openHome(tester);

      // 줄 2 높이 = 큰 쪽(표 22 + 12 + 44 + 52 × 5 = 338, 그래프 카드 316) → 상태판은 그 아래 24
      final top = tester.getTopLeft(key('health-card')).dy;
      expect(top, 657 + 338 + 24);
      expect(tester.getRect(key('health-card')), Rect.fromLTWH(272, top, 520, 332));
      expect(tester.getTopLeft(find.text('운영 상태판')), Offset(296, top + 24));
      const keys = ['cards_issued_today', 'stuck_chat_rooms', 'overdue_withdrawn', 'avatar_failures_24h', 'stuck_pending_pushes'];
      expect([for (final k in keys) tester.getRect(key('health-row-$k'))], [
        for (var i = 0; i < 5; i++) Rect.fromLTWH(296, top + 50 + 48.0 * i, 472, 44),
      ]);
      final note = find.text('환불 배치는 DB 흔적이 없어 여기서 볼 수 없어요(로그에서 확인).');
      expect(tester.getTopLeft(note), Offset(296, top + 290));
      expect((styleOf(tester, note).fontSize, styleOf(tester, note).color), (12, AdminColors.muted));
    });

    testWidgets('pen y997: 학교 3곳이면(그래프 카드 172 → 줄 2 는 표 높이) 상태판 위치가 pen 과 같은 규칙 — 줄 2 아래 24', (tester) async {
      await openHome(tester, server: FakeStatsServer()..universities = universityRows());

      // 3곳: 표 22 + 12 + 200 = 234, 그래프 카드 20 + 24 + 12 + 172 + 20 = 248 → 줄 2 높이 248
      expect(tester.getTopLeft(key('health-card')).dy, 657 + 248 + 24);
    });

    testWidgets('상태판 줄 모양: 정상 = circle-check 18 success + 14 body + 배지 "정상", 이상 = triangle-alert 18 + 14/600 ink + 배지 "2개"(경고) · "4건"(위험)', (tester) async {
      await openHome(tester);

      Finder row(String k) => key('health-row-$k');
      expect(find.descendant(of: row('cards_issued_today'), matching: find.byIcon(LucideIcons.circleCheck)), findsOneWidget);
      final okIcon = tester.widget<Icon>(find.descendant(of: row('cards_issued_today'), matching: find.byType(Icon)));
      expect((okIcon.size, okIcon.color), (18, AdminColors.success));
      final okLabel = find.text('오늘 카드가 도착했는지 (지급 요일 기준)');
      expect((styleOf(tester, okLabel).fontSize, styleOf(tester, okLabel).fontWeight, styleOf(tester, okLabel).color), (14, FontWeight.w400, AdminColors.body));
      expect(tester.getTopLeft(find.descendant(of: row('cards_issued_today'), matching: find.byType(Icon))).dx, 296);
      expect(tester.getTopLeft(find.descendant(of: row('cards_issued_today'), matching: find.byType(Icon))).dy, closeTo(tester.getTopLeft(row('cards_issued_today')).dy + 13, 0.6)); // 줄 44 가운데

      final warnIcon = tester.widget<Icon>(find.descendant(of: row('stuck_chat_rooms'), matching: find.byType(Icon)));
      expect((warnIcon.icon, warnIcon.size, warnIcon.color), (LucideIcons.triangleAlert, 18, AdminColors.warning));
      final alertIcon = tester.widget<Icon>(find.descendant(of: row('avatar_failures_24h'), matching: find.byType(Icon)));
      expect((alertIcon.icon, alertIcon.color), (LucideIcons.triangleAlert, AdminColors.danger));
      final warnLabel = find.text('48시간 지나도 안 닫힌 방');
      expect((styleOf(tester, warnLabel).fontWeight, styleOf(tester, warnLabel).color), (FontWeight.w600, AdminColors.ink));

      StatusBadge badge(String text) => tester.widget<StatusBadge>(find.widgetWithText(StatusBadge, text).first);
      expect(find.widgetWithText(StatusBadge, '정상'), findsNWidgets(3));
      expect(badge('정상').tone, StatusTone.success);
      expect(badge('2개').tone, StatusTone.warning);
      expect(badge('4건').tone, StatusTone.danger);
      // 배지는 줄 오른쪽 끝(카드 안쪽 오른쪽)
      expect(tester.getRect(find.widgetWithText(StatusBadge, '2개')).right, 768);
    });

    testWidgets('서버 판정 그대로: 모두 정상이면 다섯 줄 모두 정상 모양, 카드 줄 na 는 "해당 없음"(중립)', (tester) async {
      await openHome(
        tester,
        server: FakeStatsServer()
          ..health = healthJson(items: [
            {'key': 'cards_issued_today', 'status': 'na', 'count': 0},
            {'key': 'stuck_chat_rooms', 'status': 'ok', 'count': 0},
            {'key': 'overdue_withdrawn', 'status': 'ok', 'count': 0},
            {'key': 'avatar_failures_24h', 'status': 'ok', 'count': 0},
            {'key': 'stuck_pending_pushes', 'status': 'ok', 'count': 0},
          ]),
      );

      expect(find.byIcon(LucideIcons.circleCheck), findsNWidgets(5));
      expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);
      expect(find.widgetWithText(StatusBadge, '정상'), findsNWidgets(4));
      expect(tester.widget<StatusBadge>(find.widgetWithText(StatusBadge, '해당 없음')).tone, StatusTone.neutral);
    });

    testWidgets('카드 줄이 위험(alert — D4: 점검 대상 지역 어디도 오늘 카드를 못 받음)이면 triangle-alert + 위험 배지 "2곳"', (tester) async {
      await openHome(
        tester,
        server: FakeStatsServer()
          ..health = healthJson(items: [
            {'key': 'cards_issued_today', 'status': 'alert', 'count': 2},
            {'key': 'stuck_chat_rooms', 'status': 'ok', 'count': 0},
            {'key': 'overdue_withdrawn', 'status': 'ok', 'count': 0},
            {'key': 'avatar_failures_24h', 'status': 'ok', 'count': 0},
            {'key': 'stuck_pending_pushes', 'status': 'ok', 'count': 0},
          ]),
      );

      expect(tester.widget<StatusBadge>(find.widgetWithText(StatusBadge, '2곳')).tone, StatusTone.danger);
      final icon = tester.widget<Icon>(find.descendant(of: key('health-row-cards_issued_today'), matching: find.byType(Icon)));
      expect((icon.icon, icon.color), (LucideIcons.triangleAlert, AdminColors.danger));
      final label = find.text('오늘 카드가 도착했는지 (지급 요일 기준)');
      expect(styleOf(tester, label).fontWeight, FontWeight.w600);
    });

    testWidgets('모르는 status("weird")는 예외 없이 "확인 안 됨" + triangle-alert muted(안심 모양 금지), 모르는 key("new_check")는 줄을 숨긴다', (tester) async {
      await openHome(
        tester,
        server: FakeStatsServer()
          ..health = healthJson(items: [
            {'key': 'cards_issued_today', 'status': 'weird', 'count': 3},
            {'key': 'new_check', 'status': 'alert', 'count': 9},
            {'key': 'stuck_chat_rooms', 'status': 'ok', 'count': 0},
          ]),
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<StatusBadge>(find.widgetWithText(StatusBadge, '확인 안 됨')).tone, StatusTone.neutral);
      final icon = tester.widget<Icon>(find.descendant(of: key('health-row-cards_issued_today'), matching: find.byType(Icon)));
      expect((icon.icon, icon.color), (LucideIcons.triangleAlert, AdminColors.muted));
      expect(key('health-row-new_check'), findsNothing);
      expect(find.text('9건'), findsNothing);
      expect(find.byType(StatCard), findsNWidgets(3)); // 화면은 그대로
    });

    testWidgets('서버가 unobservable 에 refund_batch 를 주지 않으면 안내 줄을 그리지 않는다', (tester) async {
      await openHome(tester, server: FakeStatsServer()..health = healthJson(unobservable: const []));

      expect(find.textContaining('환불 배치는'), findsNothing);
    });
  });

  testWidgets('좁은 창(1280, 설계서 최소)에서도 넘치지 않는다 — 차트 카드 둘이 줄어들고 그래프가 카드 안 폭(440)에 맞춘다', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: FakeStatsServer().api(), size: const Size(1280, 1400));

    // 내용 1040 − 32 × 2 = 976 → 카드 (976 − 16) / 2 = 480 → 그래프 480 − 40 = 440
    expect(tester.getSize(key('signup-card')).width, 480);
    expect(tester.getSize(key('chart-signups')).width, 440);
    expect(tester.getSize(key('chart-intake')).width, 440);
    expect(tester.getSize(key('chart-schools')).width, 440);
    expect(tester.takeException(), isNull);
  });

  testWidgets('글자를 키워 상태판 문구가 줄을 바꾸면 줄이 늘어난다(44 는 최소 — 조용한 잘림 없음)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openHome(tester);

    final row = key('health-row-cards_issued_today');
    expect(tester.getSize(row).height, greaterThan(44));
    tester.takeException(); // 셸 메뉴(SideNav)의 기존 넘침(W0) — 이 화면 몫이 아니다
  });

  group('학교', () {
    testWidgets('학교가 없으면 가로 막대 카드 · 표 자리에 "아직 보여 줄 학교가 없어요"', (tester) async {
      await openHome(tester, server: FakeStatsServer()..universities = []);

      expect(find.text('아직 보여 줄 학교가 없어요'), findsNWidgets(2));
      expect(key('school-table'), findsNothing);
      expect(key('chart-schools'), findsNothing);
    });

    testWidgets('가로 막대는 활성 많은 순 최대 8곳(서버 순서), 표는 서버가 준 학교 전부', (tester) async {
      final many = [for (var i = 0; i < 10; i++) universityRow('학교$i대학교', 50 - i, 40 - i)];
      await openHome(tester, server: FakeStatsServer()..universities = many);

      expect(tester.getSize(key('chart-schools')).height, 34 * 8 + 70);
      expect(find.descendant(of: key('chart-schools'), matching: find.text('학교7대')), findsOneWidget);
      expect(find.descendant(of: key('chart-schools'), matching: find.text('학교8대')), findsNothing);
      expect(tester.getSize(key('school-table')).height, 44 + 52 * 10);
      expect(find.descendant(of: key('school-table'), matching: find.text('학교9대학교')), findsOneWidget);
    });

    testWidgets('카드 오픈 시각이 없는 학교는 "—"', (tester) async {
      await openHome(tester, server: FakeStatsServer()..universities = [universityRow('서울대학교', 1, 2, opensAt: null)]);

      expect(find.descendant(of: key('school-table'), matching: find.text('—')), findsOneWidget);
    });
  });

  group('통계 카드 링크(대장 결정 3)', () {
    for (final (link, path) in [('열기 →', '/heart-tasks'), ('사용자 보기 →', '/users')]) {
      testWidgets('"$link" → $path', (tester) async {
        await openHome(tester);

        await tester.tap(find.text(link).first);
        await tester.pumpAndSettle();

        expect(locationOf(tester), path);
      });
    }

    testWidgets('두 번째 "열기 →"(열린 신고)는 신고 화면', (tester) async {
      await openHome(tester);

      await tester.tap(find.text('열기 →').last);
      await tester.pumpAndSettle();

      expect(locationOf(tester), '/reports');
    });

    testWidgets('값이 0 이면 "0"', (tester) async {
      await openHome(tester, server: FakeStatsServer()..stats = {'open_reports': 0, 'pending_proofs': 0, 'signups_today': 0});

      expect(find.descendant(of: find.widgetWithText(StatCard, '검수 대기'), matching: find.text('0')), findsOneWidget);
    });
  });

  group('받는 중 · 못 받음 · 읽기만', () {
    testWidgets('받는 중이면 인사말 아래에 안내 한 줄', (tester) async {
      await openHome(tester, settle: false);
      await tester.pump();

      expect(find.text('오늘 처리할 일'), findsOneWidget);
      expect(find.text('홈 정보를 불러오고 있어요'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('홈 정보를 불러오고 있어요'), findsNothing);
    });

    testWidgets('한 가지라도 못 받으면(상태판) 오류 틀 + [다시 시도] — 누르면 처음부터 다시', (tester) async {
      final server = FakeStatsServer()..healthFailure = 500;
      await openHome(tester, server: server);

      expect(find.text('홈 정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('인터넷 연결을 확인하고 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byType(StatCard), findsNothing);
      server.healthFailure = null;
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('홈 정보를 불러오지 못했어요'), findsNothing);
      expect(find.byType(StatCard), findsNWidgets(3));
    });

    testWidgets('연결이 끊겨도(0) 같은 오류 틀', (tester) async {
      await openHome(tester, server: FakeStatsServer()..statsFailure = 0);

      expect(find.text('홈 정보를 불러오지 못했어요'), findsOneWidget);
    });

    testWidgets('읽기만 한다 — GET 이외를 보내지 않고, 한 번 들어올 때 네 곳(통계 · 일별 30 · 학교 · 상태판)', (tester) async {
      final server = await openHome(tester);

      expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
      final paths = [for (final r in server.requests) r.url.path];
      for (final path in ['/admin/stats', '/admin/stats/daily', '/admin/universities', '/admin/health']) {
        expect(paths, contains(path));
      }
      expect(server.to('/admin/stats/daily').single.url.queryParameters['days'], '30');
    });
  });

  testWidgets('다른 메뉴로 갔다 오면 새로 받는다(화면에 들어올 때마다)', (tester) async {
    final server = await openHome(tester);
    expect(server.to('/admin/stats'), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('nav-billing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpAndSettle();

    expect(server.to('/admin/stats'), hasLength(2));
  });

  testWidgets('화면 읽기: 그래프마다 한 줄 요약(합계 · 가장 많은 날)', (tester) async {
    final handle = tester.ensureSemantics();
    await openHome(tester);

    final totalMale = [for (final d in dailyStatRows()) d['male_signups']! as int].fold<int>(0, (a, b) => a + b);
    final totalFemale = [for (final d in dailyStatRows()) d['female_signups']! as int].fold<int>(0, (a, b) => a + b);
    expect(find.bySemanticsLabel(RegExp('^최근 30일 가입 합계 남 $totalMale명 · 여 $totalFemale명, 가장 많은 날 ')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^최근 14일 접수량 합계 신고 \\d+건 · 인증샷 \\d+건, 가장 많은 날 10/14 ')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^학교별 활성 인원 5곳, 가장 많은 학교 서울대학교 남 62명 · 여 58명')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('시험이 끝나도 남는 타이머 · 애니메이션이 없다(pumpAndSettle 이 끝난다)', (tester) async {
    await openHome(tester);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
