import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/me/view/avatar_regen_pick_screen.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/viewmodel/avatar_regen_pick_view_model.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/view/avatar_source_tile.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../auth/model/fake_face_detector.dart';
import '../../auth/model/fake_image_compressor.dart';
import '../../profile/model/fake_avatar_repository.dart';
import '../model/fake_me_repository.dart';

/// 1×1 투명 PNG. `Image.file` 이 실제로 읽을 수 있는 파일이어야 화면이 그려진다.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const _title = '아바타로 만들 사진을 골라주세요';
const _subtitle = '고른 사진 한 장이 새 아바타로 변환돼요.';

/// 이름 · 학교는 지어낸 값이다. 실제 사진 세 장 중 둘째가 지금 아바타 원본.
MyProfile _profile({int heartBalance = 320, int avatarRegenCost = 10}) => MyProfile(
      nickname: '여우',
      age: 23,
      university: '가나대학교',
      major: '경영학과',
      heightCm: 178,
      mbti: 'ENFP',
      avatarUrl: 'https://img.test/avatar.png',
      photos: const [
        MyPhoto(id: 'p-0', url: 'https://img.test/0.png', isAvatarSource: false),
        MyPhoto(id: 'p-1', url: 'https://img.test/1.png', isAvatarSource: true),
        MyPhoto(id: 'p-2', url: 'https://img.test/2.png', isAvatarSource: false),
      ],
      preferredAgeMin: 22,
      preferredAgeMax: 27,
      preferredHeightMin: 165,
      preferredHeightMax: 180,
      bio: '',
      heartBalance: heartBalance,
      avatarRegenCost: avatarRegenCost,
    );

/// 등록이 불린 순간 사진 교체가 몇 번 끝나 있었는지 적어 둔다 — 순서를 본다.
class _OrderedAvatars extends FakeAvatarRepository {
  _OrderedAvatars(this.me);

  final FakeMeRepository me;
  final List<int> photoSavesWhenRegistered = [];

  @override
  Future<Result<AvatarGenerationOutcome>> regenerateAvatar() {
    photoSavesWhenRegistered.add(me.photoSaves.length);
    return super.regenerateAvatar();
  }
}

