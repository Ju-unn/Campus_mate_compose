import 'package:campus_mate/common/widgets/app_dialog_route.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _opacity(WidgetTester tester, Finder finder) {
  var value = 1.0;
  for (final fade in tester.widgetList<FadeTransition>(find.ancestor(of: finder, matching: find.byType(FadeTransition)))) {
    value *= fade.opacity.value;
  }
  return value;
}

/// 가운데 팝업 카드 — 크기가 정해진 상자라 커지는 정도를 잴 수 있다.
final _card = find.byKey(const ValueKey('card'));

Widget _host({bool reduceMotion = false}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppDialog<void>(
                  context: context,
                  builder: (_) => const Center(
                    child: SizedBox(key: ValueKey('card'), width: 300, height: 200, child: Text('팝업')),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('팝업은 0.96 에서 easeOut 으로 220ms 동안 살짝 커지며(가운데 기준) 나타난다(사용자 「scale in ease out」)', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('열기'));
    await tester.pump(); // 첫 장면(t = 0)
    final start = tester.getRect(_card);
    final startOpacity = _opacity(tester, _card);
    await tester.pump(AppMotion.appear ~/ 2);
    final mid = tester.getRect(_card);
    final midOpacity = _opacity(tester, _card);
    await tester.pump(AppMotion.appear ~/ 2);
    final rest = tester.getRect(_card);

    expect(rest.size, const Size(300, 200));
    expect(start.width / rest.width, closeTo(0.96, 1e-6));
    expect(start.center.dx, closeTo(rest.center.dx, 1e-6));
    expect(start.center.dy, closeTo(rest.center.dy, 1e-6));
    expect(mid.width / rest.width, closeTo(0.96 + 0.04 * Curves.easeOut.transform(0.5), 1e-6));
    expect(startOpacity, 0);
    expect(midOpacity, closeTo(Curves.easeOut.transform(0.5), 1e-6));
    expect(_opacity(tester, _card), 1);
  });

  testWidgets('닫힐 때는 180ms 동안 easeIn 으로 흐려지며 살짝 줄어든다', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    final rest = tester.getRect(_card);

    Navigator.of(tester.element(_card)).pop();
    await tester.pump(); // 닫히기 시작(τ = 0)
    await tester.pump(AppMotion.disappear ~/ 2);
    final gone = Curves.easeIn.transform(0.5);
    expect(_opacity(tester, _card), closeTo(1 - gone, 1e-6));
    expect(tester.getRect(_card).width / rest.width, closeTo(1 - 0.04 * gone, 1e-6));

    // Flutter 애니메이션은 시간을 "넘긴" 첫 장면에서 끝난다.
    await tester.pump(AppMotion.disappear ~/ 2 + const Duration(milliseconds: 1));
    expect(_card, findsNothing);
  });

  testWidgets('뒤는 모달 딤 토큰(scrim, pen 확인 팝업 값표)이고 바깥을 누르면 닫힌다', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    final barrier = tester.widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier).last);
    expect(barrier.color.value, AppColors.scrim);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_card, findsNothing);
  });

  testWidgets('기기 "동작 줄이기" 면 첫 장면부터 다 커진 채 다 보인다', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    await tester.tap(find.text('열기'));
    await tester.pump();

    expect(tester.getRect(_card).size, const Size(300, 200));
    expect(_opacity(tester, _card), 1);
  });
}
