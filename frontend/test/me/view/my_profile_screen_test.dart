import 'dart:async';
import 'dart:io';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/view/my_friend_reviews_section.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/card_preview_screen.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:campus_mate/me/view/my_profile_screen.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:campus_mate/me/view/profile_hero.dart';
import 'package:campus_mate/me/view/profile_manage_screen.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mocktail/mocktail.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../friend_review/model/fake_friend_review_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../profile/model/fake_avatar_repository.dart';
import '../model/fake_me_repository.dart';

/// 사진 요청을 받기만 하고 답하지 않는 HttpClient. 테스트의 기본 HttpClient 는 400 을 돌려줘
/// NetworkImage 가 오류를 내므로, 그림은 "아직 오는 중" 으로 둔다(크기·자리는 그림과 상관없다).
class _PendingHttpClient extends Mock implements HttpClient {}

/// NetworkImage 는 처음 쓸 때 만든 HttpClient 하나를 계속 쓴다 — 그 전에 이 파일 전체에 건다.
/// (`debugNetworkImageHttpClientProvider` 는 테스트마다 tearDown 보다 먼저 "바뀐 채 끝남" 검사에 걸린다.)
class _PendingHttpOverrides extends HttpOverrides {
  _PendingHttpOverrides(this._client);

  final HttpClient _client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _client;
}

const _bio = '주말엔 카페 투어와 등산을 즐겨요. 새로운 사람을 만나는 걸 좋아하고, 대화가 잘 통하는 사람을 찾고 있어요.';
const _pillLabel = '다시 만들기 · 10';
const _failedMessage = '아바타를 만들지 못했어요.\n하트는 차감되지 않았어요.';
const _logoUrl = 'https://logo.test/gana.webp';

/// 이름·학교는 지어낸 값이다.
MyProfile _profile({
  int? age = 23,
  String? major = '경영학과',
  String? avatarUrl = 'https://img.test/avatar.png',
  int heartBalance = 320,
  int avatarRegenCost = 10,
}) =>
    MyProfile(
      nickname: '여우',
      age: age,
      university: '가나대학교',
      major: major,
      heightCm: 178,
      mbti: 'ENFP',
      avatarUrl: avatarUrl,
      photos: const [
        MyPhoto(id: 'p-0', url: 'https://img.test/1.png', isAvatarSource: true),
        MyPhoto(id: 'p-1', url: 'https://img.test/2.png', isAvatarSource: false),
      ],
      preferredAgeMin: 22,
      preferredAgeMax: 27,
      preferredHeightMin: 165,
      preferredHeightMax: 180,
      bio: _bio,
      heartBalance: heartBalance,
      avatarRegenCost: avatarRegenCost,
    );

final _list = find.byType(Scrollable).first;
final _preview = find.widgetWithText(ProfileEntryRow, '남이 보는 내 프로필 카드');
final _manage = find.widgetWithText(ProfileEntryRow, '프로필 편집');
final _received = find.widgetWithText(ProfileEntryRow, '친구들이 본 나');
final _written = find.widgetWithText(ProfileEntryRow, '내가 쓴 리뷰');

/// 알약 몸통(흰 · 회색 알약을 칠하는 Material).
final _pill = find.ancestor(of: find.text(_pillLabel), matching: find.byType(Material)).first;
final _toast = find.byType(AppToast);

/// [url] 그림을 decoration 으로 깐 상자.
Finder _imageBox(String url) => find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).image?.image == NetworkImage(url),
    );

/// 화면 15 한 벌 — 저장소 두 개와 라우터를 테스트가 들고 있는다.
class _Harness {
  _Harness(this.me, this.avatars, this.router);

  final FakeMeRepository me;
  final FakeAvatarRepository avatars;
  final GoRouter router;
}

