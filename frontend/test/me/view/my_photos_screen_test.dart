import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/my_photos_screen.dart';
import 'package:campus_mate/me/viewmodel/my_photos_view_model.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../auth/model/fake_face_detector.dart';
import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_me_repository.dart';

/// 사진 요청을 받기만 하고 답하지 않는 HttpClient — 서버 사진(NetworkImage)은 "아직 오는 중" 으로 남는다(15-5 테스트와 같다).
class _PendingHttpClient extends Mock implements HttpClient {}

class _PendingHttpOverrides extends HttpOverrides {
  _PendingHttpOverrides(this._client);

  final HttpClient _client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _client;
}

/// 1×1 투명 PNG. 새로 고른 사진은 `FileImage` 라 실제로 읽을 수 있는 파일이어야 그려진다.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const _guide = '사진을 길게 눌러 끌면 순서를 바꿀 수 있어요. 첫 칸이 대표 사진이에요.';

/// 서버 사진 행 — 첫 장이 아바타 원본. 이름·학교는 지어낸 값이다.
MyProfile _profile({List<String> ids = const ['p-a', 'p-b', 'p-c']}) => MyProfile(
      nickname: '여우',
      age: 23,
      university: '가나대학교',
      major: null,
      heightCm: null,
      mbti: null,
      avatarUrl: null,
      preferredAgeMin: null,
      preferredAgeMax: null,
      preferredHeightMin: null,
      preferredHeightMax: null,
      bio: null,
      photos: [
        for (final (index, id) in ids.indexed)
          MyPhoto(id: id, url: 'https://img.test/$id.png', isAvatarSource: index == 0),
      ],
    );

/// 칸마다 하나씩 있는 "사진 빼기"(x 아이콘 — 누름 칸 44 의 가운데).
final _removeButtons = find.byIcon(AppIcons.x);

