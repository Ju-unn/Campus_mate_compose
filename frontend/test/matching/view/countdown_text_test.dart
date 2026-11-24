import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/matching/view/countdown_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 다음 카드까지 남은 시간 hh:mm:ss(24시간 이상이면 앞에 N일) — 오늘 탭 11 과 홈 hero 확인 완료(pen `FMjgB`)가 같이 쓴다.
void main() {
  const style = TextStyle(fontSize: 32);

  Future<void> pump(WidgetTester tester, DateTime target) =>
      tester.pumpWidget(MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: CountdownText(target: target, style: style)));

  testWidgets('남은 시간을 hh:mm:ss 로 보이고 1초마다 줄인다', (tester) async {
    // 남은 초는 기기 시계로 센다(CountdownBuilder) — 첫 프레임까지 걸린 실제 시간(부하가 크면 수십 초)만큼 흔들려도 되게 분 · 초는 넓게 본다.
    await pump(tester, DateTime.now().add(const Duration(hours: 3, minutes: 4, seconds: 5, milliseconds: 500)));
    String label() => tester.widget<Text>(find.byType(Text)).data!;

    expect(label(), matches(RegExp(r'^03:0[34]:\d\d$')));
    final before = label();
    // 실제 시계를 1초 넘게 흘린 뒤 타이머 한 번(1초)을 돌리면 글자가 줄어 있다.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100)));
    await tester.pump(const Duration(seconds: 1));
    expect(label(), matches(RegExp(r'^03:0[34]:\d\d$')));
    expect(label(), isNot(before));
  });

  group('nextCardCountdownLabel — 24시간 이상이면 "N일 hh:mm:ss"(1.0.7 #14), 미만은 채팅 기한과 같은 hh:mm:ss', () {
    final l10n = AppLocalizationsKo();
    String label(Duration remaining) => nextCardCountdownLabel(l10n, remaining);

    test('151:20:05 → 6일 07:20:05', () {
      expect(label(const Duration(hours: 151, minutes: 20, seconds: 5)), '6일 07:20:05');
    });

    test('정확히 24:00:00 → 1일 00:00:00', () {
      expect(label(const Duration(hours: 24)), '1일 00:00:00');
    });

    test('23:59:59 는 일을 붙이지 않는다', () {
      expect(label(const Duration(hours: 23, minutes: 59, seconds: 59)), '23:59:59');
    });

    test('0 · 음수는 지금처럼 00:00:00', () {
      expect(label(Duration.zero), '00:00:00');
      expect(label(const Duration(seconds: -5)), '00:00:00');
      expect(label(const Duration(days: -2)), '00:00:00');
    });
  });

  testWidgets('6일 넘게 남으면 화면에도 "6일 07:20:0x" 로 보인다', (tester) async {
    await pump(tester, DateTime.now().add(const Duration(hours: 151, minutes: 20, seconds: 5, milliseconds: 500)));

    expect(tester.widget<Text>(find.byType(Text)).data, matches(RegExp(r'^6일 07:\d\d:\d\d$')));
  });

  testWidgets('지난 시각이면 00:00:00 에 멈춘다', (tester) async {
    await pump(tester, DateTime.now().subtract(const Duration(minutes: 1)));

    expect(find.text('00:00:00'), findsOneWidget);
  });

  testWidgets('0 이 되면 onDone 을 한 번 부른다(다음 카드 다시 읽기 신호)', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CountdownText(target: DateTime.now().subtract(const Duration(seconds: 1)), style: style, onDone: () => calls++),
    ));
    await tester.pump(const Duration(seconds: 3));

    expect(calls, 1);
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
