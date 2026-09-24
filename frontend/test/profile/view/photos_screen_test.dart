import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/profile/model/photos_repository_provider.dart';
import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_photos_repository.dart';

/// 1×1 투명 PNG. `Image.file` 이 실제로 읽을 수 있는 파일이어야 화면이 그려진다.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('photos_screen_test');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  File photoFile(String name) =>
      File('${tempDir.path}/$name')..writeAsBytesSync(base64Decode(_onePixelPng));

  Future<void> pump(
    WidgetTester tester, {
    required int photoCount,
    double textScale = 1.0,
  }) async {
    final container = ProviderContainer(
      overrides: [
        photosRepositoryProvider.overrideWithValue(FakePhotosRepository()),
        imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
      ],
    );
    addTearDown(container.dispose);

    final files = [for (var i = 0; i < photoCount; i++) photoFile('photo-$i.png')];
    var index = 0;
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = () async => files[index++];
    for (var i = 0; i < photoCount; i++) {
      await viewModel.addPhoto();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const PhotosScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// CTA 가 화면 안에 남아 있는지. 넘치면 사용자가 다음으로 갈 수 없다.
  void expectButtonOnScreen(WidgetTester tester) {
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(find.byType(AppButton)).dy, lessThanOrEqualTo(screenHeight));
  }

  testWidgets('사진 넉 장이어도 넘치지 않고 "다음" 이 화면 안에 있다', (tester) async {
    await pump(tester, photoCount: 4);

    expect(find.text('다음'), findsOneWidget);
    expectButtonOnScreen(tester);
  });

  testWidgets('글씨 배율 2.0 에서도 "다음" 이 화면 안에 있다', (tester) async {
    await pump(tester, photoCount: 4, textScale: 2.0);

    expectButtonOnScreen(tester);
  });

  testWidgets('사진이 2장 미만이면 "다음" 이 꺼져 있다', (tester) async {
    await pump(tester, photoCount: 1);

    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).enabled, isFalse);
  });

  /// 화면에 그려진 순서대로 사진 파일 이름을 읽는다.
  List<String> photoOrder(WidgetTester tester) => [
        for (final image in tester.widgetList<Image>(find.byType(Image)))
          (image.image as FileImage).file.uri.pathSegments.last,
      ];

  /// 길게 눌러 [from] 칸을 [to] 칸으로 끌어다 놓는다.
  Future<void> dragTile(WidgetTester tester, {required int from, required Offset to}) async {
    final gesture = await tester.startGesture(tester.getCenter(find.byType(Image).at(from)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('대표 배지는 첫 칸에만 붙는다', (tester) async {
    await pump(tester, photoCount: 3);

    expect(find.text('대표'), findsOneWidget);
    // 배지는 사진이 아니라 자리를 따라간다 — 첫 칸 위에 있어야 한다.
    expect(
      tester.getCenter(find.text('대표')).dx,
      lessThan(tester.getCenter(find.byType(Image).at(1)).dx),
    );
  });

  testWidgets('길게 눌러 첫 칸으로 끌면 두 사진이 자리를 바꾼다', (tester) async {
    await pump(tester, photoCount: 3);
    expect(photoOrder(tester), ['photo-0.png', 'photo-1.png', 'photo-2.png']);

    await dragTile(tester, from: 1, to: tester.getCenter(find.byType(Image).at(0)));

    // 대표 자리(첫 칸)에 있던 사진과 맞바꾼다 — 앞 사진을 지우지 않고 대표를 바꾼다.
    expect(photoOrder(tester), ['photo-1.png', 'photo-0.png', 'photo-2.png']);
  });

  testWidgets('빈 칸으로는 끌어다 놓을 수 없다', (tester) async {
    await pump(tester, photoCount: 2);
    final emptySlot = tester.getCenter(find.text('사진 추가').first);

    await dragTile(tester, from: 0, to: emptySlot);

    expect(photoOrder(tester), ['photo-0.png', 'photo-1.png']);
  });

  testWidgets('첫 칸에는 "대표로 지정" 액션이 없다', (tester) async {
    // 이미 대표인 칸에 액션을 달면 토크백 메뉴에 아무것도 안 하는 항목이 생긴다.
    final semantics = tester.ensureSemantics();
    await pump(tester, photoCount: 2);

    final node = tester.getSemantics(find.byType(Image).first);

    expect(node.label, contains('대표'));
    expect(node.getSemanticsData().customSemanticsActionIds ?? const <int>[], isEmpty);
    semantics.dispose();
  });

  testWidgets('끌지 못해도 "대표로 지정" 액션으로 첫 칸에 올릴 수 있다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, photoCount: 2);

    final node = tester.getSemantics(find.byType(Image).at(1));
    final actionIds = node.getSemanticsData().customSemanticsActionIds!;
    expect(
      actionIds.map((id) => CustomSemanticsAction.getAction(id)!.label),
      contains('대표로 지정'),
    );

    node.owner!.performAction(node.id, SemanticsAction.customAction, actionIds.first);
    await tester.pump();

    expect(photoOrder(tester), ['photo-1.png', 'photo-0.png']);
    semantics.dispose();
  });
}
