import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/common/widgets/select_count_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {TagPickerKind kind = TagPickerKind.interests}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: TagPickerScreen(kind: kind)),
      ),
    );
  }

  Future<void> pick(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.tap(find.byType(SelectChip).at(i));
      await tester.pump();
    }
  }

  Color countTextColor(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(of: find.byType(SelectCountBar), matching: find.byType(Text)).first,
    );
    return text.style!.color!;
  }

  /// 찬 알약 막대 개수(pen `rPoWT` 외 4개 — 20×4).
  int filledBars(WidgetTester tester) {
    final bars = tester.widgetList<Container>(
      find.descendant(of: find.byType(SelectCountBar), matching: find.byType(Container)),
    );
    return bars.where((bar) => (bar.decoration! as BoxDecoration).color == AppColors.primary).length;
  }

  testWidgets('태그 칩은 글자 폭만큼만 넓고 한 줄에 들어가는 만큼 놓인다', (tester) async {
    // pen 은 그리드가 아니다 — erd3 실측(2026-09-26)으로 04-5 는 한 줄에 4·3·2개가 섞여 있다.
    // 칩 폭은 글자에 맞고(마스터 `WzXvK` 패딩 [8,12]) 높이는 36 이다(04-1 기본값 35 와 다르다).
    await pump(tester);

    final chips = find.byType(SelectChip);
    expect(tester.getSize(chips.at(0)).height, 36);
    // 한 글자 태그가 네 글자 태그와 같은 폭으로 늘어나면 줄마다 개수가 pen 과 달라진다.
    final short = tester.getSize(find.widgetWithText(SelectChip, '술')).width;
    final long = tester.getSize(find.widgetWithText(SelectChip, '카페가기')).width;
    expect(short, lessThan(long));
    // 한 줄에 여러 개가 서고, 줄이 차면 다음 줄로 흐른다.
    final firstRow = tester.getTopLeft(chips.at(0)).dy;
    expect(tester.getTopLeft(chips.at(1)).dy, firstRow);
    expect(tester.getTopLeft(chips.at(44)).dy, greaterThan(firstRow));
  });

  testWidgets('막대는 20×4 알약 5개고 문구·안내와 한 줄에 놓인다', (tester) async {
    await pump(tester);

    final bars = find.descendant(
      of: find.byType(SelectCountBar),
      matching: find.byType(Container),
    );
    expect(bars, findsNWidgets(5));
    expect(tester.getSize(bars.first), const Size(20, 4));
    // 알약 사이 간격 4.
    expect(tester.getTopLeft(bars.at(1)).dx - tester.getBottomRight(bars.at(0)).dx, 4);

    // 막대 → 문구 → 안내 순서로 한 줄, 셋 사이 간격 8.
    final count = find.text('0/5개 선택');
    final hint = find.text('· 최소 3개');
    expect(tester.getCenter(count).dy, tester.getCenter(bars.at(4)).dy);
    expect(tester.getTopLeft(count).dx - tester.getBottomRight(bars.at(4)).dx, 8);
    expect(tester.getTopLeft(hint).dx - tester.getBottomRight(count).dx, 8);
  });

  testWidgets('막대 줄 높이는 안내가 있든 없든 20 이다', (tester) async {
    // pen CJQLe 의 두 글자(`GzSZ3`·`R89CUA`)는 줄 높이 속성이 없고 렌더 20 이다(erd3 2026-09-26).
    // 글꼴 기본 줄높이에 맡기면 안내가 보일 때 21.7, 사라지면 16.8 이라 하단 막대가 들썩인다.
    await pump(tester);

    expect(find.text('· 최소 3개'), findsOneWidget);
    expect(tester.getSize(find.byType(SelectCountBar)).height, 20);

    await pick(tester, 3);

    expect(find.text('· 최소 3개'), findsNothing);
    expect(tester.getSize(find.byType(SelectCountBar)).height, 20);
  });

  testWidgets('좁은 화면·큰 글씨에서는 안내가 다음 줄로 내려간다', (tester) async {
    // 한 줄에 욱여넣으려고 글자를 도로 줄이면 글씨 확대(DESIGN §11.2)가 무의미해진다 —
    // 줄을 늘려 흘리고 아무것도 자르지 않는다.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(tester);

    expect(tester.takeException(), isNull);
    // 배율 2.0 이면 글자 한 줄이 40 이다 — 막대가 그보다 낮으면 키운 글자를 줄여 그린 것이다.
    expect(tester.getSize(find.byType(SelectCountBar)).height, greaterThanOrEqualTo(40));
    // 안내는 문구 아래 줄에 서고, 두 글자 모두 화면 안에 들어온다.
    final count = find.text('0/5개 선택');
    final hint = find.text('· 최소 3개');
    expect(tester.getTopLeft(hint).dy, greaterThanOrEqualTo(tester.getBottomRight(count).dy));
    expect(tester.getBottomRight(hint).dx, lessThanOrEqualTo(360));
    expect(tester.getTopLeft(count).dx, greaterThanOrEqualTo(0));
  });

  testWidgets('3개 미만이면 흐린 글자 뒤에 최소 개수를 붙인다', (tester) async {
    await pump(tester);

    expect(find.text('0/5개 선택'), findsOneWidget);
    expect(find.text('· 최소 3개'), findsOneWidget);
    expect(countTextColor(tester), AppColors.muted);
    expect(filledBars(tester), 0);

    await pick(tester, 2);

    expect(find.text('2/5개 선택'), findsOneWidget);
    expect(find.text('· 최소 3개'), findsOneWidget);
    expect(countTextColor(tester), AppColors.muted);
    expect(filledBars(tester), 2);
  });

  testWidgets('3개를 채우면 안내가 사라지고 검은 글자가 된다', (tester) async {
    await pump(tester);

    await pick(tester, 3);

    expect(find.text('3/5개 선택'), findsOneWidget);
    expect(find.text('· 최소 3개'), findsNothing);
    expect(countTextColor(tester), AppColors.ink);
    expect(filledBars(tester), 3);
  });

  testWidgets('5개를 다 고르면 글자가 분홍으로 바뀐다', (tester) async {
    await pump(tester);

    await pick(tester, 5);

    expect(find.text('5/5개 선택'), findsOneWidget);
    // 흰 배경 위 글자라 채움색 primary 가 아니라 primaryText 다(DESIGN.md §2).
    expect(countTextColor(tester), AppColors.primaryText);
    expect(filledBars(tester), 5);
  });

  testWidgets('글자가 가장 긴 태그 목록도 360dp 에서 넘치지 않는다', (tester) async {
    // 06-2 에는 '대화가 잘 통하는' 처럼 8글자 태그가 있다 — 좁은 화면에서 한 칩이 한 줄을 넘지 않는지 본다.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester, kind: TagPickerKind.idealTraits);

    expect(tester.takeException(), isNull);
  });
}
