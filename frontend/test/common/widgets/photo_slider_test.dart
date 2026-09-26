import 'dart:typed_data';

import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1×1 투명 PNG. 사진마다 바이트 목록을 따로 만들어야 MemoryImage 끼리 서로 다른 그림이 된다.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
];

List<ImageProvider> _photos(int count) => [for (var i = 0; i < count; i++) MemoryImage(Uint8List.fromList(_png))];

/// 그림 [image] 를 깐 사진 칸.
Finder _photo(ImageProvider image) => find.byWidgetPredicate(
  (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).image?.image == image,
);

final _dots = find.byWidgetPredicate(
  (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle,
);

Color? _dotColor(WidgetTester tester, int index) =>
    (tester.widget<DecoratedBox>(_dots.at(index)).decoration as BoxDecoration).color;

// 화면 15 "수락 후 공개" 배지(pen `E2kWIB`)와 같은 짜임 — 패딩 [5,8], 아이콘 12, 간격 4, 11/600.
const _badgeKey = Key('badge');
final _textBadge = DecoratedBox(
  key: _badgeKey,
  decoration: BoxDecoration(color: AppColors.surfaceInk, borderRadius: BorderRadius.circular(AppRadius.pill)),
  child: const Padding(
    padding: EdgeInsets.symmetric(vertical: 5, horizontal: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(dimension: 12),
        SizedBox(width: 4),
        Text('수락 후 공개', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.5)),
      ],
    ),
  ),
);

