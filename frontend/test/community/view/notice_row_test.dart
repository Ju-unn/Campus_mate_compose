import 'package:campus_mate/community/view/notice_parts.dart';
import 'package:campus_mate/community/view/notice_row.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_community_repository.dart';
import 'notice_widgets_harness.dart';

/// pen NoticeRow `bGQGW` (328×103, 값표 0-1 · 21-2).
void main() {
  testWidgets('제목 16/600 최대 2줄 · "M월 D일" · NEW · 댓글 수, 그림이 있으면 56 썸네일', (tester) async {
    await pumpNoticePart(
      tester,
      NoticeRow(
        notice: noticeFixture(
          title: '업데이트 안내',
          createdAt: DateTime(2026, 11, 24, 9),
          isNew: true,
          commentCount: 3,
          imageUrl: 'https://img.test/n1.webp',
        ),
        onOpen: () {},
      ),
    );

    final title = tester.widget<Text>(find.text('업데이트 안내'));
    expect((title.maxLines, title.style?.fontSize, title.style?.fontWeight), (2, 16.0, FontWeight.w600));
    expect(title.style?.color, AppColors.ink);
    expect(find.text('11월 24일'), findsOneWidget);
    expect(find.byType(NoticeNewBadge), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.messageCircle)).size, 14);
    expect(tester.getSize(find.byKey(NoticeRow.thumbnailKey)), const Size(56, 56));
    expect(tester.widget<NoticeImage>(find.byType(NoticeImage)).width, 56);
  });

  testWidgets('그림 없는 공지는 썸네일 칸이 없고, 7일 지난 공지는 NEW 가 없다', (tester) async {
    await pumpNoticePart(tester, NoticeRow(notice: noticeFixture(title: '이용 안내'), onOpen: () {}));

    expect(find.byKey(NoticeRow.thumbnailKey), findsNothing);
    expect(find.byType(NoticeNewBadge), findsNothing);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('썸네일은 오른쪽 끝, 줄 위아래 안쪽 14', (tester) async {
    await pumpNoticePart(
      tester,
      NoticeRow(notice: noticeFixture(title: '연말 안내', imageUrl: 'https://img.test/n.webp'), onOpen: () {}),
    );

    final row = tester.getRect(find.byType(NoticeRow));
    final thumb = tester.getRect(find.byKey(NoticeRow.thumbnailKey));
    expect(thumb.right, row.right);
    expect(thumb.top - row.top, greaterThanOrEqualTo(14));
    expect(row.bottom - thumb.bottom, greaterThanOrEqualTo(14));
  });

  testWidgets('누르면 상세로 간다', (tester) async {
    var opened = 0;
    await pumpNoticePart(tester, NoticeRow(notice: noticeFixture(), onOpen: () => opened++));

    await tester.tap(find.byType(NoticeRow));

    expect(opened, 1);
  });
}
