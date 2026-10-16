import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, TileMode;

import 'package:campus_mate/home/model/home_people.dart';
import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/mosaic_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// mosaic-rail(pen `P2sFxR`) 손 조작 — 누르는 동안 멈춤 · 동작 줄이기에서 정지 + 손으로 밀기 · pause 아이콘 없음(D3 · 점검 U5).
/// 홈 화면 안 모양 · 흐름 기본은 home_screen_test 의 'mosaic-rail' 묶음이 본다. 여기서는 레일만 띄운다.
void main() {
  /// 서로 다른 그림 [count] 장(바이트 4개짜리 — 그리지 못해도 칸 크기는 그대로다).
  HomePeople people(int count) => HomePeople.fromJson({
        'people': [for (var i = 0; i < count; i++) base64Encode([0xFF, 0xD8, 0xFF, i])],
      });

  Future<void> pumpRail(WidgetTester tester, [HomePeople? shown]) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: MosaicRail(people: shown ?? people(1)))));

  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  double railX(WidgetTester tester) => tester.getTopLeft(find.byType(MosaicPersonTile).first).dx;

  /// 사람 칸 · 빈 칸 전부의 화면 자리(왼쪽부터).
  List<Rect> tiles(WidgetTester tester) => [
        for (final type in [MosaicPersonTile, MosaicEmptyTile])
          for (var i = 0; i < find.byType(type).evaluate().length; i++) tester.getRect(find.byType(type).at(i)),
      ]..sort((a, b) => a.left.compareTo(b.left));

  group('사람 칸 `O5FCD9`(Home Rail Tile · Blur Avatar) — 서버가 흐린 실제 가입자 아바타', () {
    testWidgets('서버 바이트를 Image.memory 로 그대로 그린다 — 덮어 채움 · 다시 받아도 깜빡이지 않음 · 앱에서 다시 흐리지 않음', (tester) async {
      final shown = people(1);
      await pumpRail(tester, shown);

      final tile = find.byType(MosaicPersonTile).first;
      final image = tester.widget<Image>(find.descendant(of: tile, matching: find.byType(Image)));
      expect((image.image as MemoryImage).bytes, shown.map((bytes) => bytes).single);
      expect((image.fit, image.gaplessPlayback), (BoxFit.cover, true));
      expect(find.descendant(of: find.byType(MosaicRail), matching: find.byType(ImageFiltered)), findsNothing);
      expect(find.descendant(of: find.byType(MosaicRail), matching: find.byType(BackdropFilter)), findsNothing);
    });

    testWidgets('112×140 · 모서리 14 · 칸 사이 10 · 이름 · 학교 · 배지 글자 없음', (tester) async {
      await pumpRail(tester, people(2));

      final tile = find.byType(MosaicPersonTile).first;
      expect(tester.getSize(tile), const Size(112, 140));
      final clip = tester.widget<ClipRRect>(find.descendant(of: tile, matching: find.byType(ClipRRect)));
      expect(clip.borderRadius, BorderRadius.circular(14));
      expect(find.descendant(of: tile, matching: find.byType(Text)), findsNothing);
      final first = tester.getRect(find.byType(MosaicPersonTile).at(0));
      final second = tester.getRect(find.byType(MosaicPersonTile).at(1));
      expect(second.left - first.right, 10);
    });

    testWidgets('받은 만큼만 칸을 둔다 — 12장보다 적어도 채우려고 같은 그림을 한 벌에 되풀이하지 않는다', (tester) async {
      final shown = people(3);
      await pumpRail(tester, shown);

      final copies = find.byType(MosaicEmptyTile).evaluate().length;
      final drawn = [
        for (final element in find.byType(MosaicPersonTile).evaluate()) (element.widget as MosaicPersonTile).image,
      ];
      expect(drawn.length, 3 * copies);
      for (final bytes in shown.map((bytes) => bytes)) {
        expect(drawn.where((image) => identical(image, bytes)).length, copies);
      }
    });


    testWidgets('그림을 못 풀면(깨진 바이트) 그 칸은 기본 그림 칸 모양으로 둔다 — 레일에 구멍 · 오류가 없다', (tester) async {
      await pumpRail(tester, people(1));
      // 그림 풀기는 엔진에서 실제 시간으로 끝난다.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();

      final tile = find.byType(MosaicPersonTile).first;
      expect(find.descendant(of: tile, matching: find.byType(MosaicDefaultTile)), findsOneWidget);
      expect(tester.getSize(tile), const Size(112, 140));
      expect(tester.takeException(), isNull);
    });
    testWidgets('화면 읽기는 그림 칸을 읽지 않고 끝 빈 칸 문구만 한 번 읽는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpRail(tester, people(2));

      expect(find.bySemanticsLabel(RegExp('아직 비어 있어요')), findsOneWidget);
      final images = find.descendant(of: find.byType(MosaicRail), matching: find.byType(Image));
      expect(tester.widgetList<Image>(images).every((image) => image.excludeFromSemantics), isTrue);
      semantics.dispose();
    });
  });

  group('인원 부족 `HhKIR`(Home Mosaic Rail · 인원 부족) — 서버가 빈 목록 · 못 받음 · 받는 중', () {
    const park = 'assets/images/example-photo-park-v1.webp';
    const cafe = 'assets/images/example-photo-cafe-v1.webp';

    testWidgets('레일을 숨기지 않고 흐린 예시 사진 칸 2(공원 · 카페) + 토끼 마스코트 칸을 한 벌로 되풀이한다 · 사람 칸 · 빈 칸 없음', (tester) async {
      await pumpRail(tester, HomePeople.none);

      expect(find.byType(MosaicRail), findsOneWidget);
      expect(find.byType(MosaicPersonTile), findsNothing);
      expect(find.byType(MosaicEmptyTile), findsNothing);
      final copies = find.byType(MosaicMascotTile).evaluate().length;
      expect(copies, greaterThanOrEqualTo(2));
      expect(find.byType(MosaicDefaultTile).evaluate().length, 2 * copies);
      // 한 벌 순서: 공원 → 카페 → 마스코트(왼쪽부터 되풀이).
      final tiles = [
        for (final type in [MosaicDefaultTile, MosaicMascotTile])
          for (var i = 0; i < find.byType(type).evaluate().length; i++)
            (
              tester.getRect(find.byType(type).at(i)).left,
              switch (tester.widget(find.byType(type).at(i))) { MosaicDefaultTile(:final asset) => asset, _ => 'mascot' },
            ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      final order = [for (final (_, kind) in tiles) kind];
      for (var i = 1; i < order.length; i++) {
        expect(order[i], switch (order[i - 1]) { park => cafe, cafe => 'mascot', _ => park }, reason: '$i');
      }
      expect(tester.getSize(find.byType(MosaicRail)).height, 140);
    });

    testWidgets('예시 사진 칸 — 112×140 · 모서리 14 로 자른 AI 가상 인물 사진 136×170 을 blur 10 으로 흐림(번짐은 칸 밖이라 잘림) · 글자 없음', (tester) async {
      await pumpRail(tester, HomePeople.none);

      for (final asset in [park, cafe]) {
        final tile = find.byWidgetPredicate((w) => w is MosaicDefaultTile && w.asset == asset).first;
        expect(tester.getSize(tile), const Size(112, 140), reason: asset);
        final clip = tester.widget<ClipRRect>(find.descendant(of: tile, matching: find.byType(ClipRRect)).first);
        expect(clip.borderRadius, BorderRadius.circular(14), reason: asset);
        final image = find.descendant(of: tile, matching: find.byType(Image));
        expect((tester.widget<Image>(image).image as AssetImage).assetName, asset);
        expect(tester.widget<Image>(image).fit, BoxFit.cover);
        expect(tester.getSize(image), const Size(136, 170), reason: asset);
        expect(tester.getCenter(image), tester.getCenter(tile), reason: asset);
        final blur = tester.widget<ImageFiltered>(find.descendant(of: tile, matching: find.byType(ImageFiltered)));
        expect(blur.imageFilter, ImageFilter.blur(sigmaX: 10, sigmaY: 10, tileMode: TileMode.clamp), reason: asset);
        expect(find.descendant(of: tile, matching: find.byType(Text)), findsNothing);
      }
    });

    testWidgets('마스코트 칸 — 112×140 · 모서리 14 · primary-wash · 기다리는 토끼(`mascot-male-waiting`) 88×88 가운데', (tester) async {
      await pumpRail(tester, HomePeople.none);

      final tile = find.byType(MosaicMascotTile).first;
      expect(tester.getSize(tile), const Size(112, 140));
      final box = tester.widget<Container>(find.descendant(of: tile, matching: find.byType(Container)).first).decoration!
          as BoxDecoration;
      expect((box.color, box.borderRadius), (const Color(0xFFFFF0F2), BorderRadius.circular(14)));
      final mascot = find.descendant(of: tile, matching: find.byType(Image));
      expect((tester.widget<Image>(mascot).image as AssetImage).assetName, 'assets/images/mascot-male-waiting.png');
      expect(tester.getSize(mascot), const Size(88, 88));
      expect(tester.getCenter(mascot), tester.getCenter(tile));
      expect(find.descendant(of: tile, matching: find.byType(Text)), findsNothing);
    });

    testWidgets('기본 상태 그림은 모두 장식이다 — 화면 읽기에 아무것도 읽히지 않는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpRail(tester, HomePeople.none);

      final images = tester.widgetList<Image>(find.descendant(of: find.byType(MosaicRail), matching: find.byType(Image)));
      expect(images, isNotEmpty);
      expect(images.every((image) => image.excludeFromSemantics), isTrue);
      expect(find.descendant(of: find.byType(MosaicRail), matching: find.byType(Text)), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('자동으로 흐르는 방향은 오른쪽이다', (tester) async {
    await pumpRail(tester);
    final before = railX(tester);

    await tester.pump(const Duration(seconds: 1));

    expect(railX(tester), greaterThan(before));
  });

  testWidgets('칸 사이 틈(10)을 눌러도 멈추고, 떼면 다시 흐른다', (tester) async {
    await pumpRail(tester);
    final rail = tester.getRect(find.byType(MosaicRail));
    final all = tiles(tester);
    final index = all.indexWhere((rect) => rect.left >= rail.left && all.indexOf(rect) + 1 < all.length);
    final gap = Offset((all[index].right + all[index + 1].left) / 2, all[index].center.dy);
    expect(all[index + 1].left - all[index].right, 10);

    final gesture = await tester.startGesture(gap);
    await tester.pump(const Duration(milliseconds: 100));
    final held = railX(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(railX(tester), held);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(railX(tester), greaterThan(held));
  });

  group('기기 "동작 줄이기"', () {
    testWidgets('저절로 흐르지 않는다', (tester) async {
      reduceMotion(tester);
      await pumpRail(tester);
      final before = railX(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(railX(tester), before);
    });

    testWidgets('가로로 밀면 손이 간 만큼 따라 움직이고, 놓으면 그 자리에 멈춰 있다', (tester) async {
      reduceMotion(tester);
      await pumpRail(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(MosaicRail)));
      // 가로 밀기로 알아보는 거리(슬롭)까지는 움직이지 않는다 — 목록 스크롤과 같다.
      await gesture.moveBy(const Offset(kDragSlopDefault, 0));
      await tester.pump();
      final start = railX(tester);

      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(railX(tester) - start, 30);

      await gesture.moveBy(const Offset(-50, 0));
      await tester.pump();
      expect(railX(tester) - start, -20);

      await gesture.up();
      await tester.pump();
      final released = railX(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), released);
    });

    testWidgets('한 벌보다 멀리 밀어도 끝에 걸리지 않고 계속 따라오며, 칸이 화면을 다 덮는다(끝없이 되풀이)', (tester) async {
      reduceMotion(tester);
      await pumpRail(tester);
      final width = tester.getSize(find.byType(MosaicRail)).width;
      // 한 벌 = (사람 1 + 빈 칸 1) × (칸 112 + 틈 10).
      const cycle = 2 * (mosaicTileWidth + 10);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(MosaicRail)));
      await gesture.moveBy(const Offset(-kDragSlopDefault, 0));
      await tester.pump();
      final start = railX(tester);

      for (final dx in [-(cycle + 30), 3 * cycle + 50]) {
        final before = railX(tester);
        await gesture.moveBy(Offset(dx, 0));
        await tester.pump();
        // 화면에 보이는 모습은 dx 만큼 민 것과 같다(한 벌 길이만큼 차이 나는 자리는 같은 그림).
        // 소수 오차로 -0.000…1 이 cycle 근처 나머지가 되므로 양쪽 끝 중 가까운 쪽을 잰다.
        final rest = (railX(tester) - (before + dx)) % cycle;
        expect(math.min(rest, cycle - rest), closeTo(0, 0.001), reason: '$dx');
        final all = tiles(tester);
        expect(all.first.left, lessThanOrEqualTo(0), reason: '$dx');
        expect(all.last.right, greaterThanOrEqualTo(width), reason: '$dx');
      }
      expect(railX(tester), isNot(start));
      await gesture.up();
    });
  });
}
