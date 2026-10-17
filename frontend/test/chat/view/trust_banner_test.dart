import 'package:campus_mate/chat/view/trust_banner.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/view/pretendard.dart';

/// 채팅방 헤더 아래 배너. 값은 pen 부품 `TrustPreAcceptBanner` `IhqF4`(360×125, 대장이 pen 담당에게 받아 준 값표).
/// 좌표는 배너 왼쪽 위 기준.
void main() {
  const title = '카카오톡 아이디를 먼저 공유해도 돼요';
  const caption = '24시간 뒤에 물어보지만, 지금 수락할 수도 있어요';

  setUpAll(loadPretendard);

  Future<Rect> pump(WidgetTester tester, {double scale = 1, VoidCallback? onAction, bool withAction = true}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: Scaffold(
        body: Column(
          children: [
            TrustBanner(
              title: title,
              caption: caption,
              actionLabel: withAction ? '수락하기' : null,
              onAction: withAction ? (onAction ?? () {}) : null,
            ),
          ],
        ),
      ),
    ));
    return tester.getRect(find.byType(TrustBanner));
  }

  Rect rectOf(WidgetTester tester, Finder finder, Rect banner) => tester.getRect(finder).shift(-banner.topLeft);

  testWidgets('미리 수락 배너(IhqF4) — 360×125 · primary-wash', (tester) async {
    final banner = await pump(tester);

    expect(banner.size, const Size(360, 125));
    final box = find.descendant(of: find.byType(TrustBanner), matching: find.byType(ColoredBox)).first;
    expect(tester.widget<ColoredBox>(box).color, AppColors.primaryWash);
  });

  testWidgets('안내 영역 — 위아래 12 · 좌우 16, shield-check 20 primary-text, 아이콘 → 글자 10, 제목 → 설명 2', (tester) async {
    final banner = await pump(tester);

    final icon = rectOf(tester, find.byIcon(AppIcons.shieldCheck), banner);
    expect(icon.topLeft, const Offset(16, 12));
    final iconWidget = tester.widget<Icon>(find.byIcon(AppIcons.shieldCheck));
    expect((iconWidget.size, iconWidget.color), (20, AppColors.primaryText));
    final titleRect = rectOf(tester, find.text(title), banner);
    expect(titleRect.topLeft, Offset(16 + 20 + 10, 12));
    final captionRect = rectOf(tester, find.text(caption), banner);
    expect(captionRect.left, titleRect.left);
    expect(captionRect.top - titleRect.bottom, 2);
    expect(captionRect.right, lessThanOrEqualTo(360 - 16));
  });

  testWidgets('글자 — 제목 14/600 1.5 ink · 설명 12/400 1.5 muted', (tester) async {
    await pump(tester);

    final titleStyle = tester.widget<Text>(find.text(title)).style!;
    expect((titleStyle.fontSize, titleStyle.fontWeight, titleStyle.height, titleStyle.color), (14, FontWeight.w600, 1.5, AppColors.ink));
    final captionStyle = tester.widget<Text>(find.text(caption)).style!;
    expect((captionStyle.fontSize, captionStyle.fontWeight, captionStyle.height, captionStyle.color), (12, FontWeight.w400, 1.5, AppColors.muted));
  });

  testWidgets('버튼 영역 — 안내 아래 12 · [0,16,16,16] · "수락하기" 328×44 primary', (tester) async {
    final banner = await pump(tester);

    final button = rectOf(tester, find.byType(AppButton), banner);
    final captionRect = rectOf(tester, find.text(caption), banner);
    expect(button.top - captionRect.bottom, 12);
    expect((button.left, button.width, button.height), (16, 328, 44));
    expect(banner.height - button.bottom, 16);
    expect(tester.widget<AppButton>(find.byType(AppButton)).variant, AppButtonVariant.primary);
  });

  testWidgets('"수락하기" 를 누르면 넘긴 동작을 부른다', (tester) async {
    var accepted = 0;
    await pump(tester, onAction: () => accepted += 1);

    await tester.tap(find.text('수락하기'));
    await tester.pump();

    expect(accepted, 1);
  });

  testWidgets('버튼이 없는 배너(14g · 14h · 연결 끊김)는 안내 영역만 — 위아래 12', (tester) async {
    final banner = await pump(tester, withAction: false);

    expect(find.byType(AppButton), findsNothing);
    final captionRect = rectOf(tester, find.text(caption), banner);
    expect(banner.height - captionRect.bottom, 12);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      await pump(tester, scale: scale);

      expect(tester.takeException(), isNull);
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: find.byType(TrustBanner), matching: find.byType(RichText)))) {
        expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5),
            reason: paragraph.text.toPlainText());
      }
    });
  }
}
