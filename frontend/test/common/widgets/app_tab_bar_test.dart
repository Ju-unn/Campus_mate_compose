import 'dart:ui' show Tristate;

import 'package:campus_mate/common/widgets/app_tab_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 공용 밑줄 탭 바(pen `p9s0G` Tab Bar). 나 탭 카드 미리보기(15-4 · 15-4b)와 대화 탭(13 [대화] · [보낸 신청])이 함께 쓴다.
void main() {
  Future<List<int>> pump(WidgetTester tester, {int selected = 0, double textScale = 1}) async {
    final taps = <int>[];
    tester.view.physicalSize = const Size(360, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(360, 200), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [AppTabBar(labels: const ['대화', '보낸 신청'], selected: selected, onSelected: taps.add)],
          ),
        ),
      ),
    ));
    return taps;
  }

  Finder tabOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

  testWidgets('보이는 줄 44 · 누르는 칸 48, 두 탭은 같은 폭, 아래 선 1px hairline-soft 는 보이는 줄 맨 아래', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.byType(AppTabBar)), const Size(360, AppTabBar.height + AppTabBar.extraHitHeight));
    expect((AppTabBar.height, AppTabBar.extraHitHeight), (44.0, 4.0));
    for (final label in ['대화', '보낸 신청']) {
      expect(tester.getSize(tabOf(label)), const Size(180, 48), reason: label);
    }
    final line = find.byWidgetPredicate((w) => w is ColoredBox && w.color == AppColors.hairlineSoft);
    expect(tester.getSize(line).height, 1);
    expect(tester.getRect(line).bottom, 44);
  });

  testWidgets('고른 탭은 14/700 primary-text + 밑줄 2px, 안 고른 탭은 14/500 muted + 밑줄 투명', (tester) async {
    await pump(tester, selected: 1);

    final on = tester.widget<Text>(find.text('보낸 신청')).style!;
    final off = tester.widget<Text>(find.text('대화')).style!;
    expect((on.fontSize, on.fontWeight, on.color), (14, FontWeight.w700, AppColors.primaryText));
    expect((off.fontSize, off.fontWeight, off.color), (14, FontWeight.w500, AppColors.muted));
    Color underline(String label) => tester
        .widget<Container>(find.descendant(of: tabOf(label), matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 2)))
        .color!;
    expect(underline('보낸 신청'), AppColors.primaryText);
    expect(underline('대화'), Colors.transparent);
  });

  testWidgets('탭을 누르면 그 순서를 알린다', (tester) async {
    final taps = await pump(tester);

    await tester.tap(find.text('보낸 신청'));
    await tester.tap(find.text('대화'));

    expect(taps, [1, 0]);
  });

  testWidgets('화면 읽기 — 탭마다 버튼 · 고름 상태 · 글자', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final data = tester.getSemantics(find.text('대화')).getSemanticsData();
    expect(data.label, '대화');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(tester.getSemantics(find.text('보낸 신청')).getSemanticsData().flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('글자 2배에서도 넘치지 않고 탭 바가 늘어난다', (tester) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AppTabBar)).height, greaterThan(48));
  });
}
