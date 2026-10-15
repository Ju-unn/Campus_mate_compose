import 'package:campus_mate/common/widgets/trait_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _sliderLabel = '집이 편해요부터 밖이 좋아요까지';

void main() {
  Future<void> pump(WidgetTester tester, double? value, {ValueChanged<double>? onChanged}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitSlider(
            value: value,
            onChanged: onChanged ?? (_) {},
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

  testWidgets('점을 누르면 그 칸을 고른다', (tester) async {
    final picked = <double>[];
    await pump(tester, 0, onChanged: picked.add);

    await tester.tap(dots().at(4));

    expect(picked, [1]);
  });

  // DESIGN §8.5 `trait-slider` "탭 또는 드래그(5칸 스냅)".
  testWidgets('가로로 끌면 손가락에 가장 가까운 칸으로 붙는다(5칸 스냅)', (tester) async {
    final picked = <double>[];
    await pump(tester, -1, onChanged: picked.add);
    final first = tester.getCenter(dots().at(0));
    final fourth = tester.getCenter(dots().at(3));

    // 넷째 점을 조금 지나서 놓는다 — 다섯째보다 넷째가 가깝다.
    await tester.dragFrom(first, Offset(fourth.dx - first.dx + 10, 0));

    expect(picked.last, 0.5);
  });

  testWidgets('끌다가 트랙 끝을 넘어가도 끝 칸에 머문다', (tester) async {
    final picked = <double>[];
    await pump(tester, 0, onChanged: picked.add);

    await tester.dragFrom(tester.getCenter(dots().at(2)), const Offset(2000, 0));

    expect(picked.last, 1);
  });

  testWidgets('낭독기에는 슬라이더 하나로 읽히고, 올리기 · 내리기로 한 칸씩 옮긴다', (tester) async {
    final handle = tester.ensureSemantics();
    final picked = <double>[];
    await pump(tester, 0, onChanged: picked.add);

    final slider = find.bySemanticsLabel(_sliderLabel);
    expect(
      tester.getSemantics(slider),
      isSemantics(
        isSlider: true,
        value: '5단계 중 3단계',
        increasedValue: '5단계 중 4단계',
        decreasedValue: '5단계 중 2단계',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    final node = tester.getSemantics(slider);
    node.owner!.performAction(node.id, SemanticsAction.increase);
    node.owner!.performAction(node.id, SemanticsAction.decrease);

    expect(picked, [0.5, -0.5]);
    handle.dispose();
  });

  testWidgets('끝 칸에서는 더 갈 쪽 동작이 없다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, 1);

    expect(
      tester.getSemantics(find.bySemanticsLabel(_sliderLabel)),
      isSemantics(value: '5단계 중 5단계', hasIncreaseAction: false, hasDecreaseAction: true),
    );
    handle.dispose();
  });

  testWidgets('손가락이 닿는 칸 높이는 44 다', (tester) async {
    // 눈에 보이는 점은 28 이하지만 터치 영역은 DESIGN.md §5.3 최소 44×44 를 지킨다.
    await pump(tester, 0);

    final cell = find.ancestor(of: dots().at(0), matching: find.byType(GestureDetector)).first;
    expect(tester.getSize(cell).height, 44);
  });
}
