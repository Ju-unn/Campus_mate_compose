import 'package:campus_mate/home/view/auto_marquee.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 홈 줄 자동 흐름(사람 레일 `mw7Gv` 규칙을 칩 줄 `yo9JJ` 도 같이 쓴다, 대장 10-15): 오른쪽 · 20px/초 · 누르면 멈춤 ·
/// 떼면 재개 · 동작 줄이기에서는 멈춰 있고 손으로 밀 수 있다 · 한 벌을 복제해 끝없이 · 화면 읽기는 한 벌만.
/// 여기서는 폭을 모르는 한 벌(글자 칩처럼)로 본다 — 폭을 아는 쪽(레일)은 mosaic_rail_test 가 본다.
void main() {
  const labels = ['가람대', '새솔대', '누리대', '한빛대', '다온대'];

  /// 한 벌 = 글자 칸 다섯 + 뒤 간격. 폭은 글꼴 · 배율마다 달라 마퀴가 그린 뒤 잰다.
  final cycle = Row(
    children: [
      for (final label in labels) ...[Text(label), const SizedBox(width: 6)],
    ],
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AutoMarquee(cycle: cycle))));
    await tester.pump(); // 한 벌 폭을 잰 다음 프레임
  }

  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// 화면 왼쪽 끝(x0) 이후에서 처음 보이는 "가람대" 의 자리.
  double firstX(WidgetTester tester) => [
        for (var i = 0; i < find.text(labels.first).evaluate().length; i++) tester.getTopLeft(find.text(labels.first).at(i)).dx,
      ].where((x) => x >= 0).reduce((a, b) => a < b ? a : b);

  double cycleWidth(WidgetTester tester) =>
      tester.getTopLeft(find.text(labels.first).at(1)).dx - tester.getTopLeft(find.text(labels.first).at(0)).dx;

  testWidgets('멈춰 있을 때는 한 벌이 왼쪽 끝(x0)에서 시작하고, 시간이 지나면 오른쪽으로 초당 20 흐른다', (tester) async {
    await pump(tester);
    expect(firstX(tester), 0);

    await tester.pump(const Duration(seconds: 1));

    expect(firstX(tester), closeTo(20, 0.5));
  });

  testWidgets('한 벌을 이어 붙여 화면을 다 덮는다 — 흘러도 빈 곳이 없다', (tester) async {
    await pump(tester);
    final width = tester.getSize(find.byType(AutoMarquee)).width;

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 2));
      final xs = [for (var j = 0; j < find.text(labels.last).evaluate().length; j++) tester.getTopRight(find.text(labels.last).at(j)).dx];
      expect(xs.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(width - cycleWidth(tester)), reason: '$i');
      expect(firstX(tester), lessThanOrEqualTo(cycleWidth(tester)), reason: '$i');
    }
  });

  testWidgets('누르고 있으면 멈추고, 떼면 다시 흐른다', (tester) async {
    await pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text(labels[2]).at(1)));
    await tester.pump(const Duration(milliseconds: 100));
    final held = firstX(tester);

    await tester.pump(const Duration(seconds: 1));
    expect(firstX(tester), held);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(firstX(tester), greaterThan(held));
  });

  group('기기 "동작 줄이기"', () {
    testWidgets('저절로 흐르지 않는다', (tester) async {
      reduceMotion(tester);
      await pump(tester);
      final before = firstX(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(firstX(tester), before);
    });

    testWidgets('가로로 밀면 손이 간 만큼 따라 움직이고, 놓으면 그 자리에 멈춰 있다', (tester) async {
      reduceMotion(tester);
      await pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.text(labels[2]).at(1)));
      await gesture.moveBy(const Offset(kDragSlopDefault, 0));
      await tester.pump();
      final start = firstX(tester);

      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(firstX(tester) - start, closeTo(30, 0.01));

      await gesture.up();
      await tester.pump();
      final released = firstX(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(firstX(tester), released);
    });
  });

  testWidgets('화면 읽기(스크린리더)가 켜져 있으면 저절로 흐르지 않는다 — WCAG 2.2.2 움직임 멈춤', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester);
    final before = firstX(tester);

    await tester.pump(const Duration(seconds: 1));

    expect(firstX(tester), before);
  });

  testWidgets('한 벌 폭이 0 이면(그릴 것이 없음) 흐르지도 밀리지도 않고 예외 없이 그린다', (tester) async {
    for (final reduce in [false, true]) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: reduce);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AutoMarquee(cycle: SizedBox(height: 28)))));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(find.byType(AutoMarquee), const Offset(60, 0));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'reduce=$reduce');
    }
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });

  testWidgets('화면 읽기는 복사본을 빼고 한 벌만 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    for (final label in labels) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    handle.dispose();
  });
}
