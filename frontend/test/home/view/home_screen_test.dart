import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/pressable.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/home/model/cohort_wait.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/mosaic_tile.dart';
import 'package:campus_mate/home/view/notify_icon_button.dart';
import 'package:campus_mate/home/view/tag.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/view/countdown_text.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../model/fake_home_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';

/// mosaic-rail 도 가로 Scrollable 이라 세로 목록을 짚어 준다.
final _mainList = find.byType(Scrollable).first;

const _cardProfile = CardProfile(profileId: 'p', nickname: '여우비', age: 23, university: '가람대', major: '경영학과');

/// pen 기본 09b(`bpA8x`)는 hero ① 도착이다 — 오늘 탭에 무료 카드가 한 장 있다.
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

void main() {
  const summary = HomeSummary(
    presentPeopleImages: ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png'],
    deliveredCards: 1234567,
    signups: 862,
    conversationsStarted: 391,
    reviewRating: 4.6,
    reviewCount: 57,
    campuses: ['가람대', '새솔대'],
    profileCompletionPercent: 40,
  );

  HomeSummary summaryWith({int? delivered, int? signups, int? conversations, int? percent, int? reviews}) => HomeSummary(
    presentPeopleImages: summary.presentPeopleImages,
    deliveredCards: delivered ?? summary.deliveredCards,
    signups: signups ?? summary.signups,
    conversationsStarted: conversations ?? summary.conversationsStarted,
    reviewRating: summary.reviewRating,
    reviewCount: reviews ?? summary.reviewCount,
    campuses: summary.campuses,
    profileCompletionPercent: percent ?? summary.profileCompletionPercent,
  );

  late GoRouter router;

  /// [settle] 이 true 면 hero 전환 · 요약 블록 등장이 끝날 때까지 흘린다(레일은 계속 흘러 pumpAndSettle 은 못 쓴다).
  /// [cards] 를 주면 오늘 카드는 그 저장소가 답한다([today] 는 무시) — 읽는 동안 멈추거나 읽은 횟수를 볼 때.
  Future<void> pump(
    WidgetTester tester, {
    Result<HomeSummary> result = const Success(summary),
    Result<TodayCards> today = _arrived,
    FakeCardRepository? cards,
    Result<MyProfile> me = const FailureResult(NetworkFailure()),
    bool settle = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(result)),
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
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
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
        of: find.byType(AnimatedSwitcher),
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == const Color(0xFFEBEBEB),
        ),
      );

  /// 지금 hero 틀(문구가 없는 불러오는 중에도 찾는다) — AnimatedSwitcher 아래 첫 Container.
  Finder heroFrame() => find.descendant(of: find.byType(AnimatedSwitcher), matching: find.byType(Container)).first;

  group('hero-today 불러오는 중(pen `PAtO3` 09b 메인 · 불러오는 중, hero `jHiXf`)', () {
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
      // 우상단 장수 배지 `Q4nCLG` — x280 y16 32×24 · #FF385C · 알약, 숫자 11/600 흰색.
      final badge = find.ancestor(of: find.text('2'), matching: find.byType(Container)).first;
      expect(tester.getRect(badge).shift(-tester.getTopLeft(hero)), const Rect.fromLTWH(280, 16, 32, 24));
      final box = tester.widget<Container>(badge).decoration! as BoxDecoration;
      expect((box.color, box.borderRadius), (const Color(0xFFFF385C), BorderRadius.circular(9999)));
      final digit = tester.widget<Text>(find.text('2')).style!;
      expect((digit.fontSize, digit.fontWeight, digit.color), (11, FontWeight.w600, const Color(0xFFFFFFFF)));

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

      final switcher = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
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

      expect(tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration, Duration.zero);
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

  testWidgets('stat-panel 은 저장소 숫자를 세 자리 쉼표로 보여준다', (tester) async {
    await pump(tester);

    expect(find.text('1,234,567'), findsOneWidget);
    expect(find.text('862'), findsOneWidget);
    expect(find.text('391'), findsOneWidget);
    expect(find.text('전달된 카드'), findsOneWidget);
    expect(find.text('가입 수'), findsOneWidget);
    expect(find.text('시작된 대화'), findsOneWidget);
  });

  testWidgets('stat-panel — 0 인 칸은 숨기고 남은 칸이 폭을 나눈다(DESIGN §8.9 규칙 4)', (tester) async {
    penFrame(tester);
    await pump(tester, result: Success(summaryWith(delivered: 0)));

    expect(find.text('전달된 카드'), findsNothing);
    final join = find.ancestor(of: find.text('가입 수'), matching: find.byType(Container)).first;
    final chat = find.ancestor(of: find.text('시작된 대화'), matching: find.byType(Container)).first;
    expect(tester.getSize(join).width, 160);
    expect(tester.getTopLeft(chat).dx - tester.getTopRight(join).dx, 8);
  });

  testWidgets('review-strip 은 평점과 평가 수를 보여준다', (tester) async {
    penFrame(tester);
    await pump(tester);

    expect(find.text('4.6'), findsOneWidget);
    expect(find.text('(57명 평가)'), findsOneWidget);
    expect(find.text('리뷰 남기기'), findsOneWidget);
  });

  testWidgets('review-strip — 평가 수가 임계값 미만이면 위 여백까지 블록째 숨기고 숫자 칸 아래 24 에 참여 대학이 온다', (tester) async {
    penFrame(tester);
    // 서버에 아직 없는 값이라 저장소가 채우는 목값("5.0 (1명 평가)")이 이 경우다.
    await pump(tester, result: Success(summaryWith(reviews: 1)));

    expect(find.text('리뷰 남기기'), findsNothing);
    expect(find.text('(1명 평가)'), findsNothing);
    final tile = find.ancestor(of: find.text('전달된 카드'), matching: find.byType(Container)).first;
    expect(tester.getTopLeft(find.text('참여 중인 대학')).dy - tester.getBottomLeft(tile).dy, 24);
  });

  testWidgets('버튼 글자 — 히어로 `YiLtq` 18/700 · 리뷰 `ifX9K` 16/700', (tester) async {
    penFrame(tester);
    await pump(tester);

    final hero = tester.widget<Text>(find.text('지금 확인하기')).style!;
    expect((hero.fontSize, hero.fontWeight), (18, FontWeight.w700));
    final review = tester.widget<Text>(find.text('리뷰 남기기')).style!;
    expect((review.fontSize, review.fontWeight), (16, FontWeight.w700));
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

  testWidgets('mosaic-rail 은 사람 수만큼 칸 뒤에 빈 칸 하나를 붙인 한 벌을 되풀이한다', (tester) async {
    await pump(tester);

    expect(find.text('지금 함께 있는 사람들'), findsOneWidget);
    final people = find.byType(MosaicPersonTile).evaluate().length;
    final empties = find.byType(MosaicEmptyTile).evaluate().length;
    expect(empties, greaterThanOrEqualTo(2));
    expect(people, 2 * empties);
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
        const MaterialApp(home: Scaffold(body: MosaicRail(images: ['assets/images/person-f1-blind-v1.png']))),
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

  testWidgets('프로필 완성도 카드는 저장소의 퍼센트를 보여준다', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

    expect(find.text('프로필 완성도 40%'), findsOneWidget);
    // 문구는 사용자 결정 2026-09-26(pen `tV9Oa` · `KjqWO`).
    expect(find.text('프로필을 조금 더 채우면'), findsOneWidget);
    expect(find.text('나를 더 잘 보여 줄 수 있어요'), findsOneWidget);
  });

  testWidgets('완성도 카드 `usk5M` — 마스코트 없음, 글자 상자 x14 · y8.5 · 32.5 · 67.5, 높이 19 · 19 · 16(% 12 #6A6A6A, 렌더 결과), 카드 92', (tester) async {
    // 세로 좌표만 본다. 테스트 글꼴은 둘째 줄이 넓어 pen 폭(360)에서 접힌다 — 접히지 않게 화면만 넓힌다.
    tester.view.physicalSize = const Size(420, 884);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);

    final card = find.ancestor(of: find.text('프로필을 조금 더 채우면'), matching: find.byType(Container)).last;
    expect(find.descendant(of: card, matching: find.byType(Image)), findsNothing);
    final origin = tester.getTopLeft(card);
    for (final (text, y, height) in [
      ('프로필을 조금 더 채우면', 8.5, 19.0),
      ('나를 더 잘 보여 줄 수 있어요', 32.5, 19.0),
      ('프로필 완성도 40%', 67.5, 16.0),
    ]) {
      expect(tester.getTopLeft(find.text(text)).dy - origin.dy, y, reason: text);
      expect(tester.getTopLeft(find.text(text)).dx - origin.dx, 14, reason: text);
      expect(tester.getSize(find.text(text)).height, height, reason: text);
    }
    expect(tester.getSize(card).height, 92);
    final percent = tester.widget<Text>(find.text('프로필 완성도 40%')).style!;
    expect((percent.fontSize, percent.color), (12, const Color(0xFF6A6A6A)));
  });

  testWidgets('완성도가 100 이면 완성도 카드를 숨긴다', (tester) async {
    await pump(tester, result: Success(summaryWith(percent: 100)));
    await tester.scrollUntilVisible(find.text('참여 중인 대학'), 200, scrollable: _mainList);
    await tester.drag(_mainList, const Offset(0, -500));
    await tester.pump();

    expect(find.textContaining('프로필 완성도'), findsNothing);
  });

  group('카드형 누름 반응(DESIGN §7 press)', () {
    testWidgets('완성도 카드 · "리뷰 남기기" 는 Pressable 이다 — 누르는 동안 투명도만 내려간다', (tester) async {
      penFrame(tester);
      await pump(tester);

      for (final text in ['리뷰 남기기', '프로필을 조금 더 채우면']) {
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
      // 레일 · 숫자 칸 · 리뷰 띠 · 참여 대학 · 완성도 카드 다섯 블록.
      expect(
        entrances.map((e) => (e.rise, e.delay, e.duration, e.curve, e.enabled)),
        [
          for (var i = 0; i < 5; i++)
            (8.0, Duration(milliseconds: 40 * i), AppMotion.standard, AppMotion.standardCurve, true),
        ],
      );
      final tile = find.ancestor(of: find.text('전달된 카드'), matching: find.byType(Container)).first;
      final settledY = 445.0;
      expect(tester.getTopLeft(tile).dy, settledY + 8);

      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopLeft(tile).dy, settledY);
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

  group('세 숫자가 모두 0 이면 숫자 칸 대신 빈 상태 판(pen `Tklrw` · `AJVDS`)', () {
    testWidgets('세 숫자가 모두 0 이면 판이 보이고 숫자 칸은 없다', (tester) async {
      await pump(tester, result: Success(summaryWith(delivered: 0, signups: 0, conversations: 0)));

      expect(find.text('첫 기록이 쌓이는 중이에요'), findsOneWidget);
      expect(find.text('전달된 카드'), findsNothing);
      expect(find.text('가입 수'), findsNothing);
      expect(find.text('시작된 대화'), findsNothing);
      // 다른 칸은 그대로다. 판이 숫자 칸보다 높아 리뷰 줄은 스크롤해야 보인다.
      expect(find.text('지금 함께 있는 사람들'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('리뷰 남기기'), 200, scrollable: _mainList);
      expect(find.text('리뷰 남기기'), findsOneWidget);
    });

    for (final (delivered, signups, conversations, shown) in [(1, 0, 0, '전달된 카드'), (0, 1, 0, '가입 수'), (0, 0, 1, '시작된 대화')]) {
      testWidgets('하나라도 0 보다 크면 그 칸만 보여 준다 ($delivered, $signups, $conversations)', (tester) async {
        await pump(tester, result: Success(summaryWith(delivered: delivered, signups: signups, conversations: conversations)));

        expect(find.text('첫 기록이 쌓이는 중이에요'), findsNothing);
        for (final label in ['전달된 카드', '가입 수', '시작된 대화']) {
          expect(find.text(label), label == shown ? findsOneWidget : findsNothing, reason: label);
        }
      });
    }

    testWidgets('pen 값과 같다 — 판 폭은 숫자 칸 자리 그대로, 높이 124, 마스코트 72 y12 가운데, 문구 y92 높이 20', (tester) async {
      tester.view.physicalSize = const Size(360, 884);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, result: Success(summaryWith(delivered: 0, signups: 0, conversations: 0)));

      final text = find.text('첫 기록이 쌓이는 중이에요');
      final panel = find.ancestor(of: text, matching: find.byType(DecoratedBox)).first;
      final mascot = find.descendant(of: panel, matching: find.byType(Image));
      final origin = tester.getTopLeft(panel);
      expect(tester.getSize(panel), const Size(328, 124));
      expect(tester.getSize(mascot), const Size(72, 72));
      // `U3fkT0` = 마스터 `J2kzx` "Mascot Male · Blue Scarf".
      expect((tester.widget<Image>(mascot).image as AssetImage).assetName, 'assets/images/mascot-male.png');
      expect(tester.getTopLeft(mascot) - origin, const Offset(128, 12));
      expect(tester.getTopLeft(text).dy - origin.dy, 92);
      expect(tester.getSize(text).height, 20);
      final decoration = tester.widget<DecoratedBox>(panel).decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFFFFFFF));
      expect(decoration.border, Border.all(color: const Color(0xFFE9E9E9)));
      expect(decoration.borderRadius, BorderRadius.circular(12));
      final style = tester.widget<Text>(text).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, const Color(0xFF222222)));
      expect(tester.widget<Text>(text).textAlign, TextAlign.center);
    });
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다. 숫자 칸·빈 상태 판, hero 세 상태를 본다.
  final layouts = <String, (HomeSummary, Result<TodayCards>)>{
    '숫자 칸': (summary, _arrived),
    '빈 상태 판': (summaryWith(delivered: 0, signups: 0, conversations: 0), _arrived),
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
        expect(tester.getSize(find.byType(AnimatedSwitcher)).height, 160);
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

  testWidgets('pen 좌표와 같다 — hero 버튼 y150 · 숫자 칸 y445 높이 96 · 리뷰 y565 · 태그 y680 · 카드 y732(블록 사이 24)', (tester) async {
    // pen `bpA8x` 렌더 값(앱바 56 포함, 2026-10-14 다시 잼). 블록 사이 24(`X4K49Y` · `vvDYo` · `gdS3k` · `sDLEb`+`o6qaj` · `yzF6g`),
    // 글자 상자는 lineHeight 속성이 없어 렌더 결과 — hero 줄 27(`dIoz0`), 레일 제목 23(`h7wmcH`), 대학 제목 19(`YIoXQ`).
    penFrame(tester);
    await pump(tester);

    final heroButton = find.ancestor(of: find.text('지금 확인하기'), matching: find.byType(InkWell));
    expect(tester.getTopLeft(heroButton).dy, 150); // 앱바 56 + 위 여백 8 + hero 안 y20 + 글자 54 + 12
    expect(tester.getTopLeft(find.text('지금 함께 있는 사람들')).dy, 248);
    expect(tester.getSize(find.text('지금 함께 있는 사람들')).height, 23);
    expect(tester.getTopLeft(find.byType(MosaicRail)).dy, 281);
    final tile = find.ancestor(of: find.text('전달된 카드'), matching: find.byType(Container)).first;
    expect(tester.getTopLeft(tile).dy, 445);
    expect(tester.getSize(tile).height, 96);
    final review = find.ancestor(of: find.text('리뷰 남기기'), matching: find.byType(Container)).last;
    expect(tester.getTopLeft(review).dy, 565);
    expect(tester.getTopLeft(find.text('참여 중인 대학')).dy, 653);
    expect(tester.getSize(find.text('참여 중인 대학')).height, 19);
    expect(tester.getTopLeft(find.byType(Tag).first).dy, 680);
    final nudge = find.ancestor(of: find.text('프로필을 조금 더 채우면'), matching: find.byType(Container)).last;
    expect(tester.getTopLeft(nudge).dy, 732);
  });

  testWidgets('review-strip `L7wKi` — 바탕 #FFF8EC, 별은 3D 15 다섯 개(`hN4Ow` 외)', (tester) async {
    penFrame(tester);
    await pump(tester);

    final strip = find.ancestor(of: find.text('리뷰 남기기'), matching: find.byType(Container)).last;
    expect((tester.widget<Container>(strip).decoration! as BoxDecoration).color, const Color(0xFFFFF8EC));
    final stars = find.descendant(of: strip, matching: find.byType(Icon3d));
    expect(tester.widgetList<Icon3d>(stars).map((i) => (i.icon, i.size)), List.filled(5, (AppIcon3d.star, 15.0)));
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

  testWidgets('stat-panel `krua8` — 칸 바탕 한 색 #F7F7F7 · 3D 아이콘 36 y6.5 · 숫자 18/700 #222 · 라벨 12 #6A6A6A(높이 16)', (tester) async {
    await pump(tester);

    for (final (label, icon) in [
      ('전달된 카드', AppIcon3d.send),
      ('가입 수', AppIcon3d.join),
      ('시작된 대화', AppIcon3d.chat),
    ]) {
      final tile = find.ancestor(of: find.text(label), matching: find.byType(Container)).first;
      final box = tester.widget<Container>(tile).decoration! as BoxDecoration;
      expect((box.color, box.borderRadius), (const Color(0xFFF7F7F7), BorderRadius.circular(14)), reason: label);
      final icon3d = find.descendant(of: tile, matching: find.byType(Icon3d));
      expect((tester.widget<Icon3d>(icon3d).icon, tester.widget<Icon3d>(icon3d).size), (icon, 36.0), reason: label);
      // 36 칸 자리(그림만 키우는 배율은 칸 밖으로 그린다 — pen 도 칸 y6.5 에 그림 transform).
      final slot = find.ancestor(of: icon3d, matching: find.byType(Transform)).first;
      expect(tester.getTopLeft(slot).dy - tester.getTopLeft(tile).dy, 6.5, reason: label);
      final labelStyle = tester.widget<Text>(find.text(label)).style!;
      expect((labelStyle.fontSize, labelStyle.color), (12, const Color(0xFF6A6A6A)), reason: label);
      expect(tester.getSize(find.text(label)).height, 16, reason: label);
    }
    final number = tester.widget<Text>(find.text('862')).style!;
    expect((number.fontSize, number.fontWeight, number.color), (18, FontWeight.w700, const Color(0xFF222222)));
  });

  testWidgets('완성도 막대 `v8D23` — 흰 바탕 · 테두리 #D8C8D9 40 · 그림자 y1 blur4 #745C78 1C', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: _mainList);

    final bar = find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 150 && w.constraints?.maxHeight == 6);
    final box = tester.widget<Container>(bar).decoration! as BoxDecoration;
    expect(box.color, const Color(0xFFFFFFFF));
    // 테두리는 위에 그린다 — decoration 테두리는 Container 가 안쪽 여백으로 더해 채움 막대가 4 로 준다.
    expect((tester.widget<Container>(bar).foregroundDecoration! as BoxDecoration).border, Border.all(color: const Color(0x40D8C8D9)));
    expect(box.boxShadow, const [BoxShadow(color: Color(0x1C745C78), offset: Offset(0, 1), blurRadius: 4)]);
  });

  testWidgets('유리 내비(pen `xtj0K`) — 본문은 알약 뒤로 이어지고, 끝까지 내리면 완성도 카드 아래 20 에 알약(pen `eA1oQ` 하단 여백 98)', (tester) async {
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

    final nudge = find.ancestor(of: find.text('프로필을 조금 더 채우면'), matching: find.byType(Container)).last;
    expect(tester.getRect(find.byType(GlassBottomNav)).top - tester.getBottomLeft(nudge).dy, 20);
  });

  testWidgets('토스트는 알약 위 12 에 뜬다(본문이 알약 뒤까지 이어져도)', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 20);
    addTearDown(tester.view.reset);
    await pump(tester);

    // 리뷰 주소가 비어 있으면 "곧 열려요" 토스트가 뜬다.
    await tester.scrollUntilVisible(find.text('리뷰 남기기'), 200, scrollable: _mainList);
    await tester.tap(find.text('리뷰 남기기'));
    await tester.pump();

    final toast = find.byType(AppToast);
    expect(toast, findsOneWidget);
    await tester.pump(AppMotion.press); // 아래 8 에서 올라오는 움직임(D4, me_toast_test)이 끝난 자리
    expect(tester.getRect(find.byType(GlassBottomNav)).top - tester.getBottomLeft(toast).dy, 12);
  });

  testWidgets('요약을 못 받아도 hero-today 는 남는다', (tester) async {
    await pump(tester, result: const FailureResult(NetworkFailure()));

    expect(find.text('지금 확인하기'), findsOneWidget);
    expect(find.text('전달된 카드'), findsNothing);
    // 코호트인지 모르니 대기 화면도 없다 — 카드로 가는 길이 남는 쪽이 맞다(계획서 Review Focus 3).
    expect(find.byType(CohortWaitView), findsNothing);
  });

  group('19 코호트 — 메인 탭 안에서 바꿔 끼운다(계획서 결정 1)', () {
    testWidgets('cohort 가 있으면 대기 화면이 있고 09b 는 없다. 앱바 · 하단 내비는 그대로', (tester) async {
      await pump(
        tester,
        result: Success(HomeSummary(
          presentPeopleImages: summary.presentPeopleImages,
          deliveredCards: summary.deliveredCards,
          signups: summary.signups,
          conversationsStarted: summary.conversationsStarted,
          reviewRating: summary.reviewRating,
          reviewCount: summary.reviewCount,
          campuses: summary.campuses,
          profileCompletionPercent: summary.profileCompletionPercent,
          cohort: CohortWait(firstCardAt: DateTime.now().add(const Duration(days: 3)), recruitCount: 5),
        )),
      );

      expect(find.byType(CohortWaitView), findsOneWidget);
      expect(find.text('지금 확인하기'), findsNothing);
      expect(find.text('전달된 카드'), findsNothing);
      expect(find.text('CampusMate'), findsOneWidget);
      expect(find.byType(NotifyIconButton), findsOneWidget);
      expect(find.byType(GlassBottomNav), findsOneWidget);
    });

    testWidgets('cohort 가 null 이면 09b 그대로다', (tester) async {
      await pump(tester);

      expect(find.byType(CohortWaitView), findsNothing);
      expect(find.text('지금 확인하기'), findsOneWidget);
    });
  });
}
