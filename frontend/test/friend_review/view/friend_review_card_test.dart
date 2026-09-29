import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_friend_review_repository.dart';

/// pen `S0MR2b` 마스터 본문(`kgCWd`) — 296 폭에서 두 줄.
const _comment = '처음엔 조용해 보여도 친해지면 누구보다 세심하게 챙겨주는 친구예요.';

/// FriendReviewCard(pen `S0MR2b`, 값표 B §3). 폭은 부모가 준다(20c · 14d 328, 14c 288).
void main() {
  Future<void> pump(
    WidgetTester tester,
    FriendReview review, {
    VoidCallback? onReport,
    double width = 328,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: FriendReviewCard(review: review, onReport: onReport)),
        ),
      ),
    ));
  }

  FriendReview pen({String? university = '서울대학교', String? comment = _comment, List<String>? tags}) =>
      friendReviewFixture(
        nickname: '달빛',
        university: university,
        tags: tags ?? const ['약속을 잘 지켜요', '대화가 편해요'],
        comment: comment,
      );

  Rect box(WidgetTester tester, String text) =>
      tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(Container)).first);

  testWidgets('학교 배지 · 이니셜 · 닉네임 · 관계 · 태그 · 한마디가 pen 자리에 있다(높이 179)', (tester) async {
    await pump(tester, pen());

    final card = tester.getRect(find.byType(FriendReviewCard));
    expect(card.size, const Size(328, 179));
    // 머리 줄 y16 · 48 — 배지 36 → 10 → 이니셜 36 → 10 → 이름 칸.
    final badge = box(tester, '서');
    expect(badge.size, const Size(36, 36));
    expect(badge.topLeft - card.topLeft, const Offset(16, 22));
    final initial = box(tester, '달');
    expect(initial.size, const Size(36, 36));
    expect(initial.left - badge.right, 10);
    final name = tester.getRect(find.text('달빛'));
    expect(name.left - initial.right, 10);
    expect(name.height, 24);
    final relation = tester.getRect(find.text(friendReviewRelationLabel));
    expect(relation.top - name.bottom, 1);
    expect(relation.height, 19);
    // 이름 칸 44 는 머리 줄 48 가운데.
    expect(name.top - card.top, 16 + 2);
    // 태그 줄 y76 · 31, 본문 y119 · 44.
    final chip = box(tester, '약속을 잘 지켜요');
    expect(chip.top - card.top, 76);
    expect(chip.height, 31);
    expect(chip.left - card.left, 16);
    expect(box(tester, '대화가 편해요').left - chip.right, 8);
    final body = tester.getRect(find.text(_comment));
    expect(body.top - card.top, 119);
    expect(body.height, 44);
    expect(body.width, 296);
  });

  testWidgets('색 · 글자 — 배지 surfaceInk r8 흰 12/700, 이니셜 primaryWash 원 14/700, 칩 primaryWash 12/600', (tester) async {
    await pump(tester, pen());

    final card = tester.widget<Container>(
        find.descendant(of: find.byType(FriendReviewCard), matching: find.byType(Container)).first);
    expect((card.decoration! as BoxDecoration).color, AppColors.canvas);
    expect((card.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(14));
    expect(((card.foregroundDecoration! as BoxDecoration).border! as Border).top.color, AppColors.hairline);
    expect((card.decoration! as BoxDecoration).boxShadow, isNull);

    BoxDecoration decorationOf(String text) => tester
        .widget<Container>(find.ancestor(of: find.text(text), matching: find.byType(Container)).first)
        .decoration! as BoxDecoration;
    expect(decorationOf('서').color, AppColors.surfaceInk);
    expect(decorationOf('서').borderRadius, BorderRadius.circular(8));
    expect(decorationOf('달').color, AppColors.primaryWash);
    expect(decorationOf('달').shape, BoxShape.circle);
    expect(decorationOf('약속을 잘 지켜요').color, AppColors.primaryWash);

    TextStyle styleOf(String text) => tester.widget<Text>(find.text(text)).style!;
    expect((styleOf('서').color, styleOf('서').fontSize, styleOf('서').fontWeight), (AppColors.onInk, 12, FontWeight.w700));
    expect((styleOf('달').color, styleOf('달').fontSize, styleOf('달').fontWeight),
        (AppColors.primaryText, 14, FontWeight.w700));
    expect((styleOf('달빛').color, styleOf('달빛').fontSize, styleOf('달빛').fontWeight), (AppColors.ink, 16, FontWeight.w600));
    final relation = styleOf(friendReviewRelationLabel);
    expect((relation.color, relation.fontSize, relation.fontWeight), (AppColors.muted, 12, FontWeight.w400));
    final tag = styleOf('약속을 잘 지켜요');
    expect((tag.color, tag.fontSize, tag.fontWeight), (AppColors.primaryText, 12, FontWeight.w600));
    final body = styleOf(_comment);
    expect((body.color, body.fontSize, body.fontWeight), (AppColors.body, 14, FontWeight.w400));
  });

  test('관계 문구는 고정 "추천으로 연결된 친구"(DB · API 에 관계 칸이 없다)', () {
    expect(friendReviewRelationLabel, '추천으로 연결된 친구');
  });

  testWidgets('학교가 없으면 배지 없이 이니셜이 맨 앞이다', (tester) async {
    await pump(tester, pen(university: null));

    expect(find.text('서'), findsNothing);
    expect(box(tester, '달').left - tester.getRect(find.byType(FriendReviewCard)).left, 16);
  });

  testWidgets('한마디가 없으면 본문 줄과 그 위 간격 12 가 없다(높이 123)', (tester) async {
    await pump(tester, pen(comment: null));

    expect(tester.getSize(find.byType(FriendReviewCard)).height, 16 + 48 + 12 + 31 + 16);
  });

  testWidgets('onReport 가 없으면 깃발이 없다', (tester) async {
    await pump(tester, pen());

    expect(find.byIcon(AppIcons.flag), findsNothing);
  });

  testWidgets('onReport 가 있으면 머리 줄 오른쪽 끝에 깃발 20 · 누름칸 48×48, 누르면 한 번 불린다', (tester) async {
    var reported = 0;
    await pump(tester, pen(), onReport: () => reported += 1);

    final flag = tester.widget<Icon>(find.byIcon(AppIcons.flag));
    expect((flag.size, flag.color), (20, AppColors.muted));
    final button = find.ancestor(of: find.byIcon(AppIcons.flag), matching: find.byType(IconButton));
    final cell = tester.getRect(button);
    expect(cell.size, const Size(48, 48));
    final card = tester.getRect(find.byType(FriendReviewCard));
    expect(card.right - cell.right, 16);
    expect(cell.top - card.top, 16);
    await tester.tap(button);
    expect(reported, 1);
  });

  testWidgets('태그 3개가 좁은 폭(288)에서 넘치지 않고 다음 줄로 내려간다', (tester) async {
    await pump(tester, pen(tags: const ['이야기를 잘 들어줘요', '유머 감각이 좋아요', '리액션이 좋아요']), width: 288);

    expect(tester.takeException(), isNull);
    expect(box(tester, '리액션이 좋아요').top, greaterThan(box(tester, '이야기를 잘 들어줘요').bottom));
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다.
  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      await pump(tester, pen(), onReport: () {}, width: 288, scale: scale);

      expect(tester.takeException(), isNull);
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
