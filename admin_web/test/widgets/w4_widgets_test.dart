import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_link.dart';
import 'package:campus_mate_admin/widgets/admin_select.dart';
import 'package:campus_mate_admin/widgets/chart_card.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// W4 가 더한 공용 부품: StatCard 가로 채움 · primary 배지 · 링크 · Select(pen MuZJ5) · 그래프 카드(pen egevB)
void main() {
  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(1200, 600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(32), child: Align(alignment: Alignment.topLeft, child: child)),
        ),
      ),
    );
  }

  group('StatCard', () {
    testWidgets('기본은 폭 280(W3 그대로), fill 이면 칸 폭을 채운다(A9 네 장 272)', (tester) async {
      await pump(tester, const StatCard(label: '라벨', value: '1'));
      expect(tester.getSize(find.byType(StatCard)).width, 280);

      await pump(
        tester,
        SizedBox(
          width: 1136,
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                const Expanded(child: StatCard(label: '라벨', value: '1', fill: true)),
              ],
            ],
          ),
        ),
      );
      expect([for (var i = 0; i < 4; i++) tester.getSize(find.byType(StatCard).at(i)).width], [272, 272, 272, 272]);
    });
  });

  testWidgets('StatusTone.primary: 바탕 web-primary-wash · 점 · 글자 web-primary-text(pen A9 "대화 중")', (tester) async {
    await pump(tester, const StatusBadge('대화 중', tone: StatusTone.primary));

    final box = tester.widget<Container>(find.descendant(of: find.byType(StatusBadge), matching: find.byType(Container)).first);
    expect((box.decoration! as BoxDecoration).color, AdminColors.primaryWash);
    expect(tester.widget<Text>(find.text('대화 중')).style!.color, AdminColors.primaryText);
  });

  group('AdminLink — 글자 링크(통계 카드의 "열기 →")', () {
    testWidgets('14/600 web-primary-text(줄 상자 21), 누르면 호출, 화면 읽기에는 단추', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pump(tester, AdminLink(label: '열기 →', onTap: () => taps++));

      final style = tester.widget<Text>(find.text('열기 →')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AdminColors.primaryText));
      expect(tester.getSize(find.byType(AdminLink)).height, 19);
      await tester.tap(find.text('열기 →'));
      expect(taps, 1);
      expect(tester.getSemantics(find.byType(AdminLink)), isSemantics(label: '열기 →', isButton: true));
      handle.dispose();
    });
  });

  group('AdminSelect — pen Web/Select(MuZJ5)', () {
    Future<List<String?>> openSelect(WidgetTester tester, {String? value}) async {
      final picked = <String?>[];
      await pump(
        tester,
        AdminSelect<String?>(
          key: const ValueKey('s'),
          semanticLabel: '학교 고르기',
          options: const [(null, '전체 학교'), ('a', '서울대학교'), ('b', '연세대학교')],
          value: value,
          onChanged: picked.add,
        ),
      );
      return picked;
    }

    testWidgets('닫힘: 200×36 · web-surface · outline-strong 1 · 모서리 8, 현재 글자 14 ink + chevron-down', (tester) async {
      await openSelect(tester, value: 'a');

      expect(tester.getSize(find.byKey(const ValueKey('s'))), const Size(200, 36));
      expect(find.text('서울대학교'), findsOneWidget);
      expect(find.text('연세대학교'), findsNothing); // 닫혀 있으면 다른 항목은 없다
      expect(tester.widget<Text>(find.text('서울대학교')).style!.color, AdminColors.ink);
      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    });

    testWidgets('누르면 항목이 펼쳐지고(아래 4, 폭 200), 고르면 값을 알리고 닫힌다', (tester) async {
      final picked = await openSelect(tester);

      await tester.tap(find.byKey(const ValueKey('s')));
      await tester.pump();
      expect(find.byKey(const ValueKey('s-option-1')), findsOneWidget);
      final trigger = tester.getRect(find.byKey(const ValueKey('s')));
      final menu = tester.getRect(find.byKey(const ValueKey('s-menu')));
      expect((menu.left, menu.top, menu.width), (trigger.left, trigger.bottom + 4, 200));

      await tester.tap(find.byKey(const ValueKey('s-option-1')));
      await tester.pump();
      expect(picked, ['a']);
      expect(find.byKey(const ValueKey('s-menu')), findsNothing);
    });

    testWidgets('Esc 로 닫고, 바깥을 눌러도 닫힌다', (tester) async {
      await openSelect(tester);

      await tester.tap(find.byKey(const ValueKey('s')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('s-menu')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('s')));
      await tester.pump();
      await tester.tapAt(const Offset(900, 500));
      await tester.pump();
      expect(find.byKey(const ValueKey('s-menu')), findsNothing);
    });

    testWidgets('항목이 많으면 메뉴는 320 에서 끊고 스크롤한다', (tester) async {
      await pump(
        tester,
        AdminSelect<int>(
          key: const ValueKey('s'),
          semanticLabel: '고르기',
          options: [for (var i = 0; i < 30; i++) (i, '학교 $i')],
          value: 0,
          onChanged: (_) {},
        ),
      );

      await tester.tap(find.byKey(const ValueKey('s')));
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('s-menu'))).height, lessThanOrEqualTo(320));
    });
  });

  testWidgets('ChartCard(pen egevB): 안쪽 20 — 제목 16/700 + 알약(24, 12/600 muted, surface-strong, 오른쪽 끝) 줄 → 12 → 그래프', (tester) async {
    await pump(
      tester,
      const SizedBox(
        width: 560,
        child: ChartCard(
          key: ValueKey('card'),
          pillKey: ValueKey('card-pill'),
          title: '가입 추이',
          pill: '최근 30일',
          child: SizedBox(height: 240),
        ),
      ),
    );

    final card = tester.getRect(find.byKey(const ValueKey('card')));
    expect(card.size, const Size(560, 316));
    final title = find.text('가입 추이');
    expect(tester.getTopLeft(title) - card.topLeft, const Offset(20, 21));
    final style = tester.widget<Text>(title).style!;
    expect((style.fontSize, style.fontWeight, style.color), (16, FontWeight.w700, AdminColors.ink));
    final pill = find.byKey(const ValueKey('card-pill'));
    expect(tester.getSize(pill).height, 24);
    expect(tester.getRect(pill).right, card.right - 20);
    expect((tester.widget<Container>(pill).decoration! as BoxDecoration).color, AdminColors.surfaceStrong);
    final pillStyle = tester.widget<Text>(find.text('최근 30일')).style!;
    expect((pillStyle.fontSize, pillStyle.fontWeight, pillStyle.color), (12, FontWeight.w600, AdminColors.muted));
  });
}
