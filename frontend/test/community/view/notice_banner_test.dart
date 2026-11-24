import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/view/notice_banner.dart';
import 'package:campus_mate/community/view/notice_parts.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_community_repository.dart';
import 'notice_widgets_harness.dart';

/// pen NoticeBanner `yypXr` / NEW 없음 `Xfguu` (328×52, 값표 0-1).
void main() {
  testWidgets('흰 · 모서리 md · 그림자 (0,1) 8 · 높이 52, 메가폰 28 → 제목 → NEW → chevron 20', (tester) async {
    await pumpNoticePart(tester, NoticeBanner(notice: noticeFixture(title: '업데이트 안내', isNew: true), onOpen: () {}));

    expect(tester.getSize(find.byType(NoticeBanner)).height, 52);
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(NoticeBanner), matching: find.byType(DecoratedBox)).first,
    );
    final decoration = box.decoration as ShapeDecoration;
    expect(decoration.color, AppColors.canvas);
    expect((decoration.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppRadius.md));
    expect(decoration.shadows, AppElevation.homeTileLow);
    final icon = tester.widget<Icon3d>(find.byType(Icon3d));
    expect((icon.icon, icon.size), (AppIcon3d.megaphone, 28.0));
    expect(find.text('업데이트 안내'), findsOneWidget);
    expect(find.byType(NoticeNewBadge), findsOneWidget);
    final chevron = tester.widget<Icon>(find.byIcon(AppIcons.chevronRight));
    expect((chevron.size, chevron.color), (20.0, AppColors.muted));
    expect(tester.getTopLeft(find.byType(Icon3d)).dx - tester.getTopLeft(find.byType(NoticeBanner)).dx, 14);
  });

  testWidgets('7일 지난 공지(is_new false)면 NEW 배지가 없다', (tester) async {
    await pumpNoticePart(tester, NoticeBanner(notice: noticeFixture(), onOpen: () {}));

    expect(find.byType(NoticeNewBadge), findsNothing);
  });

  testWidgets('긴 제목은 한 줄로 자른다', (tester) async {
    final longTitle = List.filled(10, '아주 긴 공지 제목').join(' ');
    await pumpNoticePart(tester, NoticeBanner(notice: noticeFixture(title: longTitle, isNew: true), onOpen: () {}));

    final title = tester.widget<Text>(find.text(longTitle));
    expect((title.maxLines, title.overflow), (1, TextOverflow.ellipsis));
    expect(tester.getSize(find.byType(NoticeBanner)).height, 52);
  });

  testWidgets('누르면 공지 목록으로 간다', (tester) async {
    var opened = 0;
    await pumpNoticePart(tester, NoticeBanner(notice: noticeFixture(), onOpen: () => opened++));

    await tester.tap(find.byType(NoticeBanner));

    expect(opened, 1);
  });
}
