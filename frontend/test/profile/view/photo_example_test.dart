import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/profile/view/photo_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 예시 그림 두 칸(pen `PhotoExample` · 아바타 변환 예시 `q7Rp0G`, 대장 전달 값).
void main() {
  Future<void> pump(WidgetTester tester, Widget example) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: example)),
      ),
    );
  }

  List<Rect> tiles(WidgetTester tester) => [
        for (final element in find.byType(ClipRRect).evaluate())
          tester.getRect(find.byWidget(element.widget)),
      ];

  group('04-2 좋은 사진 예시', () {
    testWidgets('캡션 "이런 사진이 좋아요" 14/400 body', (tester) async {
      await pump(tester, const PhotoExample.goodPhoto());

      final style = tester.widget<Text>(find.text('이런 사진이 좋아요')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w400, AppColors.body));
    });

    testWidgets('두 칸이 폭을 나눠 채운다 — 정사각 158 · 사이 12 · 모서리 14 · cover', (tester) async {
      await pump(tester, const PhotoExample.goodPhoto());

      final rects = tiles(tester);
      expect(rects.map((rect) => rect.size), [const Size(158, 158), const Size(158, 158)]);
      expect(rects[1].left - rects[0].right, 12);
      for (final clip in tester.widgetList<ClipRRect>(find.byType(ClipRRect))) {
        expect(clip.borderRadius, BorderRadius.circular(14));
      }
      expect(tester.widgetList<Image>(find.byType(Image)).map((image) => image.fit), [BoxFit.cover, BoxFit.cover]);
      // 정사각 칸이라 잘리는 곳이 없다 — 가운데 그대로.
      expect(tester.widgetList<Image>(find.byType(Image)).map((image) => image.alignment), [Alignment.center, Alignment.center]);
    });

    testWidgets('공원 · 카페 예시 사진을 쓰고, 낭독기는 "올바른 사진 예시" 로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const PhotoExample.goodPhoto());

      final assets = [
        for (final image in tester.widgetList<Image>(find.byType(Image))) (image.image as AssetImage).assetName,
      ];
      expect(assets, ['assets/images/example-photo-park-v1.webp', 'assets/images/example-photo-cafe-v1.webp']);
      expect(find.bySemanticsLabel(RegExp('^올바른 사진 예시')), findsNWidgets(2));
      handle.dispose();
    });
  });

  group('아바타 변환 예시(04-3 · 15b-4 · 15b-5)', () {
    testWidgets('캡션 "내 사진이 이런 일러스트 아바타로 바뀌어요"', (tester) async {
      await pump(tester, const PhotoExample.avatar());

      expect(find.text('내 사진이 이런 일러스트 아바타로 바뀌어요'), findsOneWidget);
    });

    // pen `q7Rp0G` · `wznui` · `M3beY` 칸 158×130(대장 전달 값 10-15) — 폭을 나눠 채우고 높이만 130.
    testWidgets('두 칸이 폭을 나눠 채운다 — 158×130 · 사이 12 · cover', (tester) async {
      await pump(tester, const PhotoExample.avatar());

      final rects = tiles(tester);
      expect(rects.map((rect) => rect.size), [const Size(158, 130), const Size(158, 130)]);
      expect(rects[0].left, 16);
      expect(rects[1].left - rects[0].right, 12);
      expect(tester.widgetList<Image>(find.byType(Image)).map((image) => image.fit), [BoxFit.cover, BoxFit.cover]);
    });

    // pen 04-3 예시는 세로 원본(결과_v28_flare_2 · 결과_s3_f2, 1024×1536)을 158×130 에 cover(가운데)로 담아 원본 세로 347~1189 줄이 보인다.
    // 앱 그림은 그 원본의 158~1182 줄을 자른 정사각(390)이라, 가운데로 담으면 248~1091 줄이 보여 얼굴이 pen 보다 15 아래에 온다.
    // 아래 맞춤이면 339~1182 줄 — pen 과 1 이내.
    testWidgets('정사각 일러스트를 아래에 맞춰 담는다 — pen 세로 원본 cover 와 같은 부분이 보인다', (tester) async {
      await pump(tester, const PhotoExample.avatar());

      expect(tester.widgetList<Image>(find.byType(Image)).map((image) => image.alignment),
          [Alignment.bottomCenter, Alignment.bottomCenter]);
    });

    testWidgets('일러스트 두 장(avatar-* 이름이 아니다)이고 낭독기는 "아바타 일러스트 예시" 로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const PhotoExample.avatar());

      final assets = [
        for (final image in tester.widgetList<Image>(find.byType(Image))) (image.image as AssetImage).assetName,
      ];
      expect(assets, ['assets/images/example-illust-a-v1.webp', 'assets/images/example-illust-b-v1.webp']);
      expect(find.bySemanticsLabel(RegExp('^아바타 일러스트 예시')), findsNWidgets(2));
      handle.dispose();
    });
  });
}