/// 15-7 사진 수정(pen `szJ79` 360×780, 계획서 2026-09-27-me-edit.md 4절 15e 표 · A6, 2026-09-28-me-profile.md A15).
void main() {
  final previousOverrides = HttpOverrides.current;
  setUpAll(() {
    registerFallbackValue(Uri());
    final client = _PendingHttpClient();
    when(() => client.getUrl(any())).thenAnswer((_) => Completer<HttpClientRequest>().future);
    HttpOverrides.global = _PendingHttpOverrides(client);
  });
  tearDownAll(() => HttpOverrides.global = previousOverrides);

  late FakeMeRepository me;
  late FakeFaceDetector faceDetector;
  late ProviderContainer container;
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('my_photos_screen_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  File photoFile(String name) => File('${tempDir.path}/$name')..writeAsBytesSync(base64Decode(_onePixelPng));

  void usePenFrame(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> openPhotos(WidgetTester tester) async {
    await tester.tap(find.text('15-5'));
    await tester.pumpAndSettle();
  }

  /// 15-5 자리(내 프로필을 보고 있는 앞 화면) 위에 15-7 을 올린다.
  Future<void> pump(WidgetTester tester, {MyProfile? profile}) async {
    me = FakeMeRepository(Success(profile ?? _profile()));
    faceDetector = FakeFaceDetector();
    container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
        faceDetectorProvider.overrideWithValue(faceDetector),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfileManage,
      routes: [
        GoRoute(
          path: AppRoutes.myProfileManage,
          builder: (context, state) => Consumer(
            builder: (context, ref, _) {
              ref.watch(myProfileProvider);
              return Scaffold(
                body: TextButton(onPressed: () => context.push(AppRoutes.myPhotos), child: const Text('15-5')),
              );
            },
          ),
        ),
        GoRoute(path: AppRoutes.myPhotos, builder: (context, state) => const MyPhotosScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await container.read(myProfileProvider.future);
    await tester.pump();
    await openPhotos(tester);
  }

  AppButton saveButton(WidgetTester tester) => tester.widget<AppButton>(find.byType(AppButton));

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byType(AppButton));
    await tester.pump();
  }

  /// 칸에 그려진 사진을 칸 순서대로 — 서버 사진은 주소, 새 사진은 파일 이름.
  List<String> photoOrder(WidgetTester tester) => [
        for (final image in tester.widgetList<Image>(find.byType(Image)))
          switch (image.image) {
            NetworkImage(:final url) => url.split('/').last,
            FileImage(:final file) => file.uri.pathSegments.last,
            _ => '?',
          },
      ];

  /// 길게 눌러 [from] 칸의 사진을 [to] 로 끌어다 놓는다. 칸 위쪽 오른쪽은 "사진 빼기" 누름 칸이라 아래쪽을 잡는다.
  Future<void> dragPhoto(WidgetTester tester, {required int from, required Offset to}) async {
    final rect = tester.getRect(find.byType(Image).at(from));
    final gesture = await tester.startGesture(rect.center + Offset(0, rect.height / 4));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('pen 값(배율 1.0, 360×780)', () {
    testWidgets('앱바 `RaeIU` — 편집 앱바, 제목 "사진 수정"', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(tester.widget<EditAppBar>(find.byType(EditAppBar)).title, '사진 수정');
      expect(tester.getBottomLeft(find.byType(AppBar)).dy, 56);
    });

    testWidgets('사진 줄 `lfmT0` — 대표 칸 160×200 (24, 위 32), gap 12, 보조 66×88 2행×2 gap 8 · 칸은 3개(D10)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final photos = find.byType(DraggablePhotoTile);
      expect(photos, findsNWidgets(3));
      expect(tester.getRect(photos.at(0)), const Rect.fromLTWH(24, 56 + 32, 160, 200));
      expect(tester.getRect(photos.at(1)), const Rect.fromLTWH(196, 88, 66, 88));
      expect(tester.getRect(photos.at(2)), const Rect.fromLTWH(270, 88, 66, 88));
      // 넷째 칸(보조 2행 왼쪽)은 빈 "사진 추가" 칸이다.
      expect(tester.getRect(find.byType(AddPhotoTile)), const Rect.fromLTWH(196, 184, 66, 88));
      // pen `lfmT0` alignItems start(대장 확인 09-29) — 보조 그리드(184) 위 = 대표 칸(200) 위, 아래 16 이 빈다.
      expect(tester.getTopLeft(photos.at(1)).dy, tester.getTopLeft(photos.at(0)).dy);
    });

    testWidgets('보조 2행 오른쪽(`myCJf` 자리)은 비워 둔다 — 사진은 최대 4장(D10)', (tester) async {
      usePenFrame(tester);
      await pump(tester, profile: _profile(ids: ['p-a', 'p-b']));

      // 사진 2 + 빈 칸 2 = 4칸. 다섯째 자리(270,184 ~ 336,272)에는 아무 칸도 없다.
      expect(find.byType(AddPhotoTile), findsNWidgets(2));
      final emptySpot = const Rect.fromLTWH(270, 184, 66, 88).center;
      for (final tile in [find.byType(DraggablePhotoTile), find.byType(AddPhotoTile)]) {
        for (final element in tile.evaluate()) {
          final box = element.renderObject! as RenderBox;
          expect((box.localToGlobal(Offset.zero) & box.size).contains(emptySpot), isFalse);
        }
      }
    });

    testWidgets('칸 모양은 04-2 그대로(C9) — 모서리 14, 대표 배지 첫 칸 (8,8), 지우기 28 원이 칸 오른쪽 위 8(대표 124,8 · 보조 30,8)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final clip = tester.widget<ClipRRect>(
        find.descendant(of: find.byType(DraggablePhotoTile).first, matching: find.byType(ClipRRect)),
      );
      expect(clip.borderRadius, BorderRadius.circular(14));
      expect(find.text('대표'), findsOneWidget);
      expect(tester.getTopLeft(find.ancestor(of: find.text('대표'), matching: find.byType(Container)).first), const Offset(32, 96));
      final circles = find.ancestor(
        of: find.byIcon(AppIcons.x),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(circles, findsNWidgets(3));
      expect(tester.getRect(circles.at(0)), const Rect.fromLTWH(24 + 124, 88 + 8, 28, 28));
      expect(tester.getRect(circles.at(1)), const Rect.fromLTWH(196 + 30, 88 + 8, 28, 28));
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.x).first);
      expect((icon.size, icon.color), (14, AppColors.onInk));
    });

    testWidgets('지우기 누름 칸은 44 — 보조 칸에도(대장 결정, 04-2 그대로)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(_removeButtons, findsNWidgets(3));
      final hitArea = find.ancestor(of: _removeButtons.at(2), matching: find.byType(GestureDetector)).first;
      expect(tester.getSize(hitArea), const Size(44, 44));
      expect(tester.getTopRight(hitArea), tester.getTopRight(find.byType(DraggablePhotoTile).at(2)));
    });

    testWidgets('서버 사진이 칸에 자리 순서대로 보인다(NetworkImage)', (tester) async {
      await pump(tester);

      expect(
        [for (final image in tester.widgetList<Image>(find.byType(Image))) image.image],
        const [
          NetworkImage('https://img.test/p-a.png'),
          NetworkImage('https://img.test/p-b.png'),
          NetworkImage('https://img.test/p-c.png'),
        ],
      );
    });

    testWidgets('빈 칸 `jieCD` — primary-wash 모서리 14, plus 24 · 8 · "사진 추가" 14/600 primary-text', (tester) async {
      await pump(tester);

      final ink = tester.widget<Ink>(find.descendant(of: find.byType(AddPhotoTile), matching: find.byType(Ink)));
      final decoration = ink.decoration! as BoxDecoration;
      expect((decoration.color, decoration.borderRadius), (AppColors.primaryWash, BorderRadius.circular(14)));
      final plus = tester.widget<Icon>(find.byIcon(AppIcons.plus));
      expect((plus.size, plus.color), (24, AppColors.primaryText));
      final style = tester.widget<Text>(find.text('사진 추가')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.primaryText));
    });

    testWidgets('빈 칸의 눌림 효과 · 바탕은 칸 크기 Material 이 그린다(COMMON §4-2)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final tile = find.ancestor(of: find.text('사진 추가'), matching: find.byType(InkWell)).first;
      final painter = find.ancestor(of: find.text('사진 추가'), matching: find.byType(Material)).first;
      expect(tester.getSize(tile), const Size(66, 88));
      expect(tester.getSize(painter), tester.getSize(tile));
    });

    testWidgets('안내문 `z5rhVO` — 사진 줄 16 아래 · 폭 312, 14/400 muted 줄 20, 줄을 바꾸고 잘리지 않는다(C2)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final rect = tester.getRect(find.text(_guide));
      expect(rect.topLeft, const Offset(24, 88 + 200 + 16));
      expect(rect.width, 312);
      final style = tester.widget<Text>(find.text(_guide)).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w400, AppColors.muted));
      expect(style.fontSize! * style.height!, closeTo(20, 0.01));
      final lines = rect.height / 20;
      expect(lines, greaterThanOrEqualTo(2));
      expect(lines, closeTo(lines.roundToDouble(), 0.01));
      expect(_clippedTexts(), isNot(contains(_guide)));
    });

    testWidgets('"저장" `m2cAn` — 312×52 · 좌우 24 · 화면 아래 8(Bottom Bar CTA `A8INC6` [8,24,8,24])', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(saveButton(tester).label, '저장');
      expect(tester.getRect(find.byType(AppButton)), const Rect.fromLTWH(24, 780 - 8 - 52, 312, 52));
      // pen `m2cAn` 은 Spacer `BCwfQ` 뒤라 바닥 고정(대장 확인 09-29, 15c `zUZFx` 와 같은 구조) · 아래 8(`A8INC6` 2026-10-01 개편, 옛 28).
      expect(780 - tester.getBottomLeft(find.byType(AppButton)).dy, 8);
    });
  });

  testWidgets('사진이 2장 미만이면 "저장" 이 꺼진다', (tester) async {
    await pump(tester, profile: _profile(ids: ['p-a', 'p-b']));
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.tap(_removeButtons.first);
    await tester.pump();

    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('올려 둔 사진도 길게 눌러 끌면 자리를 바꾼다 — 보조 칸 사진을 대표 칸으로', (tester) async {
    usePenFrame(tester);
    await pump(tester);
    expect(photoOrder(tester), ['p-a.png', 'p-b.png', 'p-c.png']);

    await dragPhoto(tester, from: 2, to: tester.getCenter(find.byType(Image).first));

    expect(photoOrder(tester), ['p-c.png', 'p-b.png', 'p-a.png']);
  });

  testWidgets('저장하면 칸 순서대로 보내고 앞 화면(15-5)으로 돌아가 내 프로필을 다시 읽게 한다', (tester) async {
    await pump(tester);
    await tester.tap(_removeButtons.at(1));
    await tester.pump();

    await tapSave(tester);
    await tester.pumpAndSettle();

    final (slots, avatarSource) = me.photoSaves.single;
    expect(slots, const [KeptPhoto('p-a'), KeptPhoto('p-c')]);
    expect(avatarSource, 0);
    expect(find.text('15-5'), findsOneWidget);
    expect(find.byType(MyPhotosScreen), findsNothing);
    expect(me.calls, 2);
  });

  testWidgets('저장이 실패하면 버튼 위 오류 글(caption · error)을 보이고 칸은 그대로 그 자리에 남는다', (tester) async {
    await pump(tester);
    me.savePhotosResult = const FailureResult(ServerRejectedFailure('사진이 바뀌었어요, 다시 열어 주세요'));

    await tapSave(tester);
    await tester.pumpAndSettle();

    final error = find.text('사진이 바뀌었어요, 다시 열어 주세요');
    expect(error, findsOneWidget);
    final style = tester.widget<Text>(error).style!;
    expect((style.fontSize, style.color), (12, AppColors.error));
    expect(tester.getBottomLeft(error).dy, lessThan(tester.getTopLeft(find.byType(AppButton)).dy));
    expect(find.byType(AppToast), findsNothing, reason: '저장 실패는 토스트가 아니라 버튼 위 글이다');
    expect(find.byType(MyPhotosScreen), findsOneWidget);
    expect(find.byType(DraggablePhotoTile), findsNWidgets(3));
  });

  testWidgets('저장 중에는 버튼이 흰 스피너로 바뀐다(D8)', (tester) async {
    await pump(tester);
    me.holdSavePhotos = Completer<void>();

    await tapSave(tester);

    expect(saveButton(tester).isLoading, isTrue);
    expect(find.descendant(of: find.byType(AppButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    me.holdSavePhotos!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('저장 중에는 칸을 누를 수 없다 — 고르기 · 빼기가 보내는 중인 칸을 흔들지 않는다(검토 사소 2)', (tester) async {
    await pump(tester);
    var picked = 0;
    container.read(myPhotosViewModelProvider.notifier).pickFromGallery = (limit) async {
      picked++;
      return [photoFile('new.png')];
    };
    me.holdSavePhotos = Completer<void>();

    await tapSave(tester);
    await tester.tap(find.byType(AddPhotoTile), warnIfMissed: false);
    await tester.pump();

    expect(picked, 0);
    expect(find.byType(DraggablePhotoTile), findsNWidgets(3));
    me.holdSavePhotos!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('얼굴이 없어 빠지면 04-2 와 같은 토스트가 버튼 위 12 에 뜨고 약 2초 뒤 사라진다', (tester) async {
    usePenFrame(tester);
    await pump(tester);
    container.read(myPhotosViewModelProvider.notifier).pickFromGallery = (limit) async => [photoFile('new.png')];
    faceDetector.nextResult = false;

    await tester.tap(find.text('사진 추가'));
    await tester.pump();
    await tester.pump();

    expect(find.text('얼굴이 보이는 사진을 골라 주세요'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppToast), matching: find.byIcon(AppIcons.alertTriangle)), findsOneWidget);
    expect(tester.getTopLeft(find.byType(AppButton)).dy - tester.getBottomLeft(find.byType(AppToast)).dy, 12);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AppToast), findsNothing);
  });

  testWidgets('고른 사진을 살펴보는 동안 들어올 칸(넷째)에 기다리는 표시가 뜨고 "저장" 이 꺼진다', (tester) async {
    usePenFrame(tester);
    await pump(tester);
    container.read(myPhotosViewModelProvider.notifier).pickFromGallery = (limit) async => [photoFile('new.png')];
    final gate = Completer<bool>();
    faceDetector.gate = gate;

    await tester.tap(find.text('사진 추가'));
    await tester.pump();
    await tester.pump();

    expect(tester.getRect(find.byType(CheckingTile)), const Rect.fromLTWH(196, 184, 66, 88));
    expect(saveButton(tester).onPressed, isNull);
    gate.complete(true);
    faceDetector.gate = null;
    await tester.pumpAndSettle();
    expect(photoOrder(tester), ['p-a.png', 'p-b.png', 'p-c.png', 'new.png']);
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('my_photos_is_filled_from_the_server_each_time_it_opens — 저장 없이 나갔다 다시 열면 서버 값(Review Focus 5)', (tester) async {
    await pump(tester);
    await tester.tap(_removeButtons.first);
    await tester.pump();
    expect(find.byType(DraggablePhotoTile), findsNWidgets(2));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await openPhotos(tester);

    expect(photoOrder(tester), ['p-a.png', 'p-b.png', 'p-c.png']);
    expect(me.photoSaves, isEmpty);
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 넘치거나 잘리지 않는다. 15c · 15-5 테스트와 같은 잣대.
  // 사진 2장이라 66×88 보조 칸에 "사진 추가" 가 둘 뜬다(옛 계획서 A6 배율 주의).
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('15-7 — 폭 360 · 글자 배율 $scale 에서 넘침 · 잘림이 없다(스크롤 전 · 끝)', (tester) async {
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester, profile: _profile(ids: ['p-a', 'p-b']));
      expect(tester.takeException(), isNull);
      final clipped = _clippedTexts();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      clipped.addAll(_clippedTexts());

      expect(tester.takeException(), isNull);
      expect(clipped, isEmpty);
    });
  }
}

/// 고정 상자에 갇혀 오류 없이 잘린 글자. 폭은 배치 때 받은 최대 폭으로 잰다(화면 15 테스트와 같은 방식).
List<String> _clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5 ||
                p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
          p.text.toPlainText(),
    ];
