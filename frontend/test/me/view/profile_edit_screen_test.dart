import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/profile_edit_screen.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_me_repository.dart';

const _bio = '주말엔 산책해요.';

const _profile = MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: null,
  heightCm: null,
  mbti: null,
  avatarUrl: null,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: null,
  preferredHeightMax: null,
  bio: _bio,
  // 관심사는 한 줄(312)에 다 들어가지 않게 넷 — 칩 줄 간격을 본다.
  interestTags: ['카페가기', '여행가기', '요리하기', '맛집탐방'],
  myTraits: ['유머러스', '성실한', '차분한'],
  idealTraits: ['솔직한', '연락 잘하는', '다정한'],
);

/// 15c 자기소개 · 태그 수정(pen `zWMxM` 360×780, 계획서 4절 15c 표 · A4).
void main() {
  late FakeMeRepository me;
  late ProviderContainer container;

  void usePenFrame(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 화면 15 자리(내 프로필을 보고 있는 앞 화면) 위에 15c 를 올린다.
  Future<void> pump(WidgetTester tester) async {
    me = FakeMeRepository(const Success(_profile));
    container = ProviderContainer(overrides: [meRepositoryProvider.overrideWithValue(me)]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(
          path: AppRoutes.myProfile,
          builder: (context, state) => Consumer(
            builder: (context, ref, _) {
              ref.watch(myProfileProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () => context.push(AppRoutes.myProfileEdit),
                  child: const Text('화면 15'),
                ),
              );
            },
          ),
        ),
        GoRoute(path: AppRoutes.myProfileEdit, builder: (context, state) => const ProfileEditScreen()),
        GoRoute(
          path: '${AppRoutes.myTags}/:kind',
          builder: (context, state) => Scaffold(body: Text('태그 편집 ${state.pathParameters['kind']}')),
        ),
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
    await openEditor(tester);
  }

  AppButton saveButton(WidgetTester tester) => tester.widget<AppButton>(find.byType(AppButton));

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byType(AppButton));
    await tester.pump();
  }

  Finder editLink(int index) => find.ancestor(of: find.text('수정').at(index), matching: find.byType(InkWell));

  group('pen 값(배율 1.0)', () {
    testWidgets('앱바 `iq3jl` — 편집 앱바, 제목 "자기소개·태그 수정"', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(tester.widget<EditAppBar>(find.byType(EditAppBar)).title, '자기소개·태그 수정');
      expect(tester.getBottomLeft(find.byType(AppBar)).dy, 56);
    });

    testWidgets('본문 `jk11O` 좌우 24 · 위 32, 자기소개 입력 `YFZxt` — 라벨 20 · 8 · 상자 312×120', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final label = tester.getRect(find.text('자기소개'));
      expect(label.topLeft, const Offset(24, 56 + 32));
      expect(label.height, 20);
      expect(tester.getRect(find.byType(TextField)), const Rect.fromLTWH(24, 116, 312, 120));
    });

    testWidgets('자기소개 입력 모양 — 라벨 14/600 body, 채움 #F7F7F7 · 테두리 #767676 1 · 모서리 8 · 안쪽 [14,16], 값 16/400 #222222(C1)', (tester) async {
      await pump(tester);

      final label = tester.widget<Text>(find.text('자기소개')).style!;
      expect((label.fontSize, label.fontWeight, label.color), (14, FontWeight.w600, AppColors.body));
      final field = tester.widget<TextField>(find.byType(TextField));
      final decoration = field.decoration!;
      expect((decoration.filled, decoration.fillColor), (true, AppColors.surfaceSoft));
      expect(decoration.contentPadding, const EdgeInsets.symmetric(horizontal: 16, vertical: 14));
      final border = decoration.enabledBorder! as OutlineInputBorder;
      expect((border.borderSide.color, border.borderSide.width), (AppColors.outline, 1));
      expect(border.borderRadius, BorderRadius.circular(8));
      expect((field.style!.fontSize, field.style!.fontWeight, field.style!.color), (16, FontWeight.w400, AppColors.ink));
      // 글은 상자 위에서부터 쓴다(위 정렬).
      expect(field.textAlignVertical, TextAlignVertical.top);
    });

    testWidgets('입력 뒤 32, 태그 섹션 셋(gap 24) — 헤더 20 · 8 · 칩, 칩 사이 · 줄 사이 8', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final interests = tester.getRect(find.text('관심사 태그'));
      expect(interests.topLeft, const Offset(24, 116 + 120 + 32));
      expect(interests.height, 20);
      final chips = find.byKey(const ValueKey('tag-chip'));
      final first = tester.getRect(chips.at(0));
      expect(first.topLeft, Offset(24, interests.bottom + 8));
      expect(tester.getRect(chips.at(1)).left - first.right, 8);
      // 넷째 칩은 다음 줄로 흐른다.
      final wrapped = tester.getRect(chips.at(3));
      expect(wrapped.left, 24);
      expect(wrapped.top - first.bottom, 8);
      expect(tester.getTopLeft(find.text('나의 특징')).dy - wrapped.bottom, 24);
      final myTraitsLast = tester.getRect(chips.at(6));
      expect(tester.getTopLeft(find.text('이상형 특징')).dy - myTraitsLast.bottom, 24);
    });

    testWidgets('섹션 헤더 `n9p0qZ` — 라벨 14/600 body, 오른쪽 끝 "수정" 14/600 primary-text + chevron-right 16(gap 2)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      for (final label in ['관심사 태그', '나의 특징', '이상형 특징']) {
        final style = tester.widget<Text>(find.text(label)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.body), reason: label);
      }
      final edit = tester.widget<Text>(find.text('수정').first).style!;
      expect((edit.fontSize, edit.fontWeight, edit.color), (14, FontWeight.w600, AppColors.primaryText));
      final chevron = find.byIcon(AppIcons.chevronRight).first;
      final icon = tester.widget<Icon>(chevron);
      expect((icon.size, icon.color), (16, AppColors.primaryText));
      expect(tester.getTopLeft(chevron).dx - tester.getTopRight(find.text('수정').first).dx, 2);
      // space_between — 라벨과 같은 줄, 본문 오른쪽 끝(336)에 붙는다.
      expect(tester.getTopRight(chevron).dx, 336);
      expect(tester.getTopLeft(find.text('수정').first).dy, tester.getTopLeft(find.text('관심사 태그')).dy);
    });

    testWidgets('칩 `WzXvK`(선택 꺼짐) — #F7F7F7 · 모서리 8 · 안쪽 [8,12], 14/600 ink, 높이 36, 누르지 않는다', (tester) async {
      await pump(tester);

      final chip = find.byKey(const ValueKey('tag-chip')).first;
      expect(tester.getSize(chip).height, 36);
      final decoration = tester.widget<DecoratedBox>(chip).decoration as BoxDecoration;
      expect((decoration.color, decoration.borderRadius), (AppColors.surfaceSoft, BorderRadius.circular(8)));
      final text = find.descendant(of: chip, matching: find.byType(Text));
      expect(tester.getTopLeft(text) - tester.getTopLeft(chip), const Offset(12, 8));
      final style = tester.widget<Text>(text).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.ink));
      expect(find.ancestor(of: chip, matching: find.byType(InkWell)), findsNothing);
    });

    testWidgets('저장 `zUZFx` — 312×56 primary "저장", 화면 아래 28', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final button = tester.getRect(find.byType(AppButton));
      expect(button, const Rect.fromLTWH(24, 780 - 28 - 56, 312, 56));
      expect(saveButton(tester).label, '저장');
      expect(saveButton(tester).variant, AppButtonVariant.primary);
    });
  });

  testWidgets('칩은 서버가 준 내 태그다 — 섹션마다 그 종류만', (tester) async {
    await pump(tester);

    for (final tag in [..._profile.interestTags, ..._profile.myTraits, ..._profile.idealTraits]) {
      expect(find.text(tag), findsOneWidget, reason: tag);
    }
    expect(find.byKey(const ValueKey('tag-chip')), findsNWidgets(10));
  });

  testWidgets('"수정 ›" 누름 영역은 48 이상이고(C3), 눌림 효과는 그 칸 크기 Material 이 그린다(COMMON §4-2)', (tester) async {
    await pump(tester);

    for (var i = 0; i < 3; i++) {
      final link = editLink(i);
      final size = tester.getSize(link);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      final painter = find.ancestor(of: link, matching: find.byType(Material)).first;
      expect(tester.getSize(painter), size);
      // 48 칸은 "수정" 글자를 세로 가운데에 둔다 — 헤더 20 위아래로 14 씩 넓힌 것.
      expect(tester.getCenter(link).dy, closeTo(tester.getCenter(find.text('수정').at(i)).dy, 0.01));
    }
  });

  for (final (index, endpoint) in [(0, 'interests'), (1, 'my-traits'), (2, 'ideal-traits')]) {
    testWidgets('$index번째 "수정 ›" 을 누르면 태그 편집 `/me/edit/tags/$endpoint` 로 간다(T5)', (tester) async {
      await pump(tester);

      await tester.tap(find.text('수정').at(index));
      await tester.pumpAndSettle();

      expect(find.text('태그 편집 $endpoint'), findsOneWidget);
    });
  }

  testWidgets('태그 편집에서 돌아와 화면 15 값이 새로 읽히면 칩이 바뀌고, 쓰던 자기소개는 남는다', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '쓰던 글');

    me.profile = const Success(
      MyProfile(
        nickname: '여우',
        age: 23,
        university: '가나대학교',
        major: null,
        heightCm: null,
        mbti: null,
        avatarUrl: null,
        preferredAgeMin: 22,
        preferredAgeMax: 27,
        preferredHeightMin: null,
        preferredHeightMax: null,
        bio: _bio,
        interestTags: ['독서', '영화', '산책'],
        myTraits: ['유머러스', '성실한', '차분한'],
        idealTraits: ['솔직한', '연락 잘하는', '다정한'],
      ),
    );
    container.invalidate(myProfileProvider);
    await tester.pumpAndSettle();

    expect(find.text('독서'), findsOneWidget);
    expect(find.text('카페가기'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '쓰던 글');
  });

  testWidgets('저장하면 PATCH {"bio"} 만 보내고 화면 15 로 돌아가 다시 읽게 한다', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '  새 소개예요.  ');
    await tester.pump();

    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(me.updates, [
      {'bio': '새 소개예요.'},
    ]);
    expect(find.text('화면 15'), findsOneWidget);
    expect(find.byType(ProfileEditScreen), findsNothing);
    expect(me.calls, 2);
  });

  testWidgets('저장이 실패하면 버튼 위 오류 글(caption · error)을 보이고 그 자리에 남는다', (tester) async {
    await pump(tester);
    me.updateResult = const FailureResult(NetworkFailure());

    await tapSave(tester);
    await tester.pumpAndSettle();

    final error = find.text(const NetworkFailure().toDisplayMessage());
    expect(error, findsOneWidget);
    final style = tester.widget<Text>(error).style!;
    expect((style.fontSize, style.color), (12, AppColors.error));
    expect(tester.getBottomLeft(error).dy, lessThan(tester.getTopLeft(find.byType(AppButton)).dy));
    expect(find.byType(ProfileEditScreen), findsOneWidget);
  });

  for (final blank in ['', '   ']) {
    testWidgets('자기소개가 비면("$blank") "저장" 이 꺼진다', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), blank);
      await tester.pump();

      expect(saveButton(tester).onPressed, isNull);
    });
  }

  testWidgets('저장 중에는 버튼이 흰 스피너로 바뀐다(D8)', (tester) async {
    await pump(tester);
    me.holdUpdate = Completer<void>();

    await tapSave(tester);

    expect(saveButton(tester).isLoading, isTrue);
    expect(find.descendant(of: find.byType(AppButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    me.holdUpdate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('profile_edit_is_filled_from_the_server_each_time_it_opens — 저장 없이 나갔다 다시 열면 서버 값(Review Focus 5)', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '고치다 만 글');

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await openEditor(tester);

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, _bio);
    expect(me.updates, isEmpty);
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 넘치거나 잘리지 않는다. 화면 15 테스트와 같은 잣대.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('15c — 폭 360 · 글자 배율 $scale 에서 넘침 · 잘림이 없다(스크롤 전 · 끝)', (tester) async {
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester);
      expect(tester.takeException(), isNull);
      final clipped = _clippedTexts();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      clipped.addAll(_clippedTexts());

      expect(tester.takeException(), isNull);
      expect(clipped, isEmpty);
      // 큰 글씨에서도 "수정" 누름 칸은 글자를 품는다.
      final link = tester.getRect(find.ancestor(of: find.text('수정').last, matching: find.byType(InkWell)));
      expect(link.contains(tester.getCenter(find.text('수정').last)), isTrue);
    });
  }
}

Future<void> openEditor(WidgetTester tester) async {
  await tester.tap(find.text('화면 15'));
  await tester.pumpAndSettle();
}

/// 고정 상자에 갇혀 오류 없이 잘린 글자. 폭은 배치 때 받은 최대 폭으로 잰다(화면 15 테스트와 같은 방식).
List<String> _clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5 ||
                p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
          p.text.toPlainText(),
    ];
