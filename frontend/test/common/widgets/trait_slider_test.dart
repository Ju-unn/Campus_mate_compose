import 'package:campus_mate/common/widgets/trait_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, double? value) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitSlider(
            value: value,
            onChanged: (_) {},
            leftLabel: '집이 편해요',
            rightLabel: '밖이 좋아요',
          ),
        ),
      ),
    );
  }

  Finder dots() => find.descendant(
        of: find.byType(TraitSlider),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );

  testWidgets('점은 비선택 18 · 선택 28 이다', (tester) async {
    // pen `mkf89` 값. 종전 12/18 은 실기기에서 어디를 골랐는지 잘 안 보였다.
    await pump(tester, 0);

    expect(dots(), findsNWidgets(TraitSlider.steps.length));
    expect(tester.getSize(dots().at(2)), const Size(28, 28));
    expect(tester.getSize(dots().at(0)), const Size(18, 18));
    expect(tester.getSize(dots().at(4)), const Size(18, 18));
  });
}
