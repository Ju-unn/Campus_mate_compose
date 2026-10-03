import 'dart:io';

import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 빈 "사진 추가" 칸(`AddPhotoTile`) — 글자가 칸에 안 들어가면 더하기 아이콘만 보인다(대장 결정 (가), 2026-09-29).
/// 15-7 보조 칸 66×88 은 글자를 키우면 좁고, 04-2 칸(폭 360 에서 158×158)은 넉넉하다.
void main() {
  Future<void> pumpTile(WidgetTester tester, {required Size size, required double scale}) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox.fromSize(size: size, child: AddPhotoTile(onTap: () async {}))),
        ),
      ),
    );
  }

  const smallCell = Size(66, 88);
  const wideCell = Size(158, 158);

  for (final scale in [1.0, 1.3, 1.5]) {
    testWidgets('66×88 칸 · 배율 $scale — 아이콘과 "사진 추가" 글자가 다 보인다', (tester) async {
      await pumpTile(tester, size: smallCell, scale: scale);

      expect(tester.takeException(), isNull);
      expect(find.byIcon(AppIcons.plus), findsOneWidget);
      expect(find.text('사진 추가'), findsOneWidget);
    });
  }

  testWidgets('66×88 칸 · 배율 2.0 — 글자는 숨기고 아이콘만, 넘치지 않는다, 낭독 이름은 "사진 추가" 그대로', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTile(tester, size: smallCell, scale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('사진 추가'), findsNothing);
    expect(find.byIcon(AppIcons.plus), findsOneWidget);
    expect(tester.getSemantics(find.byType(InkWell)), isSemantics(label: '사진 추가', hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('글자가 보일 때도 낭독 이름은 "사진 추가" 하나다 — 아이콘만 둘 때와 같은 모양', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTile(tester, size: smallCell, scale: 1.0);

    expect(tester.getSemantics(find.byType(InkWell)), isSemantics(label: '사진 추가', hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('04-2 넓은 칸(158×158)은 배율 2.0 에서도 글자가 보인다', (tester) async {
    await pumpTile(tester, size: wideCell, scale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('사진 추가'), findsOneWidget);
    expect(find.byIcon(AppIcons.plus), findsOneWidget);
  });

  group('PhotoSlotGrid — 2×2 네 칸 배치(04-2 · 15-7)', () {
    // 파일은 읽지 않는다 — 배치만 본다(그림은 아직 오는 중이어도 칸 크기는 같다).
    SelectedPhoto photo(String name) => SelectedPhoto(File('missing/$name.png'));

    Future<void> pumpGrid(WidgetTester tester, PhotosUiState state, {double columnGap = 16}) async {
      tester.view.physicalSize = const Size(328, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: PhotoSlotGrid(
              state: state,
              viewModel: container.read(photosViewModelProvider.notifier),
              columnGap: columnGap,
            ),
          ),
        ),
      );
    }

    testWidgets('사진 → 사진 칸, 나머지 → "사진 추가" 칸, 칸 순서는 왼쪽 위부터 가로로', (tester) async {
      await pumpGrid(tester, PhotosUiState(photos: [photo('a'), photo('b')]));

      final photos = find.byType(DraggablePhotoTile);
      expect(photos, findsNWidgets(2));
      expect(find.byType(AddPhotoTile), findsNWidgets(2));
      expect(tester.widget<DraggablePhotoTile>(photos.at(1)).index, 1);
      expect(tester.getTopLeft(photos.at(1)), const Offset(156 + 16, 0));
    });

    testWidgets('살펴보는 중이면 들어올 자리(사진 다음 칸)에만 기다리는 표시', (tester) async {
      await pumpGrid(tester, PhotosUiState(photos: [photo('a')], isCheckingPhotos: true));

      expect(tester.getTopLeft(find.byType(CheckingTile)), const Offset(156 + 16, 0));
      expect(find.byType(AddPhotoTile), findsNWidgets(2));
    });

    testWidgets('칸 높이 158 · 행 사이 12 고정, 칸 폭은 열 간격을 뺀 나머지의 반', (tester) async {
      await pumpGrid(tester, const PhotosUiState(), columnGap: 12);

      final tiles = find.byType(AddPhotoTile);
      expect(tiles, findsNWidgets(4));
      expect(tester.getRect(tiles.at(0)), const Rect.fromLTWH(0, 0, 158, 158));
      expect(tester.getRect(tiles.at(1)), const Rect.fromLTWH(170, 0, 158, 158));
      expect(tester.getRect(tiles.at(3)), const Rect.fromLTWH(170, 170, 158, 158));
      expect(tester.getSize(find.byType(PhotoSlotGrid)), const Size(328, 328));
    });
  });
}
