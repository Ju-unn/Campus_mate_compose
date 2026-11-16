import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/media/model/repository/face_detector_provider.dart';
import 'package:campus_mate/auth/media/model/repository/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/profile/avatar/view/avatar_source_tile.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/profile/avatar/model/repository/photos_repository_provider.dart';
import 'package:campus_mate/profile/avatar/view/avatar_source_screen.dart';
import 'package:campus_mate/profile/avatar/view/photo_example.dart';
import 'package:campus_mate/profile/avatar/viewmodel/photos_view_model.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../auth/media/model/repository/fake_face_detector.dart';
import '../../../auth/media/model/repository/fake_image_compressor.dart';
import '../../onboarding/model/repository/fake_onboarding_repository.dart';
import '../model/repository/fake_photos_repository.dart';

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
      File('${tempDir.path}/$name')..writeAsBytesSync([...base64Decode(_onePixelPng), ...utf8.encode(name)]); // 이름을 꼬리에 붙여 서로 다른 사진으로 — 같은 바이트는 같은 사진으로 막힌다

  Future<void> pump(
    WidgetTester tester, {
    required int photoCount,
    double textScale = 1.0,
    FakePhotosRepository? photos,
    List<double?> faceRatios = const [],
    List<bool> companions = const [],
    // 04-3 을 한 번 연 뒤 04-2 로 돌아가 한 일. 끝나면 다시 "다음" 으로 04-3 에 온다.
    Future<void> Function(PhotosViewModel viewModel, FakeFaceDetector faces)? backTo04_2,
  }) async {
    final faces = FakeFaceDetector()
      ..queuedWidthRatios.addAll(faceRatios)
      ..queuedHasCompanion.addAll(companions);
    final container = ProviderContainer(
      overrides: [
        photosRepositoryProvider.overrideWithValue(photos ?? FakePhotosRepository()),
        imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
        faceDetectorProvider.overrideWithValue(faces),
        // 올리기가 막히면 가입 막힘을 사용 통계로 알리려고 온보딩 단계 캐시를 읽는다 — 진짜 저장소를 만들지 않게 가짜를 둔다.
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
      ],
    );
    addTearDown(container.dispose);

    final files = [for (var i = 0; i < photoCount; i++) photoFile('photo-$i.png')];
    var index = 0;
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = ((limit) async => [files[index++]])
      ..hashSource = (path) async => sha256OfFile(path); // 가짜 시계는 isolate 를 기다리지 못한다
    for (var i = 0; i < photoCount; i++) {
      await viewModel.addPhoto();
    }
    viewModel.prepareAvatarSource();
    if (backTo04_2 != null) {
      await backTo04_2(viewModel, faces);
      viewModel.prepareAvatarSource();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

  // pen `q7Rp0G`(2026-10-14 시안, 사용자 결정 10-14 · 대장 전달 값) — 안내 아래 24, 버튼 줄 위.
  testWidgets('안내 카드 아래 24 에 아바타 변환 예시, 그 아래에 버튼', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, photoCount: 4);
    await tester.scrollUntilVisible(find.byType(PhotoExample), 200, scrollable: find.byType(Scrollable).first);

    expect(find.text('내 사진이 이런 일러스트 아바타로 바뀌어요'), findsOneWidget);
    final example = tester.getRect(find.byType(PhotoExample));
    expect(example.top - tester.getRect(find.byType(NoticeCard)).bottom, 24);
    expect(example.bottom, lessThanOrEqualTo(tester.getTopLeft(find.byType(AppButton)).dy));
  });

  // 올리기 오류는 안내 카드 바로 아래 8 — 예시 그림은 그 뒤다(15b-4/5 와 같은 순서, 대장 검토 10-15).
  testWidgets('올리기가 실패하면 오류 문구가 안내 카드 바로 아래에 오고 예시는 그 아래다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final photos = FakePhotosRepository()..nextResult = const FailureResult(NetworkFailure());
    await pump(tester, photoCount: 2, photos: photos);

    await tester.tap(find.text('이 사진으로 아바타 만들기'));
    await tester.pump();
    await tester.pump();

    final error = find.text(failureText(AppLocalizationsKo(), const NetworkFailure()));
    expect(error, findsOneWidget);
    expect(tester.getTopLeft(error).dy - tester.getRect(find.byType(NoticeCard)).bottom, 8);
    expect(tester.getRect(find.byType(PhotoExample)).top - tester.getBottomLeft(error).dy, 24);
  });

  // 사용자 결정 2026-11-15 — 새 부품 없이 올리기 오류와 같은 자리(안내 카드 아래 8)에 보인다.
  testWidgets('얼굴이 작은 사진만 있으면 오류 자리에 "얼굴이 크게 나온 사진을 골라 주세요" 가 나오고 버튼이 꺼진다', (tester) async {
    await pump(tester, photoCount: 2, faceRatios: [0.1, 0.05]);

    final message = find.text('얼굴이 크게 나온 사진을 골라 주세요');
    expect(message, findsOneWidget);
    expect(tester.getTopLeft(message).dy - tester.getRect(find.byType(NoticeCard)).bottom, 8);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
  });

  // 사용자 결정 2026-11-17 — 여러 명이 나온 사진은 아바타 원본으로 쓰지 않는다. 얼굴 크기 문구와 같은 자리.
  testWidgets('여러 명이 나온 사진만 있으면 오류 자리에 "혼자 나온 사진을 골라 주세요" 가 나오고 버튼이 꺼진다', (tester) async {
    await pump(tester, photoCount: 2, faceRatios: [0.3, 0.3], companions: [true, true]);

    final message = find.text('혼자 나온 사진을 골라 주세요');
    expect(message, findsOneWidget);
    expect(tester.getTopLeft(message).dy - tester.getRect(find.byType(NoticeCard)).bottom, 8);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
  });

  testWidgets('04-2 에 남은 얼굴 없음 오류가 04-3 의 작은 얼굴 문구를 가리지 않는다', (tester) async {
    // 전부 작음 → 04-3 → 뒤로 → 04-2 에서 얼굴 없는 사진을 더하려다 실패(error = 얼굴 없음) → 다음 → 04-3.
    await pump(
      tester,
      photoCount: 2,
      faceRatios: [0.1, 0.05],
      backTo04_2: (viewModel, faces) async {
        faces.nextResult = false;
        viewModel.pickFromGallery = (limit) async => [photoFile('no-face.png')];
        await viewModel.addPhoto();
      },
    );

    expect(find.text('얼굴이 크게 나온 사진을 골라 주세요'), findsOneWidget);
    expect(find.text('얼굴이 보이는 사진을 골라 주세요'), findsNothing);
  });

  testWidgets('얼굴이 작은 사진을 누르면 문구가 나오고 버튼이 꺼지며, 큰 사진으로 돌아가면 사라진다', (tester) async {
    await pump(tester, photoCount: 2, faceRatios: [0.3, 0.1]);
    final message = find.text('얼굴이 크게 나온 사진을 골라 주세요');

    await tester.tap(find.byType(AvatarSourceTile).last);
    await tester.pump();
    expect(message, findsOneWidget);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);

    await tester.tap(find.byType(AvatarSourceTile).first);
    await tester.pump();
    expect(message, findsNothing);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
  });

  testWidgets('기준을 넘는 사진이 있으면 그 사진이 골라져 문구 없이 버튼이 켜진다', (tester) async {
    await pump(tester, photoCount: 2, faceRatios: [0.1, 0.3]);

    expect(find.text('얼굴이 크게 나온 사진을 골라 주세요'), findsNothing);
    expect(tester.widget<AvatarSourceTile>(find.byType(AvatarSourceTile).last).isSelected, isTrue);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
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

  group('서버가 글자 많은 사진을 거절(422 `photo_looks_like_document`)', () {
    /// 04-2 자리 위에 04-3 을 올린 뒤 "이 사진으로 아바타 만들기" 를 누른다.
    Future<void> submitOnTopOf04_2(WidgetTester tester, {String? code}) async {
      final photos = FakePhotosRepository()
        ..resultAt[1] = FailureResult(ServerRejectedFailure('서버 임시 문구', code: code));
      final container = ProviderContainer(
        overrides: [
          photosRepositoryProvider.overrideWithValue(photos),
          imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
          faceDetectorProvider.overrideWithValue(FakeFaceDetector()),
          onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        ],
      );
      addTearDown(container.dispose);
      final files = [for (var i = 0; i < 3; i++) photoFile('photo-$i.png')];
      var index = 0;
      final viewModel = container.read(photosViewModelProvider.notifier)
        ..pickFromGallery = ((limit) async => [files[index++]])
        ..hashSource = (path) async => sha256OfFile(path); // 가짜 시계는 isolate 를 기다리지 못한다
      for (var i = 0; i < 3; i++) {
        await viewModel.addPhoto();
      }
      viewModel.prepareAvatarSource();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, navigatorKey: navigator, home: const Text('04-2 자리')),
        ),
      );
      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const AvatarSourceScreen())));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
    }

    testWidgets('사진을 고칠 수 있는 04-2 로 돌아간다 — 서버 문구는 04-3 에 띄우지 않는다', (tester) async {
      await submitOnTopOf04_2(tester, code: 'photo_looks_like_document');

      expect(find.byType(AvatarSourceScreen), findsNothing);
      expect(find.text('04-2 자리'), findsOneWidget);
      expect(find.text('서버 임시 문구'), findsNothing);
    });

    testWidgets('모르는 code 는 지금처럼 04-3 에 머물며 서버 문구를 안내 카드 아래에 보인다', (tester) async {
      await submitOnTopOf04_2(tester, code: 'photo_unsafe');

      expect(find.byType(AvatarSourceScreen), findsOneWidget);
      expect(find.text('서버 임시 문구'), findsOneWidget);
    });
  });
}
