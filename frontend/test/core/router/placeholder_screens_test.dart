import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('스플래시 화면은 로딩 스피너 없이 "CampusMate" 문구만 headline 스타일로 보인다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('CampusMate'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final text = tester.widget<Text>(find.text('CampusMate'));
    expect(text.style?.fontSize, AppTypography.headline.fontSize);
    expect(text.style?.fontWeight, AppTypography.headline.fontWeight);
  });

  testWidgets('홈 화면 자리는 "오늘의 카드" 문구를 보인다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('오늘의 카드'), findsOneWidget);
  });
}
