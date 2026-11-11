import 'package:campus_mate/common/widgets/sheet_handle.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('시트 손잡이 — 36×4 hairline 모서리 8(pen L3Bec · w8UdMw · vH016 은 4px 높이라 같은 모양)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: SheetHandle(key: ValueKey('handle'))))));

    expect(tester.getSize(find.byKey(const ValueKey('handle'))), const Size(36, 4));
    // paid_card_info_sheet_test 가 DecoratedBox 색을 찾는다.
    final decoration = tester.widget<DecoratedBox>(find.descendant(of: find.byType(SheetHandle), matching: find.byType(DecoratedBox))).decoration as BoxDecoration;
    expect(decoration.color, AppColors.hairline);
    expect(decoration.borderRadius, BorderRadius.circular(8));
  });
}
