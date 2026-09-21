import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ButtonStyle> styleOf(WidgetTester tester, AppButton button) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: button)));
    final elevatedButton = tester.widget<ElevatedButton>(
      find.descendant(of: find.byType(AppButton), matching: find.byType(ElevatedButton)),
    );
    return elevatedButton.style!;
  }

  group('AppButton 탭 처리', () {
    testWidgets('onPressed 가 있으면 탭하면 호출된다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(label: '다음으로', onPressed: () => tapped = true),
          ),
        ),
      );

      await tester.tap(find.text('다음으로'));

      expect(tapped, isTrue);
    });

    testWidgets('onPressed 가 null 이면 비활성 상태다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppButton(label: '다음으로', onPressed: null))),
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.enabled, isFalse);
    });
  });

  group('AppButton 라벨 스타일', () {
    testWidgets('primary 는 label(18/700) 크기를 쓴다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppButton(label: '다음으로', onPressed: null))),
      );

      final text = tester.widget<Text>(find.text('다음으로'));
      expect(text.style?.fontSize, AppTypography.label.fontSize);
      expect(text.style?.fontWeight, AppTypography.label.fontWeight);
    });

    testWidgets('text variant 는 labelSmall(14/600) 크기를 쓴다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppButton(label: '나중에', onPressed: null, variant: AppButtonVariant.text),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('나중에'));
      expect(text.style?.fontSize, AppTypography.labelSmall.fontSize);
      expect(text.style?.fontWeight, AppTypography.labelSmall.fontWeight);
    });
  });

  group('AppButton 크기·라운드 (DESIGN.md §8.3)', () {
    testWidgets('56dp 계열 variant 는 높이 56, 라운드 16이다', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '다음으로', onPressed: null),
      );

      expect(style.minimumSize?.resolve({})?.height, 56);
      final shape = style.shape?.resolve({}) as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, AppRadius.button);
    });

    testWidgets('text variant 는 높이 48이다', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '나중에', onPressed: null, variant: AppButtonVariant.text),
      );

      expect(style.minimumSize?.resolve({})?.height, 48);
    });

    testWidgets('height 를 주면 그 높이를 쓴다 (수락함 행의 44dp 인라인 버튼)', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '거절', onPressed: null, height: 44),
      );

      expect(style.minimumSize?.resolve({})?.height, 44);
    });
  });

  group('AppButton 색 (DESIGN.md §8.3)', () {
    testWidgets('primary 의 평상시 채움·텍스트색', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '다음으로', onPressed: null),
      );

      expect(style.backgroundColor?.resolve({}), AppColors.primary);
      expect(style.foregroundColor?.resolve({}), AppColors.onPrimary);
    });

    testWidgets('primary 눌림 색은 primary-pressed 다', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '다음으로', onPressed: null),
      );

      expect(
        style.backgroundColor?.resolve({WidgetState.pressed}),
        AppColors.primaryPressed,
      );
    });

    testWidgets('secondary 는 primary-disabled 채움 + ink 텍스트다', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '취소', onPressed: null, variant: AppButtonVariant.secondary),
      );

      expect(style.backgroundColor?.resolve({}), AppColors.primaryDisabled);
      expect(style.foregroundColor?.resolve({}), AppColors.ink);
    });

    testWidgets('danger-strong 은 error 채움 + on-primary 텍스트다', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(
          label: '탈퇴',
          onPressed: null,
          variant: AppButtonVariant.dangerStrong,
        ),
      );

      expect(style.backgroundColor?.resolve({}), AppColors.error);
      expect(style.foregroundColor?.resolve({}), AppColors.onPrimary);
    });

    testWidgets('text variant 는 평상시 배경이 없고 primary-text 텍스트다', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '나중에', onPressed: null, variant: AppButtonVariant.text),
      );

      expect(style.backgroundColor?.resolve({}), Colors.transparent);
      expect(style.foregroundColor?.resolve({}), AppColors.primaryText);
    });

    testWidgets('onPressed 가 null 이면 button-disabled 색(primary-disabled + disabled)', (
      tester,
    ) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '다음으로', onPressed: null),
      );

      expect(
        style.backgroundColor?.resolve({WidgetState.disabled}),
        AppColors.primaryDisabled,
      );
      expect(style.foregroundColor?.resolve({WidgetState.disabled}), AppColors.disabled);
    });
  });
}
