import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 화면 15 본문 폭 328(360 - 좌우 16) 에 놓는다.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 328,
              child: ProfileEntryRow(icon: AppIcons.calendar, title: '선호 나이 범위', note: '22세–27세'),
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

  testWidgets('채움·모서리·아이콘 색은 pen 값과 같다', (tester) async {
    await pump(tester);

    final row = tester.widget<Container>(
      find.descendant(of: find.byType(ProfileEntryRow), matching: find.byType(Container)).first,
    );
    final decoration = row.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.surfaceSoft);
    expect(decoration.borderRadius, BorderRadius.circular(14));
    final surface = tester.widget<Container>(
      find.ancestor(of: find.byIcon(AppIcons.calendar), matching: find.byType(Container)).first,
    );
    expect((surface.decoration! as BoxDecoration).color, AppColors.canvas);
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

  testWidgets('누를 곳이 없다 — 값 수정 화면이 아직 없다(사용자 결정 2026-09-27)', (tester) async {
    await pump(tester);

    final row = find.byType(ProfileEntryRow);
    expect(find.descendant(of: row, matching: find.byType(InkWell)), findsNothing);
    expect(find.descendant(of: row, matching: find.byType(GestureDetector)), findsNothing);
  });

  testWidgets('글자 배율 2.0 이면 넘치지 않고 행이 늘어난다(높이 84 는 최소값)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ProfileEntryRow)).height, greaterThan(84));
  });
}
