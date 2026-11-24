import 'package:campus_mate/common/widgets/wash_notice.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 값은 datingApp.pen Notice `WQIrY` 의 앱 쓰임(15-4 card_preview · 06-4 xxLBt · 02 RxIqA): 아이콘 · 링크 없이 글만.
void main() {
  testWidgets('pen WQIrY — primary-wash 바탕 · 모서리 12 · 안쪽 14 · 14/400 body 줄높이 1.5', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [WashNotice(text: '안내 글')]),
        ),
      ),
    );

    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: find.text('안내 글'), matching: find.byType(DecoratedBox)).first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, AppColors.primaryWash);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(tester.getTopLeft(find.text('안내 글')) - tester.getTopLeft(find.byType(WashNotice)), const Offset(14, 14));
    expect(tester.getSize(find.byType(WashNotice)).width, 800); // 폭은 부모가 정한다(stretch)
    final style = tester.widget<Text>(find.text('안내 글')).style!;
    expect((style.fontSize, style.fontWeight, style.height, style.color), (14.0, FontWeight.w400, 1.5, AppColors.body));
  });
}
