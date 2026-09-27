import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/safety/view/block_confirm_sheet.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool? confirmed;

  setUp(() => confirmed = null);

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => confirmed = await showBlockConfirmSheet(context, '토끼'),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('pen aCTy1 문구 그대로 보인다', (tester) async {
    await open(tester);

    expect(find.text('토끼 님을 차단할까요?'), findsOneWidget);
    expect(
      find.text('이 대화는 내 목록에서 사라지고, 서로의 카드에 다시 나타나지 않아요. '
          '상대에게는 대화를 나갔다고 표시돼요. 차단은 설정 > 차단 목록에서 해제할 수 있어요.'),
      findsOneWidget,
    );
    final title = tester.widget<Text>(find.text('토끼 님을 차단할까요?'));
    expect(title.style!.fontSize, 20);
    expect(title.style!.fontWeight, FontWeight.w700);
  });

  testWidgets('차단을 누르면 true', (tester) async {
    await open(tester);

    await tester.tap(find.text('차단'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('취소나 바깥 탭은 false', (tester) async {
    await open(tester);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    confirmed = null;
    await tester.tap(find.text('열기'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });

  testWidgets('버튼 두 종 — 320×52, 모서리 8, 주색·회색 채움', (tester) async {
    await open(tester);

    final block = find.widgetWithText(SafetySheetButton, '차단');
    final cancel = find.widgetWithText(SafetySheetButton, '취소');
    expect(tester.getSize(block), const Size(320, 52));
    expect(tester.getSize(cancel), const Size(320, 52));

    Material materialOf(Finder button) => tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first);
    expect(materialOf(block).color, AppColors.primary);
    expect(materialOf(cancel).color, AppColors.surfaceStrong);
    expect(
      (materialOf(block).shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(8),
    );
    // 버튼 간격 16(pen `cLFGm` → `B6RP1`).
    expect(tester.getTopLeft(cancel).dy - tester.getBottomLeft(block).dy, 16);
  });

  testWidgets('눌림 효과는 버튼 안의 Material 에 그린다(COMMON §4-2)', (tester) async {
    await open(tester);

    for (final label in ['차단', '취소']) {
      final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(material), const Size(320, 52), reason: label);
    }
  });

  testWidgets('글자 2배에서도 넘치거나 잘리는 글자가 없다', (tester) async {
    await open(tester, scale: 2);

    expect(tester.takeException(), isNull);
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: find.byType(SafetySheet), matching: find.byType(RichText)))) {
      expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width),
          lessThanOrEqualTo(paragraph.size.height + 0.5),
          reason: paragraph.text.toPlainText());
    }
    expect(tester.getSize(find.widgetWithText(SafetySheetButton, '차단')).height, greaterThan(52));
  });
}
