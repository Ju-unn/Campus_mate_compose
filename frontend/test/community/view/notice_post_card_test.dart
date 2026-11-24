import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/view/community_card_parts.dart';
import 'package:campus_mate/community/view/notice_parts.dart';
import 'package:campus_mate/community/view/notice_post_card.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_community_repository.dart';
import 'notice_widgets_harness.dart';

/// pen NoticePost · Detail `pnMfk` (328 폭, 값표 0-3).
void main() {
  testWidgets('운영자 줄(메가폰 32 · "CampusMate 운영자" · 날짜) → 제목 20/600 → 16:9 그림 → 본문 16/400 1.6', (tester) async {
    await pumpNoticePart(
      tester,
      NoticePostCard(
        notice: noticeFixture(
          title: '업데이트 안내',
          text: '본문 글',
          createdAt: DateTime(2026, 11, 24, 9),
          imageUrl: 'https://img.test/n1.webp',
        ),
      ),
    );

    expect(find.byType(CommunityCardFrame), findsOneWidget);
    final icon = tester.widget<Icon3d>(find.byType(Icon3d));
    expect((icon.icon, icon.size), (AppIcon3d.megaphone, 32.0));
    expect(find.text('CampusMate 운영자'), findsOneWidget);
    expect(find.text('11월 24일'), findsOneWidget);
    expect(tester.widget<Text>(find.text('업데이트 안내')).style, AppTypography.title.copyWith(color: AppColors.ink));
    expect(tester.widget<Text>(find.text('본문 글')).style, AppTypography.body.copyWith(color: AppColors.ink));
    final image = tester.getSize(find.byKey(NoticePostCard.imageKey));
    expect(image.width, 296);
    expect(image.height, closeTo(296 * 9 / 16, 0.01));
    expect(tester.widget<NoticeImage>(find.byType(NoticeImage)).width, 296);
  });

  testWidgets('그림이 없으면 그림 칸이 없다', (tester) async {
    await pumpNoticePart(tester, NoticePostCard(notice: noticeFixture()));

    expect(find.byKey(NoticePostCard.imageKey), findsNothing);
  });

  testWidgets('운영자 글이라 … · 신고 · NEW 가 없다(대장 판정 5)', (tester) async {
    await pumpNoticePart(tester, NoticePostCard(notice: noticeFixture(isNew: true)));

    expect(find.byIcon(AppIcons.ellipsis), findsNothing);
    expect(find.byType(CommunityMoreButton), findsNothing);
    expect(find.byType(NoticeNewBadge), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('본문의 태그 · 주소는 글자 그대로 보인다(해석하지 않는다)', (tester) async {
    await pumpNoticePart(tester, NoticePostCard(notice: noticeFixture(text: '<b>굵게</b> https://example.test')));

    expect(find.text('<b>굵게</b> https://example.test'), findsOneWidget);
  });
}
