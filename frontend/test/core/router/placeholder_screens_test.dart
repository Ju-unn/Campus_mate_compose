import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('스플래시 화면은 스피너 없이 마스코트·빨간 "CampusMate"·부제를 보인다(pen jXJSY)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('하루 한 사람, 같은 캠퍼스에서'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final text = tester.widget<Text>(find.text('CampusMate'));
    expect(text.style?.fontSize, AppTypography.display.fontSize);
    expect(text.style?.color, AppColors.primary);
  });
}
