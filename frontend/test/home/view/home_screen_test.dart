import 'dart:async';
import 'dart:typed_data';

import 'package:campus_mate/billing/store/view/heart_balance_chip.dart';
import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/common/widgets/pressable.dart';
import 'package:campus_mate/common/widgets/retry_notice.dart';
import 'package:campus_mate/consent/model/repository/open_url.dart';
import 'package:campus_mate/core/app_update/store_listing.dart';
import 'package:campus_mate/core/app_update/update_requirement_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/home/model/data/cohort_wait.dart';
import 'package:campus_mate/home/model/data/home_people.dart';
import 'package:campus_mate/home/model/repository/home_repository_provider.dart';
import 'package:campus_mate/home/model/data/home_summary.dart';
import 'package:campus_mate/home/model/data/profile_completion_item.dart';
import 'package:campus_mate/home/view/auto_marquee.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/home_banner_carousel.dart';
import 'package:campus_mate/home/view/home_grid.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/mosaic_tile.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
import 'package:campus_mate/home/view/tag.dart';
import 'package:campus_mate/home/viewmodel/home_people_provider.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/matching/model/data/card_profile.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/matching/model/data/daily_card.dart';
import 'package:campus_mate/matching/view/countdown_text.dart';
import 'package:campus_mate/me/model/repository/me_repository_provider.dart';
import 'package:campus_mate/me/model/data/my_profile.dart';
import 'package:campus_mate/notifications/model/repository/notifications_repository_provider.dart';
import 'package:campus_mate/tour/model/repository/tour_seen_store.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/tour_target.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/repository/fake_chat_repository.dart';
import '../../matching/model/repository/fake_card_repository.dart';
import '../../me/model/repository/fake_me_repository.dart';
import '../model/repository/fake_home_repository.dart';
import '../../notifications/model/repository/fake_notifications_repository.dart';
import '../../tour/model/repository/fake_tour_seen_store.dart';

/// mosaic-rail 도 가로 Scrollable 이라 세로 목록을 짚어 준다.
final _mainList = find.byType(Scrollable).first;

const _cardProfile = CardProfile(profileId: 'p', nickname: '여우비', age: 23, university: '가람대', major: '경영학과');

/// pen 기본 09b(`k13Z5C`)는 hero ① 도착이다 — 오늘 탭에 무료 카드가 한 장 있다.
const Result<TodayCards> _arrived = Success(
  TodayCards(cards: [DailyCard(cardId: 'free', source: CardSource.daily, profile: _cardProfile)]),
);

MyProfile _me(String university) => MyProfile(
  nickname: '여우',
  age: 23,
  university: university,
  major: '경영학과',
  heightCm: 178,
  mbti: 'ENFP',
  avatarUrl: null,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: 165,
  preferredHeightMax: 180,
  bio: '',
);

/// hero 의 AnimatedSwitcher — 화면 아래 토스트 자리(`ToastPresence`, 2026-11-16)도 AnimatedSwitcher 라 본문 쪽 첫 번째를 고른다.
final _heroSwitcher = find.byType(AnimatedSwitcher).first;

