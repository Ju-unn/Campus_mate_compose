import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/view/category_chip.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// pen CategoryChip `eYps8`(Off) · `J8hpZ`(On). 대장 판정 8: 보이는 높이 32, 누르는 영역 44.
void main() {
  Future<void> pumpChip(WidgetTester tester, {required bool selected, VoidCallback? onTap}) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: CategoryChip(category: CommunityCategory.free, selected: selected, onTap: onTap ?? () {}),
          ),
        ),
      ),
    );
  }

  ShapeDecoration surface(WidgetTester tester) =>
      tester.widget<DecoratedBox>(find.byKey(CategoryChip.surfaceKey)).decoration as ShapeDecoration;

  testWidgets('보이는 칩 높이 32 · 누르는 영역 44 · 좌우 안쪽 14', (tester) async {
    await pumpChip(tester, selected: false);
    final hit = tester.getSize(find.byType(CategoryChip));
    final visible = tester.getRect(find.byKey(CategoryChip.surfaceKey));
    final label = tester.getRect(find.text('자유'));
    expect(hit.height, 44);
    expect(visible.height, 32);
    expect(label.left - visible.left, 14);
    expect(visible.right - label.right, 14);
  });

  testWidgets('Off(eYps8): canvas 채움 · hairline 1 테두리 · 알약 · 글자 14/600 lh1.2 body', (tester) async {
    await pumpChip(tester, selected: false);
    final shape = surface(tester).shape as StadiumBorder;
    expect(surface(tester).color, AppColors.canvas);
    expect((shape.side.color, shape.side.width), (AppColors.hairline, 1));
    final style = tester.widget<Text>(find.text('자유')).style!;
    expect((style.fontSize, style.fontWeight, style.height, style.color), (14, FontWeight.w600, 1.2, AppColors.body));
  });

  testWidgets('On(J8hpZ): primary-wash 채움 · primary 1.5 테두리 · 글자 700 primary-text', (tester) async {
    await pumpChip(tester, selected: true);
    final shape = surface(tester).shape as StadiumBorder;
    expect(surface(tester).color, AppColors.primaryWash);
    expect((shape.side.color, shape.side.width), (AppColors.primary, 1.5));
    final style = tester.widget<Text>(find.text('자유')).style!;
    expect((style.fontWeight, style.color), (FontWeight.w700, AppColors.primaryText));
  });

  testWidgets('누르면 알리고, 낭독기는 고른 상태의 버튼으로 읽는다', (tester) async {
    var taps = 0;
    await pumpChip(tester, selected: true, onTap: () => taps++);
    await tester.tap(find.byType(CategoryChip));
    expect(taps, 1);
    expect(
      tester.getSemantics(find.byType(CategoryChip)),
      matchesSemantics(label: '자유', isButton: true, isSelected: true, hasSelectedState: true, hasTapAction: true),
    );
  });
}
