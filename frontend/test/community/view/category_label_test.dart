import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/view/category_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// pen CategoryLabel · Small `Xbtho`: primary-wash 알약 · 안쪽 [4,10] · 14/700 lh1.3 primary-text. 렌더 46×26("연애").
void main() {
  testWidgets('연애 라벨: 46×26 · primary-wash 알약 · 14/700 lh1.3 primary-text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: CategoryLabel(category: CommunityCategory.love))),
      ),
    );
    final box = tester.getRect(find.byType(CategoryLabel));
    final label = tester.getRect(find.text('연애'));
    expect(box.height, closeTo(26, 0.5));
    expect((label.left - box.left, box.right - label.right), (10, 10));
    final decoration = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(CategoryLabel), matching: find.byType(DecoratedBox)),
    ).decoration as ShapeDecoration;
    expect((decoration.color, decoration.shape), (AppColors.primaryWash, const StadiumBorder()));
    final style = tester.widget<Text>(find.text('연애')).style!;
    expect((style.fontSize, style.fontWeight, style.height, style.color), (14, FontWeight.w700, 1.3, AppColors.primaryText));
  });
}