void main() {
  late Directory tempDir;
  late File picked;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('avatar_regen_pick_test');
    picked = File('${tempDir.path}/new.png')..writeAsBytesSync(base64Decode(_onePixelPng));
  });

  tearDown(() {
    // 윈도에서는 화면이 읽던 그림 파일이 아직 열려 있을 수 있다 — 그림 캐시를 비우고, 그래도 안 지워지면 임시 폴더라 둔다.
    imageCache.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // 시스템 임시 폴더라 나중에 치워진다.
    }
  });

  late FakeMeRepository me;
  late _OrderedAvatars avatars;
  late FakeFaceDetector faces;
  late ProviderContainer container;

  /// 15 위에 15b-4 를 올린다. [pick] 이 갤러리가 돌려줄 사진(null 이면 고르지 않고 닫음).
  Future<void> pump(
    WidgetTester tester, {
    MyProfile? profile,
    Future<File?> Function()? pick,
  }) async {
    me = FakeMeRepository(Success(profile ?? _profile()));
    // 등록한 뒤 상태를 한 번 물으면 바로 완성으로 끝나게 한다 — 안 그러면 묻는 타이머가 시험이 끝난 뒤에도 남는다.
    avatars = _OrderedAvatars(me)..statusResults.add(const Success(AvatarReady('https://img.test/new.png')));
    faces = FakeFaceDetector();
    container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        avatarRepositoryProvider.overrideWithValue(avatars),
        faceDetectorProvider.overrideWithValue(faces),
        imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 라 듣는 쪽이 있어야 훅을 꽂은 뷰모델이 화면이 붙을 때까지 남는다.
    final keep = container.listen(avatarRegenPickViewModelProvider, (_, _) {});
    addTearDown(keep.close);
    container.read(avatarRegenPickViewModelProvider.notifier).pickFromGallery = pick ?? () async => picked;
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(path: AppRoutes.myProfile, builder: (context, state) => const Scaffold(body: Text('화면 15'))),
        GoRoute(path: AppRoutes.myAvatarRegen, builder: (context, state) => const AvatarRegenPickScreen()),
        GoRoute(path: AppRoutes.heartStore, builder: (context, state) => const Scaffold(body: Text('18 스토어 화면'))),
      ],
    );
    addTearDown(router.dispose);
    // 15 의 프로필이 먼저 읽혀 있어야 시트가 비용 · 잔액을 안다(실제로는 15 가 이미 읽어 둔다).
    await container.read(myProfileProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    unawaited(router.push(AppRoutes.myAvatarRegen));
    await tester.pumpAndSettle();
  }

  void usePenFrame(WidgetTester tester, {double height = 780}) {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> choosePhoto(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byType(AddPhotoTile));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  final cta = find.byType(AppButton);

  group('틀 — 15b-4 `nN9EC` (사진을 고르기 전)', () {
    testWidgets('상단 막대 "아바타 다시 만들기"(편집 앱바), 제목 24/700 · 부제 16 · 사진 칸 158 · 안내 카드 · 버튼', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(tester.widget<EditAppBar>(find.byType(EditAppBar)).title, '아바타 다시 만들기');
      final title = tester.widget<Text>(find.text(_title)).style!;
      expect((title.fontSize, title.fontWeight, title.color), (24, FontWeight.w700, AppColors.ink));
      final subtitle = tester.widget<Text>(find.text(_subtitle)).style!;
      expect((subtitle.fontSize, subtitle.fontWeight, subtitle.color, subtitle.height), (16, FontWeight.w400, AppColors.body, 1.6));
      expect(find.byType(NoticeCard), findsOneWidget);
      expect(find.text('상호 수락 전에는 아바타만 보여요'), findsOneWidget);
      expect(find.byType(AddPhotoTile), findsOneWidget);
    });

    testWidgets('사진 칸 158×158 (x16), 칸 아래 안내 카드까지 16, 제목 · 부제 · 칸은 왼쪽 16', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final tile = tester.getRect(find.byType(AddPhotoTile));
      expect(tile.size, const Size(158, 158));
      expect(tile.left, 16);
      expect(tester.getRect(find.byType(NoticeCard)).top - tile.bottom, 16);
      expect(tester.getTopLeft(find.text(_title)).dx, 16);
      expect(tester.getTopLeft(find.text(_subtitle)).dx, 16);
    });

    testWidgets('사진 칸 `I7hYbr` — 분홍 #FFF0F2 바탕 · 모서리 14 · + 아이콘과 "사진 추가"(가입 04-2 와 같은 칸)', (tester) async {
      await pump(tester);

      expect(find.text('사진 추가'), findsOneWidget);
      final fill = tester.widget<Ink>(find.descendant(of: find.byType(AddPhotoTile), matching: find.byType(Ink)));
      final decoration = fill.decoration! as BoxDecoration;
      expect((decoration.color, decoration.borderRadius), (AppColors.primaryWash, BorderRadius.circular(14)));
    });

    testWidgets('버튼은 꺼져 있다(#E5E5E5) — 사진을 고르기 전엔 누를 수 없다', (tester) async {
      await pump(tester);

      expect(tester.widget<AppButton>(cta).onPressed, isNull);
      expect(tester.getSize(cta).height, 52);
    });
  });

  group('사진 고르기 — 15b-5 `J4qtZj` (고른 뒤)', () {
    testWidgets('칸을 누르면 갤러리에서 한 장 — 사진 · 빨간 테두리 3px · 왼쪽 위 "아바타로 선택" 배지, 버튼이 켜진다(#FF385C)', (tester) async {
      await pump(tester);

      await choosePhoto(tester);

      final tile = tester.widget<AvatarSourceTile>(find.byType(AvatarSourceTile));
      expect(tile.isSelected, isTrue);
      expect(find.text('아바타로 선택'), findsOneWidget);
      expect(find.byType(AddPhotoTile), findsNothing);
      expect(tester.getSize(find.byType(AvatarSourceTile)), const Size(158, 158));
      expect(tester.widget<AppButton>(cta).onPressed, isNotNull);
      // 압축 · 얼굴 검사를 거친 파일이다.
      expect(faces.hasFaceCalls, hasLength(1));
    });

    testWidgets('고른 뒤 칸을 다시 누르면 다른 사진으로 바꾼다', (tester) async {
      final second = File('${tempDir.path}/second.png')..writeAsBytesSync(base64Decode(_onePixelPng));
      var calls = 0;
      await pump(tester, pick: () async => calls++ == 0 ? picked : second);
      await choosePhoto(tester);

      await tester.runAsync(() async {
        await tester.tap(find.byType(AvatarSourceTile));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.descendant(of: find.byType(AvatarSourceTile), matching: find.byType(Image))).image as FileImage;
      expect(image.file.path, second.path);
    });

    testWidgets('얼굴이 안 보이는 사진은 칸에 넣지 않고 같은 문구로 알린다(04-2 와 같다)', (tester) async {
      await pump(tester);
      faces.nextResult = false;

      await choosePhoto(tester);

      expect(find.text('얼굴이 보이는 사진을 골라 주세요'), findsOneWidget);
      expect(find.byType(AddPhotoTile), findsOneWidget);
      expect(tester.widget<AppButton>(cta).onPressed, isNull);
    });

    testWidgets('고르지 않고 닫거나 갤러리가 열리지 않아도(권한 거부 등) 아무 일도 없다', (tester) async {
      await pump(tester, pick: () async => null);
      await choosePhoto(tester);
      expect(find.byType(AddPhotoTile), findsOneWidget);
      expect(find.byType(AvatarSourceTile), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('갤러리가 예외를 던져도(권한 거부) 화면은 그대로다', (tester) async {
      await pump(tester, pick: () async => throw Exception('denied'));
      await choosePhoto(tester);
      expect(find.byType(AddPhotoTile), findsOneWidget);
      expect(find.textContaining('denied'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('얼굴 검사가 예외를 던지면 통과시킨다 — 서버 SafeSearch 가 다시 본다', (tester) async {
      await pump(tester);
      faces.nextError = Exception('ml kit');

      await choosePhoto(tester);

      expect(find.byType(AvatarSourceTile), findsOneWidget);
    });

    testWidgets('살펴보는 동안은 도는 칸이고 버튼은 꺼져 있다', (tester) async {
      await pump(tester);
      faces.gate = Completer<bool>();

      await tester.runAsync(() async {
        await tester.tap(find.byType(AddPhotoTile));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.byType(CheckingTile), findsOneWidget);
      expect(tester.widget<AppButton>(cta).onPressed, isNull);
      faces.gate!.complete(true);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarSourceTile), findsOneWidget);
    });
  });

  group('하트 확인 → 사진 교체 → 아바타 등록', () {
    Future<void> press(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }

    testWidgets('버튼 → 15b 시트(서버 비용 · 잔액) — 시트 뒤에야 서버를 부른다', (tester) async {
      await pump(tester);
      await choosePhoto(tester);

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text('아바타를 다시 만들까요?'), findsOneWidget);
      expect(find.textContaining('하트 10개가 차감돼요. 지금 보유한 하트는 320개예요.'), findsOneWidget);
      expect(me.photoSaves, isEmpty);
      expect(avatars.regenerateCount, 0);
    });

    testWidgets('"10 쓰고 만들기" → 원본 칸만 새 파일로 바꾸고(나머지는 그대로, 장수 그대로) 그다음 아바타 등록 1회, 15 로 돌아간다', (tester) async {
      await pump(tester);
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      await press(tester, '10 쓰고 만들기');

      expect(me.photoSaves, hasLength(1));
      final (slots, avatarSource) = me.photoSaves.single;
      expect(slots, [const KeptPhoto('p-0'), isA<NewPhoto>(), const KeptPhoto('p-2')]);
      expect(avatarSource, 1);
      expect(avatars.regenerateCount, 1);
      expect(find.text('화면 15'), findsOneWidget);
    });

    testWidgets('사진 교체가 아바타 등록보다 먼저다', (tester) async {
      await pump(tester);
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      await press(tester, '10 쓰고 만들기');

      // 등록이 불린 순간 사진 교체는 이미 한 번 끝나 있었다.
      expect(avatars.photoSavesWhenRegistered, [1]);
    });

    testWidgets('첫 1회 무료면 "무료로 만들기" 시트다', (tester) async {
      await pump(tester, profile: _profile(avatarRegenCost: 0));
      await choosePhoto(tester);

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text('무료로 만들기'), findsOneWidget);
      await press(tester, '무료로 만들기');
      expect(me.photoSaves, hasLength(1));
      expect(avatars.regenerateCount, 1);
    });

    testWidgets('"취소" 는 사진도 아바타도 바꾸지 않고 15b-5 에 그대로 있다', (tester) async {
      await pump(tester);
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      await press(tester, '취소');

      expect(me.photoSaves, isEmpty);
      expect(avatars.regenerateCount, 0);
      expect(find.byType(AvatarSourceTile), findsOneWidget);
      expect(find.text('화면 15'), findsNothing);
    });

    testWidgets('하트가 모자라면 시트에서 막힌다 — 사진 교체도 부르지 않고, "하트 충전하기" 는 스토어(18)로 간다', (tester) async {
      await pump(tester, profile: _profile(heartBalance: 3));
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text('하트가 모자라요'), findsOneWidget);
      await press(tester, '하트 충전하기');

      expect(find.text('18 스토어 화면'), findsOneWidget);
      expect(me.photoSaves, isEmpty);
      expect(avatars.regenerateCount, 0);
    });

    testWidgets('하트가 모자란 채로 시트를 취소해도 아무것도 바뀌지 않는다', (tester) async {
      await pump(tester, profile: _profile(heartBalance: 3));
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      await press(tester, '취소');

      expect(me.photoSaves, isEmpty);
      expect(avatars.regenerateCount, 0);
    });

    testWidgets('사진 교체가 실패하면(검사 · 업로드 실패) 문구를 보이고 아바타 등록은 부르지 않는다 — 문구는 15-7 저장과 같은 서버 문구', (tester) async {
      await pump(tester);
      me.savePhotosResult = const FailureResult(ServerRejectedFailure('사진을 다시 확인해 주세요'));
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      await press(tester, '10 쓰고 만들기');

      expect(find.text('사진을 다시 확인해 주세요'), findsOneWidget);
      expect(avatars.regenerateCount, 0);
      expect(find.text('화면 15'), findsNothing);
      expect(tester.widget<AppButton>(cta).onPressed, isNotNull); // 다시 누를 수 있다
    });

    testWidgets('교체는 됐는데 등록이 막히면 문구를 보이고, 다시 누르면 사진은 다시 올리지 않고 등록만 한다', (tester) async {
      await pump(tester);
      avatars.nextResult = const FailureResult(ServerRejectedFailure('잠시 뒤 다시 시도해 주세요'));
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();
      await press(tester, '10 쓰고 만들기');

      expect(me.photoSaves, hasLength(1));
      expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);
      expect(find.text('화면 15'), findsNothing);

      avatars.nextResult = const Success(AvatarPending());
      await tester.tap(cta);
      await tester.pumpAndSettle();
      await press(tester, '10 쓰고 만들기');

      expect(me.photoSaves, hasLength(1)); // 사진은 다시 안 올렸다
      expect(avatars.regenerateCount, 2);
      expect(find.text('화면 15'), findsOneWidget);
    });

    testWidgets('다른 사진으로 바꾸면 다시 교체한다 — 교체된 뒤라도', (tester) async {
      final second = File('${tempDir.path}/second.png')..writeAsBytesSync(base64Decode(_onePixelPng));
      var calls = 0;
      await pump(tester, pick: () async => calls++ == 0 ? picked : second);
      avatars.nextResult = const FailureResult(ServerRejectedFailure('잠시 뒤 다시 시도해 주세요'));
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();
      await press(tester, '10 쓰고 만들기');
      expect(me.photoSaves, hasLength(1));

      await tester.runAsync(() async {
        await tester.tap(find.byType(AvatarSourceTile));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();
      await press(tester, '10 쓰고 만들기');

      expect(me.photoSaves, hasLength(2));
    });

    testWidgets('올리는 동안은 버튼에 도는 표시이고 한 번 더 눌러도 요청이 겹치지 않는다', (tester) async {
      await pump(tester);
      me.holdSavePhotos = Completer<void>();
      await choosePhoto(tester);
      await tester.tap(cta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 쓰고 만들기'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.widget<AppButton>(cta).isLoading, isTrue);
      expect(tester.widget<AppButton>(cta).onPressed, isNull);
      expect(me.photoSaves, hasLength(1));

      me.holdSavePhotos!.complete();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(me.photoSaves, hasLength(1));
      expect(avatars.regenerateCount, 1);
    });
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서도 넘치지 않고 버튼은 바닥에 남는다(스크롤)', (tester) async {
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getBottomLeft(cta).dy, 780 - 28);
    });
  }
}
