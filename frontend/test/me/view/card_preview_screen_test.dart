import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/view/card_preview_screen.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_me_repository.dart';

const _notice = '대화 상대가 보는 내 프로필이에요. 실제 사진과 카카오톡 아이디는 둘 다 수락한 뒤에 공개돼요.';

/// 서버 `GET /me/card-preview` 가 준 내 카드(이름·학교는 지어낸 값).
CardDetail _detail({String? avatarUrl = 'https://img.test/avatar.png'}) => CardDetail(
      cardId: 'me-1',
      profile: CardProfile(
        profileId: 'me-1',
        nickname: '하늘',
        age: 24,
        university: '가나대학교',
        major: '경영학과',
        avatarUrl: avatarUrl,
      ),
      survey: List.filled(9, 0.5),
      animalType: AnimalType.fox,
      impressionType: ImpressionType.kind,
      religion: Religion.none,
      isSmoker: false,
      interests: const ['등산', '재즈'],
      myTraits: const ['유머러스'],
      idealTraits: const ['다정한'],
      heightCm: 178,
      mbti: 'ENFP',
      studentNumber: '22',
      bio: '주말엔 산책해요.',
      idealNote: '대화가 잘 통하는 사람이 좋아요.',
    );

final _list = find.byType(Scrollable).first;

