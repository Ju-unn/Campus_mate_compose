import 'package:campus_mate/common/widgets/app_bottom_sheet.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(400, 800);
const double _sheetHeight = 300;
final _sheet = find.byKey(const ValueKey('sheet'));

Widget _host({bool reduceMotion = false}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppBottomSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(key: ValueKey('sheet'), height: _sheetHeight, child: Text('시트')),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

/// 시트 뒤 딤의 지금 색.
Color _dim(WidgetTester tester) => tester.widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier).last).color.value!;

void main() {
  Future<void> open(WidgetTester tester, {bool reduceMotion = false}) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(reduceMotion: reduceMotion));
    await tester.tap(find.text('열기'));
    await tester.pump(); // 첫 장면(t = 0)
  }

  testWidgets('시트는 아래에서 standard(220ms · easeOutCubic)로 올라오고 뒷배경은 모달 딤 토큰까지 fade 로 어두워진다', (tester) async {
    await open(tester);
    expect(tester.getRect(_sheet).top, _screen.height);
    expect(_dim(tester).a, 0);

    await tester.pump(AppMotion.appear ~/ 2);
    expect(
      tester.getRect(_sheet).top,
      closeTo(_screen.height - _sheetHeight * Curves.easeOutCubic.transform(0.5), 0.01),
    );
    // 딤은 Flutter 기본 그대로 경로 진행에 Curves.ease 를 걸어 짙어진다.
    expect(_dim(tester).a, closeTo(AppColors.scrim.a * Curves.ease.transform(0.5), 1e-3));

    await tester.pump(AppMotion.appear ~/ 2);
    expect(tester.getRect(_sheet).top, _screen.height - _sheetHeight);
    expect(_dim(tester), AppColors.scrim);
  });

  testWidgets('닫힐 때는 180ms 동안 easeIn 으로 내려간다', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();

    Navigator.of(tester.element(_sheet)).pop();
    await tester.pump();
    await tester.pump(AppMotion.disappear ~/ 2);
    expect(
      tester.getRect(_sheet).top,
      closeTo(_screen.height - _sheetHeight * (1 - Curves.easeIn.transform(0.5)), 0.01),
    );
    // Flutter 애니메이션은 시간을 "넘긴" 첫 장면에서 끝난다.
    await tester.pump(AppMotion.disappear ~/ 2 + const Duration(milliseconds: 1));
    expect(_sheet, findsNothing);
  });

  testWidgets('바탕은 투명이라 시트가 자기 모양을 그린다', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor, Colors.transparent);
  });

  testWidgets('기기 "동작 줄이기" 면 첫 장면부터 올라와 있고 딤도 다 어둡다', (tester) async {
    await open(tester, reduceMotion: true);
    expect(tester.getRect(_sheet).top, _screen.height - _sheetHeight);
    expect(_dim(tester), AppColors.scrim);
  });
}
