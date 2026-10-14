import 'dart:math' as math;

import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/mosaic_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// mosaic-rail(pen `P2sFxR`) 손 조작 — 누르는 동안 멈춤 · 동작 줄이기에서 정지 + 손으로 밀기 · pause 아이콘 없음(D3 · 점검 U5).
/// 홈 화면 안 모양 · 흐름 기본은 home_screen_test 의 'mosaic-rail' 묶음이 본다. 여기서는 레일만 띄운다.
void main() {
  const image = 'assets/images/person-f1-blind-v1.png';

  Future<void> pumpRail(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: Scaffold(body: MosaicRail(images: [image]))));

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
