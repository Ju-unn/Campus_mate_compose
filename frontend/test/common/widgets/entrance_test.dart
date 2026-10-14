import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 처음 그릴 때 한 번 — 투명 + 아래에서 제자리로(DESIGN §7). transform · opacity 만 쓴다.
void main() {
  Future<void> pump(WidgetTester tester, Entrance entrance) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topLeft, child: entrance))),
      );

  double opacityOf(WidgetTester tester) =>
      tester.widget<Opacity>(find.descendant(of: find.byType(Entrance), matching: find.byType(Opacity))).opacity;

  double yOf(WidgetTester tester) => tester.getTopLeft(find.text('블록')).dy;

  testWidgets('처음엔 투명하고 [rise] 만큼 아래에 있다가, 시간이 다 되면 제자리 · 불투명이다', (tester) async {
    await pump(tester, const Entrance(rise: 16, child: Text('블록')));

    expect(opacityOf(tester), 0);
    expect(yOf(tester), 16);

    await tester.pump(AppMotion.standard);
    expect(opacityOf(tester), 1);
    expect(yOf(tester), 0);
  });

  testWidgets('[delay] 동안은 처음 모양 그대로 기다린다', (tester) async {
    await pump(tester, const Entrance(rise: 8, delay: Duration(milliseconds: 120), child: Text('블록')));

    await tester.pump(const Duration(milliseconds: 100));
    expect((opacityOf(tester), yOf(tester)), (0, 8));

    await tester.pumpAndSettle();
    expect((opacityOf(tester), yOf(tester)), (1, 0));
  });

  testWidgets('[scaleFrom] 은 크기만 키운다 — emphasis 커브가 넘쳐도 투명도는 1 을 넘지 않는다', (tester) async {
    await pump(
      tester,
      const Entrance(scaleFrom: 0.92, duration: AppMotion.emphasis, curve: AppMotion.emphasisCurve, child: Text('블록')),
    );

    double scale() => tester
        .widget<Transform>(find.descendant(of: find.byType(Entrance), matching: find.byType(Transform)))
        .transform
        .entry(0, 0);
    expect(scale(), closeTo(0.92, 1e-6));
    for (var ms = 0; ms < AppMotion.emphasis.inMilliseconds; ms += 30) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(opacityOf(tester), inInclusiveRange(0, 1));
    }
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, 1e-6));
  });

  testWidgets('기기 "동작 줄이기"면 처음부터 최종 상태다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await pump(tester, const Entrance(rise: 16, child: Text('블록')));

    expect((opacityOf(tester), yOf(tester)), (1, 0));
  });

  testWidgets('enabled 가 false 면 움직이지 않는다', (tester) async {
    await pump(tester, const Entrance(rise: 16, enabled: false, child: Text('블록')));

    expect((opacityOf(tester), yOf(tester)), (1, 0));
  });

  testWidgets('투명한 동안에도 스크린리더는 읽는다 — 효과 때문에 내용이 사라지지 않는다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const Entrance(rise: 16, child: Text('블록')));

    expect(opacityOf(tester), 0);
    expect(find.bySemanticsLabel('블록'), findsOneWidget);
    handle.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('움직이는 동안에도 누를 수 있다', (tester) async {
    var taps = 0;
    await pump(
      tester,
      Entrance(rise: 16, child: TextButton(onPressed: () => taps++, child: const Text('블록'))),
    );

    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('블록'));
    expect(taps, 1);
  });
}
