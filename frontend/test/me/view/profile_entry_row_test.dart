import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 화면 15 본문 폭 328(360 - 좌우 16) 에 놓는다.
  Future<void> pump(WidgetTester tester, {VoidCallback? onTap}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 328,
              child: ProfileEntryRow(icon: AppIcons.calendar, title: '선호 나이 범위', note: '22세–27세', onTap: onTap),
            ),
          ),
        ),
      ),
    );
  }

  Rect rectOf(WidgetTester tester, Finder finder) {
    final origin = tester.getTopLeft(find.byType(ProfileEntryRow));
    return tester.getRect(finder).shift(-origin);
  }

  testWidgets('마스터 fN0xc 규격 — 328×84, 받침 원 44 (16,20), 셰브런 20 (292,32)', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.byType(ProfileEntryRow)), const Size(328, 84));
    final surface = find.ancestor(of: find.byIcon(AppIcons.calendar), matching: find.byType(Container)).first;
    expect(rectOf(tester, surface), const Rect.fromLTWH(16, 20, 44, 44));
    expect(rectOf(tester, find.byIcon(AppIcons.chevronRight)), const Rect.fromLTWH(292, 32, 20, 20));
    // Copy(`iksDh`)는 받침 원 뒤 gap 12 = x72.
    expect(rectOf(tester, find.text('선호 나이 범위')).left, 72);
  });

  // 사용자 결정 09-28(계획서 N5) — 흰 바탕 + 카드 그림자 두 겹. 누르지 않는 행도 같은 모양이다.
  for (final tappable in [false, true]) {
    testWidgets('틀 `fN0xc` — #FFFFFF · 모서리 14 · 그림자 = AppElevation.card, 그림자는 Material 밖 상자가 그린다'
        '(${tappable ? '누르는 행' : '보이기만 하는 행'})', (tester) async {
      await pump(tester, onTap: tappable ? () {} : null);

      final shadow = find.descendant(
        of: find.byType(ProfileEntryRow),
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).boxShadow != null,
        ),
      );
      expect(shadow, findsOneWidget);
      final decoration = tester.widget<DecoratedBox>(shadow).decoration as BoxDecoration;
      expect((decoration.boxShadow, decoration.borderRadius), (AppElevation.card, BorderRadius.circular(14)));
      expect(tester.getSize(shadow), const Size(328, 84));
      // 바탕은 그림자 상자 안 Material 이 칠한다 — Material elevation 은 쓰지 않는다(§6 한 단계 규칙).
      final painter = find.descendant(of: shadow, matching: find.byType(Material)).first;
      final material = tester.widget<Material>(painter);
      expect((material.color, material.borderRadius, material.elevation), (AppColors.canvas, BorderRadius.circular(14), 0));
      expect(tester.getSize(painter), const Size(328, 84));
    });
  }

  testWidgets('아이콘 원 `zdZqS` #F7F7F7(흰 바탕 위라 원이 보인다), 아이콘 · 셰브런 색은 pen 값과 같다', (tester) async {
    await pump(tester);

    final surface = tester.widget<Container>(
      find.ancestor(of: find.byIcon(AppIcons.calendar), matching: find.byType(Container)).first,
    );
    expect((surface.decoration! as BoxDecoration).color, AppColors.surfaceSoft);
    expect((surface.decoration! as BoxDecoration).shape, BoxShape.circle);
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.calendar));
    expect((icon.size, icon.color), (22, AppColors.muted));
    final chevron = tester.widget<Icon>(find.byIcon(AppIcons.chevronRight));
    expect((chevron.size, chevron.color), (20, AppColors.muted));
  });

  testWidgets('Title 16/600 ink 렌더 25(`ZMu82`), Note 14/400 muted 1.5(`B4ppA`), 둘 사이 3', (tester) async {
    await pump(tester);

    final title = tester.widget<Text>(find.text('선호 나이 범위')).style!;
    expect((title.fontSize, title.fontWeight, title.color), (16, FontWeight.w600, AppColors.ink));
    expect(tester.getSize(find.text('선호 나이 범위')).height, 25);
    final note = tester.widget<Text>(find.text('22세–27세')).style!;
    expect((note.fontSize, note.fontWeight, note.color, note.height), (14, FontWeight.w400, AppColors.muted, 1.5));
    expect(tester.getTopLeft(find.text('22세–27세')).dy - tester.getBottomLeft(find.text('선호 나이 범위')).dy, 3);
  });

  testWidgets('onTap 이 없으면 누를 곳이 없다', (tester) async {
    await pump(tester);

    final row = find.byType(ProfileEntryRow);
    expect(find.descendant(of: row, matching: find.byType(InkWell)), findsNothing);
    expect(find.descendant(of: row, matching: find.byType(GestureDetector)), findsNothing);
  });

  group('onTap 이 있으면(U1 — 셰브런이 값 수정 화면으로 잇는다)', () {
    testWidgets('행 전체를 누르면 onTap 이 불린다', (tester) async {
      var taps = 0;
      await pump(tester, onTap: () => taps++);

      await tester.tap(find.byType(ProfileEntryRow));

      expect(taps, 1);
    });

    testWidgets('채움 · 모서리는 행 크기 Material 이 칠하고, 눌림 효과도 그 Material 에 그린다(COMMON §4-2)', (tester) async {
      await pump(tester, onTap: () {});

      final row = find.byType(ProfileEntryRow);
      final ink = find.descendant(of: row, matching: find.byType(InkWell));
      final painter = find.ancestor(of: ink, matching: find.byType(Material)).first;
      // 가장 가까운 Material 이 화면(Scaffold)이면 스크롤 뒤 눌림 효과가 공중에 뜬다.
      expect(tester.getSize(painter), const Size(328, 84));
      expect(tester.getSize(ink), const Size(328, 84));
      final material = tester.widget<Material>(painter);
      expect((material.color, material.borderRadius), (AppColors.canvas, BorderRadius.circular(14)));
      // 채움은 Material 한 곳만 — 안쪽 상자가 또 칠하면 눌림 효과가 그 밑에 깔려 안 보인다.
      final fills = tester.widgetList<Container>(find.descendant(of: row, matching: find.byType(Container)));
      expect(fills.where((c) => (c.decoration as BoxDecoration?)?.color == AppColors.canvas), isEmpty);
    });

    testWidgets('pen 규격은 그대로 — 328×84, 받침 원 (16,20), 셰브런 (292,32)', (tester) async {
      await pump(tester, onTap: () {});

      expect(tester.getSize(find.byType(ProfileEntryRow)), const Size(328, 84));
      final surface = find.ancestor(of: find.byIcon(AppIcons.calendar), matching: find.byType(Container)).first;
      expect(rectOf(tester, surface), const Rect.fromLTWH(16, 20, 44, 44));
      expect(rectOf(tester, find.byIcon(AppIcons.chevronRight)), const Rect.fromLTWH(292, 32, 20, 20));
    });
  });

  testWidgets('글자 배율 2.0 이면 넘치지 않고 행이 늘어난다(높이 84 는 최소값)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ProfileEntryRow)).height, greaterThan(84));
  });
}
