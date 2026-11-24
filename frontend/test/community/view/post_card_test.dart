import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/view/category_label.dart';
import 'package:campus_mate/community/view/post_card.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_community_repository.dart';

/// pen PostCard · Feed `WHqdP` / PostCard · Detail `UCWuL` (328 폭, 값표 0-3).
void main() {
  final now = DateTime(2026, 11, 24, 14, 3);
  const longText = '다들 첫 데이트 장소 어디로 정하세요? 너무 뻔한 데 말고 대화하기 좋은 곳 추천해 주세요. '
      '카페는 이미 많이 가 봤고 영화관은 대화를 못 해서 별로더라고요. 산책 코스나 전시회도 괜찮을 것 같은데 '
      '처음부터 부담스러울까요? 다들 어떻게 하셨는지 궁금해요.';

  Future<void> pumpCard(
    WidgetTester tester,
    CommunityItem item, {
    bool detail = false,
    VoidCallback? onOpen,
    VoidCallback? onMore,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 328,
                child: PostCard(item: item, now: now, detail: detail, onOpen: onOpen, onMore: onMore ?? () {}),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('카드 틀: 흰 · 모서리 lg(24) · 그림자 (0,1) 8 #00000014 — 투표 카드와 같은 바깥 모양', (tester) async {
    await pumpCard(tester, postFixture());
    final frame = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(PostCard), matching: find.byType(DecoratedBox)).first,
    );
    final decoration = frame.decoration as ShapeDecoration;
    expect(decoration.color, AppColors.canvas);
    expect((decoration.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppRadius.lg));
    expect(decoration.shadows, AppElevation.homeTileLow);
  });

  testWidgets('위 → 아래: 머리줄 48 → 12 → 카테고리 라벨 → 12 → 본문 → 12 → 구분선 1 → 12 → 아래 줄 48, 안쪽 16', (tester) async {
    await pumpCard(tester, postFixture(text: '짧은 글'));
    final box = tester.getRect(find.byType(PostCard));
    final label = tester.getRect(find.byType(CategoryLabel));
    final body = tester.getRect(find.text('짧은 글'));
    final line = tester.getRect(find.byKey(PostCard.separatorKey));
    expect(label.top, box.top + 16 + 48 + 12);
    expect(label.left, box.left + 16);
    expect(body.top, closeTo(label.bottom + 12, 0.01));
    expect(line.top, closeTo(body.bottom + 12, 0.01));
    expect((line.height, line.left, line.right), (1, box.left + 16, box.right - 16));
    expect(box.bottom, closeTo(line.bottom + 12 + 48 + 16, 0.01));
  });

  testWidgets('머리줄: 익명 아바타 40 · "익명" · 시간 · … 48(ellipsis 20 muted) · 신고 버튼 없음', (tester) async {
    await pumpCard(tester, postFixture(createdAt: DateTime(2026, 11, 24, 14)));
    expect(tester.getSize(find.byKey(PostCard.avatarKey)), const Size(40, 40));
    expect(find.text('익명'), findsOneWidget);
    expect(find.text('3분 전'), findsOneWidget);
    final more = find.byTooltip('더보기');
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    final icon = tester.widget<Icon>(find.descendant(of: more, matching: find.byType(Icon)));
    expect((icon.icon, icon.size, icon.color), (AppIcons.ellipsis, 20, AppColors.muted));
    expect(find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.siren), findsNothing);
  });

  testWidgets('카테고리 라벨은 글의 카테고리(대장 판정 3)', (tester) async {
    await pumpCard(tester, postFixture(category: CommunityCategory.love));
    expect(find.descendant(of: find.byType(CategoryLabel), matching: find.text('연애')), findsOneWidget);
  });

  testWidgets('본문 16/400 lh1.5 ls-0.16 ink — 피드는 4줄에서 말줄임, 상세는 전부', (tester) async {
    await pumpCard(tester, postFixture(text: longText));
    final feed = tester.widget<Text>(find.text(longText));
    expect((feed.maxLines, feed.overflow), (4, TextOverflow.ellipsis));
    final style = feed.style!;
    expect((style.fontSize, style.fontWeight, style.height, style.letterSpacing, style.color),
        (16, FontWeight.w400, 1.5, -0.16, AppColors.ink));
    await pumpCard(tester, postFixture(text: longText), detail: true);
    expect(tester.widget<Text>(find.text(longText)).maxLines, isNull);
  });

  testWidgets('아래 줄: 말풍선 16 muted · "댓글 N" 12/500 muted(왼쪽 8) — 참여 수는 없다', (tester) async {
    await pumpCard(tester, postFixture(commentCount: 4));
    final box = tester.getRect(find.byType(PostCard));
    final bubble = find.byWidgetPredicate((w) => w is Icon && w.icon == AppIcons.messageCircle);
    expect(tester.getRect(bubble).left, box.left + 16 + 8);
    expect(tester.getSize(bubble), const Size(16, 16));
    final count = tester.widget<Text>(find.text('댓글 4')).style!;
    expect((count.fontSize, count.fontWeight, count.color), (12, FontWeight.w500, AppColors.muted));
    expect(find.byWidgetPredicate((w) => w is Icon && w.icon == AppIcons.users), findsNothing);
  });

  testWidgets('피드 카드를 누르면 상세로 간다, … 는 메뉴를 연다', (tester) async {
    var opened = 0;
    var menus = 0;
    await pumpCard(tester, postFixture(), onOpen: () => opened++, onMore: () => menus++);
    await tester.tap(find.text('취업 준비 다들 어떻게 해요?'));
    await tester.tap(find.byTooltip('더보기'));
    expect((opened, menus), (1, 1));
  });

  testWidgets('눌림 효과는 카드 안 Material 에 갇힌다(COMMON §4-2)', (tester) async {
    await pumpCard(tester, postFixture(), onOpen: () {});
    final ink = find.descendant(of: find.byType(PostCard), matching: find.byType(InkWell)).first;
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.getSize(material), tester.getSize(find.byType(PostCard)));
  });
}
