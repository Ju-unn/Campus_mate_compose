import 'package:campus_mate/billing/view/heart_purchase_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pretendard.dart';

void main() {
  setUpAll(loadPretendard);

  Future<void> pump(WidgetTester tester, Widget button, {double width = 360, bool disableAnimations = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Center(child: SizedBox(width: width, child: Align(alignment: Alignment.topLeft, child: button))),
          ),
        ),
      ),
    );
  }

  (Color?, Color?) paint(WidgetTester tester, String label) {
    final text = find.text(label);
    final fill = tester.widget<Material>(find.ancestor(of: text, matching: find.byType(Material)).first).color;
    return (fill, tester.widget<Text>(text).style!.color);
  }

  testWidgets('켜짐 — pen `g7Agjb` primary 채움 · 흰 글자 16/700, 글자 폭 + 좌우 16 · 높이 52 · 모서리 14', (tester) async {
    var taps = 0;
    await pump(tester, HeartPurchaseButton(label: '100하트 받기 · 5,700원', onPressed: () => taps++));

    expect(paint(tester, '100하트 받기 · 5,700원'), (AppColors.primary, AppColors.onPrimary));
    final style = tester.widget<Text>(find.text('100하트 받기 · 5,700원')).style!;
    expect((style.fontSize, style.fontWeight), (16, FontWeight.w700));
    final ink = find.byType(InkWell);
    // pen `ipbPs` 192 = 글자 160 + 좌우 16. 글자 폭은 렌더(자간 토큰 −0.16)라 속성(좌우 16)으로 본다.
    expect(tester.getSize(ink).height, 52);
    expect(tester.getSize(ink).width, closeTo(tester.getSize(find.text('100하트 받기 · 5,700원')).width + 32, 0.5));
    final material = tester.widget<Material>(find.ancestor(of: ink, matching: find.byType(Material)).first);
    expect(material.borderRadius, BorderRadius.circular(14));
    await tester.tap(ink);
    expect(taps, 1);
  });

  testWidgets('꺼짐 — 회색 #E5E5E5 · 글자 #929292, 눌러도 아무 일 없다(15e-6 `SLjgz` 지급 확인 중)', (tester) async {
    await pump(tester, const HeartPurchaseButton(label: '지급 확인 중이에요', onPressed: null));

    expect(paint(tester, '지급 확인 중이에요'), (AppColors.primaryDisabled, AppColors.disabled));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('진행 중 — 글자 앞 20 짜리 도는 표시 + 간격 8, 가운데 정렬(18d-3 `SjbFx` 아이콘 x86.5 · 글자 x114.5)', (tester) async {
    await pump(tester, const HeartPurchaseButton(label: '결제 진행 중이에요', onPressed: null, busy: true, expand: true), width: 328);

    final spinner = find.byType(CircularProgressIndicator);
    expect(tester.getSize(spinner), const Size(20, 20));
    final text = tester.getRect(find.text('결제 진행 중이에요'));
    final box = tester.getRect(find.byType(InkWell));
    expect(text.left - tester.getRect(spinner).right, 8);
    // 아이콘 + 8 + 글자 묶음이 가운데(pen 86.5 = (328 − 20 − 8 − 글자 127) / 2 — 글자 폭은 렌더라 양쪽 여백이 같은지로 본다).
    expect(tester.getRect(spinner).left - box.left, closeTo(box.right - text.right, 0.5));
    expect(box.size, const Size(328, 52));
  });

  testWidgets('움직임 줄이기가 켜져 있으면 도는 표시가 멈춘 고리다', (tester) async {
    await pump(
      tester,
      const HeartPurchaseButton(label: '결제 확인 중이에요', onPressed: null, busy: true),
      disableAnimations: true,
    );

    expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value, isNotNull);
  });

  testWidgets('neutral(시트 "취소") — 회색 채움 · 글자 #222222, 꺼지면 글자만 #929292(18d-3 `UTe5A`)', (tester) async {
    await pump(tester, HeartPurchaseButton(label: '취소', neutral: true, expand: true, onPressed: () {}));
    expect(paint(tester, '취소'), (AppColors.primaryDisabled, AppColors.ink));

    await pump(tester, const HeartPurchaseButton(label: '취소', neutral: true, expand: true, onPressed: null));
    expect(paint(tester, '취소'), (AppColors.primaryDisabled, AppColors.disabled));
  });

  testWidgets('글자가 칸보다 길면 줄여 넣는다 — 넘침 오류 없음', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(
      tester,
      const SizedBox(width: 200, child: HeartPurchaseButton(label: '800하트 받기 · 38,400원', onPressed: null, expand: true)),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('낭독 — 버튼 이름 하나, 꺼지면 enabled 아님', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const HeartPurchaseButton(label: '구매할 수 없어요', onPressed: null));

    expect(
      tester.getSemantics(find.bySemanticsLabel('구매할 수 없어요')),
      isSemantics(isButton: true, isEnabled: false),
    );
    handle.dispose();
  });
}
