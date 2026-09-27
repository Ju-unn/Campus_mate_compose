import 'package:campus_mate/chat/view/trust_reveal_bubble.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 14b 신뢰 확인 카드(pen `albnG` 안 `fjiZE` = `MAn9h` 마스터, 덮어쓰기 없음). 좌표는 카드 왼쪽 위 기준.
void main() {
  Future<Rect> pump(
    WidgetTester tester, {
    String? kakaoId = 'minseo_choi',
    double scale = 1,
    VoidCallback? onViewProfile,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // 실제처럼 대화 목록(세로 제한 없음) 안에 둔다. pen 카드 폭 328(대화 목록 좌우 여백 16).
        body: ListView(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 328,
                child: TrustRevealBubble(kakaoId: kakaoId, onViewProfile: onViewProfile ?? () {}),
              ),
            ),
          ],
        ),
      ),
    ));
    return tester.getRect(find.byType(TrustRevealBubble));
  }

  Rect rectOf(WidgetTester tester, Finder finder, Rect card) => tester.getRect(finder).shift(-card.topLeft);

  Finder kakaoRow() => find.ancestor(of: find.text('카카오톡 아이디'), matching: find.byType(Container)).first;

  testWidgets('배지는 shield-check 14 이고 글자와 6 떨어진다(pen ha583)', (tester) async {
    await pump(tester);

    final icon = tester.widget<Icon>(find.byIcon(AppIcons.shieldCheck));
    expect(icon.size, 14);
    expect(icon.color, AppColors.primaryText);
    expect(
      tester.getTopLeft(find.text('신뢰 확인 완료')).dx - tester.getTopRight(find.byIcon(AppIcons.shieldCheck)).dx,
      6,
    );
  });

  testWidgets('세로 자리는 pen 과 같다 — 배지 16 · 제목 43 · 카톡 76(60) · 버튼 146 · 카드 206', (tester) async {
    final card = await pump(tester);

    expect(rectOf(tester, find.text('신뢰 확인 완료'), card).top, 16);
    final title = rectOf(tester, find.text('서로 실제 프로필을 공개했어요'), card);
    expect(title.top, 43);
    // pen `lIf91` 줄높이 1.4 를 렌더 23 으로 그린다 — 뒤 자리가 23 기준이라 23 에 맞춘다.
    expect(title.height, 23);
    final kakao = rectOf(tester, kakaoRow(), card);
    expect(kakao.top, 76);
    expect(kakao.height, 60);
    final button = find.ancestor(of: find.text('상대 프로필 보기'), matching: find.byType(InkWell)).first;
    expect(rectOf(tester, button, card).top, 146);
    expect(card.height, 206);
  });

  testWidgets('상대 프로필 보기 — 버튼 안을 한 번 누르면 넓힌 누르는 영역과 겹쳐도 한 번만 불린다', (tester) async {
    var opened = 0;
    await pump(tester, onViewProfile: () => opened += 1);

    await tester.tap(find.text('상대 프로필 보기'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('카톡 행 — 여백 [10,12], 라벨 11 보통 굵기, 라벨과 값 사이 2, 복사 아이콘 x 266', (tester) async {
    final card = await pump(tester);

    final row = rectOf(tester, kakaoRow(), card);
    final label = rectOf(tester, find.text('카카오톡 아이디'), card);
    final value = rectOf(tester, find.text('minseo_choi'), card);
    expect(label.top - row.top, 10);
    expect(label.left - row.left, 12);
    expect(label.height, 16);
    expect(value.top - label.bottom, 2);
    expect(value.height, 22);
    final labelStyle = tester.widget<Text>(find.text('카카오톡 아이디')).style!;
    expect(labelStyle.fontSize, 11);
    expect(labelStyle.fontWeight, FontWeight.w400);
    // 보이는 아이콘은 pen 자리(`FZqNL` 행 안 x 266, y 21) 그대로, 누르는 영역은 48 이다.
    final copy = rectOf(tester, find.byIcon(AppIcons.copy), card);
    expect(copy.left - row.left, 266);
    expect(copy.top - row.top, 21);
    final copyButton = find.ancestor(of: find.byIcon(AppIcons.copy), matching: find.byType(IconButton));
    expect(tester.getSize(copyButton), const Size(48, 48));
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      await pump(tester, scale: scale);

      expect(tester.takeException(), isNull);
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: find.byType(TrustRevealBubble), matching: find.byType(RichText)))) {
        expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5),
            reason: paragraph.text.toPlainText());
      }
    });
  }
}
