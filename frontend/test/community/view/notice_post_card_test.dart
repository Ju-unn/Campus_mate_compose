import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/view/community_card_parts.dart';
import 'package:campus_mate/community/view/notice_parts.dart';
import 'package:campus_mate/community/view/notice_post_card.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/view/photo_zoom_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_community_repository.dart';
import 'notice_widgets_harness.dart';

/// pen NoticePost · Detail `pnMfk` (328 폭, 값표 0-3).
void main() {
  testWidgets('운영자 줄(메가폰 32 · "CampusMate 운영자" · 날짜) → 제목 20/600 → 그림(오는 중 16:9) → 본문 16/400 1.6', (tester) async {
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
    // 그림 칸 자체는 세로를 묶지 않는다 — 16:9 칸이면 받은 그림이 다시 잘린다.
    final slot = tester.renderObject<RenderBox>(
      find.descendant(of: find.byKey(NoticePostCard.imageKey), matching: find.byType(LayoutBuilder)),
    );
    expect(slot.constraints.maxHeight, double.infinity);
  });

  // 사용자 11-25: 「이미지 잘려 보이는데?? 세로 제한 없애면 안되나?? … 이미지를 다 보이게 폰 이미지화면에 맞춰줄 수 없나?」
  group('상세 그림은 자르지 않는다 — 카드 안 폭(296)에 맞추고 높이는 그림 비율대로', () {
    /// [width]×[height] 단색 PNG. 그림 크기만 보면 되니 내용은 상관없다.
    Future<Uint8List> pngOf(WidgetTester tester, int width, int height) async => (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint());
          final image = await recorder.endRecording().toImage(width, height);
          return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        }))!;

    /// 받은 그림(imageBuilder)을 296 폭 칸에 그려 칸 크기를 잰다.
    Future<Size> loadedSize(WidgetTester tester, Uint8List png) async {
      await pumpNoticePart(tester, NoticePostCard(notice: noticeFixture(imageUrl: 'https://img.test/n1.webp')));
      final cached = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      final provider = MemoryImage(png);
      await pumpNoticePart(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 296, child: Builder(builder: (context) => cached.imageBuilder!(context, provider))),
        ),
      );
      await tester.runAsync(() => precacheImage(provider, tester.element(find.byType(Image))));
      await tester.pump();
      return tester.getSize(find.byType(Image));
    }

    testWidgets('정사각형 그림은 296 × 296', (tester) async {
      expect(await loadedSize(tester, await pngOf(tester, 360, 360)), const Size(296, 296));
    });

    testWidgets('세로로 긴 그림(1:4)도 상한 없이 296 × 1184 — 잘리지 않는다', (tester) async {
      expect(await loadedSize(tester, await pngOf(tester, 100, 400)), const Size(296, 1184));
      expect(tester.widget<Image>(find.byType(Image)).fit, isNot(BoxFit.cover));
    });

    // 사용자 11-25 B: 그림을 누르면 전체 화면으로 크게(내 사진 확대 뷰어 재사용, 같은 주소 · 같은 캐시).
    testWidgets('받은 그림을 누르면 전체 화면 크게 보기 — 낭독기에는 "사진 크게 보기" 버튼', (tester) async {
      await loadedSize(tester, await pngOf(tester, 360, 360));
      expect(find.bySemanticsLabel('사진 크게 보기'), findsOneWidget);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      final viewer = tester.widget<PhotoZoomViewer>(find.byType(PhotoZoomViewer));
      expect(viewer.image, const CachedNetworkImageProvider('https://img.test/n1.webp'));
    });

    testWidgets('그림이 오는 중이면 눌러도 크게 보기가 열리지 않는다', (tester) async {
      await pumpNoticePart(tester, NoticePostCard(notice: noticeFixture(imageUrl: 'https://img.test/n1.webp')));

      await tester.tap(find.byKey(NoticePostCard.imageKey), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoZoomViewer), findsNothing);
      expect(find.bySemanticsLabel('사진 크게 보기'), findsNothing);
    });

    testWidgets('오는 중 · 못 받으면 16:9 빈 칸(높이가 0 으로 꺼지지 않게)', (tester) async {
      await pumpNoticePart(tester, NoticePostCard(notice: noticeFixture(imageUrl: 'https://img.test/n1.webp')));
      final cached = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      final context = tester.element(find.byType(CachedNetworkImage));

      for (final empty in [cached.placeholder!(context, cached.imageUrl), cached.errorWidget!(context, cached.imageUrl, Exception('x'))]) {
        await pumpNoticePart(tester, Align(alignment: Alignment.topLeft, child: SizedBox(width: 296, child: empty)));
        expect(tester.getSize(find.byWidget(empty)), const Size(296, 296 * 9 / 16));
      }
    });
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
