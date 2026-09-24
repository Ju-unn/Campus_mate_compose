import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/profile/model/photos_repository_provider.dart';
import 'package:campus_mate/profile/view/avatar_source_screen.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_face_detector.dart';
import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_photos_repository.dart';

/// 1×1 투명 PNG. `Image.file` 이 실제로 읽을 수 있는 파일이어야 화면이 그려진다.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('avatar_source_test');
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
        faceDetectorProvider.overrideWithValue(FakeFaceDetector()),
      ],
    );
    addTearDown(container.dispose);

    final files = [for (var i = 0; i < photoCount; i++) photoFile('photo-$i.png')];
    var index = 0;
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [files[index++]];
    for (var i = 0; i < photoCount; i++) {
      await viewModel.addPhoto();
    }
    viewModel.prepareAvatarSource();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const AvatarSourceScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// CTA 가 화면 안에 남아 있는지. 넘치면 사용자가 아바타를 만들 수 없다.
  void expectButtonOnScreen(WidgetTester tester) {
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(find.byType(AppButton)).dy, lessThanOrEqualTo(screenHeight));
  }

  testWidgets('사진 넉 장이어도 기본 화면 크기에서 넘치지 않고 버튼이 보인다', (tester) async {
    // 사진 칸이 158 고정이라 가운데를 스크롤로 내주기 전에는 800×600 에서 이미 넘쳤다.
    // RenderFlex 오버플로가 나면 이 테스트가 실패한다.
    await pump(tester, photoCount: 4);

    expect(find.text('이 사진으로 아바타 만들기'), findsOneWidget);
    expectButtonOnScreen(tester);
  });

  testWidgets('글씨 배율 2.0 에서도 버튼이 화면 안에 있다', (tester) async {
    await pump(tester, photoCount: 4, textScale: 2.0);

    expectButtonOnScreen(tester);
  });

  testWidgets('고른 한 장에만 "아바타로 선택" 배지가 붙는다', (tester) async {
    await pump(tester, photoCount: 4);

    expect(find.text('아바타로 선택'), findsOneWidget);
  });

  testWidgets('04-3 에는 대표 배지를 보여주지 않는다(pen dWNkb)', (tester) async {
    // 여기서 고르는 건 순서가 아니라 아바타 원본이다 — 대표 자리는 04-2 에서 정한다.
    await pump(tester, photoCount: 4);

    expect(find.text('대표'), findsNothing);
  });
}
