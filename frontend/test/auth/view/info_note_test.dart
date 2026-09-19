import 'package:campus_mate/auth/view/info_note.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _text = '학교·학과·학번은 카드와 프로필에 공개돼요.';

void main() {
  Future<void> pumpNote(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InfoNote(icon: AppIcons.eye, text: _text)),
      ),
    );
  }

  BoxDecoration findSurface(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(InfoNote), matching: find.byType(Container)),
    );
    return container.decoration! as BoxDecoration;
  }

  group('InfoNote', () {
    testWidgets('아이콘과 안내 문구를 함께 보여준다', (tester) async {
      await pumpNote(tester);

      expect(find.byIcon(AppIcons.eye), findsOneWidget);
      expect(find.text(_text), findsOneWidget);
    });

    testWidgets('primary-wash 채움에 radius md 인 카드 위에 올린다 (pen 실측)', (tester) async {
      await pumpNote(tester);

      expect(findSurface(tester).color, AppColors.primaryWash);
      expect(findSurface(tester).borderRadius, BorderRadius.circular(AppRadius.md));
    });

    testWidgets('아이콘은 20dp primary-text 로 세운다', (tester) async {
      await pumpNote(tester);

      final icon = tester.widget<Icon>(find.byIcon(AppIcons.eye));
      expect(icon.size, 20);
      expect(icon.color, AppColors.primaryText);
    });

    testWidgets('문구는 bodySmall 크기에 body 색이다', (tester) async {
      await pumpNote(tester);

      final style = tester.widget<Text>(find.text(_text)).style!;
      expect(style.fontSize, AppTypography.bodySmall.fontSize);
      expect(style.color, AppColors.body);
    });
  });
}
