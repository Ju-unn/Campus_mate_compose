import 'package:campus_mate/common/widgets/trait_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 10b 카드 안쪽 폭(360 화면에서 286)에 놓는다.
  Future<void> pump(WidgetTester tester, {double scale = 1.0}) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 286,
              child: TraitBar(name: '친해지기', leftLabel: '낯가림', rightLabel: '금방 친해짐', value: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('이름은 줄 위 왼쪽에 12/600/1.4 #222222 이고 줄과 4 떨어진다(pen TraitLine `G9dS3S`)', (tester) async {
    await pump(tester);

    final name = find.text('친해지기');
    final style = tester.widget<Text>(name).style!;
    expect((style.fontSize, style.fontWeight, style.height, style.color), (12, FontWeight.w600, 1.4, AppColors.ink));
    expect(tester.getTopLeft(name).dx, 0);
    // 라벨이 아니라 줄(Row) 위쪽으로 잰다 — 시험 글꼴에서 "금방 친해짐" 이 두 줄로 접혀 라벨이 가운데로 내려간다.
    final row = find.descendant(of: find.byType(TraitBar), matching: find.byType(Row));
    expect(tester.getTopLeft(row).dy - tester.getBottomLeft(name).dy, 4);
  });

  testWidgets('배율 1.0 에서 라벨 60 · 간격 8 · 바 150 · 간격 8 · 라벨 60 이다', (tester) async {
    // pen `TORAs` 성향 줄 `J8vEs` — 바 `pDG6u` x68 · 폭 150.
    await pump(tester);

    final left = tester.getRect(find.text('낯가림'));
    final bar = tester.getRect(find.descendant(of: find.byType(TraitBar), matching: find.byType(Stack)));
    final right = tester.getRect(find.text('금방 친해짐'));
    expect((left.left, left.width), (0, 60));
    expect((bar.left, bar.width), (68, 150));
    expect((right.left, right.width), (226, 60));
  });

  testWidgets('배율 2.0 에서 라벨 글자가 칸에 잘리지 않는다', (tester) async {
    // 넘침 오류 없이 고정 폭 칸 안에서 조용히 잘린다(백로그 31) — 글자 상자 크기로 본다.
    await pump(tester, scale: 2.0);

    for (final label in ['낯가림', '금방 친해짐']) {
      final p = tester.renderObject<RenderParagraph>(find.text(label));
      expect(p.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(p.size.width + 0.5), reason: label);
      expect(p.getMaxIntrinsicHeight(p.size.width), lessThanOrEqualTo(p.size.height + 0.5), reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('배율 2.0 에서 띄어쓴 라벨은 낱말 사이에서만 줄을 바꾼다', (tester) async {
    // 엔진의 최소 폭은 띄어쓴 한글에서 한 음절 폭이라 "금방/친해/짐" 처럼 낱말 가운데서 갈렸다(14c 검토 권고 1).
    await pump(tester, scale: 2.0);

    // 한 줄짜리 "낯가림" 높이의 두 배 = 두 줄("금방" / "친해짐").
    final oneLine = tester.getSize(find.text('낯가림')).height;
    expect(tester.getSize(find.text('금방 친해짐')).height, oneLine * 2);
  });
}
