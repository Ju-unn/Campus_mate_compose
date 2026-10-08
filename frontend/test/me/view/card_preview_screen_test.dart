import 'dart:async';
import 'dart:ui' show Tristate;
import 'dart:typed_data';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository.dart';
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
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/me/view/me_tab_bar.dart';
import 'package:campus_mate/safety/view/revealed_profile_parts.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../account/model/fake_account_repository.dart';
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

/// 1×1 투명 PNG.
const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01, //
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const _noticeAfter = '수락하면 상대에게 이렇게 보여요';

/// 내 프로필(실사진 두 장). 이름·학교는 지어낸 값이다.
MyProfile _profile({int photos = 2}) => MyProfile(
  nickname: '하늘',
  age: 24,
  university: '가나대학교',
  major: '경영학과',
  heightCm: 178,
  mbti: 'ENFP',
  avatarUrl: 'https://img.test/avatar.png',
  photos: [
    for (var i = 0; i < photos; i++) MyPhoto(id: 'p-$i', url: 'https://img.test/$i.png', isAvatarSource: i == 0),
  ],
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: 165,
  preferredHeightMax: 180,
  bio: '주말엔 산책해요.',
);

/// 15-4 남이 보는 내 프로필(pen `gnEwq` 360×1714, 계획서 4절 15-4 표 · A13).
void main() {
  /// 화면 15 자리 위에 15-4 를 올린다. [settle] 이 false 면 첫 프레임(불러오는 중)에서 멈춘다.
  Future<FakeMeRepository> pump(
    WidgetTester tester, {
    Result<CardDetail>? result,
    Result<MyProfile>? profile,
    FakeAccountRepository? account,
    bool settle = true,
  }) async {
    final repository = FakeMeRepository(profile ?? Success(_profile()))..cardPreview = result ?? Success(_detail());
    final container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(repository),
        accountRepositoryProvider.overrideWithValue(account ?? FakeAccountRepository()),
        // 실사진 서명 URL 은 네트워크 없이 작은 그림으로 대신한다.
        partnerPhotoImageProvider.overrideWithValue((url) => MemoryImage(Uint8List.fromList(_png))),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(
          path: AppRoutes.myProfile,
          builder: (context, state) => const Scaffold(body: Text('화면 15')),
        ),
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
    testWidgets('안내 `Ocmk4` — #FFF0F2 모서리 12 안쪽 14, 아이콘 없음, 328 폭 · 탭 바 아래 24', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(noticeBox, findsOneWidget);
      final decoration = tester.widget<DecoratedBox>(noticeBox).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(12));
      final box = tester.getRect(noticeBox);
      expect(box.topLeft, const Offset(16, 56 + 44 + 24)); // 앱바 56 + 탭 바 44 + 본문 위 24
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

  /// 탭 하나(`bUSON` 수락 전 · `Qt845` 수락 후)의 글자 · 밑줄을 읽는다.
  ({TextStyle style, Color underline}) tabLook(WidgetTester tester, String label) {
    final tab = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
    final underline = find.descendant(
      of: tab,
      matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 2),
    );
    return (style: tester.widget<Text>(find.text(label)).style!, underline: tester.widget<Container>(underline).color!);
  }

  group('밑줄 탭 바(pen `p9s0G` Tab Bar — 알약 세그먼트가 아니다)', () {
    testWidgets('앱바 바로 아래 360×44, 두 탭은 같은 폭 180, 아래 선 1px #EBEBEB', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final bar = find.byType(MeTabBar);
      expect(tester.getTopLeft(bar), const Offset(0, 56));
      // 보이는 줄은 44(아래 선 1px 은 그 안에 든다)이고, 누르는 칸만 48 이다 — 모자란 4 는 아래 선 밑으로 투명하게 늘렸다.
      expect(tester.getSize(bar), const Size(360, 48));
      expect(
        tester.getRect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == AppColors.hairlineSoft)).bottom,
        56 + 44,
      );
      for (final label in ['수락 전', '수락 후']) {
        expect(
          tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first).width,
          180,
          reason: label,
        );
      }
      // 아래 선 1px #EBEBEB, 바탕 #FFFFFF.
      final line = find.byWidgetPredicate((w) => w is ColoredBox && w.color == AppColors.hairlineSoft);
      expect(tester.getSize(line).height, 1);
      expect(
        tester.widget<ColoredBox>(find.descendant(of: bar, matching: find.byType(ColoredBox)).first).color,
        AppColors.canvas,
      );
      // 알약 세그먼트(SegmentedButton)가 아니다.
      expect(find.byType(SegmentedButton<int>), findsNothing);
    });

    testWidgets('처음엔 "수락 전" — 글자 #C4224B 14/700 + 밑줄 2px #C4224B, "수락 후" 는 #6A6A6A 14/500 + 밑줄 투명 (15-4 `O9ZIzO`)', (
      tester,
    ) async {
      await pump(tester);

      final before = tabLook(tester, '수락 전');
      expect(
        (before.style.fontSize, before.style.fontWeight, before.style.color),
        (14, FontWeight.w700, AppColors.primaryText),
      );
      expect(before.underline, AppColors.primaryText);
      final after = tabLook(tester, '수락 후');
      expect((after.style.fontSize, after.style.fontWeight, after.style.color), (14, FontWeight.w500, AppColors.muted));
      expect(after.underline, Colors.transparent);
      expect(find.text(_notice), findsOneWidget);
      expect(find.text(_noticeAfter), findsNothing);
    });

    testWidgets('글자는 탭 위에서 12, 밑줄은 바 맨 아래', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final tabFinder = find.ancestor(of: find.text('수락 전'), matching: find.byType(InkWell)).first;
      final tab = tester.getRect(tabFinder);
      expect(tester.getTopLeft(find.text('수락 전')).dy - tab.top, 12);
      final underline = find.descendant(
        of: tabFinder,
        matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 2),
      );
      // 밑줄은 보이는 줄(44)의 맨 아래 — 누르는 칸의 아래 4 는 그 밑이다.
      expect(tester.getRect(underline).bottom, tab.top + 44);
      expect(tester.getRect(underline).height, 2);
    });

    testWidgets('R2 누르는 칸은 48 — 보이는 줄(44) 아래 4 를 눌러도 탭이 눌리고, 본문의 보이는 자리는 그대로(안내가 탭 바 아래 24)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      for (final label in ['수락 전', '수락 후']) {
        expect(
          tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first),
          const Size(180, 48),
          reason: label,
        );
      }
      // 보이는 줄 바로 밑(y 100 + 2)을 누른다 — 줄 밖이라 글자가 아니라 투명한 4 다.
      await tester.tapAt(const Offset(270, 56 + 44 + 2));
      await tester.pumpAndSettle();
      expect(find.text(_noticeAfter), findsOneWidget);
      // 안내의 보이는 자리: 앱바 56 + 보이는 탭 바 44 + 24 = 124 (누르는 칸을 넓혀도 그대로).
      final box = tester.getRect(find.ancestor(of: find.text(_noticeAfter), matching: find.byType(DecoratedBox)).first);
      expect(box.top, 56 + 44 + 24);
    });

    testWidgets('"수락 후" 를 누르면 15-4b 로 — 탭 색이 바뀌고(`g1rDs`) 안내 글이 바뀐다', (tester) async {
      await pump(tester);

      await tester.tap(find.text('수락 후'));
      await tester.pumpAndSettle();

      final after = tabLook(tester, '수락 후');
      expect(
        (after.style.fontWeight, after.style.color, after.underline),
        (FontWeight.w700, AppColors.primaryText, AppColors.primaryText),
      );
      final before = tabLook(tester, '수락 전');
      expect(
        (before.style.fontWeight, before.style.color, before.underline),
        (FontWeight.w500, AppColors.muted, Colors.transparent),
      );
      expect(find.text(_noticeAfter), findsOneWidget);
      expect(find.text(_notice), findsNothing);
    });

    testWidgets('다시 "수락 전" 을 누르면 되돌아온다 — 같은 카드다', (tester) async {
      await pump(tester);
      await tester.tap(find.text('수락 후'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('수락 전'));
      await tester.pumpAndSettle();

      expect(find.text(_notice), findsOneWidget);
      expect(find.text('하늘, 24'), findsOneWidget);
      expect(find.byType(PhotoSlider), findsNothing);
    });

    testWidgets('낭독: 탭은 버튼이고 고른 탭만 selected, 낭독기로 "수락 후" 를 누르면 본문이 바뀐다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      final selected = tester.getSemantics(find.bySemanticsLabel('수락 전'));
      final other = tester.getSemantics(find.bySemanticsLabel('수락 후'));
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      expect(other.flagsCollection.isSelected, Tristate.isFalse);
      expect(selected.flagsCollection.isButton, isTrue);
      expect(other.flagsCollection.isButton, isTrue);
      expect(find.text(_noticeAfter), findsNothing);

      // 화면 읽기 도구가 하듯 의미 트리의 "탭" 동작을 한 번 보낸다 — Semantics(onTap:) 가 없으면 여기서 실패한다.
      tester.semantics.tap(find.semantics.byLabel('수락 후'));
      await tester.pumpAndSettle();

      expect(find.text(_noticeAfter), findsOneWidget);
      expect(find.text(_notice), findsNothing);
      expect(tester.getSemantics(find.bySemanticsLabel('수락 후')).flagsCollection.isSelected, Tristate.isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel('수락 전')).flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });
  });

  group('15-4b 수락 후(pen `vn8R2`)', () {
    Future<FakeMeRepository> openAfter(
      WidgetTester tester, {
      Result<MyProfile>? profile,
      FakeAccountRepository? account,
    }) async {
      usePenFrame(tester, height: 1000);
      final repository = await pump(tester, profile: profile, account: account);
      await tester.tap(find.text('수락 후'));
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('안내 `J7rLm` "수락하면 상대에게 이렇게 보여요" — 같은 분홍 상자, 아이콘 없음, 탭 바 아래 24', (tester) async {
      await openAfter(tester);

      final box = find.ancestor(of: find.text(_noticeAfter), matching: find.byType(DecoratedBox)).first;
      expect(tester.getTopLeft(box), const Offset(16, 56 + 44 + 24));
      expect(tester.getSize(box).width, 328);
      expect(find.descendant(of: box, matching: find.byType(Icon)), findsNothing);
    });

    testWidgets('실제 사진 슬라이더 288×260 — 내 프로필의 사진들, 안쪽 1px 테두리(bordered)', (tester) async {
      await openAfter(tester);

      final slider = tester.widget<PhotoSlider>(find.byType(PhotoSlider));
      expect(slider.photos.length, 2);
      expect(slider.photoSize, const Size(288, 260));
      expect(slider.bordered, isTrue);
    });

    testWidgets('카카오톡 아이디 카드 — 내 계정의 아이디, 복사 버튼', (tester) async {
      await openAfter(tester);
      await scrollToEnd(tester);

      expect(find.byType(KakaoIdCard), findsOneWidget);
      expect(find.text('카카오톡 아이디'), findsOneWidget);
      expect(find.text('fox_rain'), findsOneWidget);
      expect(find.byTooltip('복사'), findsOneWidget);
    });

    // 14c(partner_profile_screen_test "이런 사람이 좋아요 글 아래 간격")와 같은 잣대 — 카드의 footer 간격 13 / 1 / 3 이 15-4b 에서도 그대로다.
    Rect kakaoRect(WidgetTester tester) =>
        tester.getRect(find.ancestor(of: find.text('카카오톡 아이디'), matching: find.byType(Container)).first);

    testWidgets('안내 → 카드 32, "이런 사람이 좋아요" 글 아래 끝 → 카카오 카드 위 끝 13, 카카오 카드 → 구분선 1', (tester) async {
      await openAfter(tester);
      await scrollToEnd(tester);

      final notice = find.ancestor(of: find.text(_noticeAfter), matching: find.byType(DecoratedBox)).first;
      // 안내 ↔ 카드 32 는 스크롤 위치에서 재야 하니 맨 위로 되돌려 잰다.
      await tester.drag(_list, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(ProfileCard)).dy - tester.getBottomLeft(notice).dy, 32);

      await scrollToEnd(tester);
      expect(find.text('이런 사람이 좋아요'), findsOneWidget);
      expect(kakaoRect(tester).top - tester.getRect(find.text('대화가 잘 통하는 사람이 좋아요.')).bottom, 13);
      expect(tester.getRect(find.byType(Divider).last).top - kakaoRect(tester).bottom, 1);
    });

    testWidgets('카카오 카드가 빠져도(아이디 없음) 글 아래 끝 → 구분선 위 끝은 13 이다', (tester) async {
      final empty = FakeAccountRepository()
        ..accountResult = Success(
          AccountInfo(
            loginProvider: 'kakao',
            realName: null,
            birthYear: null,
            university: '가나대학교',
            joinedAt: DateTime.utc(2026),
            kakaoId: null,
          ),
        );
      await openAfter(tester, account: empty);
      await scrollToEnd(tester);

      expect(
        tester.getRect(find.byType(Divider).last).top - tester.getRect(find.text('대화가 잘 통하는 사람이 좋아요.')).bottom,
        13,
      );
    });

    testWidgets('카드 맨 아래: 구분선 → 신고하기 줄 11 · 줄 아래 → 카드 아래 끝 3 + 안쪽 여백(누르는 영역 안)', (tester) async {
      await openAfter(tester);
      await scrollToEnd(tester);

      final divider = tester.getRect(find.byType(Divider).last);
      final report = tester.getRect(find.text('신고하기'));
      // 링크 글자 윗선까지 11 (누르는 영역 위 11 = pen 구분선 뒤 간격) — 글자 줄높이만큼 안쪽이라 11 이상 + 줄높이 여유 안.
      expect(report.top - divider.bottom, greaterThanOrEqualTo(11));
      final card = tester.getRect(find.byType(ProfileCard));
      expect(card.bottom - report.bottom, greaterThanOrEqualTo(17 + 3));
    });

    testWidgets('카카오톡 아이디가 빈 문자열이어도 카카오 카드는 뜨지 않는다', (tester) async {
      final blank = FakeAccountRepository()
        ..accountResult = Success(
          AccountInfo(
            loginProvider: 'kakao',
            realName: null,
            birthYear: null,
            university: '가나대학교',
            joinedAt: DateTime.utc(2026),
            kakaoId: '',
          ),
        );
      await openAfter(tester, account: blank);
      await scrollToEnd(tester);

      expect(find.byType(KakaoIdCard), findsNothing);
      expect(find.text('카카오톡 아이디'), findsNothing);
      expect(find.byType(ReportBlockLinks), findsOneWidget);
    });

    testWidgets('신고하기 · 차단하기 줄은 보이지만 내 카드라 누를 곳이 없다', (tester) async {
      await openAfter(tester);
      await scrollToEnd(tester);

      expect(find.byType(ReportBlockLinks), findsOneWidget);
      expect(find.text('신고하기'), findsOneWidget);
      expect(find.text('차단하기'), findsOneWidget);
      expect(find.ancestor(of: find.text('신고하기'), matching: find.byType(InkWell)), findsNothing);
      expect(find.ancestor(of: find.text('차단하기'), matching: find.byType(InkWell)), findsNothing);
    });

    testWidgets('"신뢰 확인 완료" 는 이 화면에 없다(수락 후에도 pen 에 없음)', (tester) async {
      await openAfter(tester);

      expect(find.text('신뢰 확인 완료'), findsNothing);
    });

    testWidgets('읽는 동안은 도는 표시만 보이고, 다 읽으면 카드가 한 번에 뜬다', (tester) async {
      usePenFrame(tester, height: 1000);
      final slow = _SlowAccount();
      await pump(tester, account: slow);
      await tester.tap(find.text('수락 후'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ProfileCard), findsNothing);
      slow.release.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ProfileCard), findsOneWidget);
    });

    // pen 에 없는 상태 — PR 본문 "pen 에 없는 상태" 에 적는다.
    testWidgets('실사진이 0장이면 슬라이더 칸이 빠지고 나머지는 그대로다', (tester) async {
      await openAfter(tester, profile: Success(_profile(photos: 0)));

      expect(find.byType(PhotoSlider), findsNothing);
      expect(find.byType(ProfileCard), findsOneWidget);
      expect(find.text(_noticeAfter), findsOneWidget);
    });

    testWidgets('내 프로필을 못 읽어도 카드와 나머지 칸은 그려진다(사진 칸만 빠짐)', (tester) async {
      await openAfter(tester, profile: const FailureResult(NetworkFailure()));

      expect(find.byType(PhotoSlider), findsNothing);
      expect(find.byType(ProfileCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('카카오톡 아이디가 비었으면 카카오 카드 칸이 빠진다', (tester) async {
      final empty = FakeAccountRepository()
        ..accountResult = Success(
          AccountInfo(
            loginProvider: 'kakao',
            realName: null,
            birthYear: null,
            university: '가나대학교',
            joinedAt: DateTime.utc(2026),
            kakaoId: null,
          ),
        );
      await openAfter(tester, account: empty);
      await scrollToEnd(tester);

      expect(find.byType(KakaoIdCard), findsNothing);
      expect(find.byType(ReportBlockLinks), findsOneWidget);
    });

    testWidgets('계정을 못 읽어도 같다', (tester) async {
      final failing = FakeAccountRepository()..accountResult = const FailureResult(NetworkFailure());
      await openAfter(tester, account: failing);
      await scrollToEnd(tester);

      expect(find.byType(KakaoIdCard), findsNothing);
      expect(find.byType(ProfileCard), findsOneWidget);
    });

    testWidgets('탭을 오가도 계정을 다시 읽지 않고 도는 표시도 다시 뜨지 않는다', (tester) async {
      usePenFrame(tester, height: 1000);
      final account = FakeAccountRepository();
      await pump(tester, account: account);
      await tester.tap(find.text('수락 후'));
      await tester.pumpAndSettle();
      final reads = account.accountFetches;

      await tester.tap(find.text('수락 전'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('수락 후'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ProfileCard), findsOneWidget);
      await tester.pumpAndSettle();
      expect(account.accountFetches, reads);
    });

    for (final scale in [1.3, 1.5, 2.0]) {
      testWidgets('글자 배율 $scale 에서도 수락 후 탭이 넘치거나 잘리지 않는다(스크롤 전 · 끝)', (tester) async {
        usePenFrame(tester, height: 1000);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pump(tester);
        await tester.tap(find.text('수락 후'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final clipped = _clippedTexts(exceptWidth: 'fox_rain');
        await scrollToEnd(tester);
        clipped.addAll(_clippedTexts(exceptWidth: 'fox_rain'));

        expect(tester.takeException(), isNull);
        expect(clipped, isEmpty);
      });
    }

    testWidgets('카드 읽기에 실패하면 두 탭 모두 같은 실패 화면이고 탭 바는 남는다', (tester) async {
      usePenFrame(tester);
      await pump(tester, result: const FailureResult(NetworkFailure()));
      await tester.tap(find.text('수락 후'));
      await tester.pumpAndSettle();

      expect(find.byType(MeLoadError), findsOneWidget);
      expect(find.byType(MeTabBar), findsOneWidget);
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
///
/// [exceptWidth] 글자는 폭 검사에서 뺀다(높이는 본다) — 카톡 아이디는 끊을 곳이 없는 한 덩어리라 좁으면 글자 단위로 줄을 바꾼다
/// (14c 배율 시험과 같은 규칙).
List<String> _clippedTexts({String? exceptWidth}) => [
  for (final element in find.byType(RichText).evaluate())
    if (element.renderObject case final RenderParagraph p
        when p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5 ||
            (p.text.toPlainText() != exceptWidth && p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
      p.text.toPlainText(),
];

/// 읽기가 [release] 될 때까지 멈춰 있는 계정 저장소 — "읽는 중" 모양을 본다.
class _SlowAccount extends FakeAccountRepository {
  final Completer<void> release = Completer<void>();

  @override
  Future<Result<AccountInfo>> fetchAccount() async {
    await release.future;
    return super.fetchAccount();
  }
}
