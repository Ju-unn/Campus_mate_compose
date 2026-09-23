import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/profile/model/photos_repository_provider.dart';
import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
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
}
