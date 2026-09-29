import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const leadingKey = Key('leading');

  /// pen 시트 안 버튼 폭 320(360 − 좌우 20)에 놓는다. 시트처럼 세로로 쌓는 [Column] 안이다.
  Future<void> pumpButton(WidgetTester tester, SafetySheetButton button) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: Column(mainAxisSize: MainAxisSize.min, children: [button]),
            ),
          ),
        ),
      ),
    );
  }

  group('SafetySheetButton.primary leading(15b CTA pen wf0b2)', () {
    testWidgets('leading 이 있으면 글자 앞 8 에 두고 버튼은 320×52 그대로', (tester) async {
      await pumpButton(
        tester,
        SafetySheetButton.primary(
          label: '10 쓰고 만들기',
          onPressed: () {},
          leading: const SizedBox(key: leadingKey, width: 26, height: 26),
        ),
      );

      final leading = tester.getRect(find.byKey(leadingKey));
      final label = tester.getRect(find.text('10 쓰고 만들기'));
      expect(label.left - leading.right, 8);
      expect(leading.center.dy, label.center.dy);
      expect(tester.getSize(find.byType(SafetySheetButton)), const Size(320, 52));
      // 아이콘 + 글자 묶음이 버튼 가운데에 온다(pen justifyContent center).
      final button = tester.getRect(find.byType(SafetySheetButton));
      expect((leading.left - button.left) - (button.right - label.right), closeTo(0, 0.5));
    });

    testWidgets('leading 이 없으면 지금과 같은 모양 — 글자 하나만 가운데', (tester) async {
      await pumpButton(tester, SafetySheetButton.primary(label: '차단', onPressed: () {}));

      // 기존 안전 시트(신고 · 차단 · 해제 · 연락처)가 쓰는 모양이다. 줄(Row)을 끼우지 않는다.
      expect(find.descendant(of: find.byType(SafetySheetButton), matching: find.byType(Row)), findsNothing);
      expect(
        find.descendant(of: find.byType(Center), matching: find.text('차단')),
        findsOneWidget,
      );
      expect(tester.getSize(find.byType(SafetySheetButton)), const Size(320, 52));
    });

    testWidgets('글자를 2.0 배로 키워도 leading 과 글자가 잘리지 않고 버튼이 따라 커진다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpButton(
        tester,
        SafetySheetButton.primary(
          label: '10 쓰고 만들기',
          onPressed: () {},
          leading: const SizedBox(key: leadingKey, width: 26, height: 26),
        ),
      );

      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.byType(SafetySheetButton));
      final label = tester.getRect(find.text('10 쓰고 만들기'));
      expect(button.contains(label.topLeft) && button.contains(label.bottomRight), isTrue);
      expect(button.height, greaterThan(52));
    });
  });
}
