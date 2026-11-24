import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/community/view/notice_parts.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'notice_widgets_harness.dart';

void main() {
  testWidgets('NEW 배지: primary 채움 · 끝까지 둥근 모서리 · 흰 "NEW"', (tester) async {
    await pumpNoticePart(tester, const Align(alignment: Alignment.centerLeft, child: NoticeNewBadge()));

    expect(find.text('NEW'), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(NoticeNewBadge), matching: find.byType(DecoratedBox)),
    );
    final decoration = box.decoration as ShapeDecoration;
    expect(decoration.color, AppColors.primary);
    expect(decoration.shape, isA<StadiumBorder>());
    expect(tester.widget<Text>(find.text('NEW')).style?.color, AppColors.onPrimary);
  });

  testWidgets('날짜는 "M월 D일"(연도 없음)', (tester) async {
    await pumpNoticePart(
      tester,
      Builder(builder: (context) => Text(noticeDateLabel(context, DateTime(2026, 11, 5, 9)))),
    );

    expect(find.text('11월 5일'), findsOneWidget);
  });

  testWidgets('그림은 기기 캐시 그림(CachedNetworkImage)으로, 표시 폭 × 화소 배율로 줄여 받는다', (tester) async {
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await pumpNoticePart(
      tester,
      const SizedBox(width: 56, height: 56, child: NoticeImage(url: 'https://img.test/x.webp', width: 56)),
    );

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.imageUrl, 'https://img.test/x.webp');
    expect(image.memCacheWidth, (56 * 2.75).round());
    expect(image.fit, BoxFit.cover);
    expect(find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage), findsNothing);
  });

  testWidgets('오는 중 · 실패면 빈 칸이다', (tester) async {
    await pumpNoticePart(
      tester,
      const SizedBox(width: 56, height: 56, child: NoticeImage(url: 'https://img.test/x.webp', width: 56)),
    );
    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    final context = tester.element(find.byType(CachedNetworkImage));

    expect(image.placeholder!(context, image.imageUrl), isA<SizedBox>());
    expect(image.errorWidget!(context, image.imageUrl, Exception('x')), isA<SizedBox>());
    expect(tester.takeException(), isNull);
  });
}