void main() {
  const summary = HomeSummary(
    deliveredCards: 1234567,
    signups: 862,
    conversationsStarted: 391,
    reviewRating: 4.6,
    reviewCount: 57,
    campuses: ['가람대', '새솔대'],
    profileCompletionPercent: 40,
  );

  HomeSummary summaryWith({
    int? delivered,
    int? signups,
    int? conversations,
    int? percent,
    double? rating,
    int? reviews,
    List<ProfileCompletionItem> missing = const [],
  }) => HomeSummary(
    deliveredCards: delivered ?? summary.deliveredCards,
    signups: signups ?? summary.signups,
    conversationsStarted: conversations ?? summary.conversationsStarted,
    reviewRating: rating ?? summary.reviewRating,
    reviewCount: reviews ?? summary.reviewCount,
    campuses: summary.campuses,
    profileCompletionPercent: percent ?? summary.profileCompletionPercent,
    profileCompletionMissing: missing,
  );

  /// 서버가 배너 두 장을 준 홈(홈 v3 `kkKiZ` — 사람 줄 아래 · 링크 칸 위).
  const banners = [
    HomeBanner(imageUrl: 'https://cdn.test/a.webp', altText: '크리스마스에 어디 가세요?'),
    HomeBanner(imageUrl: 'https://cdn.test/b.webp', altText: '곧 1월 1일이에요'),
  ];
  const withBanners = HomeSummary(
    deliveredCards: 1234567,
    signups: 862,
    conversationsStarted: 391,
    reviewRating: 4.6,
    reviewCount: 57,
    campuses: ['가람대', '새솔대'],
    profileCompletionPercent: 40,
    banners: banners,
  );

  late GoRouter router;
  late ProviderContainer homeContainer;

  /// [settle] 이 true 면 hero 전환 · 요약 블록 등장이 끝날 때까지 흘린다(레일은 계속 흘러 pumpAndSettle 은 못 쓴다).
  /// [cards] 를 주면 오늘 카드는 그 저장소가 답한다([today] 는 무시) — 읽는 동안 멈추거나 읽은 횟수를 볼 때.
  /// [home] 을 주면 요약 · 사람 칸은 그 저장소가 답한다([result] 는 무시).
  Future<void> pump(
    WidgetTester tester, {
    Result<HomeSummary> result = const Success(summary),
    Result<TodayCards> today = _arrived,
    FakeCardRepository? cards,
    FakeHomeRepository? home,
    Result<MyProfile> me = const FailureResult(NetworkFailure()),
    bool settle = true,
    List<Override> overrides = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...overrides,
        homeRepositoryProvider.overrideWithValue(home ?? FakeHomeRepository(result)),
        notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        meRepositoryProvider.overrideWithValue(FakeMeRepository(me)),
        // 하단 내비 뱃지가 수락 대기·안 읽은 메시지를 읽는다(§8.8). hero 는 오늘 탭 상태를 읽는다.
        cardRepositoryProvider.overrideWithValue(cards ?? (FakeCardRepository()..today = today)),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);
    router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
        GoRoute(path: AppRoutes.today, builder: (context, state) => const Text('오늘 탭')),
        GoRoute(path: AppRoutes.settings, builder: (context, state) => const Text('16 설정')),
      ],
    );
    addTearDown(router.dispose);
    homeContainer = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, routerConfig: router),
      ),
    );
    await tester.pump();
    if (settle) await tester.pump(const Duration(seconds: 1));
  }

  /// 기본 테스트 화면(800×600)에선 리뷰 띠가 화면 밖이다 — pen 프레임으로 본다.
  void penFrame(WidgetTester tester, [double width = 360]) {
    tester.view.physicalSize = Size(width, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder heroOf(String line) => find.ancestor(of: find.text(line), matching: find.byType(Container)).last;

  /// hero 안의 스켈레톤 막대(pen `TmUDw` Skeleton · Block, #EBEBEB).
  Finder skeletonBars() => find.descendant(
        of: _heroSwitcher,
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == const Color(0xFFEBEBEB),
        ),
      );

  /// 지금 hero 틀(문구가 없는 불러오는 중에도 찾는다) — AnimatedSwitcher 아래 첫 Container.
  Finder heroFrame() => find.descendant(of: _heroSwitcher, matching: find.byType(Container)).first;

  group('hero-today 불러오는 중(pen `VdvmY` 09b 메인 · 불러오는 중, hero `jHiXf`)', () {
    /// 오늘 카드를 읽는 동안 멈춰 둔 저장소. `holdToday!.complete()` 로 그때의 `today` 를 돌려주며 끝낸다.
    FakeCardRepository holding() => FakeCardRepository()..holdToday = Completer<void>();

    testWidgets('읽는 동안 — #F7F7F7 r32 328×160 · 막대 3개 #EBEBEB r6 · 마스코트 그대로 · 문구와 버튼 없음 · 정적', (tester) async {
      penFrame(tester);
      final semantics = tester.ensureSemantics();
      await pump(tester, cards: holding());

      final hero = heroFrame();
      final box = tester.widget<Container>(hero).decoration! as BoxDecoration;
      expect((box.color, box.borderRadius), (const Color(0xFFF7F7F7), BorderRadius.circular(32)));
      expect(tester.getSize(hero), const Size(328, 160));
      // `dX7EM` x20 y20 세로 쌓기 — `BJJfw` 148×20 · 사이 8 · `YHQnE` 112×20 · 사이 22 · `nBNDt` 104×32.
      final origin = tester.getTopLeft(hero);
      expect([for (var i = 0; i < 3; i++) tester.getRect(skeletonBars().at(i)).shift(-origin)], const [
        Rect.fromLTWH(20, 20, 148, 20),
        Rect.fromLTWH(20, 48, 112, 20),
        Rect.fromLTWH(20, 90, 104, 32),
      ]);
      for (final bar in tester.widgetList<DecoratedBox>(skeletonBars())) {
        expect((bar.decoration as BoxDecoration).borderRadius, BorderRadius.circular(6));
      }
      // `ymdUS` = 다른 hero 의 커플 마스코트 그대로(x172 y-5 160×170).
      final mascot = find.descendant(of: hero, matching: find.byType(Image));
      expect((tester.widget<Image>(mascot).image as AssetImage).assetName, 'assets/images/home-top-mascot-couple.webp');
      expect(tester.getRect(mascot).shift(-origin), const Rect.fromLTWH(172, -5, 160, 170));
      for (final text in ['오늘의 카드가', '지금 확인하기', '결정 대기 카드가', '오늘 카드는']) {
        expect(find.text(text), findsNothing, reason: text);
      }
      // 반짝임 없음(DESIGN §7 · pen context "애니메이션 없음").
      expect(
        find.descendant(of: hero, matching: find.byWidgetPredicate((w) => w is AnimatedWidget || w is ImplicitlyAnimatedWidget)),
        findsNothing,
      );
      expect(find.bySemanticsLabel('오늘의 카드를 불러오는 중'), findsOneWidget);
      semantics.dispose();
    });

    for (final (name, result, line) in [
      ('① 도착', _arrived, '오늘의 카드가'),
      (
        '② 결정 대기',
        const Success(TodayCards(cards: [DailyCard(cardId: 'paid', source: CardSource.purchased, profile: _cardProfile)])),
        '결정 대기 카드가',
      ),
      ('③ 확인 완료', Success(TodayCards(cards: const [], nextIssueAt: DateTime.now().add(const Duration(hours: 5)))), '오늘 카드는'),
    ]) {
      testWidgets('읽기가 끝나면 standard(220ms) 로 $name 으로 겹쳐 바뀐다', (tester) async {
        final cards = holding();
        await pump(tester, cards: cards, settle: false);
        expect(skeletonBars(), findsNWidgets(3));

        cards.today = result;
        cards.holdToday!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(skeletonBars(), findsNWidgets(3));
        expect(find.text(line), findsOneWidget);
        await tester.pump(AppMotion.standard);
        expect(skeletonBars(), findsNothing);
        expect(find.text(line), findsOneWidget);
      });
    }

    testWidgets('기기 "동작 줄이기"면 읽기가 끝나는 프레임에 바로 바뀌고, 화면이 멈춘다(pumpAndSettle 이 끝난다)', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final cards = holding();
      await pump(tester, cards: cards, settle: false);
      await tester.pumpAndSettle();
      expect(skeletonBars(), findsNWidgets(3));

      cards.today = _arrived;
      cards.holdToday!.complete();
      await tester.pump();
      await tester.pump();
      expect(skeletonBars(), findsNothing);
      expect(find.text('오늘의 카드가'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('320 폭 — 틀 288, 막대 자리 그대로, 마스코트는 오른쪽 끝 밖 4, 넘침 없음', (tester) async {
      penFrame(tester, 320);
      await pump(tester, cards: holding());

      final hero = heroFrame();
      expect(tester.getSize(hero), const Size(288, 160));
      final origin = tester.getTopLeft(hero);
      expect(tester.getRect(skeletonBars().first).shift(-origin), const Rect.fromLTWH(20, 20, 148, 20));
      final mascot = tester.getRect(find.descendant(of: hero, matching: find.byType(Image)));
      expect(mascot.right - tester.getRect(hero).right, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('글자 배율 2.4 — 막대는 글자가 아니라 그대로, hero 160 · 넘침 없음', (tester) async {
      penFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, cards: holding());

      expect(tester.getSize(heroFrame()), const Size(328, 160));
      expect([for (var i = 0; i < 3; i++) tester.getSize(skeletonBars().at(i))],
          const [Size(148, 20), Size(112, 20), Size(104, 32)]);
      await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);
      expect(tester.takeException(), isNull);
    });
  });

  group('hero-today 세 상태(DESIGN §8.9 · pen `U1k8ZK` · `fxlhV` · `HGxAR`)', () {
    testWidgets('① 도착 — "지금 확인하기"를 누르면 오늘 탭으로 간다', (tester) async {
      await pump(tester);

      expect(find.text('오늘의 카드가'), findsOneWidget);
      expect(find.text('도착했어요'), findsOneWidget);
      await tester.tap(find.text('지금 확인하기'));
      await tester.pumpAndSettle();

      expect(find.text('오늘 탭'), findsOneWidget);
    });

    testWidgets('② 결정 대기 — 산 카드만 남으면 "결정 대기 카드가 N장 남아 있어요" · "이어서 확인하기" → 오늘 탭', (tester) async {
      penFrame(tester);
      await pump(
        tester,
        today: const Success(TodayCards(cards: [
          DailyCard(cardId: 'paid-1', source: CardSource.purchased, profile: _cardProfile),
          DailyCard(cardId: 'paid-2', source: CardSource.purchased, profile: _cardProfile),
        ])),
      );

      expect(find.text('결정 대기 카드가'), findsOneWidget);
      expect(find.text('2장 남아 있어요'), findsOneWidget);
      expect(find.text('지금 확인하기'), findsNothing);
      final hero = heroOf('결정 대기 카드가');
      expect((tester.widget<Container>(hero).decoration! as BoxDecoration).color, const Color(0xFFFFF0F2));
      // 우상단 장수 배지 `Q4nCLG` — x280 y16 32×24 · #FF385C · 알약, 숫자 10/600 흰색.
      final badge = find.ancestor(of: find.text('2'), matching: find.byType(Container)).first;
      expect(tester.getRect(badge).shift(-tester.getTopLeft(hero)), const Rect.fromLTWH(280, 16, 32, 24));
      final box = tester.widget<Container>(badge).decoration! as BoxDecoration;
      expect((box.color, box.borderRadius), (const Color(0xFFFF385C), BorderRadius.circular(9999)));
      final digit = tester.widget<Text>(find.text('2')).style!;
      expect((digit.fontSize, digit.fontWeight, digit.color), (10, FontWeight.w600, const Color(0xFFFFFFFF)));

      await tester.tap(find.text('이어서 확인하기'));
      await tester.pumpAndSettle();
      expect(find.text('오늘 탭'), findsOneWidget);
    });

    testWidgets('③ 확인 완료 — #F7F7F7 · "오늘 카드는 모두 확인했어요" · "다음 카드까지" + 카운트다운 32/700, 버튼 없음', (tester) async {
      penFrame(tester);
      await pump(
        tester,
        today: Success(TodayCards(cards: const [], nextIssueAt: DateTime.now().add(const Duration(hours: 3, seconds: 30)))),
      );

      expect(find.text('오늘 카드는'), findsOneWidget);
      expect(find.text('모두 확인했어요'), findsOneWidget);
      expect(find.text('지금 확인하기'), findsNothing);
      expect(find.text('이어서 확인하기'), findsNothing);
      final hero = heroOf('오늘 카드는');
      expect((tester.widget<Container>(hero).decoration! as BoxDecoration).color, const Color(0xFFF7F7F7));
      expect(tester.getSize(hero).height, 160);
      final countdown = find.descendant(of: hero, matching: find.byType(CountdownText));
      expect(countdown, findsOneWidget);
      // 기기 시계로 센다 — 시험이 도는 사이 1초가 넘어가도 시 · 분은 같다.
      expect(find.descendant(of: countdown, matching: find.textContaining('03:00:')), findsOneWidget);
      final digits = tester.widget<Text>(find.descendant(of: countdown, matching: find.byType(Text))).style!;
      expect((digits.fontSize, digits.fontWeight, digits.letterSpacing, digits.color), (32, FontWeight.w700, -0.96, const Color(0xFF222222)));
      expect(digits.fontFeatures, contains(const FontFeature.tabularFigures()));
      final label = tester.widget<Text>(find.text('다음 카드까지')).style!;
      expect((label.fontSize, label.fontWeight, label.color), (14, FontWeight.w400, const Color(0xFF6A6A6A)));
      // `xq5wi` y16 h128 가운데 정렬 — 렌더 글자 상자(lineHeight 속성 없음): 줄 27 · 27, 간격 8, 라벨 21(lh 1.5), 숫자 44.
      final top = tester.getTopLeft(hero).dy;
      for (final (finder, y, height) in [
        (find.text('오늘 카드는'), 16.5, 27.0),
        (find.text('모두 확인했어요'), 43.5, 27.0),
        (find.text('다음 카드까지'), 78.5, 21.0),
        (find.descendant(of: countdown, matching: find.byType(Text)), 99.5, 44.0),
      ]) {
        expect(tester.getTopLeft(finder).dy - top, y);
        expect(tester.getSize(finder).height, height);
      }
    });

    testWidgets('③ 다음 지급 시각을 모르면 카운트다운 없이 문구만', (tester) async {
      await pump(tester, today: const Success(TodayCards(cards: [])));

      expect(find.text('모두 확인했어요'), findsOneWidget);
      expect(find.text('다음 카드까지'), findsNothing);
      expect(find.byType(CountdownText), findsNothing);
    });

    testWidgets('못 읽으면 지금까지의 문구(도착)를 둔다 — pen 에 실패 hero 가 없다', (tester) async {
      await pump(tester, today: const FailureResult(NetworkFailure()));

      expect(find.text('오늘의 카드가'), findsOneWidget);
      expect(find.text('지금 확인하기'), findsOneWidget);
      expect(skeletonBars(), findsNothing);
    });

    testWidgets('상태가 바뀌면 AnimatedSwitcher 가 standard(220ms) 로 바꾼다', (tester) async {
      await pump(tester, today: const Success(TodayCards(cards: [])), settle: false);

      final switcher = tester.widget<AnimatedSwitcher>(_heroSwitcher);
      expect((switcher.duration, switcher.switchInCurve), (AppMotion.standard, AppMotion.standardCurve));
      // 처음 읽는 동안의 스켈레톤이 확인 완료로 바뀌는 중이다 — 둘이 겹쳐 있다가 220ms 뒤 하나만 남는다.
      // 도착 문구는 한 번도 보이지 않는다(읽는 동안 "도착했어요" 가 떴다가 바뀌던 버그).
      await tester.pump(const Duration(milliseconds: 100));
      expect(skeletonBars(), findsNWidgets(3));
      expect(find.text('오늘 카드는'), findsOneWidget);
      expect(find.text('오늘의 카드가'), findsNothing);
      await tester.pump(AppMotion.standard);
      expect(skeletonBars(), findsNothing);
    });

    testWidgets('③ 카운트다운이 0 이 되면 푸시를 기다리지 않고 다시 읽는다 — 20초 간격 3번까지, 그 뒤로는 멈춘다', (tester) async {
      // 다음 지급 시각이 이미 지났는데 서버가 계속 대기를 준다(배치가 늦거나 기기 시계가 빠름) — 끝없이 돌면 안 된다.
      final cards = FakeCardRepository()
        ..today = Success(TodayCards(cards: const [], nextIssueAt: DateTime.now().subtract(const Duration(minutes: 1))));
      await pump(tester, cards: cards);

      expect(find.text('모두 확인했어요'), findsOneWidget);
      expect(cards.fetchTodayCount, 2);
      await tester.pump(const Duration(minutes: 1));
      expect(cards.fetchTodayCount, 5);
      await tester.pump(const Duration(minutes: 5));
      expect(cards.fetchTodayCount, 5);
    });

    testWidgets('기기 "동작 줄이기"면 hero 는 바로 바뀐다(시간 0)', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pump(tester, today: const Success(TodayCards(cards: [])), settle: false);

      expect(tester.widget<AnimatedSwitcher>(_heroSwitcher).duration, Duration.zero);
    });

    for (final width in [320.0, 360.0, 430.0]) {
      testWidgets('마스코트 `S49nUs` 는 오른쪽 기준 — $width 폭에서 카드 오른쪽 끝 밖 4 · 위 -5 · 160×170', (tester) async {
        penFrame(tester, width);
        await pump(tester);

        final hero = heroOf('오늘의 카드가');
        final mascot = tester.getRect(find.descendant(of: hero, matching: find.byType(Image)));
        final box = tester.getRect(hero);
        expect(mascot.right - box.right, 4);
        expect(mascot.top - box.top, -5);
        expect(mascot.size, const Size(160, 170));
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('숫자 3칸은 홈에서 빠졌다 — 요약에 값이 있어도 그리지 않는다(사용자 결정 11-12)', (tester) async {
    penFrame(tester);
    await pump(tester);
    await tester.drag(_mainList, const Offset(0, -400));
    await tester.pump(const Duration(seconds: 1));

    for (final gone in ['1,234,567', '862', '391', '전달된 카드', '가입 수', '시작된 대화']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
  });

  // 리뷰 띠 되살리기(2026-11-15 사용자 「링크 있으니깐 리뷰 살리기 가능하지 않나?」, pen 시안 A `TdmIQ` · 마스터 `L7wKi`):
  // 링크 칸 아래 24 · 참여 대학 위 24.
  group('리뷰 띠(pen `L7wKi`)', () {
    Finder strip() => find.byKey(homeReviewStripKey);

    testWidgets('평가가 있으면 별점 · 별 다섯 · "(N명 평가)" · "리뷰 남기기", 328×64 · #FFF8EC · 모서리 14, 링크 칸 → 24 → 띠 → 24 → 참여 대학', (tester) async {
      penFrame(tester);
      await pump(tester);
      await tester.ensureVisible(find.text('참여 중인 대학'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('4.6'), findsOneWidget);
      expect(find.text('(57명 평가)'), findsOneWidget);
      expect(find.text('리뷰 남기기'), findsOneWidget);
      expect(find.text('CampusMate 가 마음에 드셨나요?'), findsNothing);
      final rect = tester.getRect(strip());
      expect(rect.size, const Size(328, 64));
      final box = tester.widget<Container>(strip()).decoration! as BoxDecoration;
      expect((box.color, box.borderRadius), (AppColors.reviewStripSurface, BorderRadius.circular(14)));
      expect(rect.top - tester.getRect(find.byType(HomeGrid)).bottom, 24);
      expect(tester.getRect(find.text('참여 중인 대학')).top - rect.bottom, 24);
      final button = tester.widget<Text>(find.text('리뷰 남기기')).style!;
      expect((button.fontSize, button.fontWeight, button.color), (16, FontWeight.w700, AppColors.primaryText));
      expect(tester.getSize(find.ancestor(of: find.text('리뷰 남기기'), matching: find.byType(Pressable))).height, 48);
    });

    testWidgets('평가 0명 — 띠를 숨기지 않고 "CampusMate 가 마음에 드셨나요?"(14/600 ink) + "리뷰 남기기", 별점 · 평가 수는 없다', (tester) async {
      penFrame(tester);
      await pump(tester, result: Success(summaryWith(rating: 0, reviews: 0)));
      await tester.ensureVisible(strip());
      await tester.pump(const Duration(seconds: 1));

      final prompt = find.text('CampusMate 가 마음에 드셨나요?');
      expect(prompt, findsOneWidget);
      final style = tester.widget<Text>(prompt).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.ink));
      expect(tester.widget<Text>(prompt).maxLines, 1);
      expect(find.text('리뷰 남기기'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      expect(find.textContaining('명 평가'), findsNothing);
      expect(tester.getSize(strip()), const Size(328, 64));
      // pen `QCtib`: 이 상태의 버튼은 가로 안쪽 여백이 없다 — 버튼 칸 폭 = 글자 폭.
      final button = find.ancestor(of: find.text('리뷰 남기기'), matching: find.byType(Pressable));
      expect(tester.getSize(button).width, tester.getSize(find.text('리뷰 남기기')).width);
      expect(tester.takeException(), isNull);
    });

    // 안드로이드: 플레이 별점 보고서에는 평가 수가 없다(서버 count null) — 별점만 보이고 "(N명 평가)" 는 숨긴다.
    testWidgets('평가 수를 모르면(null) 별점 · 별만 보이고 "(N명 평가)" 는 없다', (tester) async {
      penFrame(tester);
      await pump(
        tester,
        result: const Success(HomeSummary(
          deliveredCards: 0,
          signups: 0,
          conversationsStarted: 0,
          reviewRating: 4.5,
          reviewCount: null,
          campuses: ['가람대'],
          profileCompletionPercent: 40,
        )),
      );
      await tester.ensureVisible(strip());
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('4.5'), findsOneWidget);
      expect(find.textContaining('명 평가'), findsNothing);
      expect(find.text('CampusMate 가 마음에 드셨나요?'), findsNothing);
      expect(find.text('리뷰 남기기'), findsOneWidget);
    });

    testWidgets('스토어 주소가 없는 플랫폼(웹 · 데스크톱)이면 띠를 그리지 않는다 — 링크 칸 아래 24 에 참여 대학', (tester) async {
      penFrame(tester);
      await pump(tester, overrides: [storeListingProvider.overrideWithValue(const StoreListing(null))]);
      await tester.ensureVisible(find.text('참여 중인 대학'));
      await tester.pump(const Duration(seconds: 1));

      expect(strip(), findsNothing);
      expect(find.text('리뷰 남기기'), findsNothing);
      expect(tester.getRect(find.text('참여 중인 대학')).top - tester.getRect(find.byType(HomeGrid)).bottom, 24);
    });
  });

  testWidgets('버튼 글자 — 히어로 `YiLtq` 18/700', (tester) async {
    penFrame(tester);
    await pump(tester);

    final hero = tester.widget<Text>(find.text('지금 확인하기')).style!;
    expect((hero.fontSize, hero.fontWeight), (18, FontWeight.w700));
  });

  group('배너 슬라이드(홈 v3 `kkKiZ` — 사람 줄 아래 24 · 링크 칸 위 24)', () {
    testWidgets('서버가 배너를 주면 사람 줄 → 24 → 배너 → 24 → 링크 칸 순서로 놓는다', (tester) async {
      penFrame(tester);
      await pump(tester, result: const Success(withBanners));

      final rail = tester.getRect(find.byType(MosaicRail));
      final carousel = tester.getRect(find.byType(HomeBannerCarousel));
      final grid = tester.getRect(find.byType(HomeGrid));
      expect(tester.widget<HomeBannerCarousel>(find.byType(HomeBannerCarousel)).banners, banners);
      expect(carousel.top - rail.bottom, 24);
      expect(carousel.width, 328);
      expect(grid.top - carousel.bottom, 24);
    });

    testWidgets('배너가 없으면(옛 서버 · 빈 목록) 칸을 앞뒤 간격째 뺀다 — 사람 줄 아래 24 에 링크 칸', (tester) async {
      penFrame(tester);
      await pump(tester);

      expect(find.byType(HomeBannerCarousel), findsNothing);
      expect(tester.getRect(find.byType(HomeGrid)).top - tester.getRect(find.byType(MosaicRail)).bottom, 24);
    });
  });

  testWidgets('campus-strip 은 저장소의 대학을 태그 하나씩 보여준다', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('참여 중인 대학'), 200, scrollable: _mainList);

    expect(find.text('가람대'), findsOneWidget);
    expect(find.text('새솔대'), findsOneWidget);
    // pen `zOaUW` 은 태그를 한 줄에 옆으로 늘어놓는다 — 태그가 폭을 다 먹으면 세로로 쌓인다.
    expect(tester.getTopLeft(find.text('새솔대')).dy, tester.getTopLeft(find.text('가람대')).dy);
  });

  group('campus-strip 내 학교(pen `zOaUW` · `T2Pfi4`)', () {
    testWidgets('내 학교 칩이 맨 앞 · primary-wash 채움 · primary-text 글자, 나머지는 surface-soft · body', (tester) async {
      penFrame(tester);
      await pump(tester, me: Success(_me('새솔대')));

      final tags = tester.widgetList<Tag>(find.byType(Tag)).map((t) => t.label).toList();
      expect(tags, ['새솔대', '가람대']);
      Container chip(String label) =>
          tester.widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
      expect((chip('새솔대').decoration! as BoxDecoration).color, const Color(0xFFFFF0F2));
      expect(tester.widget<Text>(find.text('새솔대')).style!.color, const Color(0xFFC4224B));
      expect((chip('가람대').decoration! as BoxDecoration).color, const Color(0xFFF7F7F7));
      expect(tester.widget<Text>(find.text('가람대')).style!.color, const Color(0xFF3F3F3F));
    });

    testWidgets('색만으로 가르지 않는다 — 스크린리더는 "내 학교" 를 같이 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      penFrame(tester);
      await pump(tester, me: Success(_me('새솔대')));

      // 목록 칸 글자는 한 의미 노드로 합쳐진다 — "내 학교" 가 한 번, 내 학교 이름 바로 앞에만 붙는다.
      final label = tester.getSemantics(find.bySemanticsLabel(RegExp('내 학교'))).label;
      handle.dispose();
      expect('내 학교'.allMatches(label).length, 1);
      expect(label, contains('내 학교\n새솔대'));
      expect(label, isNot(contains('내 학교\n가람대')));
    });

    testWidgets('내 프로필을 못 읽었으면 저장소 순서 그대로, 강조 없음', (tester) async {
      penFrame(tester);
      await pump(tester);

      expect(tester.widgetList<Tag>(find.byType(Tag)).map((t) => (t.label, t.mine)), [('가람대', false), ('새솔대', false)]);
    });
  });

  // 참여 대학 칩 줄(pen `yo9JJ`) — 칩이 5개 이상이면 사람 레일과 같은 규칙으로 흐른다(사용자 지시 10-15, [AutoMarquee]).
  group('campus-strip 자동 흐름(칩 5개 이상)', () {
    const five = ['가람대', '새솔대', '누리대', '한빛대', '다온대'];
    HomeSummary withCampuses(List<String> campuses) => HomeSummary(
          deliveredCards: summary.deliveredCards,
          signups: summary.signups,
          conversationsStarted: summary.conversationsStarted,
          reviewRating: summary.reviewRating,
          reviewCount: summary.reviewCount,
          campuses: campuses,
          profileCompletionPercent: summary.profileCompletionPercent,
        );

    /// 칩 줄이 유리 내비 위로 오게 조금 올린다(끝을 넘겨 늘어나지 않을 만큼).
    Future<void> showStrip(WidgetTester tester, List<String> campuses, {Result<MyProfile>? me}) async {
      penFrame(tester);
      await pump(tester, result: Success(withCampuses(campuses)), me: me ?? const FailureResult(NetworkFailure()));
      await tester.drag(_mainList, const Offset(0, -150));
      await tester.pump(const Duration(seconds: 1));
    }

    /// 멈춰 있을 때 x16(본문 왼쪽)에 오는 둘째 벌의 첫 칩 자리.
    double chipX(WidgetTester tester, String label) {
      final copies = find.text(label);
      return tester.getTopLeft(copies.evaluate().length > 1 ? copies.at(1) : copies).dx;
    }

    void reduceMotion(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    testWidgets('5개면 시간이 지나면 오른쪽으로 흐른다 · 칩 줄 높이 28 그대로', (tester) async {
      await showStrip(tester, five);
      final before = chipX(tester, five.first);

      await tester.pump(const Duration(seconds: 1));

      expect(chipX(tester, five.first), greaterThan(before));
      expect(find.byType(AutoMarquee), findsNWidgets(2)); // 사람 레일 + 칩 줄
      final strip = find.ancestor(of: find.text(five.first).first, matching: find.byType(AutoMarquee));
      expect(tester.getSize(strip).height, 28);
      expect(tester.getSize(strip).width, 328);
    });

    testWidgets('4개면 흐르지 않고 지금 모양(줄바꿈 칩 줄) 그대로다', (tester) async {
      await showStrip(tester, five.take(4).toList());
      final before = chipX(tester, five.first);

      await tester.pump(const Duration(seconds: 1));

      expect(chipX(tester, five.first), before);
      expect(find.text(five.first), findsOneWidget);
      expect(find.ancestor(of: find.text(five.first), matching: find.byType(Wrap)), findsOneWidget);
      expect(find.byType(AutoMarquee), findsOneWidget); // 사람 레일만
    });

    testWidgets('기기 "동작 줄이기" 면 5개여도 저절로 흐르지 않는다', (tester) async {
      reduceMotion(tester);
      await showStrip(tester, five);
      final before = chipX(tester, five.first);

      await tester.pump(const Duration(seconds: 1));

      expect(chipX(tester, five.first), before);
    });

    testWidgets('누르고 있으면 멈추고, 떼면 다시 흐른다', (tester) async {
      await showStrip(tester, five);
      final gesture = await tester.startGesture(tester.getCenter(find.text(five[2]).at(1)));
      await tester.pump(const Duration(milliseconds: 100));
      final held = chipX(tester, five.first);

      await tester.pump(const Duration(seconds: 1));
      expect(chipX(tester, five.first), held);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(chipX(tester, five.first), greaterThan(held));
    });

    testWidgets('화면 읽기는 칩 목록을 한 번만 읽고, 내 학교는 맨 앞에서 "내 학교" 와 함께 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await showStrip(tester, five, me: Success(_me('다온대')));

      expect(tester.widgetList<Tag>(find.byType(Tag)).first.label, '다온대');
      final label = tester.getSemantics(find.bySemanticsLabel(RegExp('내 학교'))).label;
      expect('내 학교'.allMatches(label).length, 1);
      for (final campus in five) {
        expect(campus.allMatches(label).length, 1, reason: campus);
      }
      handle.dispose();
    });

    testWidgets('글자 2배에서도 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await showStrip(tester, five);
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('mosaic-rail 은 사람 수만큼 칸 뒤에 빈 칸 하나를 붙인 한 벌을 되풀이한다', (tester) async {
    await pump(tester);

    expect(find.text('지금 함께 있는 사람들'), findsOneWidget);
    final people = find.byType(MosaicPersonTile).evaluate().length;
    final empties = find.byType(MosaicEmptyTile).evaluate().length;
    expect(empties, greaterThanOrEqualTo(2));
    expect(people, 2 * empties);
  });

  group('mosaic-rail 사람 칸은 요약과 따로 받는다(`GET /home/people`)', () {
    List<Uint8List> drawn(WidgetTester tester) => [
          for (final element in find.byType(MosaicPersonTile).evaluate()) (element.widget as MosaicPersonTile).image,
        ];

    testWidgets('서버가 준 그림을 사람 칸으로 그린다(한 벌 = 받은 그림 + 빈 칸)', (tester) async {
      await pump(tester);

      final copies = find.byType(MosaicEmptyTile).evaluate().length;
      expect(drawn(tester), [for (var i = 0; i < copies; i++) ...twoPeople.map((image) => image)]);
    });

    testWidgets('서버가 빈 목록(인원 부족)이면 레일을 숨기지 않고 토끼 마스코트 칸만(없는 사람 그림 없음, 사용자 11-13), 자리는 pen 그대로', (tester) async {
      penFrame(tester);
      await pump(tester, home: FakeHomeRepository(const Success(summary), people: const Success(HomePeople.none)));

      // 보여 줄 사람이 없는데 "함께 있는 사람들" 이라 하지 않게 제목도 바꾼다.
      expect(find.text('곧 더 많은 사람들이 모여요'), findsOneWidget);
      expect(find.text('지금 함께 있는 사람들'), findsNothing);
      expect(find.byType(MosaicPersonTile), findsNothing);
      expect(find.byType(MosaicEmptyTile), findsNothing);
      expect(find.byType(MosaicMascotTile), findsWidgets);
      expect(find.descendant(of: find.byType(MosaicRail), matching: find.byType(ImageFiltered)), findsNothing);
      expect((tester.getRect(find.byType(MosaicRail)).top, tester.getRect(find.byType(MosaicRail)).bottom), (283, 423));
      // 못 받았거나 빈 목록이면 5분 붙잡기 타이머가 걸린다 — 테스트가 끝나기 전에 흘려 보낸다.
      await tester.pump(homePeopleRetryAfter);
    });

    testWidgets('사람 칸을 못 받아도 레일은 기본 그림 칸으로 서 있고, 다른 블록은 그대로다', (tester) async {
      await pump(tester, home: FakeHomeRepository(const Success(summary), people: const FailureResult(NetworkFailure())));

      expect(find.byType(MosaicMascotTile), findsWidgets);
      expect(find.byType(MosaicPersonTile), findsNothing);
      expect(find.text('곧 더 많은 사람들이 모여요'), findsOneWidget);
      expect(find.byType(HomeGrid), findsOneWidget);
      await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);
      expect(find.text('참여 중인 대학'), findsOneWidget);
      // 못 받았거나 빈 목록이면 5분 붙잡기 타이머가 걸린다 — 테스트가 끝나기 전에 흘려 보낸다.
      await tester.pump(homePeopleRetryAfter);
    });

    testWidgets('받는 동안은 기본 그림 칸이고, 도착하면 서버 그림으로 바뀐다 — 요약은 기다리지 않는다', (tester) async {
      final home = FakeHomeRepository(const Success(summary))..holdPeople = Completer<void>();
      await pump(tester, home: home);

      expect(find.byType(HomeGrid), findsOneWidget);
      expect(find.byType(MosaicMascotTile), findsWidgets);
      expect(find.byType(MosaicPersonTile), findsNothing);
      expect(find.text('곧 더 많은 사람들이 모여요'), findsOneWidget);

      home.holdPeople!.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byType(MosaicMascotTile), findsNothing);
      expect(find.text('지금 함께 있는 사람들'), findsOneWidget, reason: '실제 사람 칸이 나오면 원래 제목');
      expect(find.text('곧 더 많은 사람들이 모여요'), findsNothing);
      expect(drawn(tester), isNotEmpty);
    });

    testWidgets('요약을 못 받으면(학교가 열렸는지 모른다) 사람 칸도 아직 부르지 않고, 요약이 오면 그때 받아 그린다', (tester) async {
      final home = FakeHomeRepository(const FailureResult(NetworkFailure()));
      await pump(tester, home: home);
      expect(find.byType(MosaicRail), findsNothing);
      expect(home.peopleCalls, 0);

      home.summary = const Success(summary);
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen))).invalidate(homeSummaryProvider);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // 요약을 그린 프레임에서 사람 칸을 부르기 시작해 다음 프레임에 그린다.
      await tester.pump();

      expect(drawn(tester), isNotEmpty);
      expect(home.peopleCalls, 1);
    });

    testWidgets('학교 대기(19 코호트) 사용자는 `/home/people` 을 부르지 않는다', (tester) async {
      final home = FakeHomeRepository(Success(HomeSummary(
        deliveredCards: summary.deliveredCards,
        signups: summary.signups,
        conversationsStarted: summary.conversationsStarted,
        reviewRating: summary.reviewRating,
        reviewCount: summary.reviewCount,
        campuses: summary.campuses,
        profileCompletionPercent: summary.profileCompletionPercent,
        cohort: CohortWait(firstCardAt: DateTime.now().add(const Duration(days: 3)), recruitCount: 5),
      )));
      await pump(tester, home: home);

      expect(find.byType(CohortWaitView), findsOneWidget);
      expect(home.peopleCalls, 0);
    });

    testWidgets('못 받았으면 기본 그림 칸 — 5분 뒤 다른 탭에 갔다 홈에 돌아오면 다시 받아 서버 그림을 그린다', (tester) async {
      final home = FakeHomeRepository(const Success(summary), people: const FailureResult(NetworkFailure()));
      await pump(tester, home: home);
      expect(find.byType(MosaicMascotTile), findsWidgets);

      router.go(AppRoutes.today);
      await tester.pump();
      home.people = Success(twoPeople);
      await tester.pump(const Duration(minutes: 5));
      router.go(AppRoutes.home);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(home.peopleCalls, 2);
      expect(find.byType(MosaicMascotTile), findsNothing);
      expect(drawn(tester), isNotEmpty);
    });
  });

  testWidgets('mosaic-rail 머리줄에 "일시정지"(pen `Ab3td` 오른쪽)는 없다 — 사용자 결정 2026-09-26', (tester) async {
    await pump(tester);

    expect(find.text('일시정지'), findsNothing);
    expect(find.byIcon(AppIcons.pause), findsNothing);
  });

  testWidgets('빈 칸은 바탕이 비어 있어도 칸 전체가 눌린다 — 누르면 레일이 멈춰야 한다', (tester) async {
    await pump(tester);

    // 화면 안에 든 빈 칸의 글자 밖(왼쪽 위 모서리 안쪽)을 누른다.
    final rail = tester.getRect(find.byType(MosaicRail));
    final empties = find.byType(MosaicEmptyTile);
    final visible = [
      for (var i = 0; i < empties.evaluate().length; i++) empties.at(i),
    ].firstWhere((tile) => tester.getRect(tile).left >= rail.left && tester.getRect(tile).right <= rail.right);
    final tilePaint = tester.renderObject(find.descendant(of: visible, matching: find.byType(CustomPaint)).first);
    final path = tester.hitTestOnBinding(tester.getRect(visible).topLeft + const Offset(4, 4)).path;
    expect(path.map((entry) => entry.target), contains(same(tilePaint)));
  });

  testWidgets('빈 칸 `FqMYC` — 마스코트 없음 · 바탕 없음 · 1px 점선 테두리 · "아직 비어 있어요" 12 #6A6A6A 가운데(x8 y62 96×16)', (tester) async {
    await pump(tester);

    final tile = find.byType(MosaicEmptyTile).first;
    expect(find.descendant(of: tile, matching: find.byType(Image)), findsNothing);
    final paint = tester.widget<CustomPaint>(find.descendant(of: tile, matching: find.byType(CustomPaint)).first);
    expect(paint.foregroundPainter, isNotNull);
    final text = find.descendant(of: tile, matching: find.text('아직 비어 있어요'));
    // 테스트 글꼴은 한글 한 자가 1em 이라 96 폭에서 두 줄로 접힌다(Pretendard 는 한 줄 y62 높이 16) — 가로 자리 · 세로 가운데만 본다.
    final rect = tester.getRect(text).shift(-tester.getTopLeft(tile));
    expect((rect.left, rect.width, rect.center.dy), (8, 96, 70));
    expect(tester.widget<Text>(text).style!.height! * 12, 16);
    expect(tester.getSize(tile), const Size(112, 140));
    final style = tester.widget<Text>(text).style!;
    expect((style.fontSize, style.color), (12, const Color(0xFF6A6A6A)));
    expect(tester.widget<Text>(text).textAlign, TextAlign.center);
  });

  group('mosaic-rail 자동 흐름', () {
    double railX(WidgetTester tester) => tester.getTopLeft(find.byType(MosaicPersonTile).first).dx;

    testWidgets('시간이 지나면 칸이 오른쪽으로 움직인다', (tester) async {
      await pump(tester);
      final before = railX(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(railX(tester), greaterThan(before));
    });

    testWidgets('누르고 있으면 멈추고, 떼면 다시 흐른다', (tester) async {
      await pump(tester);
      // 칸 위를 누른다 — 레일이 흘러 있어 가운데가 칸 사이 틈(10)일 수 있다.
      final rail = tester.getRect(find.byType(MosaicRail));
      final tile = [
        for (var i = 0; i < find.byType(MosaicPersonTile).evaluate().length; i++)
          tester.getRect(find.byType(MosaicPersonTile).at(i)),
      ].firstWhere((rect) => rect.left >= rail.left && rect.right <= rail.right);
      final gesture = await tester.startGesture(tile.center);
      await tester.pump(const Duration(milliseconds: 100));
      final held = railX(tester);

      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), held);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), greaterThan(held));
    });

    testWidgets('두 손가락 중 하나만 떼면 여전히 멈춰 있다', (tester) async {
      // 레일만 띄운다. 홈 목록 안에서는 첫 손가락이 목록 끌기를 시작해 목록이 자식을 IgnorePointer 로
      // 막으므로 둘째 손가락이 레일에 닿지 않는다(Flutter DragScrollActivity.shouldIgnorePointer) — 위젯 약속으로 고정한다.
      await tester.pumpWidget(
        MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: MosaicRail(people: twoPeople))),
      );
      final center = tester.getCenter(find.byType(MosaicRail));
      final first = await tester.startGesture(center);
      final second = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await second.up();
      await tester.pump();
      final held = railX(tester);

      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), held);

      await first.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(railX(tester), greaterThan(held));
    });

    testWidgets('움직이는 칸 묶음은 RepaintBoundary 안에 있다 — 매 프레임 옮기기만 하고 다시 그리지 않는다', (tester) async {
      await pump(tester);

      final boundary = find.descendant(
        of: find.descendant(of: find.byType(MosaicRail), matching: find.byType(Transform)),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundary, findsOneWidget);
      expect(tester.widget<RepaintBoundary>(boundary).child, isA<IntrinsicHeight>());
    });

    testWidgets('화면 읽기는 되풀이한 칸을 한 벌만 읽는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      // 목록 칸 글자는 한 의미 노드로 합쳐진다 — 그 안에 빈 칸 글자가 한 번만 있어야 한다.
      final label = tester.getSemantics(find.bySemanticsLabel(RegExp('아직 비어 있어요'))).label;
      semantics.dispose();
      expect('아직 비어 있어요'.allMatches(label).length, 1);
    });

    testWidgets('기기 "애니메이션 줄이기"가 켜져 있으면 흐르지 않는다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pump(tester);
      final before = railX(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(railX(tester), before);
    });
  });

  // 완성도 카드는 10-15 에 잠깐 뺐다가 사용자 요청으로 되살렸다(pen `xEpOD` / `e26o6` Profile Completion Banner) — 참여 대학 아래.
  // 완성도 카드 칩 판(2026-11-15 사용자 「~더 채우기 칩 모양으로 간략하게」 · 「칩은 "사진 더 채우기"」, pen 시안 A `TdmIQ`).
  group('프로필 완성도 카드(칩 판)', () {
    const all = ProfileCompletionItem.values;
    const chipTexts = ['사진 더 채우기', 'MBTI 채우기', '선호 키 채우기', '관심 태그 채우기'];
    Finder card() => find.byKey(homeProfileNudgeKey);

    Future<void> pumpNudge(WidgetTester tester, List<ProfileCompletionItem> missing) async {
      penFrame(tester);
      await pump(tester, result: Success(summaryWith(missing: missing)));
      await tester.ensureVisible(card());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('"프로필 완성도 N%" 14/700 ink + chevron 20 · 게이지 6(안쪽 폭 전체) · 안 채운 항목 칩, 종전 두 줄 문구는 없다', (tester) async {
      await pumpNudge(tester, all);

      final title = tester.widget<Text>(find.text('프로필 완성도 40%')).style!;
      expect((title.fontSize, title.fontWeight, title.color), (14, FontWeight.w700, AppColors.ink));
      final chevron = tester.widget<Icon>(find.descendant(of: card(), matching: find.byIcon(AppIcons.chevronRight)));
      expect((chevron.size, chevron.color), (20.0, AppColors.primaryText));
      for (final text in chipTexts) {
        expect(find.descendant(of: card(), matching: find.text(text)), findsOneWidget, reason: text);
      }
      expect(find.text('프로필을 조금 더 채우면'), findsNothing);
      expect(find.text('나를 더 잘 보여 줄 수 있어요'), findsNothing);
      final gauge = tester.getRect(find.byKey(homeProfileGaugeKey));
      final rect = tester.getRect(card());
      expect((gauge.height, gauge.width), (6.0, 328 - 14 * 2));
      expect((gauge.left - rect.left, rect.right - gauge.right), (14, 14));
    });

    testWidgets('카드 — primary-wash · 모서리 24 · 안쪽 위 12 · 줄 사이 8, 참여 대학 칩 아래 24', (tester) async {
      await pumpNudge(tester, all);

      final box = tester.widget<Container>(card()).decoration! as BoxDecoration;
      expect((box.color, box.borderRadius), (AppColors.primaryWash, BorderRadius.circular(24)));
      final rect = tester.getRect(card());
      final chevron = tester.getRect(find.descendant(of: card(), matching: find.byIcon(AppIcons.chevronRight)));
      final gauge = tester.getRect(find.byKey(homeProfileGaugeKey));
      final firstChip = tester.getRect(find.ancestor(of: find.text(chipTexts.first), matching: find.byType(Container)).first);
      expect(chevron.top - rect.top, 12);
      expect(gauge.top - chevron.bottom, 8);
      expect(firstChip.top - gauge.bottom, 8);
      expect(rect.left, 16);
      expect(rect.top - tester.getBottomLeft(find.byType(Tag).last).dy, 24);
    });

    testWidgets('칩 — 높이 28 · 알약 · 좌우 10 · 흰 바탕 · 12/400 primaryText, 가로 · 줄 사이 6', (tester) async {
      await pumpNudge(tester, all);

      final chips = [
        for (final text in chipTexts) find.ancestor(of: find.text(text), matching: find.byType(Container)).first,
      ];
      for (final (i, chip) in chips.indexed) {
        final box = tester.widget<Container>(chip).decoration! as BoxDecoration;
        expect((box.color, box.borderRadius), (AppColors.canvas, BorderRadius.circular(9999)), reason: chipTexts[i]);
        expect(tester.getSize(chip).height, 28, reason: chipTexts[i]);
        final text = tester.getRect(find.text(chipTexts[i]));
        expect(text.left - tester.getRect(chip).left, 10, reason: chipTexts[i]);
        final style = tester.widget<Text>(find.text(chipTexts[i])).style!;
        expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, AppColors.primaryText));
      }
      final first = tester.getRect(chips[0]);
      final second = tester.getRect(chips[1]);
      expect(second.left - first.right, 6);
      final wrap = tester.widget<Wrap>(find.descendant(of: card(), matching: find.byType(Wrap)));
      expect((wrap.spacing, wrap.runSpacing), (6, 6));
    });

    testWidgets('칩 2개는 한 줄 — 카드 94(12 + 20 + 8 + 6 + 8 + 28 + 12)', (tester) async {
      await pumpNudge(tester, const [ProfileCompletionItem.mbti, ProfileCompletionItem.interestTags]);

      expect(find.text('MBTI 채우기'), findsOneWidget);
      expect(find.text('관심 태그 채우기'), findsOneWidget);
      expect(find.text('사진 더 채우기'), findsNothing);
      expect(tester.getSize(card()), const Size(328, 94));
    });

    testWidgets('칩 4개는 360 폭에서 두 줄 — 카드 128(94 + 6 + 28)', (tester) async {
      await pumpNudge(tester, all);

      expect(tester.getSize(card()).height, 128);
    });

    testWidgets('목록이 비면(옛 서버 · 다 채움) 칩 줄과 그 위 간격이 없다 — 카드 58(12 + 20 + 8 + 6 + 12)', (tester) async {
      await pumpNudge(tester, const []);

      expect(find.descendant(of: card(), matching: find.byType(Wrap)), findsNothing);
      expect(tester.getSize(card()).height, 58);
    });

    testWidgets('화면 읽기는 카드 하나로 "프로필 완성도 N%, 더 채울 수 있는 것: …" 을 읽고 칩을 따로 읽지 않는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpNudge(tester, const [ProfileCompletionItem.photos, ProfileCompletionItem.mbti]);

      final data = tester.getSemantics(card()).getSemanticsData();
      expect(data.label, '프로필 완성도 40%, 더 채울 수 있는 것: 사진 더 채우기, MBTI 채우기');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(find.bySemanticsLabel('사진 더 채우기'), findsNothing);
      handle.dispose();
    });

    testWidgets('목록이 비면 화면 읽기는 "프로필 완성도 N%" 만 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpNudge(tester, const []);

      expect(tester.getSemantics(card()).getSemanticsData().label, '프로필 완성도 40%');
      handle.dispose();
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale — 칩 · 카드가 늘어나고 넘치거나 잘리지 않는다', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpNudge(tester, all);

        expect(tester.takeException(), isNull);
        for (final text in chipTexts) {
          final chip = find.ancestor(of: find.text(text), matching: find.byType(Container)).first;
          expect(tester.getRect(chip).contains(tester.getCenter(find.text(text))), isTrue, reason: text);
          expect(tester.getSize(find.text(text)).height, lessThanOrEqualTo(tester.getSize(chip).height), reason: text);
        }
        expect(tester.getSize(card()).height, greaterThan(128));
      });
    }
  });

  testWidgets('완성도가 100 이면 완성도 카드를 숨긴다', (tester) async {
    await pump(tester, result: Success(summaryWith(percent: 100)));
    await tester.scrollUntilVisible(find.text('참여 중인 대학'), 200, scrollable: _mainList);
    await tester.drag(_mainList, const Offset(0, -500));
    await tester.pump();

    expect(find.textContaining('프로필 완성도'), findsNothing);
    expect(find.byKey(homeProfileNudgeKey), findsNothing);
  });

  group('카드형 누름 반응(DESIGN §7 press)', () {
    testWidgets('완성도 카드 · "리뷰 남기기" 는 Pressable 이다 — 누르는 동안 투명도만 내려간다', (tester) async {
      penFrame(tester);
      await pump(tester);
      // 리뷰 띠가 돌아와 완성도 카드가 유리 내비 아래에 있다 — 끝까지 바로 옮겨 알약 위로 꺼낸다(끌면 당김 늘어남이 치수를 바꾼다).
      final position = tester.state<ScrollableState>(_mainList).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump(const Duration(seconds: 1));

      for (final text in ['리뷰 남기기', '프로필 완성도 40%']) {
        final pressable = find.ancestor(of: find.text(text), matching: find.byType(Pressable));
        expect(pressable, findsOneWidget, reason: text);
        final rect = tester.getRect(find.text(text));
        final gesture = await tester.startGesture(tester.getCenter(find.text(text)));
        await tester.pump(const Duration(milliseconds: 200));
        final opacity = tester.widget<AnimatedOpacity>(find.descendant(of: pressable, matching: find.byType(AnimatedOpacity)));
        expect(opacity.opacity, Pressable.pressedOpacity, reason: text);
        expect(tester.getRect(find.text(text)), rect, reason: text);
        await gesture.cancel();
        await tester.pump(const Duration(milliseconds: 200));
      }
    });
  });

  group('요약 블록 도착(DESIGN §7 standard)', () {
    testWidgets('처음 받을 때 블록마다 투명 · 아래 8 에서 40ms 간격으로 올라온다', (tester) async {
      penFrame(tester);
      await pump(tester, settle: false);

      final entrances = tester.widgetList<Entrance>(find.byType(Entrance)).toList();
      // 레일 · 링크 칸 · 리뷰 띠 · 참여 대학 · 완성도 카드 다섯 블록(시안 A `TdmIQ` — 배너 없는 요약, 숫자 칸은 빠졌다).
      expect(
        entrances.map((e) => (e.rise, e.delay, e.duration, e.curve, e.enabled)),
        [
          for (var i = 0; i < 5; i++)
            (8.0, Duration(milliseconds: 40 * i), AppMotion.standard, AppMotion.standardCurve, true),
        ],
      );
      final tile = find.byType(HomeGrid);
      expect(tester.getTopLeft(tile).dy, 447 + 8);

      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopLeft(tile).dy, 447);
    });

    testWidgets('이미 받아 둔 요약으로 홈에 다시 오면 움직이지 않는다', (tester) async {
      penFrame(tester);
      await pump(tester);

      router.go(AppRoutes.today);
      await tester.pumpAndSettle();
      router.go(AppRoutes.home);
      await tester.pump();
      await tester.pump();

      expect(tester.widgetList<Entrance>(find.byType(Entrance)).map((e) => e.enabled), everyElement(isFalse));
    });
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다. 링크 칸(배너 있음 · 없음), hero 세 상태를 본다.
  final layouts = <String, (HomeSummary, Result<TodayCards>)>{
    '링크 2칸': (summary, _arrived),
    '배너 있음': (withBanners, _arrived),
    'hero 결정 대기': (
      summary,
      const Success(TodayCards(cards: [DailyCard(cardId: 'paid', source: CardSource.purchased, profile: _cardProfile)])),
    ),
    'hero 확인 완료': (summary, Success(TodayCards(cards: const [], nextIssueAt: DateTime.now().add(const Duration(hours: 9))))),
  };
  for (final MapEntry(key: layout, value: (data, today)) in layouts.entries) {
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('[$layout] pen 프레임 크기(360×884)·글자 배율 $scale 에서 어느 줄도 넘치지 않는다', (tester) async {
      // 테스트 글꼴은 한글이 Pretendard 보다 넓다 — 여기서 버티면 실제 폰에서도 버틴다.
      tester.view.physicalSize = const Size(360, 884);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester, result: Success(data), today: today);
      if (scale == 1.0) {
        expect(tester.getSize(_heroSwitcher).height, 160);
      }
      await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('[$layout] 글자 배율 2.0 에서 본문 글자가 고정 상자에 잘리지 않는다', (tester) async {
    // 넘침 오류는 Flex 만 낸다 — SizedBox·Container 높이에 갇힌 글자는 오류 없이 잘린다.
    tester.view.physicalSize = const Size(360, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 앱바·내비까지 화면 전체를 본다. 내비 "커뮤니티" 는 칸 폭 안에서 일부러 말줄임한다.
    List<String> clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.text.toPlainText() != '커뮤니티' &&
                (p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                    p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
          p.text.toPlainText(),
    ];

    await pump(tester, result: Success(data), today: today);
    final clipped = clippedTexts();
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);
    clipped.addAll(clippedTexts());
    // 넘침은 위 배율 테스트가 본다 — 여기서는 잘림만 본다.
    tester.takeException();

    expect(clipped, isEmpty);
  });
  }

  // 시안 A `TdmIQ`(11-16): hero → 24 → 레일 제목(25) → 10 → 레일 → 24 → [배너] → 24 → 링크 칸(328×80) → 24 → 리뷰 띠(64) → 24 →
  // 참여 대학 제목(25) → 8 → 칩 → 24 → 완성도 카드. 숫자 3칸은 사용자 결정(11-12)으로 뺐다.
  testWidgets('블록 사이 — hero 아래 24 에 레일 제목 · 블록마다 24 · 대학 제목 아래 8 에 칩 · 칩 아래 24 에 완성도 카드', (tester) async {
    penFrame(tester);
    await pump(tester);

    final hero = tester.getRect(heroFrame());
    final railTitle = tester.getRect(find.text('지금 함께 있는 사람들'));
    final rail = tester.getRect(find.byType(MosaicRail));
    final grid = tester.getRect(find.byType(HomeGrid));
    final campusTitle = tester.getRect(find.text('참여 중인 대학'));
    final tag = tester.getRect(find.byType(Tag).first);
    final card = tester.getRect(find.byKey(homeProfileNudgeKey));
    final review = tester.getRect(find.byKey(homeReviewStripKey));
    expect(railTitle.top - hero.bottom, 24);
    expect(rail.top - railTitle.bottom, 10);
    expect(grid.top - rail.bottom, 24);
    expect(grid.size, const Size(328, 80));
    expect(review.top - grid.bottom, 24);
    expect(campusTitle.top - review.bottom, 24);
    expect(tag.top - campusTitle.bottom, 8);
    expect(card.top - tester.getRect(find.byType(Tag).last).bottom, 24);
  });

  // 위 간격으로 셈한 좌표(앱바 56 포함). 배너 없음: hero 64~224 · 레일 제목 248(25) · 레일 283~423 · 링크 칸 447~527 ·
  // 리뷰 띠 551~615 · 대학 639(25) · 칩 672 · 완성도 724(칩 없는 카드 58). 배너 있음: 배너 447~647(그림 184 + 10 + 점 6) ·
  // 링크 칸 671~751 · 리뷰 띠 775 · 대학 863.
  testWidgets('좌표 — 배너 없음 · 있음', (tester) async {
    penFrame(tester);
    await pump(tester);

    expect(tester.getRect(heroFrame()), const Rect.fromLTWH(16, 64, 328, 160));
    expect(tester.getRect(find.text('지금 함께 있는 사람들')).top, 248);
    expect(tester.getSize(find.text('지금 함께 있는 사람들')).height, 25);
    expect(tester.getRect(find.byType(MosaicRail)).top, 283);
    expect(tester.getRect(find.byType(MosaicRail)).bottom, 423);
    expect(tester.getRect(find.byType(HomeGrid)), const Rect.fromLTWH(16, 447, 328, 80));
    expect(tester.getRect(find.byKey(homeReviewStripKey)), const Rect.fromLTWH(16, 551, 328, 64));
    expect(tester.getRect(find.text('참여 중인 대학')).top, 639);
    expect(tester.getRect(find.byType(Tag).first).top, 672);
    expect(tester.getRect(find.byKey(homeProfileNudgeKey)), const Rect.fromLTWH(16, 724, 328, 58));

    await pump(tester, result: const Success(withBanners));
    expect(tester.getRect(find.byType(HomeBannerCarousel)), const Rect.fromLTWH(16, 447, 328, 200));
    expect(tester.getRect(find.byType(HomeGrid)), const Rect.fromLTWH(16, 671, 328, 80));
    expect(tester.getRect(find.byKey(homeReviewStripKey)).top, 775);
    expect(tester.getRect(find.text('참여 중인 대학')).top, 863);
  });

  testWidgets('바로가기 줄은 없다 — hero 다음이 바로 레일이다(사용자 결정 10-15)', (tester) async {
    penFrame(tester);
    await pump(tester);

    for (final label in ['하트 스토어', '친구 초대', '프로필 완성', '도움말']) {
      expect(find.descendant(of: find.byType(HomeScreen), matching: find.text(label)), findsNothing, reason: label);
    }
  });

  testWidgets('섹션 제목 "지금 함께 있는 사람들" · "참여 중인 대학" 은 18/700 ink · 줄 높이 25', (tester) async {
    penFrame(tester);
    await pump(tester);

    for (final title in ['지금 함께 있는 사람들', '참여 중인 대학']) {
      final style = tester.widget<Text>(find.text(title)).style!;
      expect((style.fontSize, style.fontWeight, style.color), (18, FontWeight.w700, const Color(0xFF222222)), reason: title);
      expect(tester.getSize(find.text(title)).height, 25, reason: title);
    }
  });

  testWidgets('인스타그램 배너는 없다 — 인스타는 링크 칸(인스타그램 · 문의하기) 안에 있다', (tester) async {
    penFrame(tester);
    await pump(tester);
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

    expect(find.text('CampusMate 인스타그램'), findsNothing);
    expect(find.descendant(of: find.byType(HomeGrid), matching: find.text('인스타그램')), findsOneWidget);
  });

  testWidgets('hero `U1k8ZK` — 바탕 #FFF0F2 · 하트 장식 없음 · 마스코트 `S49nUs` x172 y-5 160×170 · 제목 #222 · 버튼 `t0Un8s` #FF385C 글자 흰색', (tester) async {
    penFrame(tester);
    await pump(tester);

    final title = find.text('오늘의 카드가');
    final hero = heroOf('오늘의 카드가');
    expect((tester.widget<Container>(hero).decoration! as BoxDecoration).color, const Color(0xFFFFF0F2));
    expect(tester.getSize(hero), const Size(328, 160));
    expect(find.descendant(of: hero, matching: find.byIcon(AppIcons.heart)), findsNothing);
    final mascot = find.descendant(of: hero, matching: find.byType(Image));
    expect((tester.widget<Image>(mascot).image as AssetImage).assetName, 'assets/images/home-top-mascot-couple.webp');
    expect(tester.getRect(mascot).shift(-tester.getTopLeft(hero)), const Rect.fromLTWH(172, -5, 160, 170));
    expect(tester.widget<Text>(title).style!.color, const Color(0xFF222222));
    expect(tester.getSize(title).height, 27);
    final button = find.ancestor(of: find.text('지금 확인하기'), matching: find.byType(Material)).first;
    expect(tester.widget<Material>(button).color, const Color(0xFFFF385C));
    expect(tester.widget<Text>(find.text('지금 확인하기')).style!.color, const Color(0xFFFFFFFF));
  });

  testWidgets('완성도 막대 `v8D23` — 흰 바탕 · 테두리 #D8C8D9 40 · 그림자 y1 blur4 #745C78 1C', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

    // 칩 판(11-16)에서 게이지는 폭 150 고정이 아니라 카드 안쪽 폭 전체다 — 색 · 테두리 · 그림자는 그대로.
    final bar = find.byKey(homeProfileGaugeKey);
    final box = tester.widget<Container>(bar).decoration! as BoxDecoration;
    expect(box.color, const Color(0xFFFFFFFF));
    // 테두리는 위에 그린다 — decoration 테두리는 Container 가 안쪽 여백으로 더해 채움 막대가 4 로 준다.
    expect((tester.widget<Container>(bar).foregroundDecoration! as BoxDecoration).border, Border.all(color: const Color(0x40D8C8D9), width: 0.5));
    expect(box.boxShadow, const [BoxShadow(color: Color(0x1C745C78), offset: Offset(0, 1), blurRadius: 4)]);
  });

  testWidgets('유리 내비(pen `xtj0K`) — 본문은 알약 뒤로 이어지고, 끝까지 내리면 완성도 카드 아래 20 에 알약(하단 여백 118 = 20 + 98)', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 20);
    addTearDown(tester.view.reset);
    await pump(tester);

    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);
    expect(tester.widget<GlassBottomNav>(find.byType(GlassBottomNav)).current, AppTab.main);
    expect(tester.getRect(_mainList).bottom, 780);
    // 레일이 계속 흘러 pumpAndSettle 은 끝나지 않는다 — 끝에 닿을 때까지 끌고, 당김 늘어남이 돌아오도록 여러 프레임을 흘린다.
    final position = tester.state<ScrollableState>(_mainList).position;
    do {
      await tester.drag(_mainList, const Offset(0, -3000));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    } while (position.pixels < position.maxScrollExtent);

    final nudge = find.byKey(homeProfileNudgeKey);
    expect(tester.getRect(find.byType(GlassBottomNav)).top - tester.getBottomLeft(nudge).dy, 20);
  });

  testWidgets('토스트는 알약 위 12 에 뜬다(본문이 알약 뒤까지 이어져도)', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 20);
    addTearDown(tester.view.reset);
    // 링크 칸을 열지 못하면 실패 토스트가 뜬다(홈 v3 — 리뷰 띠가 빠져 이 길로 토스트를 띄운다).
    await pump(tester, overrides: [openExternalUrlProvider.overrideWithValue((_) async => false)]);

    await tester.tap(find.text('인스타그램'));
    await tester.pump();

    final toast = find.byType(AppToast);
    expect(toast, findsOneWidget);
    await tester.pump(AppMotion.press); // 아래 8 에서 올라오는 움직임(D4, me_toast_test)이 끝난 자리
    expect(tester.getRect(find.byType(GlassBottomNav)).top - tester.getBottomLeft(toast).dy, 12);
  });

  // 사용자 결정(2026-11-16, 「다시 시도 + 자동」): 요약을 못 받으면 hero 아래 요약 자리에 앱 공용 작은 불러오기 실패 안내를 둔다.
  // "다시 시도" 는 다시 읽고, 앱이 다시 앞으로 오면 요약이 비어 있을 때만 다시 읽는다.
  group('요약 못 받음 — 다시 시도(RetryNotice.inline) · 앱 복귀 때 다시 읽기', () {
    final retry = find.byType(RetryNotice);
    final retryButton = find.descendant(of: retry, matching: find.byType(AppButton));

    /// AppLifecycleListener 는 한 칸씩 넘어가는 순서만 받는다 — 기기와 같은 순서로 보낸다(cohort_wait_view_test 와 같다).
    Future<void> backgroundAndResume(WidgetTester tester) async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
    }

    testWidgets('못 받으면 hero 아래 24 에 공용 실패 안내("잠시 후 다시 시도해 주세요" + 다시 시도)가 뜬다', (tester) async {
      await pump(tester, result: const FailureResult(NetworkFailure()));

      expect(retry, findsOneWidget);
      // 나 탭 · 계정 불러오기 실패와 같은 문구(검토 권고 2026-11-16) — 저장소가 실패 종류를 삼켜 일반 안내다.
      expect(find.descendant(of: retry, matching: find.text(AppLocalizationsKo().errorTryLater)), findsOneWidget);
      expect(find.descendant(of: retry, matching: find.text(AppLocalizationsKo().commonRetry)), findsOneWidget);
      expect(tester.getTopLeft(retry).dy - tester.getBottomLeft(heroFrame()).dy, 24);
      expect(find.byType(MosaicRail), findsNothing);
    });

    testWidgets('받는 중(처음)에는 안내가 없다 — 실패와 받는 중을 가른다', (tester) async {
      final home = HoldingHomeRepository(const Success(summary));
      await pump(tester, home: home, settle: false);

      expect(retry, findsNothing);
      home.release();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('"다시 시도" 는 요약을 다시 읽고, 받으면 안내가 빠지고 요약 섹션이 처음 받을 때처럼 올라온다', (tester) async {
      final home = FakeHomeRepository(const FailureResult(NetworkFailure()));
      await pump(tester, home: home);
      expect(home.calls, 1);

      home.summary = const Success(summary);
      await tester.tap(find.text(AppLocalizationsKo().commonRetry));
      await tester.pump();
      expect(home.calls, 2);
      await tester.pump(const Duration(seconds: 1));

      expect(retry, findsNothing);
      expect(find.byType(MosaicRail), findsOneWidget);
      expect(find.byType(HomeGrid), findsOneWidget);
      // 처음 받는 요약이라 블록 등장 효과가 걸린다(이미 받아 둔 요약을 다시 읽을 때와 다르다).
      expect(find.ancestor(of: find.byType(HomeGrid), matching: find.byType(Entrance)), findsOneWidget);
    });

    testWidgets('다시 읽는 동안에는 안내 자리가 그대로이고 "다시 시도" 가 도는 표시로 바뀐다(안내 ↔ 빈 화면 깜빡임 없음)', (tester) async {
      final home = HoldingHomeRepository(const FailureResult(NetworkFailure()));
      home.release();
      await pump(tester, home: home);
      expect(retry, findsOneWidget);
      final place = tester.getRect(retry);

      home.hold();
      await tester.tap(find.text(AppLocalizationsKo().commonRetry));
      await tester.pump();

      expect(retry, findsOneWidget);
      expect(tester.getRect(retry).top, place.top);
      expect(tester.widget<AppButton>(retryButton).isLoading, isTrue);
      expect(find.byType(MosaicRail), findsNothing);

      home.release();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(retry, findsOneWidget);
      expect(tester.widget<AppButton>(retryButton).isLoading, isFalse);
    });

    testWidgets('못 받은 채 앱이 다시 앞으로 오면 요약을 다시 읽어 그린다', (tester) async {
      final home = FakeHomeRepository(const FailureResult(NetworkFailure()));
      await pump(tester, home: home);
      expect(home.calls, 1);

      home.summary = const Success(summary);
      await backgroundAndResume(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(home.calls, 2);
      expect(retry, findsNothing);
      expect(find.byType(MosaicRail), findsOneWidget);
    });

    testWidgets('"다시 시도" 로 읽는 중에 앱이 다시 앞으로 와도 겹쳐 읽지 않는다', (tester) async {
      final home = HoldingHomeRepository(const FailureResult(NetworkFailure()));
      home.release();
      await pump(tester, home: home);
      expect(home.calls, 1);

      home.hold();
      await tester.tap(find.text(AppLocalizationsKo().commonRetry));
      await tester.pump();
      expect(home.calls, 2);

      await backgroundAndResume(tester);
      expect(home.calls, 2);

      home.release();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('못 받은 채 다른 탭에 갔다 홈으로 돌아오면 한 번 다시 읽어 그린다', (tester) async {
      final home = FakeHomeRepository(const FailureResult(NetworkFailure()));
      await pump(tester, home: home);
      expect(home.calls, 1);

      router.go(AppRoutes.today);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(HomeScreen), findsNothing);

      home.summary = const Success(summary);
      router.go(AppRoutes.home);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(home.calls, 2);
      expect(retry, findsNothing);
      expect(find.byType(MosaicRail), findsOneWidget);
    });

    testWidgets('요약을 받아 둔 채 다른 탭에 갔다 홈으로 돌아오면 다시 읽지 않는다', (tester) async {
      final home = FakeHomeRepository(const Success(summary));
      await pump(tester, home: home);

      router.go(AppRoutes.today);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      router.go(AppRoutes.home);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(home.calls, 1);
    });

    testWidgets('요약을 받아 둔 채 앱이 다시 앞으로 오면 다시 읽지 않는다(돈 드는 호출 없음)', (tester) async {
      final home = FakeHomeRepository(const Success(summary));
      await pump(tester, home: home);
      expect(home.calls, 1);

      await backgroundAndResume(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(home.calls, 1);
    });
  });

  testWidgets('요약을 못 받아도 hero-today 는 남고 배너 · 링크 칸 · 완성도 카드는 통째로 숨는다(요약 없이 지어내지 않는다)', (tester) async {
    await pump(tester, result: const FailureResult(NetworkFailure()));

    expect(find.text('지금 확인하기'), findsOneWidget);
    expect(find.byType(HomeBannerCarousel), findsNothing);
    expect(find.byType(HomeGrid), findsNothing);
    expect(find.textContaining('프로필 완성도'), findsNothing);
    expect(find.text('전달된 카드'), findsNothing);
    expect(find.text('인스타그램'), findsNothing);
    // 코호트인지 모르니 대기 화면도 없다 — 카드로 가는 길이 남는 쪽이 맞다(계획서 Review Focus 3).
    expect(find.byType(CohortWaitView), findsNothing);
  });

  // 출시 전 막기(사용자 결정 11-11 「대기 화면 + 설정만」) — pen `tUaGw` 는 하단 내비가 없고 앱바 `D4Q6U` 는 톱니만이다.
  group('19 코호트 — 메인 탭 안에서 바꿔 끼운다(계획서 결정 1)', () {
    HomeSummary waiting() => HomeSummary(
          deliveredCards: summary.deliveredCards,
          signups: summary.signups,
          conversationsStarted: summary.conversationsStarted,
          reviewRating: summary.reviewRating,
          reviewCount: summary.reviewCount,
          campuses: summary.campuses,
          profileCompletionPercent: summary.profileCompletionPercent,
          cohort: CohortWait(firstCardAt: DateTime.now().add(const Duration(days: 3)), recruitCount: 5),
        );

    testWidgets('cohort 가 있으면 대기 화면이 있고 09b 는 없다. 하단 내비 · 하트 칩 · 종은 없고 톱니만 있다', (tester) async {
      // 잔액을 읽어도 칩이 없어야 한다 — 못 읽어서 숨은 것과 구별한다.
      await pump(tester, result: Success(waiting()), me: Success(_me('새솔대')));

      expect(find.byType(CohortWaitView), findsOneWidget);
      expect(find.text('지금 확인하기'), findsNothing);
      expect(find.text('전달된 카드'), findsNothing);
      // 앱바 제목 `D4Q6U/PjvNd` 는 대기 화면에서 끈다(사용자 「campusmate 로고 없고」 11-11).
      expect(find.text('CampusMate'), findsNothing);
      expect(find.byType(GlassBottomNav), findsNothing);
      expect(find.byType(HeartBalanceChip), findsNothing);
      expect(find.byType(NotifyIconButton), findsNothing);
      expect(find.byTooltip('설정'), findsOneWidget);
    });

    testWidgets('톱니는 제목 없이도 앱바 오른쪽 48×48(오른쪽 여백 8) 안 settings 22 #6A6A6A 다(pen D4Q6U padding [0,8,0,20])', (tester) async {
      penFrame(tester);
      await pump(tester, result: Success(waiting()));

      expect(find.text('CampusMate'), findsNothing);
      final gear = find.byTooltip('설정');
      expect(tester.getRect(gear), const Rect.fromLTWH(304, 4, 48, 48));
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.settings));
      expect((icon.size, icon.color), (22.0, const Color(0xFF6A6A6A)));
    });

    testWidgets('톱니를 누르면 설정(16)으로 간다', (tester) async {
      await pump(tester, result: Success(waiting()));

      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();

      expect(find.text('16 설정'), findsOneWidget);
    });

    testWidgets('cohort 가 null 이면 09b 그대로다 — 제목 "CampusMate" · 하단 내비 · 하트 칩 · 종이 있고 톱니는 없다', (tester) async {
      await pump(tester, me: Success(_me('새솔대')));

      expect(find.byType(CohortWaitView), findsNothing);
      expect(find.text('CampusMate'), findsOneWidget);
      expect(find.text('지금 확인하기'), findsOneWidget);
      expect(find.byType(GlassBottomNav), findsOneWidget);
      expect(find.byType(HeartBalanceChip), findsOneWidget);
      expect(find.byType(NotifyIconButton), findsOneWidget);
      expect(find.byTooltip('설정'), findsNothing);
    });
  });

  group('앱 투어(pen 섹션 24 vfrto) — 학교가 열린 홈에 처음 왔을 때 계정마다 한 번', () {
    late FakeTourSeenStore store;
    setUp(() => store = FakeTourSeenStore());

    List<Override> tour({String? profileId = 'profile-a'}) => [
          tourSeenStoreProvider.overrideWithValue(store),
          tourAccountIdProvider.overrideWithValue(() => profileId),
        ];

    HomeSummary waiting() => HomeSummary(
          deliveredCards: summary.deliveredCards,
          signups: summary.signups,
          conversationsStarted: summary.conversationsStarted,
          reviewRating: summary.reviewRating,
          reviewCount: summary.reviewCount,
          campuses: summary.campuses,
          profileCompletionPercent: summary.profileCompletionPercent,
          cohort: CohortWait(firstCardAt: DateTime.now().add(const Duration(days: 3)), recruitCount: 5),
        );

    testWidgets('학교가 열려 있고(코호트 없음) 이 계정이 본 적 없으면 시작하고, 시작하는 순간 본 것으로 저장한다', (tester) async {
      await pump(tester, overrides: tour());

      expect(homeContainer.read(appTourViewModelProvider).active, isTrue);
      expect(store.marked, ['profile-a']);
    });

    testWidgets('이미 본 계정이면 시작하지 않는다', (tester) async {
      store = FakeTourSeenStore(seen: {'profile-a'});
      await pump(tester, overrides: tour());

      expect(homeContainer.read(appTourViewModelProvider).active, isFalse);
    });

    testWidgets('학교 오픈 전(코호트 대기)에는 시작하지 않고 본 것으로도 남기지 않는다 — 오픈 뒤 첫 홈에서 본다', (tester) async {
      await pump(tester, result: Success(waiting()), overrides: tour());

      expect(homeContainer.read(appTourViewModelProvider).active, isFalse);
      expect(store.marked, isEmpty);
    });

    testWidgets('요약을 못 받아 학교가 열렸는지 모르면 시작하지 않는다', (tester) async {
      await pump(tester, result: const FailureResult(NetworkFailure()), overrides: tour());

      expect(homeContainer.read(appTourViewModelProvider).active, isFalse);
      expect(store.marked, isEmpty);
    });

    testWidgets('투어 대상 표식 — 히어로(1단계)와 프로필 완성도 카드(2단계)', (tester) async {
      // 완성도 카드는 목록 끝이라 긴 화면에서 본다.
      tester.view.physicalSize = const Size(360, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester);

      Finder target(TourTargetId id) => find.byWidgetPredicate((w) => w is TourTarget && w.id == id);
      expect(find.descendant(of: target(TourTargetId.homeHero), matching: find.text('지금 확인하기')), findsOneWidget);
      expect(find.descendant(of: target(TourTargetId.homeProfileNudge), matching: find.text('프로필 완성도 40%')), findsOneWidget);
    });
  });
}

/// 요약 응답을 붙잡아 둘 수 있는 가짜 저장소 — [hold] 하면 [release] 할 때까지 답하지 않는다(처음엔 붙잡힌 채 시작).
class HoldingHomeRepository extends FakeHomeRepository {
  HoldingHomeRepository(super.summary);

  Completer<void>? _gate = Completer<void>();

  void hold() => _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<Result<HomeSummary>> fetchSummary() async {
    calls++;
    await _gate?.future;
    return summary;
  }
}

