import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/model/photos_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
import 'package:campus_mate/profile/view/hint_line.dart';
import 'package:campus_mate/profile/view/photo_example.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_face_detector.dart';
import '../../account/model/fake_account_repository.dart';
import '../../auth/model/fake_image_compressor.dart';
import '../../core/draft/fake_draft_store.dart';
import '../../me/model/fake_me_repository.dart';
import '../model/fake_onboarding_repository.dart';
import '../model/fake_photos_repository.dart';

/// 1×1 투명 PNG. `Image.file` 이 실제로 읽을 수 있는 파일이어야 화면이 그려진다.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// 사진 칸 안의 사진만 — 아래 안내 박스의 3D 아이콘 · 좋은 사진 예시도 `Image` 다.
final _slotImages = find.descendant(of: find.byType(PhotoSlotGrid), matching: find.byType(Image));

const _galleryGuide = '갤러리에서 여러 장을 한 번에 고를 수 있어요. 최소 2장이 필요해요.';
const _reorderGuide = '사진을 길게 눌러 끌면 순서를 바꿀 수 있어요. 첫 칸이 대표 사진이에요.';
const _oldRulesTitle = '이런 사진은 올릴 수 없어요';
const _notice = '글자 많은 사진·얼굴 가린 사진은 올릴 수 없어요';
const _document = '학생증·신분증처럼 글자가 많은 사진은 올릴 수 없어요. 얼굴이 잘 나온 일반 사진을 올려 주세요';