/// 15-4 남이 보는 내 프로필(pen `gnEwq` 360×1714, 계획서 4절 15-4 표 · A13).
void main() {
  /// 화면 15 자리 위에 15-4 를 올린다. [settle] 이 false 면 첫 프레임(불러오는 중)에서 멈춘다.
  Future<FakeMeRepository> pump(
    WidgetTester tester, {
    Result<CardDetail>? result,
    bool settle = true,
  }) async {
    final repository = FakeMeRepository(const FailureResult(UnknownFailure()))
      ..cardPreview = result ?? Success(_detail());
    final container = ProviderContainer(overrides: [meRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(path: AppRoutes.myProfile, builder: (context, state) => const Scaffold(body: Text('화면 15'))),
        GoRoute(path: AppRoutes.myCardPreview, builder: (context, state) => const CardPreviewScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    unawaited(router.push(AppRoutes.myCardPreview));
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
    return repository;
  }

  void usePenFrame(WidgetTester tester, {double height = 780}) {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// ListView 는 아래 칸을 그리기 전엔 끝 길이를 어림한다 — 진짜 끝까지 되풀이한다.
  Future<void> scrollToEnd(WidgetTester tester) async {
    final position = tester.state<ScrollableState>(_list).position;
    do {
      await tester.drag(_list, const Offset(0, -3000));
      await tester.pumpAndSettle();
    } while (position.pixels < position.maxScrollExtent);
  }

  final noticeBox = find.ancestor(
    of: find.text(_notice),
    matching: find.byWidgetPredicate(
      (w) => w is DecoratedBox && (w.decoration as BoxDecoration?)?.color == AppColors.primaryWash,
    ),
  );

  group('앱바 `QfTUe` · 틀', () {
    testWidgets('편집 앱바(N14) 제목 "남이 보는 내 프로필", 뒤로를 누르면 화면 15 로 돌아간다', (tester) async {
      await pump(tester);

      expect(tester.widget<EditAppBar>(find.byType(EditAppBar)).title, '남이 보는 내 프로필');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('화면 15'), findsOneWidget);
      expect(find.byType(CardPreviewScreen), findsNothing);
    });

    testWidgets('하단 내비가 없다', (tester) async {
      await pump(tester);

      expect(find.byType(AppBottomNav), findsNothing);
    });
  });

  group('pen 값(배율 1.0, 본문 `iFAyO` 위 24 · 좌우 16 · 사이 32 · 아래 40)', () {
    testWidgets('안내 `Ocmk4` — #FFF0F2 모서리 12 안쪽 14, 아이콘 없음, 328 폭 · 앱바 아래 24', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(noticeBox, findsOneWidget);
      final decoration = tester.widget<DecoratedBox>(noticeBox).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(12));
      final box = tester.getRect(noticeBox);
      expect(box.topLeft, const Offset(16, 56 + 24));
      expect(box.width, 328);
      expect(tester.getTopLeft(find.text(_notice)) - box.topLeft, const Offset(14, 14));
      expect(box.bottom - tester.getBottomLeft(find.text(_notice)).dy, 14);
      expect(find.descendant(of: noticeBox, matching: find.byType(Icon)), findsNothing);
    });

    testWidgets('안내 글 14/400 body 줄높이 1.5(원문 그대로)', (tester) async {
      await pump(tester);

      final style = tester.widget<Text>(find.text(_notice)).style!;
      expect((style.fontSize, style.fontWeight, style.color, style.height), (14, FontWeight.w400, AppColors.body, 1.5));
    });

    testWidgets('카드 `kpIeX` 는 안내 아래 32, 328 폭 — 끝까지 스크롤하면 카드 끝과 화면 끝 사이 40', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final card = find.byType(ProfileCard);
      expect(tester.getTopLeft(card).dy - tester.getBottomLeft(noticeBox).dy, 32);
      expect(tester.getTopLeft(card).dx, 16);
      expect(tester.getSize(card).width, 328);

      await scrollToEnd(tester);
      expect(780 - tester.getBottomLeft(card).dy, 40);
    });
  });

  group('카드 = 10b · 14c 와 같은 ProfileCard, 슬롯 없음(N2 · N17)', () {
    testWidgets('서버가 준 내 카드를 그대로 그린다 — 닉네임 · 나이 · 학교 · 자기소개 · 태그', (tester) async {
      await pump(tester);

      final card = tester.widget<ProfileCard>(find.byType(ProfileCard));
      expect(card.detail.cardId, 'me-1');
      expect(find.text('하늘, 24'), findsOneWidget);
      expect(find.text('가나대학교 경영학과 22학번'), findsOneWidget);
      expect(find.text('주말엔 산책해요.'), findsOneWidget);
      await scrollToEnd(tester);
      expect(find.text('등산'), findsOneWidget);
      expect(find.text('대화가 잘 통하는 사람이 좋아요.'), findsOneWidget);
    });

    testWidgets('슬롯 셋 다 비었다 — 이름 줄 오른쪽 "신뢰 확인 완료"(`CTtPd`) 꺼짐', (tester) async {
      await pump(tester);

      final card = tester.widget<ProfileCard>(find.byType(ProfileCard));
      expect((card.header, card.nameTrailing, card.footer), (null, null, null));
      expect(find.text('신뢰 확인 완료'), findsNothing);
    });

    // Review Focus 1 — 미리보기에 수락 뒤 공개 값이 새면 안 된다. 앱은 슬롯을 비워 그 줄이 아예 없다.
    testWidgets('card_preview_has_no_photos_kakao_or_report_links — 사진 슬라이더 · 카카오 카드 · 신고/차단 링크가 없다', (tester) async {
      await pump(tester);

      for (final pass in ['처음', '끝까지 스크롤한 뒤']) {
        expect(find.byType(PhotoSlider), findsNothing, reason: pass);
        expect(find.text('카카오톡 아이디'), findsNothing, reason: pass);
        expect(find.text('신고하기'), findsNothing, reason: pass);
        expect(find.text('차단하기'), findsNothing, reason: pass);
        await scrollToEnd(tester);
      }
    });

    testWidgets('아바타가 없는 사람도 카드가 그대로 그려진다(Review Focus 5 — 10b 와 같은 규칙)', (tester) async {
      await pump(tester, result: Success(_detail(avatarUrl: null)));

      expect(tester.takeException(), isNull);
      expect(find.text('하늘, 24'), findsOneWidget);
    });
  });

  group('불러오는 중 · 실패(N9 — pen 에 없는 상태, 화면 15 와 같은 모양)', () {
    testWidgets('불러오는 중이면 가운데 로딩 표시, 앱바는 그대로', (tester) async {
      await pump(tester, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(EditAppBar), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('실패하면 MeLoadError(문구 + "다시 시도"), 앱바는 그대로, 안내 상자도 없다', (tester) async {
      await pump(tester, result: const FailureResult(NetworkFailure()));

      expect(find.byType(MeLoadError), findsOneWidget);
      expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);
      expect(find.byType(EditAppBar), findsOneWidget);
      expect(find.text(_notice), findsNothing);
    });

    testWidgets('"다시 시도" 를 누르면 다시 읽어 카드를 그린다', (tester) async {
      final repository = await pump(tester, result: const FailureResult(NetworkFailure()));
      expect(repository.cardPreviewCalls, 1);

      repository.cardPreview = Success(_detail());
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repository.cardPreviewCalls, 2);
      expect(find.text('하늘, 24'), findsOneWidget);
    });
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다. 화면 15 테스트와 같은 잣대.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('15-4 — 폭 360 · 글자 배율 $scale 에서 넘침 · 잘림이 없다(스크롤 전 · 끝)', (tester) async {
      // 테스트 글꼴은 한글이 Pretendard 보다 넓다 — 여기서 버티면 실제 폰에서도 버틴다.
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester);
      expect(tester.takeException(), isNull);
      final clipped = _clippedTexts();
      await scrollToEnd(tester);
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
