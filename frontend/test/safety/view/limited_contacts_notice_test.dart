import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/safety/view/limited_contacts_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 8d "일부 연락처만 허용" 안내 카드(pen `KvQom` — 원본 8d `bWKuJ`). 값표는 위젯 소스 주석에 있다.
void main() {
  const title = '일부 연락처만 허용돼 있어요';
  const description = '목록에 보이지 않는 지인이 있다면 기기 설정에서 전체로 바꿔 주세요.';
  const buttonLabel = '기기 설정 열기';

  var openCount = 0;

  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    openCount = 0;
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: LimitedContactsNotice(onOpenSettings: () => openCount += 1)),
      ),
    ));
  }

  Finder cardBox() => find.byKey(limitedContactsNoticeCardKey);
  Finder button() => find.widgetWithText(OutlinedButton, buttonLabel);

  testWidgets('shows title, description and the button label', (tester) async {
    await pump(tester);

    expect(find.text(title), findsOneWidget);
    expect(find.text(description), findsOneWidget);
    expect(find.text(buttonLabel), findsOneWidget);
  });

  testWidgets('outer padding [8,24,12,24]; card fills the width (KvQom)', (tester) async {
    await pump(tester);

    final card = tester.getRect(cardBox());
    expect(card.left, 24);
    expect(card.width, 312);
    expect(tester.getRect(find.byType(LimitedContactsNotice)).top, 0);
    expect(card.top, 8);
    expect(tester.getRect(find.byType(LimitedContactsNotice)).bottom - card.bottom, 12);
  });

  testWidgets('card is #F7F7F7 with radius 12 and no border', (tester) async {
    await pump(tester);

    final decoration = tester.widget<DecoratedBox>(find.descendant(of: cardBox(), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
    expect(decoration.color, AppColors.surfaceSoft);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(decoration.border, isNull);
  });

  testWidgets('title row: blue info 3D icon 18 + 6 + 14/600 ink title; card padding [14,16]', (tester) async {
    await pump(tester);

    final card = tester.getRect(cardBox());
    final icon = tester.getRect(find.byType(Icon3d));
    expect(tester.widget<Icon3d>(find.byType(Icon3d)).icon, AppIcon3d.infoBlue);
    expect(icon.size, const Size(18, 18));
    expect(icon.left - card.left, 16);
    final titleRect = tester.getRect(find.text(title));
    expect(titleRect.left - icon.right, 6);
    // 제목 줄: 위 여백 14. 줄높이 속성 없음, 렌더 ≈ 19.6(14 × 1.4) — 아이콘 18 은 줄 가운데에 선다.
    expect(titleRect.top - card.top, 14);
    expect(icon.center.dy, closeTo(titleRect.center.dy, 0.01));
    final style = tester.widget<Text>(find.text(title)).style!;
    expect(style.fontSize, 14);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.color, AppColors.ink);
  });

  testWidgets('description is 12/400 muted, line height 1.5, 6 below the title', (tester) async {
    await pump(tester);

    final style = tester.widget<Text>(find.text(description)).style!;
    expect(style.fontSize, 12);
    expect(style.fontWeight, FontWeight.w400);
    expect(style.height, 1.5);
    expect(style.color, AppColors.muted);
    final card = tester.getRect(cardBox());
    final desc = tester.getRect(find.text(description));
    expect(desc.left - card.left, 16);
    expect(desc.top - tester.getRect(find.text(title)).bottom, 6);
  });

  testWidgets('button: 44 high, fits its text, white, #DDDDDD 1px border, radius 14, label 14/600 ink', (tester) async {
    await pump(tester);

    final card = tester.getRect(cardBox());
    final rect = tester.getRect(button());
    expect(rect.height, 44);
    expect(rect.left - card.left, 16);
    // 글자에 맞춘 폭 — 카드 폭 가득이 아니다(pen: 폭 hug).
    expect(rect.width, lessThan(card.width / 2));
    final style = tester.widget<OutlinedButton>(button()).style!;
    expect(style.backgroundColor!.resolve({}), AppColors.canvas);
    final side = style.side!.resolve({})!;
    expect(side.color, AppColors.hairline);
    expect(side.width, 1);
    final shape = style.shape!.resolve({}) as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(14));
    final label = tester.widget<Text>(find.text(buttonLabel)).style!;
    expect(label.fontSize, 14);
    expect(label.fontWeight, FontWeight.w600);
    expect(style.foregroundColor!.resolve({}), AppColors.ink);
  });

  testWidgets('vertical rhythm: description → 18 → button → 14 → card end', (tester) async {
    await pump(tester);

    final card = tester.getRect(cardBox());
    final desc = tester.getRect(find.text(description));
    final rect = tester.getRect(button());
    // pen 을 직접 읽은 값: 카드 gap 6 + 투명 Spacer 6 + gap 6 = 18(카드 높이 151).
    expect(rect.top - desc.bottom, 18);
    expect(card.bottom - rect.bottom, 14);
  });

  testWidgets('tapping the button calls onOpenSettings once', (tester) async {
    await pump(tester);

    await tester.tap(button());

    expect(openCount, 1);
  });

  testWidgets('semantics: title is a header, the button reads its label', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(tester.getSemantics(find.text(title)).flagsCollection.isHeader, isTrue);
    final buttonNode = tester.getSemantics(button());
    expect(buttonNode.label, buttonLabel);
    expect(buttonNode.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale: 넘침 없음 · 단추 터치 높이 44 이상', (tester) async {
      await pump(tester, scale: scale);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(button()).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(button()).width, greaterThanOrEqualTo(44));
      final clipped = [
        for (final element in find.byType(RichText).evaluate())
          if (element.renderObject case final RenderParagraph p
              when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                  p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
            p.text.toPlainText(),
      ];
      expect(clipped, isEmpty);
    });
  }
}
