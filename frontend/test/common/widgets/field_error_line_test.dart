import 'package:campus_mate/common/widgets/field_error_line.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 값은 datingApp.pen TextInput `PccKZ` 오류 줄(ErrorRow) — `LabeledField` 오류 줄과 같은 모양: 위 8 · circleAlert 14 · 4 · 12 error.
void main() {
  testWidgets('칸 아래 8 에 circleAlert 14(error) + 4 + 12 error 글자', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Column(children: [FieldErrorLine('오류 글')])),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(AppIcons.circleAlert));
    expect((icon.size, icon.color), (14.0, AppColors.error));
    expect(tester.getTopLeft(find.byIcon(AppIcons.circleAlert)).dy - tester.getTopLeft(find.byType(FieldErrorLine)).dy,
        greaterThanOrEqualTo(8));
    expect(tester.getTopLeft(find.text('오류 글')).dx - tester.getTopRight(find.byIcon(AppIcons.circleAlert)).dx, 4);
    final style = tester.widget<Text>(find.text('오류 글')).style!;
    expect((style.fontSize, style.color), (12.0, AppColors.error));
  });
}
