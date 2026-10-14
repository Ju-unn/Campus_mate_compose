import 'package:campus_mate/matching/view/countdown_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 다음 카드까지 남은 시간 hh:mm:ss — 오늘 탭 11 과 홈 hero 확인 완료(pen `FMjgB`)가 같이 쓴다.
void main() {
  const style = TextStyle(fontSize: 32);

  Future<void> pump(WidgetTester tester, DateTime target) =>
      tester.pumpWidget(MaterialApp(home: CountdownText(target: target, style: style)));

  testWidgets('남은 시간을 hh:mm:ss 로 보이고 1초마다 줄인다', (tester) async {
    // 남은 초는 기기 시계로 센다(CountdownBuilder) — 첫 프레임까지 걸린 실제 시간만큼 초 자리가 흔들려도 되게 본다.
    await pump(tester, DateTime.now().add(const Duration(hours: 3, minutes: 4, seconds: 5, milliseconds: 500)));
    String label() => tester.widget<Text>(find.byType(Text)).data!;

    expect(label(), matches(RegExp(r'^03:04:0[0-5]$')));
    final before = label();
    // 실제 시계를 1초 넘게 흘린 뒤 타이머 한 번(1초)을 돌리면 글자가 줄어 있다.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100)));
    await tester.pump(const Duration(seconds: 1));
    expect(label(), matches(RegExp(r'^03:04:0[0-4]$')));
    expect(label(), isNot(before));
  });

  testWidgets('지난 시각이면 00:00:00 에 멈춘다', (tester) async {
    await pump(tester, DateTime.now().subtract(const Duration(minutes: 1)));

    expect(find.text('00:00:00'), findsOneWidget);
  });

  testWidgets('숫자 폭이 같다(tabularFigures) — 받은 글자 모양에 없으면 덧붙인다', (tester) async {
    await pump(tester, DateTime.now().add(const Duration(hours: 1)));

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style!.fontSize, 32);
    expect(text.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('1초마다 다시 그리는 칸은 RepaintBoundary 안에 있다 — 옆 그림까지 다시 그리지 않는다', (tester) async {
    await pump(tester, DateTime.now().add(const Duration(hours: 1)));

    expect(find.ancestor(of: find.byType(Text), matching: find.byType(RepaintBoundary)), findsWidgets);
    expect(
      find.descendant(of: find.byType(CountdownText), matching: find.byType(RepaintBoundary)),
      findsOneWidget,
    );
  });
}
