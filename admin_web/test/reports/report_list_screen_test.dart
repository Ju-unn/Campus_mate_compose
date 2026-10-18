import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/heart_task_fakes.dart' show testNow;
import '../helpers/report_fakes.dart';

/// A4 신고 목록(pen i5AYYB · 1440×900, 값표 ① · ⑥ + PNG A4_신고_목록 · A4_목록_* 측정).
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  // 실제 Pretendard 로 잰다 — 시험 기본 글꼴은 글자가 넓어 칸 폭을 넘친다(W1 화면 시험과 같은 이유).
  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  /// pen 예시 다섯 줄과 같은 꼴(사유 · 대상만 서버 값으로)
  FakeReportServer fiveOpen() {
    return FakeReportServer([
      reportRow('r1', type: 'profile', reason: 'spam', createdAt: '2026-10-16T00:30:00+00:00', target: targetProfile(nickname: '닉네임E', university: '고려대학교'), openReporters: 3),
      reportRow('r2', type: 'friend_review', reason: 'fake', createdAt: '2026-10-17T10:03:00+00:00', target: targetProfile(id: 'p2', nickname: '닉네임D'), openReporters: 2),
      reportRow('r3', type: 'poll', reason: 'abuse', createdAt: '2026-10-17T13:15:00+00:00', target: targetProfile(id: 'p3', nickname: '닉네임F'), openReporters: 1, preview: '학식 어때요?'),
      reportRow('r4', type: 'message', reason: 'abuse', createdAt: '2026-10-18T02:40:00+00:00', target: targetProfile(id: 'p4', nickname: '닉네임C'), openReporters: 4),
      reportRow('r5', type: 'profile', reason: 'sexual', createdAt: '2026-10-18T04:02:00+00:00', openReporters: 5),
    ]);
  }

  Future<FakeReportServer> openList(
    WidgetTester tester, {
    FakeReportServer? server,
    Size size = const Size(1440, 900),
    bool settle = true,
  }) async {
    final fake = server ?? fiveOpen();
    await pumpAdminApp(
      tester,
      auth: FakeAdminAuth(mfa: aal2),
      api: fake.api(),
      initialPath: '/reports',
      size: size,
      settle: settle,
      overrides: [clockProvider.overrideWithValue(() => testNow)],
    );
    return fake;
  }

  Finder row(String id) => find.byKey(ValueKey('report-row-$id'));
  Finder table() => find.byKey(const ValueKey('report-table'));
  Finder inRow(String id, String text) => find.descendant(of: row(id), matching: find.text(text));
  TextStyle styleOf(WidgetTester tester, Finder text) => tester.widget<Text>(text).style!;

  group('pen 배치(i5AYYB)', () {
    testWidgets('내용 32 안쪽: 칩 줄 y96 높이 36 · 24 아래 표(폭 가득 1136) · 표 아래 24 에 "오래된 순 · 최대 50건"', (tester) async {
      await openList(tester);

      expect(tester.getRect(find.widgetWithText(AdminChip, '전체')).topLeft, const Offset(272, 96));
      expect(tester.getSize(find.widgetWithText(AdminChip, '전체')).height, 36);
      final tableRect = tester.getRect(table());
      // 머리 44 + 줄 52 × 5
      expect(tableRect, const Rect.fromLTWH(272, 156, 1136, 44 + 52 * 5));
      final note = find.text('오래된 순 · 최대 50건');
      expect(tester.getRect(note).top, tableRect.bottom + 24);
      expect(styleOf(tester, note).fontSize, 12);
      expect(styleOf(tester, note).color, AdminColors.muted);
    });

    testWidgets('칩: 종류 5(전체 · 프로필 · 메시지 · 친구 리뷰 · 투표) → 구분선 1×24 web-outline → 상태 3(열림 · 조치 · 기각), 사이 8', (tester) async {
      await openList(tester);

      final labels = ['전체', '프로필', '메시지', '친구 리뷰', '투표', '열림', '조치', '기각'];
      final rects = [for (final l in labels) tester.getRect(find.widgetWithText(AdminChip, l))];
      for (var i = 1; i < 5; i++) {
        expect(rects[i].left - rects[i - 1].right, 8, reason: labels[i]);
      }
      final divider = tester.getRect(find.byKey(const ValueKey('chip-divider')));
      expect(divider.size, const Size(1, 24));
      expect(divider.left - rects[4].right, 8);
      expect(rects[5].left - divider.right, 8);
      expect(divider.center.dy, rects[4].center.dy);
      expect(tester.widget<ColoredBox>(find.descendant(of: find.byKey(const ValueKey('chip-divider')), matching: find.byType(ColoredBox))).color, AdminColors.outline);
      // 처음은 전체 · 열림
      expect(tester.widget<AdminChip>(find.widgetWithText(AdminChip, '전체')).selected, isTrue);
      expect(tester.widget<AdminChip>(find.widgetWithText(AdminChip, '열림')).selected, isTrue);
      expect(tester.widget<AdminChip>(find.widgetWithText(AdminChip, '조치')).selected, isFalse);
    });

    testWidgets('표(gVa8u): 모서리 14 · web-surface · web-outline 1, 머리줄 44 web-surface-strong · 머리 칸 12/700 web-muted', (tester) async {
      await openList(tester);

      final box = tester.widget<Container>(table());
      expect((box.decoration! as BoxDecoration).color, AdminColors.surface);
      expect((box.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(14));
      expect((box.foregroundDecoration! as BoxDecoration).border, Border.all(color: AdminColors.outline));
      expect(box.clipBehavior, isNot(Clip.none));
      final head = find.byKey(const ValueKey('report-table-head'));
      expect(tester.getSize(head).height, 44);
      expect(tester.widget<Container>(head).color, AdminColors.surfaceStrong);
      final headStyle = styleOf(tester, find.text('대상 종류'));
      expect((headStyle.fontSize, headStyle.fontWeight, headStyle.color), (12, FontWeight.w700, AdminColors.muted));
    });

    testWidgets('열: 대상 종류 110 · 신고 사유 170 · 신고자 수 90 · 대상 요약 230 · 접수 시각 160 · 지난 시간 150 · 상태 110(칸 안쪽 16)', (tester) async {
      await openList(tester);

      const heads = ['대상 종류', '신고 사유', '신고자 수', '대상 요약', '접수 시각', '접수 뒤 지난 시간', '상태'];
      const lefts = [288.0, 398.0, 568.0, 658.0, 888.0, 1048.0, 1198.0];
      for (final (i, head) in heads.indexed) {
        expect(tester.getRect(find.text(head)).left, lefts[i], reason: head);
      }
    });

    testWidgets('줄: 높이 52 · 아래 web-hairline 1 · 칸 14 web-ink — 프로필 / 광고·스팸 / — / 닉네임E · 고려대학교 / 2026-10-16 09:30 / 2일 4시간 / 대기', (tester) async {
      await openList(tester);

      expect(tester.getRect(row('r1')), const Rect.fromLTWH(272, 200, 1136, 52));
      expect(tester.getRect(row('r2')).top, 252);
      for (final cell in ['프로필', '광고·스팸', '3명', '닉네임E · 고려대학교', '2026-10-16 09:30', '2일 4시간']) {
        expect(inRow('r1', cell), findsOneWidget, reason: cell);
      }
      final cellStyle = styleOf(tester, inRow('r1', '닉네임E · 고려대학교'));
      expect((cellStyle.fontSize, cellStyle.fontWeight, cellStyle.color), (14, FontWeight.w400, AdminColors.ink));
      final badge = tester.widget<StatusBadge>(find.descendant(of: row('r1'), matching: find.byType(StatusBadge)));
      expect((badge.label, badge.tone), ('대기', StatusTone.warning));
      final line = tester.widget<DecoratedBox>(find.byKey(const ValueKey('report-row-line-r1')));
      expect((line.decoration as BoxDecoration).border, const Border(bottom: BorderSide(color: AdminColors.hairline)));
    });

    testWidgets('신고자 수 칸은 목록 응답의 open_reporters, 대상 요약은 종류마다(메시지 "닉네임 의 메시지" 등) · 투표 글은 질문 앞부분', (tester) async {
      await openList(tester);

      expect(inRow('r2', '닉네임D 의 리뷰'), findsOneWidget);
      expect(inRow('r3', '학식 어때요?'), findsOneWidget);
      expect(inRow('r3', '닉네임F 의 투표 글'), findsNothing);
      expect(inRow('r4', '닉네임C 의 메시지'), findsOneWidget);
      for (final (id, count) in [('r1', '3명'), ('r2', '2명'), ('r3', '1명'), ('r4', '4명'), ('r5', '5명')]) {
        expect(inRow(id, count), findsOneWidget, reason: id);
        expect(inRow(id, '—'), findsNothing, reason: id);
      }
      // 오래된 순(서버 순서 그대로)
      expect(tester.getRect(row('r1')).top, lessThan(tester.getRect(row('r5')).top));
      expect(inRow('r5', '1시간'), findsOneWidget);
      expect(inRow('r3', '16시간'), findsOneWidget);
    });

    testWidgets('대상 계정이 지워진 줄의 신고자 수는 "—"(서버 0 을 그대로 쓰지 않는다), 신고자 수 칸이 없는 옛 응답도 "—"', (tester) async {
      final server = FakeReportServer([
        reportRow('r1', target: null, openReporters: 0),
        {...reportRow('r2')}..remove('open_reporters'),
      ]);
      await openList(tester, server: server);

      expect(inRow('r1', '—'), findsNWidgets(2)); // 신고자 수 + 대상 요약
      expect(inRow('r1', '0'), findsNothing);
      expect(inRow('r1', '0명'), findsNothing);
      expect(inRow('r2', '—'), findsOneWidget);
      expect(inRow('r2', '닉네임B 의 메시지'), findsOneWidget);
    });
  });

  group('필터', () {
    testWidgets('상태 칩 · 종류 칩을 누르면 그 조건으로 새로 받는다(같은 칩을 다시 눌러도)', (tester) async {
      final server = await openList(tester);

      await tester.tap(find.widgetWithText(AdminChip, '메시지'));
      await tester.pumpAndSettle();
      expect(row('r4'), findsOneWidget);
      expect(row('r1'), findsNothing);
      await tester.tap(find.widgetWithText(AdminChip, '조치'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AdminChip, '조치'));
      await tester.pumpAndSettle();

      expect(server.requests.where((r) => r.url.path == '/admin/reports').map((r) => r.url.query), [
        'status=open',
        'status=open&type=message',
        'status=actioned&type=message',
        'status=actioned&type=message',
      ]);
      expect(tester.widget<AdminChip>(find.widgetWithText(AdminChip, '조치')).selected, isTrue);
      expect(tester.widget<AdminChip>(find.widgetWithText(AdminChip, '열림')).selected, isFalse);
    });

    testWidgets('닫힌 신고의 상태 배지: 조치 web-success · 기각 web-surface-strong + web-muted', (tester) async {
      await openList(
        tester,
        server: FakeReportServer([
          reportRow('a', status: 'actioned'),
          reportRow('d', status: 'dismissed', createdAt: '2026-10-18T03:00:00+00:00'),
        ]),
      );

      await tester.tap(find.widgetWithText(AdminChip, '조치'));
      await tester.pumpAndSettle();
      final actioned = tester.widget<StatusBadge>(find.descendant(of: row('a'), matching: find.byType(StatusBadge)));
      expect((actioned.label, actioned.tone), ('조치', StatusTone.success));

      await tester.tap(find.widgetWithText(AdminChip, '기각'));
      await tester.pumpAndSettle();
      final dismissed = tester.widget<StatusBadge>(find.descendant(of: row('d'), matching: find.byType(StatusBadge)));
      expect((dismissed.label, dismissed.tone), ('기각', StatusTone.neutral));
      expect((StatusTone.neutral.wash, StatusTone.neutral.ink), (AdminColors.surfaceStrong, AdminColors.muted));
    });

    testWidgets('줄을 누르면 그 신고의 상세 주소(/reports/{id})로 간다', (tester) async {
      await openList(tester);

      await tester.tap(row('r4'));
      await tester.pumpAndSettle();

      expect(locationOf(tester), '/reports/r4');
      expect(find.byKey(const ValueKey('report-head')), findsOneWidget);
    });
  });

  group('시안에 없던 상태(⑥ · A4_목록_*)', () {
    testWidgets('받는 중: 칩 줄 아래 틀 없이 도는 아이콘 + "신고 목록을 불러오고 있어요"', (tester) async {
      final server = fiveOpen()..holdList = Completer<void>();
      await openList(tester, server: server, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final frame = tester.widget<AdminTableEmpty>(find.byType(AdminTableEmpty));
      expect(frame.framed, isFalse);
      expect(find.descendant(of: find.byType(AdminTableEmpty), matching: find.byType(AdminLoader)), findsOneWidget);
      expect(find.text('신고 목록을 불러오고 있어요'), findsOneWidget);

      server.holdList!.complete();
      await tester.pumpAndSettle();
      expect(row('r1'), findsOneWidget);
    });

    testWidgets('못 받음: 틀 없이 circle-alert + "목록을 불러오지 못했어요" + 다시 시도', (tester) async {
      final server = fiveOpen()..listFailure = 0;
      await openList(tester, server: server);

      expect(tester.widget<AdminTableEmpty>(find.byType(AdminTableEmpty)).framed, isFalse);
      expect(find.text('목록을 불러오지 못했어요'), findsOneWidget);
      server.listFailure = null;
      await tester.tap(find.widgetWithText(AdminButton, '다시 시도'));
      await tester.pumpAndSettle();
      expect(row('r1'), findsOneWidget);
    });

    testWidgets('빈 목록(kSwZk): 열림이면 "열린 신고가 없어요" / "새 신고가 들어오면 여기에 보여요", 그 밖은 "조건에 맞는 신고가 없어요"', (tester) async {
      await openList(tester, server: FakeReportServer(const []));

      final empty = tester.widget<AdminTableEmpty>(find.byType(AdminTableEmpty));
      expect(empty.framed, isTrue);
      expect(tester.getRect(find.byType(AdminTableEmpty)).top, 156);
      expect(find.text('열린 신고가 없어요'), findsOneWidget);
      expect(find.text('새 신고가 들어오면 여기에 보여요'), findsOneWidget);

      await tester.tap(find.widgetWithText(AdminChip, '기각'));
      await tester.pumpAndSettle();
      expect(find.text('조건에 맞는 신고가 없어요'), findsOneWidget);
    });
  });

  group('크기', () {
    testWidgets('목록이 길면 표만 스크롤 — 칩 줄은 제자리', (tester) async {
      await openList(
        tester,
        server: FakeReportServer([
          for (var i = 0; i < 20; i++) reportRow('x$i', createdAt: '2026-10-17T${(10 + i ~/ 2).toString().padLeft(2, '0')}:${i.isOdd ? '30' : '00'}:00+00:00'),
        ]),
      );

      await tester.drag(row('x3'), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.widgetWithText(AdminChip, '전체')).top, 96);
      expect(tester.getRect(row('x0')).top, lessThan(200));
    });

    testWidgets('1280 폭(최소 창)에서도 넘치지 않는다 — 대상 요약 칸만 줄어든다', (tester) async {
      await openList(tester, size: const Size(1280, 800));

      expect(tester.takeException(), isNull);
      expect(tester.getRect(table()).width, 1280 - 240 - 64);
      expect(tester.getRect(find.text('접수 시각')).left - tester.getRect(find.text('대상 요약')).left, lessThan(230));
    });

    testWidgets('글자를 키워도(1.3배) 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openList(tester);

      expect(tester.takeException(), isNull);
      expect(row('r1'), findsOneWidget);
    });
  });

  testWidgets('줄은 화면 읽기에 누를 수 있는 것으로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await openList(tester);

    expect(tester.getSemantics(row('r1')), isSemantics(isButton: true, hasTapAction: true));
    handle.dispose();
  });
}
