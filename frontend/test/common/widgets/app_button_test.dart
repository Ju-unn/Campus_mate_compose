import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
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
    testWidgets('primary 는 button(16/700) 크기를 쓴다 — pen Button `HE8FZ` 라벨 `ifX9K`', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppButton(label: '다음으로', onPressed: null))),
      );

      final text = tester.widget<Text>(find.text('다음으로'));
      expect(text.style?.fontSize, 16);
      expect(text.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('text variant 는 16/600 크기를 쓴다 — pen Text 변형 `rK7sg` 라벨', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppButton(label: '나중에', onPressed: null, variant: AppButtonVariant.text),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('나중에'));
      expect(text.style?.fontSize, 16);
      expect(text.style?.fontWeight, FontWeight.w600);
    });
  });

  group('AppButton 크기·라운드 (DESIGN.md §8.3)', () {
    testWidgets('채움 variant 는 높이 52, 라운드 14다 — pen Button `HE8FZ`(2026-10-01 개편, 옛 56 · 16)', (tester) async {
      final style = await styleOf(
        tester,
        const AppButton(label: '다음으로', onPressed: null),
      );

      expect(style.minimumSize?.resolve({})?.height, 52);
      final shape = style.shape?.resolve({}) as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, 14);
    });

    testWidgets('text variant 는 높이 48이다 — pen `rK7sg`', (tester) async {
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

  // 계획서 D8 — 06-1 예시 `k5Gv4l`: 저장 중엔 글자 자리에 흰 20 스피너(`sMuCd`), 누름은 막는다.
  group('AppButton 저장 중(isLoading)', () {
    testWidgets('글자 대신 흰 20 스피너가 돈다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AppButton(label: '저장', onPressed: () {}, isLoading: true))),
      );

      expect(find.text('저장'), findsNothing);
      final spinner = find.descendant(of: find.byType(AppButton), matching: find.byType(CircularProgressIndicator));
      expect(spinner, findsOneWidget);
      expect(tester.getSize(spinner), const Size(20, 20));
      expect(tester.widget<CircularProgressIndicator>(spinner).color, AppColors.onPrimary);
    });

    testWidgets('스피너 선 두께는 2 — 앱의 다른 작은 스피너와 같다(대장 09-28, pen `sMuCd` 값이 오면 다시 맞춘다)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AppButton(label: '저장', onPressed: () {}, isLoading: true))),
      );

      expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).strokeWidth, 2);
    });

    testWidgets('눌러도 onPressed 가 불리지 않는다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppButton(label: '저장', onPressed: () => tapped = true, isLoading: true)),
        ),
      );

      await tester.tap(find.byType(AppButton));

      expect(tapped, isFalse);
    });

    testWidgets('채움은 꺼진 회색이 아니라 평상시 primary 그대로다 — 흰 스피너가 보여야 한다', (tester) async {
      // 화면은 저장 중이면 onPressed 를 null 로 넘긴다(canSubmit 에 isSubmitting 이 들어 있다).
      final style = await styleOf(tester, const AppButton(label: '저장', onPressed: null, isLoading: true));

      expect(style.backgroundColor?.resolve({WidgetState.disabled}), AppColors.primary);
    });

    testWidgets('낭독기에는 버튼 이름이 그대로 들린다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AppButton(label: '저장', onPressed: () {}, isLoading: true))),
      );

      expect(find.bySemanticsLabel('저장'), findsOneWidget);
    });
  });
}