void main() {
  late Directory tempDir;
  late FakeFaceDetector faceDetector;
  late FakeOnboardingRepository onboarding;
  late FakeMeRepository me;
  late FakeAccountRepository account;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('photos_screen_test');
    faceDetector = FakeFaceDetector();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  File photoFile(String name) =>
      File('${tempDir.path}/$name')..writeAsBytesSync(base64Decode(_onePixelPng));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required int photoCount,
    double textScale = 1.0,
    FakePhotosRepository? photos,
    FakeDraftStore? drafts,
  }) async {
    onboarding = FakeOnboardingRepository()..nextResult = const Success(OnboardingStep.photos);
    me = FakeMeRepository(const Success(savedOnboardingProfile));
    account = FakeAccountRepository()..kakaoIdResult = const Success('fox_rain_22');
    final container = ProviderContainer(
      overrides: [
        photosRepositoryProvider.overrideWithValue(photos ?? FakePhotosRepository()),
        imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
        faceDetectorProvider.overrideWithValue(faceDetector),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        meRepositoryProvider.overrideWithValue(me),
        accountRepositoryProvider.overrideWithValue(account),
        if (drafts != null) draftStoreProvider.overrideWithValue(drafts),
      ],
    );
    addTearDown(container.dispose);
    await container.read(onboardingStepListenableProvider).refresh();

    final files = [for (var i = 0; i < photoCount; i++) photoFile('photo-$i.png')];
    var index = 0;
    final viewModel = container.read(photosViewModelProvider.notifier)
      ..pickFromGallery = (limit) async => [files[index++]];
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
    return container;
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

  group('뒤로가기', () {
    testWidgets('앱바 뒤로를 누르면 카카오톡 아이디를 읽은 뒤 04-1b 로 가고, 아이디는 폰에 남기지 않는다', (tester) async {
      final drafts = FakeDraftStore();
      final container = await pump(tester, photoCount: 2, drafts: drafts);

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pumpAndSettle();

      final steps = container.read(onboardingStepListenableProvider);
      expect(steps.value, OnboardingStep.kakaoId);
      expect(account.kakaoIdFetches, 1);
      expect(container.read(kakaoIdViewModelProvider).kakaoIdInput, 'fox_rain_22');
      expect(drafts.dump, isNot(contains('fox_rain')));
      // 04-2 는 아직 지금 단계라 고른 사진은 메모리에 그대로 있다 — 04-1b 를 저장하면 다시 보인다.
      expect(container.read(photosViewModelProvider).photos, hasLength(2));
    });

    testWidgets('안드로이드 시스템 뒤로는 앱바 화살표와 같고 종료 안내는 뜨지 않는다', (tester) async {
      final container = await pump(tester, photoCount: 2);
      expect(find.byType(BackExitScope), findsOneWidget, reason: '라우터와 두 겹이면 같은 뒤로가기에 안내까지 뜬다');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(container.read(onboardingStepListenableProvider).value, OnboardingStep.kakaoId);
      expect(find.text(backExitMessage), findsNothing);
    });
  });

  // 2×2 배치는 15-7 과 같은 PhotoSlotGrid 를 쓴다 — 두 벌이면 한쪽만 고쳐진다. 04-2 열 간격은 12(pen F5DPI).
  testWidgets('사진 칸은 공용 PhotoSlotGrid 로, 열 간격 12 다', (tester) async {
    await pump(tester, photoCount: 2);

    expect(tester.widget<PhotoSlotGrid>(find.byType(PhotoSlotGrid)).columnGap, AppSpacing.sm);
  });

  group('pen 04-2 재배치(campus-pen 10-16) — 예시가 첫 화면에', () {
    Finder noticeBox() => find.ancestor(of: find.text(_notice), matching: find.byType(Container)).first;

    testWidgets('제목 → 부제 → 32 → 좋은 사진 예시(188) → 16 → 안내 한 줄 → 16 → 사진 칸 → 16 → 설명 줄 둘(6)', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, photoCount: 2);

      final subtitle = tester.getRect(find.text('얼굴이 잘 보이는 사진을 2~4장 골라주세요.'));
      final example = tester.getRect(find.byType(PhotoExample));
      final notice = tester.getRect(noticeBox());
      final grid = tester.getRect(find.byType(PhotoSlotGrid));
      final hints = tester.widgetList<HintLine>(find.byType(HintLine)).toList();
      final first = tester.getRect(find.byType(HintLine).at(0));
      final second = tester.getRect(find.byType(HintLine).at(1));

      expect(example.top, closeTo(subtitle.bottom + 32, 0.01));
      expect(example.height, closeTo(188, 0.5));
      expect(notice.top, closeTo(example.bottom + 16, 0.01));
      // 안내 높이는 글 줄 수를 따른다(아래 시험이 한 줄 46 을 본다 — 시험 글꼴은 글자마다 1em 이라 360 폭에서는 두 줄로 접힌다).
      expect(notice.height, closeTo(tester.getSize(find.text(_notice)).height + 28, 0.01));
      expect(grid.top, closeTo(notice.bottom + 16, 0.01));
      expect(first.top, closeTo(grid.bottom + 16, 0.01));
      expect(second.top, closeTo(first.bottom + 6, 0.01));
      expect([for (final hint in hints) hint.text], [_galleryGuide, _reorderGuide]);
      expect(find.text('이런 사진이 좋아요'), findsOneWidget);
      expect(find.text(_oldRulesTitle), findsNothing);
    });

    testWidgets('안내 한 줄 — 아이콘 · 머리 없이 본문 12/normal, 안쪽 14 · 한 줄이면 높이 46', (tester) async {
      // 시험 글꼴은 글자마다 1em(26자 × 12 = 312)이라 글이 한 줄에 드는 폭(420)에서 잰다. 기기 글꼴은 360 폭에서도 한 줄이다.
      tester.view.physicalSize = const Size(420, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, photoCount: 2);

      final box = noticeBox();
      expect(find.descendant(of: box, matching: find.byType(Icon3d)), findsNothing);
      expect(find.descendant(of: box, matching: find.byType(Icon)), findsNothing);
      expect(find.descendant(of: box, matching: find.byType(Text)), findsOneWidget);
      final style = tester.widget<Text>(find.text(_notice)).style!;
      expect((style.fontSize, style.fontWeight), (12, FontWeight.w400));
      final text = tester.getRect(find.text(_notice));
      expect(text.topLeft - tester.getTopLeft(box), const Offset(14, 14));
      expect(text.height, closeTo(18, 0.01), reason: '한 줄');
      expect(tester.getSize(box).height, 46);
    });

    for (final height in [780.0, 600.0]) {
      testWidgets('좋은 사진 예시가 첫 화면(360×$height)에 스크롤 없이 다 보이고, 아래는 스크롤로 내려간다', (tester) async {
        tester.view.physicalSize = Size(360, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pump(tester, photoCount: 4);

        final scroll = find.byType(Scrollable).first;
        final viewport = tester.getRect(scroll);
        final example = tester.getRect(find.byType(PhotoExample));
        expect(tester.state<ScrollableState>(scroll).position.pixels, 0);
        expect(example.top, greaterThanOrEqualTo(viewport.top));
        expect(example.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(tester.state<ScrollableState>(scroll).position.maxScrollExtent, greaterThan(0));

        await tester.scrollUntilVisible(find.text(_reorderGuide), 200, scrollable: scroll);
        expect(tester.takeException(), isNull);
        expectButtonOnScreen(tester);
      });
    }
  });

  group('서버가 글자 많은 사진을 거절(422 `photo_looks_like_document`)', () {
    Future<ProviderContainer> rejected(WidgetTester tester, {String? code = 'photo_looks_like_document'}) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final photos = FakePhotosRepository()
        ..resultAt[1] = FailureResult(ServerRejectedFailure('서버 임시 문구', code: code));
      final container = await pump(tester, photoCount: 3, photos: photos);
      final viewModel = container.read(photosViewModelProvider.notifier)..prepareAvatarSource();
      await viewModel.submit();
      await tester.pump();
      return container;
    }

    Finder addTiles() => find.byType(AddPhotoTile);
    BoxDecoration addTileFace(WidgetTester tester, int index) =>
        tester.widget<Ink>(find.descendant(of: addTiles().at(index), matching: find.byType(Ink))).decoration! as BoxDecoration;

    testWidgets('사진 칸 바로 아래 8 에 앱 고정 문구(circle-alert 14 · 12/normal error), 그 사진은 빠지고 빈 칸에 오류 테두리 2', (tester) async {
      await rejected(tester);

      expect(find.text('서버 임시 문구'), findsNothing);
      expect(find.byType(AppToast), findsNothing, reason: '토스트가 아니라 칸 아래 글');
      final note = find.byType(PhotoDocumentNote);
      expect(find.descendant(of: note, matching: find.text(_document)), findsOneWidget);
      expect(tester.getTopLeft(note).dy, closeTo(tester.getRect(find.byType(PhotoSlotGrid)).bottom + 8, 0.01));
      final style = tester.widget<Text>(find.text(_document)).style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, AppColors.error));
      expect(tester.widget<Text>(find.text(_document)).maxLines, isNull, reason: '두 줄로 내려간다');
      final icon = tester.widget<Icon>(find.descendant(of: note, matching: find.byIcon(AppIcons.circleAlert)));
      expect((icon.size, icon.color), (14, AppColors.error));
      expect(find.byType(DraggablePhotoTile), findsNWidgets(2));
      expect(addTileFace(tester, 0).border, Border.all(color: AppColors.error, width: 2));
      expect(addTileFace(tester, 1).border, isNull);
      // 문구 아래로 설명 줄이 16 띄워 이어진다.
      expect(tester.getTopLeft(find.byType(HintLine).first).dy, closeTo(tester.getRect(note).bottom + 16, 0.01));
    });

    testWidgets('사진을 빼면 문구 · 테두리가 사라진다', (tester) async {
      await rejected(tester);

      await tester.tap(find.byIcon(AppIcons.x).first);
      await tester.pump();

      expect(find.byType(PhotoDocumentNote), findsNothing);
      expect(addTileFace(tester, 0).border, isNull);
    });

    testWidgets('모르는 code 는 지금처럼 서버 문구 토스트, 사진 · 칸 모양은 그대로', (tester) async {
      await rejected(tester, code: 'photo_unsafe');

      expect(find.byType(PhotoDocumentNote), findsNothing);
      expect(find.widgetWithText(AppToast, '서버 임시 문구'), findsOneWidget);
      expect(find.byType(DraggablePhotoTile), findsNWidgets(3));
      expect(addTileFace(tester, 0).border, isNull);
    });
  });

  // 사진 크게 보기는 15-7 내 사진 수정에서만(사용자 결정 2026-10-16) — 가입 중 04-2 는 칸을 눌러도 아무 화면도 안 뜬다.
  testWidgets('사진 칸을 눌러도 확대가 열리지 않고, 화면 읽기에도 탭 동작이 없다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, photoCount: 2);
    await tester.ensureVisible(find.byType(PhotoSlotGrid));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DraggablePhotoTile).at(1));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(PhotosScreen), findsOneWidget);
    expect(tester.getSemantics(find.byType(DraggablePhotoTile).at(1)), isSemantics(label: '사진 2', hasTapAction: false));
    semantics.dispose();
  });

  testWidgets('사진이 2장 미만이면 "다음" 이 꺼져 있다', (tester) async {
    await pump(tester, photoCount: 1);

    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).enabled, isFalse);
  });

  /// 화면에 그려진 순서대로 사진 파일 이름을 읽는다.
  List<String> photoOrder(WidgetTester tester) => [
        for (final image in tester.widgetList<Image>(_slotImages))
          (image.image as FileImage).file.uri.pathSegments.last,
      ];

  /// 길게 눌러 [from] 칸을 [to] 자리로 끌어다 놓는다. [to] 는 칸을 보이게 민 뒤에 잰다.
  Future<void> dragTile(WidgetTester tester, {required int from, required Finder to}) async {
    // 좋은 사진 예시가 칸 위로 올라와(pen 10-16) 칸이 첫 화면 아래에 걸칠 수 있다 — 사람처럼 칸을 보이게 한 뒤 끈다.
    await tester.ensureVisible(find.byType(PhotoSlotGrid));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(_slotImages.at(from)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(to));
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
      lessThan(tester.getCenter(_slotImages.at(1)).dx),
    );
  });

  testWidgets('길게 눌러 첫 칸으로 끌면 두 사진이 자리를 바꾼다', (tester) async {
    await pump(tester, photoCount: 3);
    expect(photoOrder(tester), ['photo-0.png', 'photo-1.png', 'photo-2.png']);

    await dragTile(tester, from: 1, to: _slotImages.at(0));

    // 대표 자리(첫 칸)에 있던 사진과 맞바꾼다 — 앞 사진을 지우지 않고 대표를 바꾼다.
    expect(photoOrder(tester), ['photo-1.png', 'photo-0.png', 'photo-2.png']);
  });

  testWidgets('빈 칸으로는 끌어다 놓을 수 없다', (tester) async {
    await pump(tester, photoCount: 2);
    await dragTile(tester, from: 0, to: find.text('사진 추가').first);

    expect(photoOrder(tester), ['photo-0.png', 'photo-1.png']);
  });

  testWidgets('첫 칸에는 "대표로 지정" 액션이 없다', (tester) async {
    // 이미 대표인 칸에 액션을 달면 토크백 메뉴에 아무것도 안 하는 항목이 생긴다.
    final semantics = tester.ensureSemantics();
    await pump(tester, photoCount: 2);

    final node = tester.getSemantics(_slotImages.first);

    expect(node.label, contains('대표'));
    expect(node.getSemanticsData().customSemanticsActionIds ?? const <int>[], isEmpty);
    semantics.dispose();
  });

  testWidgets('끌지 못해도 "대표로 지정" 액션으로 첫 칸에 올릴 수 있다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, photoCount: 2);

    final node = tester.getSemantics(_slotImages.at(1));
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

  testWidgets('얼굴이 없어 빠지면 버튼 위에 토스트로 알린다', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await pump(tester, photoCount: 2);
    container.read(photosViewModelProvider.notifier).pickFromGallery =
        (limit) async => [photoFile('photo-new.png')];
    faceDetector.nextResult = false;

    // 안내 박스가 칸 위로 올라가 아랫줄 칸은 스크롤해야 보인다(04-2 재배치 10-15).
    await tester.ensureVisible(find.text('사진 추가').first);
    await tester.tap(find.text('사진 추가').first);
    await tester.pump();
    await tester.pump();

    expect(find.text('얼굴이 보이는 사진을 골라 주세요'), findsOneWidget);
    // 토스트는 "다음" 버튼 위에 뜬다.
    expect(
      tester.getBottomLeft(find.byType(AppToast)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(AppButton)).dy),
    );

    // 초점을 받을 일이 없는 안내라 liveRegion 이라야 토크백이 바로 읽어 준다.
    expect(tester.getSemantics(find.byType(AppToast)), isSemantics(isLiveRegion: true));

    // 3초 뒤에는 저절로 사라진다.
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(AppToast), findsNothing);
    semantics.dispose();
  });

  testWidgets('살펴보는 동안에는 "다음" 이 꺼지고 끝나면 다시 켜진다', (tester) async {
    final container = await pump(tester, photoCount: 2);
    container.read(photosViewModelProvider.notifier).pickFromGallery =
        (limit) async => [photoFile('photo-new.png')];
    final gate = Completer<bool>();
    faceDetector.gate = gate;

    // 안내 박스가 칸 위로 올라가 아랫줄 칸은 스크롤해야 보인다(04-2 재배치 10-15).
    await tester.ensureVisible(find.text('사진 추가').first);
    await tester.tap(find.text('사진 추가').first);
    await tester.pump();
    await tester.pump();

    // 두 장이라 이미 넘어갈 수 있지만, 늦게 끝난 검사가 04-3 이 올리는 목록에 끼어든다.
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).enabled, isFalse);

    gate.complete(true);
    faceDetector.gate = null;
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).enabled, isTrue);
  });

  testWidgets('살펴보는 동안 들어올 칸에 기다리는 표시가 뜬다', (tester) async {
    final container = await pump(tester, photoCount: 2);
    container.read(photosViewModelProvider.notifier).pickFromGallery =
        (limit) async => [photoFile('photo-new.png')];
    final gate = Completer<bool>();
    faceDetector.gate = gate;

    // 안내 박스가 칸 위로 올라가 아랫줄 칸은 스크롤해야 보인다(04-2 재배치 10-15).
    await tester.ensureVisible(find.text('사진 추가').first);
    await tester.tap(find.text('사진 추가').first);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 두 장 다음 칸(아랫줄 왼쪽)에서 기다린다 — 엉뚱한 칸이 덮이면 고른 사진이 사라진 것처럼 보인다.
    final spinner = tester.getRect(find.byType(CircularProgressIndicator));
    final firstPhoto = tester.getRect(_slotImages.first);
    expect(spinner.center.dy, greaterThan(firstPhoto.bottom));
    expect(spinner.center.dx, lessThan(firstPhoto.right));

    gate.complete(true);
    faceDetector.gate = null;
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_slotImages, findsNWidgets(3));
  });

  testWidgets('사진 추가 칸의 바탕은 화면이 아니라 칸이 칠한다', (tester) async {
    // `Ink` 는 가장 가까운 Material 에 칠한다 — 그게 Scaffold 면 분홍 바탕이 화면에 눌러앉아,
    // 목록을 당겼다 놓을 때 글자만 따라 움직인다(칩에서 사용자가 본 것과 같은 자리, 2026-09-26).
    await pump(tester, photoCount: 0);

    final label = find.text('사진 추가');
    final tile = find.ancestor(of: label, matching: find.byType(InkWell)).first;
    final painter = find.ancestor(of: label, matching: find.byType(Material)).first;

    expect(tester.getSize(painter), tester.getSize(tile));
  });
}