void main() {
  // 화면 15 본문 폭 328(360 - 좌우 16) 에 놓는다.
  Future<void> pump(
    WidgetTester tester, {
    required List<ImageProvider> photos,
    Size photoSize = const Size(252, 184),
    Widget? badge,
    double width = 328,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PhotoSlider(photos: photos, photoSize: photoSize, firstPhotoBadge: badge),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('328 폭에서 첫 장 252×184, 둘째 장 x260, 점 줄은 사진 아래 8', (tester) async {
    // pen `o2Nhn` — 사진 `T09a8` 252×184, `i4Pnj` x260(68 만 보임). 점 `SC7rv` y222 = 섹션 제목 30 + 184 + 8.
    final photos = _photos(2);
    await pump(tester, photos: photos);

    final first = tester.getRect(_photo(photos[0]));
    final second = tester.getRect(_photo(photos[1]));
    expect(first.topLeft, Offset.zero);
    expect(first.width, moreOrLessEquals(252));
    expect(first.height, 184);
    expect(second.left, moreOrLessEquals(260));
    expect(second.height, 184);

    final dot0 = tester.getRect(_dots.at(0));
    final dot1 = tester.getRect(_dots.at(1));
    expect(dot0.top, first.bottom + 8);
    expect(dot0.size, const Size(6, 6));
    expect(dot1.size, const Size(6, 6));
    expect(dot1.left - dot0.right, 6);
    // pen 활성 x155 · 비활성 x167 → 두 점의 가운데가 328 의 가운데 164.
    expect(dot0.left, 155);
    expect((dot0.left + dot1.right) / 2, 164);
  });

  testWidgets('점은 사진 수만큼, 처음엔 0번이 활성이고 넘기면 1번이 활성이다', (tester) async {
    // pen `SC7rv` — 활성 `oYvj4` #222222, 비활성 `GyrzV` #DDDDDD.
    final photos = _photos(3);
    await pump(tester, photos: photos);

    expect(_dots, findsNWidgets(3));
    expect(_dotColor(tester, 0), AppColors.ink);
    expect(_dotColor(tester, 1), AppColors.hairline);
    expect(_dotColor(tester, 2), AppColors.hairline);

    await tester.drag(find.byType(PageView), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(_dotColor(tester, 0), AppColors.hairline);
    expect(_dotColor(tester, 1), AppColors.ink);
    expect(_dotColor(tester, 2), AppColors.hairline);
    expect(tester.getRect(_photo(photos[1])).left, moreOrLessEquals(0));
  });

  testWidgets('사진 수가 바뀌어도 활성 점은 실제로 보이는 장을 따른다', (tester) async {
    // 같은 State 로 사진 목록만 바꿔 다시 그린다(검토 탐침: 3장 끝 → 2장에서 활성 점 없음, → 1장 → 3장에서 3번 점 활성).
    int shownPage() => tester.widget<PageView>(find.byType(PageView)).controller!.page!.round();
    int activeDot() {
      for (var i = 0; i < _dots.evaluate().length; i++) {
        if (_dotColor(tester, i) == AppColors.ink) return i;
      }
      return -1;
    }

    Future<void> swipeToEnd() async {
      for (var i = 0; i < 2; i++) {
        await tester.drag(find.byType(PageView), const Offset(-200, 0));
        await tester.pumpAndSettle();
      }
    }

    final photos = _photos(3);
    await pump(tester, photos: photos);
    await swipeToEnd();
    expect(activeDot(), 2);

    await pump(tester, photos: photos.sublist(0, 2));
    await tester.pumpAndSettle();
    expect(activeDot(), shownPage());

    await pump(tester, photos: photos.sublist(0, 1));
    await tester.pumpAndSettle();
    await pump(tester, photos: photos);
    await tester.pumpAndSettle();
    expect(shownPage(), 0);
    expect(activeDot(), 0);

    // 0장을 거쳐 다시 3장이 되어도 예외 없이 맞는다.
    await swipeToEnd();
    await pump(tester, photos: const []);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await pump(tester, photos: photos);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(activeDot(), shownPage());
  });

  testWidgets('첫 장 배지는 첫 장 안 오른쪽 위(top 12, right 13)에 있고 넘기면 같이 움직인다', (tester) async {
    // pen `E2kWIB` 89×28 — 첫 장 안 x150 y12 (252 - 13 - 89 = 150).
    final photos = _photos(2);
    await pump(tester, photos: photos, badge: const SizedBox(key: _badgeKey, width: 89, height: 28));

    final badge = find.byKey(_badgeKey);
    expect(badge, findsOneWidget);
    expect(find.descendant(of: _photo(photos[0]), matching: badge), findsOneWidget);
    expect(find.descendant(of: _photo(photos[1]), matching: badge), findsNothing);

    final first = tester.getRect(_photo(photos[0]));
    final before = tester.getRect(badge);
    expect(before.top - first.top, 12);
    expect(first.right - before.right, moreOrLessEquals(13));
    expect(before.left, moreOrLessEquals(150));

    await tester.drag(find.byType(PageView), const Offset(-200, 0));
    await tester.pumpAndSettle();

    final after = tester.getRect(badge);
    expect(after.left, lessThan(before.left));
    expect(after.left - tester.getRect(_photo(photos[0])).left, moreOrLessEquals(150));
  });

  testWidgets('사진이 1장이면 점이 없다', (tester) async {
    final photos = _photos(1);
    await pump(tester, photos: photos);

    expect(_photo(photos[0]), findsOneWidget);
    expect(_dots, findsNothing);
    expect(tester.getSize(find.byType(PhotoSlider)).height, 184);
  });

  testWidgets('사진이 0장이면 아무것도 그리지 않는다', (tester) async {
    await pump(tester, photos: const []);

    expect(find.byType(PageView), findsNothing);
    expect(_dots, findsNothing);
    expect(tester.getSize(find.byType(PhotoSlider)).height, 0);
  });

  testWidgets('photoSize 288×260 도 같은 규칙으로 그린다(14c)', (tester) async {
    // 14c "Real Photo Slider" 288×260.
    final photos = _photos(2);
    await pump(tester, photos: photos, photoSize: const Size(288, 260));

    final first = tester.getRect(_photo(photos[0]));
    expect(first.width, moreOrLessEquals(288));
    expect(first.height, 260);
    expect(tester.getRect(_photo(photos[1])).left, moreOrLessEquals(296));
    expect(tester.getRect(_dots.at(0)).top, 268);
  });

  testWidgets('부모 폭이 사진 + 8 보다 좁으면 한 장이 폭을 다 쓰고 넘치지 않는다', (tester) async {
    final photos = _photos(2);
    await pump(tester, photos: photos, photoSize: const Size(288, 260), width: 280);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_photo(photos[0])).width, moreOrLessEquals(272));
    // 다음 장은 x280 = 화면 밖에서 시작한다. PageView 는 화면 밖 장을 만들지 않는다(엿보기 없음).
    expect(_photo(photos[1]), findsNothing);
  });

  testWidgets('부모 폭이 바뀌어도 사진 폭과 간격은 그대로다', (tester) async {
    // 화면 분할·회전으로 폭이 바뀌는 경우. viewportFraction 을 다시 계산해야 252 가 유지된다.
    final photos = _photos(2);
    await pump(tester, photos: photos);
    await pump(tester, photos: photos, width: 400);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_photo(photos[0])).width, moreOrLessEquals(252));
    expect(tester.getRect(_photo(photos[1])).left, moreOrLessEquals(260));
  });

  testWidgets('사진마다 "실제 사진 n, 전체 N장" 이미지 라벨이 있다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, photos: _photos(2));

    expect(
      tester.getSemantics(find.bySemanticsLabel('실제 사진 1, 전체 2장')),
      isSemantics(label: '실제 사진 1, 전체 2장', isImage: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('실제 사진 2, 전체 2장')),
      isSemantics(label: '실제 사진 2, 전체 2장', isImage: true),
    );
    handle.dispose();
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('배율 $scale 에서 글자 배지를 얹어도 넘치지 않고 첫 장 안에 든다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final photos = _photos(2);
      await pump(tester, photos: photos, badge: _textBadge);

      expect(tester.takeException(), isNull);
      final first = tester.getRect(_photo(photos[0]));
      final badge = tester.getRect(find.byKey(_badgeKey));
      // 사진 칸이 clip 이라 배지가 넘치면 오류 없이 잘린다 — 칸 안에 드는지로 본다.
      expect(first.expandToInclude(badge), first);
      expect(first.height, 184);
    });
  }
}