void main() {
  final previousOverrides = HttpOverrides.current;
  setUpAll(() {
    registerFallbackValue(Uri());
    final client = _PendingHttpClient();
    when(() => client.getUrl(any())).thenAnswer((_) => Completer<HttpClientRequest>().future);
    HttpOverrides.global = _PendingHttpOverrides(client);
  });
  tearDownAll(() => HttpOverrides.global = previousOverrides);

  /// [settle] 이 false 면 첫 프레임(불러오는 중)에서 멈춘다.
  Future<_Harness> pump(
    WidgetTester tester, {
    Result<MyProfile>? result,
    FakeAvatarRepository? avatars,
    bool settle = true,
  }) async {
    final repository = FakeMeRepository(result ?? Success(_profile()));
    final avatarRepository = avatars ?? FakeAvatarRepository();
    final container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(repository),
        avatarRepositoryProvider.overrideWithValue(avatarRepository),
        // 하단 내비 뱃지가 수락 대기·안 읽은 메시지를 읽는다(§8.8).
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        // 지인 리뷰 칸(`Cux1p`)이 받은 · 쓴 리뷰 개수를 읽는다.
        friendReviewRepositoryProvider.overrideWithValue(FakeFriendReviewRepository()),
        // 히어로 학교 줄이 로고를 읽는다 — 덮지 않으면 Supabase 를 부르다 실패해 이름만 그린다.
        universityLogosProvider.overrideWith((ref) => const {'가나대학교': _logoUrl}),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(path: AppRoutes.myProfile, builder: (context, state) => const MyProfileScreen()),
        GoRoute(path: AppRoutes.friendReviews, builder: (context, state) => const Scaffold(body: Text('20c 화면'))),
        GoRoute(path: AppRoutes.friendReviewsWritten, builder: (context, state) => const Scaffold(body: Text('20e 화면'))),
        GoRoute(path: AppRoutes.settings, builder: (context, state) => const Scaffold(body: Text('설정 화면'))),
        GoRoute(path: AppRoutes.myCardPreview, builder: (context, state) => const CardPreviewScreen()),
        GoRoute(path: AppRoutes.myProfileManage, builder: (context, state) => const ProfileManageScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    if (settle) await tester.pump();
    return _Harness(repository, avatarRepository, router);
  }

  void usePenFrame(WidgetTester tester, {double height = 884}) {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// ListView 는 아래 칸을 그리기 전엔 끝 길이를 어림한다 — 한 번 끌면 어림한 끝에서 멈추므로 진짜 끝까지 되풀이한다.
  Future<void> scrollToEnd(WidgetTester tester) async {
    final position = tester.state<ScrollableState>(_list).position;
    do {
      await tester.drag(_list, const Offset(0, -3000));
      await tester.pumpAndSettle();
    } while (position.pixels < position.maxScrollExtent);
  }

  /// 만드는 중이면 토스트의 도는 표시 때문에 pumpAndSettle 이 끝나지 않는다 — 시간을 정해 흘린다.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 알약 → 15b 시트 → [cta] 를 누른다.
  Future<void> chooseInSheet(WidgetTester tester, String cta) async {
    await tester.tap(find.text(_pillLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cta));
    await settle(tester);
  }

  group('앱바 `hwVQB`', () {
    testWidgets('제목 "내 프로필" 과 설정 톱니(48×48, settings 22 ink)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(find.text('내 프로필'), findsOneWidget);
      final gear = find.byTooltip('설정');
      expect(tester.getSize(gear), const Size(48, 48));
      // pen `C7teyl` x304 y4 — 오른쪽 여백 8.
      expect(tester.getTopLeft(gear), const Offset(304, 4));
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.settings));
      expect((icon.size, icon.color), (22, AppColors.ink));
    });

    testWidgets('톱니를 누르면 설정으로 간다', (tester) async {
      // pen 에서 설정(16)으로 가는 문은 15 내 프로필 `nkFJV` 의 톱니(`hwVQB` 안 `C7teyl`) 하나뿐이다.
      await pump(tester);

      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();

      expect(find.text('설정 화면'), findsOneWidget);
    });
  });

  testWidgets('하단 내비는 "나" 탭이 켜져 있다', (tester) async {
    await pump(tester);

    expect(tester.widget<AppBottomNav>(find.byType(AppBottomNav)).current, AppTab.me);
  });

  testWidgets('히어로 `l8p6X` 가 내 프로필 값으로 맨 위에 있다', (tester) async {
    await pump(tester);

    expect(tester.widget<ProfileHero>(find.byType(ProfileHero)).profile.nickname, '여우');
    expect(find.text('여우, 23'), findsOneWidget);
    // 학교 줄 `NvYvt` — 학교와 학과를 줄바꿈으로 나눈 두 줄.
    expect(find.text('가나대학교\n경영학과'), findsOneWidget);
    expect(find.image(const NetworkImage(_logoUrl)), findsOneWidget);
    expect(_imageBox('https://img.test/avatar.png'), findsOneWidget);
    expect(find.text(_pillLabel), findsOneWidget);
  });

  group('본문 — 히어로 자리 `nrcYh` [8,16,20,16] · 본문 `rcsgx` [24,16,40,16]', () {
    testWidgets('히어로 위 8 · 좌우 16 · 328×360, 히어로 ↔ 입구 줄 44(20 + 24), 입구 두 줄 사이 12(`sx7MA`)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final top = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(top, 56);
      final hero = tester.getRect(find.byType(ProfileHero));
      expect(hero.topLeft, Offset(16, top + 8));
      expect(hero.size, const Size(328, 360));
      final preview = tester.getRect(_preview);
      final manage = tester.getRect(_manage);
      // pen 본문 y444 + 24 = 468.
      expect(preview.top - hero.bottom, 44);
      expect(preview.top - top, 468 - 56);
      expect(manage.top - preview.bottom, 12);
      // 높이 84 는 최소값(§11.2) — 테스트 글꼴은 한글이 Pretendard 보다 넓어 두 노트가 두 줄로 내려간다.
      expect((preview.left, preview.width), (16, 328));
      expect((manage.left, manage.width), (16, 328));
      expect(preview.height, greaterThanOrEqualTo(84));
      expect(manage.height, greaterThanOrEqualTo(84));
    });

    testWidgets('본문 아래 40 — 끝까지 스크롤하면 지인 리뷰 칸 끝("내가 쓴 리뷰" 줄)과 하단 내비 사이 40', (tester) async {
      usePenFrame(tester, height: 600);
      await pump(tester);
      await scrollToEnd(tester);

      expect(tester.getTopLeft(find.byType(AppBottomNav)).dy - tester.getBottomLeft(_written).dy, 40);
    });

    testWidgets('지인 리뷰 칸 `Cux1p` 은 입구 줄 아래 32(N3) — 두 줄을 누르면 20c · 20e 로 간다', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(tester.getTopLeft(find.byType(MyFriendReviewsSection)).dy - tester.getBottomLeft(_manage).dy, 32);
      for (final (row, screen) in [(_received, '20c 화면'), (_written, '20e 화면')]) {
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.text(screen), findsOneWidget);
        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
      }
    });
  });

  group('입구 두 줄 `sx7MA`', () {
    testWidgets('`k3r5C` eye "남이 보는 내 프로필 카드" / "상대에게 보이는 모습을 미리 봐요" — 누르면 15-4 가 뜬다', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final row = tester.widget<ProfileEntryRow>(_preview);
      expect((row.icon, row.note), (AppIcons.eye, '상대에게 보이는 모습을 미리 봐요'));
      await tester.ensureVisible(_preview);
      await tester.pumpAndSettle();
      await tester.tap(_preview);
      await tester.pumpAndSettle();

      expect(find.byType(CardPreviewScreen), findsOneWidget);
    });

    testWidgets('`sC8BR` pencil "프로필 편집" / "사진·기본 정보·선호 조건·자기소개" — 누르면 15-5 가 뜬다', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final row = tester.widget<ProfileEntryRow>(_manage);
      expect((row.icon, row.note), (AppIcons.pencil, '사진·기본 정보·선호 조건·자기소개'));
      await tester.ensureVisible(_manage);
      await tester.pumpAndSettle();
      await tester.tap(_manage);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileManageScreen), findsOneWidget);
    });

    testWidgets('눌림 효과는 스크롤 밖이 아니라 줄 크기 Material 이 그린다(COMMON §4-2)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      for (final row in [_preview, _manage]) {
        final ink = find.descendant(of: row, matching: find.byType(InkWell));
        final painter = find.ancestor(of: ink, matching: find.byType(Material)).first;
        expect(tester.getSize(painter), tester.getSize(row));
        expect(tester.getSize(ink), tester.getSize(row));
        expect(tester.getSize(row).width, 328);
      }
    });

    testWidgets('입구 아이콘은 pen 의 Lucide 이름과 같다(`k3r5C` eye · `sC8BR` pencil)', (tester) async {
      expect(AppIcons.eye, LucideIcons.eye);
      expect(AppIcons.pencil, LucideIcons.pencil);
    });
  });

  testWidgets('15-5 로 옮긴 옛 섹션(실사진 · Facts · 선호 줄 · 자기소개 · "프로필 수정")과 옛 헤더 · 아바타 섹션은 없다', (tester) async {
    await pump(tester);

    for (final pass in ['처음', '끝까지 스크롤한 뒤']) {
      expect(find.byType(PhotoSlider), findsNothing, reason: pass);
      for (final text in [
        '실제 사진',
        '실제 사진 교체',
        '기본 정보',
        '내 키',
        '선호 나이 범위',
        '선호 키 범위',
        _bio,
        '자기소개 · 태그',
        '프로필 수정',
        '상대에게는 이렇게 보여요',
        'AI 아바타',
      ]) {
        expect(find.text(text), findsNothing, reason: '$pass · $text');
      }
      await scrollToEnd(tester);
    }
  });

  group('불러오는 중·실패(N9 — 15-4 · 15-5 와 같은 모양)', () {
    testWidgets('불러오는 중이면 가운데 로딩 표시, 앱바 톱니와 하단 내비는 그대로', (tester) async {
      await pump(tester, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('설정'), findsOneWidget);
      expect(find.byType(AppBottomNav), findsOneWidget);
      await tester.pump();
    });

    testWidgets('실패하면 문구와 "다시 시도", 앱바 톱니와 하단 내비는 그대로', (tester) async {
      await pump(tester, result: const FailureResult(NetworkFailure()));

      // 사용자 결정 2026-09-27 — 공통 "알 수 없는 오류" 문구가 아니다.
      expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);
      expect(find.text(const UnknownFailure().toDisplayMessage()), findsNothing);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.byTooltip('설정'), findsOneWidget);
      expect(find.byType(AppBottomNav), findsOneWidget);
    });

    testWidgets('"다시 시도" 를 누르면 다시 불러와 화면을 그린다', (tester) async {
      final harness = await pump(tester, result: const FailureResult(NetworkFailure()));
      expect(harness.me.calls, 1);

      harness.me.profile = Success(_profile());
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await tester.pump();

      expect(harness.me.calls, 2);
      expect(find.text('여우, 23'), findsOneWidget);
    });
  });

  group('15 연결 — 15b · 15-2 · 15-3(옛 A8, 입구 `R5Quru`)', () {
    testWidgets('알약을 누르면 15b 시트가 서버 비용 · 잔액으로 뜬다', (tester) async {
      await pump(tester, result: Success(_profile(heartBalance: 320, avatarRegenCost: 10)));

      await tester.tap(find.text(_pillLabel));
      await tester.pumpAndSettle();

      expect(find.text('아바타를 다시 만들까요?'), findsOneWidget);
      expect(find.textContaining('하트 10개가 차감돼요. 지금 보유한 하트는 320개예요.'), findsOneWidget);
      expect(find.text('10 쓰고 만들기'), findsOneWidget);
    });

    testWidgets('취소하면 아무것도 부르지 않는다', (tester) async {
      final harness = await pump(tester);

      await chooseInSheet(tester, '취소');

      expect(harness.avatars.regenerateCount, 0);
      expect(_toast, findsNothing);
    });

    testWidgets('"10 쓰고 만들기" → 다시 만들기 1회, 만드는 동안 알약이 꺼지고(15-2) 변환 중 토스트(도는 표시)', (tester) async {
      final harness = await pump(tester);

      await chooseInSheet(tester, '10 쓰고 만들기');

      expect(harness.avatars.regenerateCount, 1);
      expect(tester.widget<ProfileHero>(find.byType(ProfileHero)).onRegenerate, isNull);
      expect(tester.widget<Material>(_pill).color, AppColors.primaryDisabled);
      expect(find.text('아바타로 변환 중이에요'), findsOneWidget);
      // 04-3 토스트와 같은 도는 표시(loader-circle 16 자리).
      expect(find.descendant(of: _toast, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    });

    testWidgets('만드는 동안 알약을 눌러도 시트가 안 뜨고 두 번째 요청이 나가지 않는다', (tester) async {
      final harness = await pump(tester);
      await chooseInSheet(tester, '10 쓰고 만들기');

      await tester.tap(find.text(_pillLabel), warnIfMissed: false);
      await settle(tester);

      expect(find.text('아바타를 다시 만들까요?'), findsNothing);
      expect(harness.avatars.regenerateCount, 1);
    });

    testWidgets('변환 중 토스트는 내비 위 12 · 가로 가운데(04-3 과 같은 자리, N18)', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await chooseInSheet(tester, '10 쓰고 만들기');

      expect(tester.getTopLeft(find.byType(AppBottomNav)).dy - tester.getBottomLeft(_toast).dy, 12);
      expect(tester.getCenter(_toast).dx, 180);
    });

    testWidgets('실패로 바뀌면 15-3 토스트(triangle-alert + 두 줄)가 2초 뜨고 알약은 다시 켜진다', (tester) async {
      final avatars = FakeAvatarRepository()..statusResults.add(const Success(AvatarFailed()));
      await pump(tester, avatars: avatars);

      await chooseInSheet(tester, '10 쓰고 만들기');

      expect(find.text(_failedMessage), findsOneWidget);
      expect(find.text('아바타로 변환 중이에요'), findsNothing);
      final icon = tester.widget<Icon>(find.descendant(of: _toast, matching: find.byType(Icon)));
      expect((icon.icon, icon.size, icon.color), (AppIcons.alertTriangle, 16, AppColors.onInk));
      // 두 줄 — 줄높이 20 × 2(pen `k110R` 글자 153×40).
      expect(tester.getSize(find.text(_failedMessage)).height, 40);
      expect(tester.widget<ProfileHero>(find.byType(ProfileHero)).onRegenerate, isNotNull);
      expect(tester.widget<Material>(_pill).color, AppColors.canvas);

      await tester.pump(MeToastHost.duration);
      expect(find.text(_failedMessage), findsNothing);
    });

    testWidgets('완성(ready)으로 바뀌면 내 프로필을 다시 읽어 새 그림을 그린다', (tester) async {
      final avatars = FakeAvatarRepository()..statusResults.add(const Success(AvatarReady('https://img.test/new.png')));
      final harness = await pump(tester, avatars: avatars);
      expect(harness.me.calls, 1);
      harness.me.profile = Success(_profile(avatarUrl: 'https://img.test/new.png', heartBalance: 310));

      await chooseInSheet(tester, '10 쓰고 만들기');

      expect(harness.me.calls, 2);
      expect(_imageBox('https://img.test/new.png'), findsOneWidget);
      expect(_toast, findsNothing);
      expect(tester.widget<ProfileHero>(find.byType(ProfileHero)).onRegenerate, isNotNull);
    });

    testWidgets('실패로 끝나면 내 프로필을 다시 읽지 않는다(하트 · 그림 그대로)', (tester) async {
      final avatars = FakeAvatarRepository()..statusResults.add(const Success(AvatarFailed()));
      final harness = await pump(tester, avatars: avatars);

      await chooseInSheet(tester, '10 쓰고 만들기');

      expect(harness.me.calls, 1);
    });

    testWidgets('하트가 모자라다는(402) 서버 문구는 그 문구 그대로 토스트 — 15-3 문구가 아니다', (tester) async {
      final avatars = FakeAvatarRepository()..nextResult = const FailureResult(ServerRejectedFailure('하트가 모자라요'));
      await pump(tester, avatars: avatars);

      await chooseInSheet(tester, '10 쓰고 만들기');

      expect(find.descendant(of: _toast, matching: find.text('하트가 모자라요')), findsOneWidget);
      expect(find.text(_failedMessage), findsNothing);
      expect(tester.widget<ProfileHero>(find.byType(ProfileHero)).onRegenerate, isNotNull);
      await tester.pump(MeToastHost.duration);
      expect(_toast, findsNothing);
    });

    testWidgets('15b-3 "하트 충전하기" → 시트가 닫히고 "곧 열려요"(C5), 다시 만들기는 부르지 않는다', (tester) async {
      final harness = await pump(tester, result: Success(_profile(heartBalance: 3, avatarRegenCost: 10)));

      await chooseInSheet(tester, '하트 충전하기');

      expect(find.text('하트가 모자라요'), findsNothing);
      expect(find.text('곧 열려요'), findsOneWidget);
      expect(harness.avatars.regenerateCount, 0);
      await tester.pump(MeToastHost.duration);
      expect(find.text('곧 열려요'), findsNothing);
    });

    testWidgets('만드는 중에 화면을 떠나면 그만 묻는다(폴링 멈춤)', (tester) async {
      final harness = await pump(tester);
      await chooseInSheet(tester, '10 쓰고 만들기');
      final asked = harness.avatars.statusCount;

      harness.router.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 12));

      expect(find.text('설정 화면'), findsOneWidget);
      expect(harness.avatars.statusCount, asked);
    });

    testWidgets('만드는 중에 떠났다 돌아오면 상태를 다시 묻고 폴링을 잇는다(Review Focus 3)', (tester) async {
      final harness = await pump(tester);
      await chooseInSheet(tester, '10 쓰고 만들기');
      harness.router.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      final asked = harness.avatars.statusCount;

      harness.router.go(AppRoutes.myProfile);
      await settle(tester);

      expect(harness.avatars.statusCount, asked + 1);
      expect(find.text('아바타로 변환 중이에요'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(harness.avatars.statusCount, asked + 2);
    });

    testWidgets('등록 응답을 기다리는 사이 떠나도 폴링이 남지 않는다', (tester) async {
      final avatars = FakeAvatarRepository()..generateGate = Completer<void>();
      final harness = await pump(tester, avatars: avatars);
      await chooseInSheet(tester, '10 쓰고 만들기');

      harness.router.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      avatars.generateGate!.complete();
      await tester.pump();
      final asked = avatars.statusCount;
      await tester.pump(const Duration(seconds: 12));

      expect(avatars.statusCount, asked);
    });

    testWidgets('등록 응답을 기다리는 사이 떠났다가 응답 전에 돌아오면 폴링을 잇는다', (tester) async {
      // 뷰모델의 폴링 타이머는 하나다 — 떠난 화면이 뒤늦게 끊으면 돌아온 화면이 "변환 중" 에 멈춘다(검토 권고 1).
      final avatars = FakeAvatarRepository()..generateGate = Completer<void>();
      final harness = await pump(tester, avatars: avatars);
      await chooseInSheet(tester, '10 쓰고 만들기');

      harness.router.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      harness.router.go(AppRoutes.myProfile);
      await settle(tester);
      avatars.generateGate!.complete();
      await tester.pump();
      final asked = avatars.statusCount;
      await tester.pump(const Duration(seconds: 12));

      expect(find.text('아바타로 변환 중이에요'), findsOneWidget);
      expect(avatars.statusCount, greaterThan(asked));
    });

    testWidgets('만드는 중이 아니면 화면을 열어도 상태를 묻지 않는다', (tester) async {
      final harness = await pump(tester);
      await tester.pump(const Duration(seconds: 6));

      expect(harness.avatars.statusCount, 0);
    });
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('pen 프레임 폭 360·글자 배율 $scale 에서 어느 줄도 넘치지 않는다', (tester) async {
      // 테스트 글꼴은 한글이 Pretendard 보다 넓다 — 여기서 버티면 실제 폰에서도 버틴다.
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester);
      expect(tester.takeException(), isNull);
      await scrollToEnd(tester);

      expect(tester.takeException(), isNull);
    });
  }

  // 1.3 은 검토에서 size.width 로 재면 "여우, 23" 을 잘렸다고 잘못 세던 배율이다.
  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 어떤 글자도 고정 상자에 잘리지 않는다(스크롤 전·끝 두 번)', (tester) async {
      // 넘침 오류는 Flex 만 낸다 — SizedBox·Container 높이에 갇힌 글자는 오류 없이 잘린다.
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // 앱바·내비까지 화면 전체를 본다. 내비 "커뮤니티" 는 칸 폭 안에서, 히어로 학교 줄은 두 줄로 일부러 말줄임한다(N7).
      const intendedEllipsis = {'커뮤니티', '가나대학교\n경영학과'};
      List<String> clippedTexts() => [
            for (final element in find.byType(RichText).evaluate())
              if (element.renderObject case final RenderParagraph p
                  when !intendedEllipsis.contains(p.text.toPlainText()) &&
                      // 폭은 배치 때 받은 최대 폭으로 잰다 — size.width 로 재면 소수점 오차로 한 줄이 두 줄로 세어진다.
                      (p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5 ||
                          p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
                p.text.toPlainText(),
          ];

      await pump(tester);
      final clipped = clippedTexts();
      await scrollToEnd(tester);
      clipped.addAll(clippedTexts());
      // 넘침은 위 배율 테스트가 본다 — 여기서는 잘림만 본다.
      tester.takeException();

      expect(clipped, isEmpty);
    });
  }
}
