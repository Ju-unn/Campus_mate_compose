import 'package:campus_mate/common/widgets/pressable.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카드형 누름 반응(DESIGN §7 — press 120ms, 투명도만, 크기 · 위치 고정).
void main() {
  Future<int Function()> pump(WidgetTester tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: () => taps++,
              child: const SizedBox(width: 200, height: 80, child: Text('카드')),
            ),
          ),
        ),
      ),
    );
    return () => taps;
  }

  double opacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.descendant(of: find.byType(Pressable), matching: find.byType(AnimatedOpacity))).opacity;

  testWidgets('누르는 동안 투명도가 [Pressable.pressedOpacity] 로 내려가고 떼면 1 로 돌아온다 — 120ms(press)', (tester) async {
    final taps = await pump(tester);
    final rectBefore = tester.getRect(find.text('카드'));

    final gesture = await tester.startGesture(tester.getCenter(find.text('카드')));
    await tester.pump(kPressTimeout);
    expect(opacity(tester), Pressable.pressedOpacity);
    final animated = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect((animated.duration, animated.curve), (AppMotion.press, AppMotion.pressCurve));
    // 레이아웃을 흔들지 않는다 — 크기 · 자리 그대로.
    expect(tester.getRect(find.text('카드')), rectBefore);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(taps(), 1);
  });

  testWidgets('끌어서 누름이 취소되면 투명도가 돌아오고 누름은 없다', (tester) async {
    final taps = await pump(tester);

    final gesture = await tester.startGesture(tester.getCenter(find.text('카드')));
    await tester.pump(kPressTimeout);
    await gesture.moveBy(const Offset(0, 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(opacity(tester), 1);
    expect(taps(), 0);
  });

  testWidgets('기기 "동작 줄이기"면 투명도는 바뀌되 시간은 0 이다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester);

    final gesture = await tester.startGesture(tester.getCenter(find.text('카드')));
    await tester.pump(kPressTimeout);

    final animated = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect((animated.opacity, animated.duration), (Pressable.pressedOpacity, Duration.zero));
    await gesture.up();
  });

  testWidgets('스크린리더에는 버튼으로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final data = tester.getSemantics(find.text('카드')).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });
}
