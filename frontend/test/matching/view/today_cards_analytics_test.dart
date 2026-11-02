import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/paid_card.dart';
import 'package:campus_mate/matching/view/today_cards_screen.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../core/analytics/fake_analytics_service.dart';
import '../../home/model/fake_home_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';
import '../model/fake_card_repository.dart';

/// 사용 통계 card_view · card_detail_open · paid_card_view · paid_card_sheet_open — 오늘 탭에서 남는 이벤트.
/// 카드 id · 상대 id · 닉네임은 어느 이벤트에도 실리지 않는다(출처 free · purchased 와 칸 상태만).
const _free = DailyCard(
  cardId: 'card-free-1',
  source: CardSource.daily,
  profile: CardProfile(profileId: 'profile-secret-1', nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
);
const _bought = DailyCard(
  cardId: 'card-bought-2',
  source: CardSource.purchased,
  profile: CardProfile(profileId: 'profile-secret-2', nickname: '토끼', age: 24),
);
const _offer = PaidCardOffered(offerId: 'offer-secret-1', bandCount: 7, reasons: [], preview: null, cost: 50);

MyProfile _profile(int hearts) => MyProfile(
      nickname: '여우',
      age: 23,
      university: '가나대학교',
      major: '경영학과',
      heightCm: 178,
      mbti: 'ENFP',
      avatarUrl: null,
      preferredAgeMin: 22,
      preferredAgeMax: 27,
      preferredHeightMin: 165,
      preferredHeightMax: 180,
      bio: '',
      heartBalance: hearts,
      avatarRegenCost: 10,
    );

void main() {
  late FakeCardRepository cards;
  late FakeMeRepository me;
  late FakeAnalyticsService analytics;
  late ProviderContainer container;

  setUp(() {
    cards = FakeCardRepository();
    me = FakeMeRepository(Success(_profile(320)));
    analytics = FakeAnalyticsService();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(path: '/today', builder: (context, state) => const TodayCardsScreen()),
        GoRoute(
          path: '${AppRoutes.cardDetail}/:cardId',
          builder: (context, state) => Scaffold(appBar: AppBar(), body: const Text('10b 상세')),
        ),
      ],
    );
    addTearDown(router.dispose);
    container = ProviderContainer(
      overrides: [
        analyticsServiceProvider.overrideWithValue(analytics),
        cardRepositoryProvider.overrideWithValue(cards),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        meRepositoryProvider.overrideWithValue(me),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  Iterable<String> calls(String name) => analytics.calls.where((call) => call.startsWith(name));

  group('card_view — 카드가 화면에 보였다', () {
    testWidgets('무료 카드는 free, 산 카드는 purchased', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free, _bought]));

      await pump(tester);

      expect(calls('card_view'), ['card_view:free', 'card_view:purchased']);
    });

    testWidgets('같은 카드는 목록을 다시 읽어도 한 번만 센다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free]));
      await pump(tester);

      await container.read(todayCardsViewModelProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(calls('card_view'), ['card_view:free']);
    });

    testWidgets('카드가 없는 오늘(대기 화면)은 남기지 않는다', (tester) async {
      cards.today = Success(TodayCards(cards: const [], nextIssueAt: DateTime.now().add(const Duration(hours: 3))));

      await pump(tester);

      expect(calls('card_view'), isEmpty);
    });
  });

  group('card_detail_open — 카드를 눌러 상세를 열었다', () {
    testWidgets('누르면 출처만 남기고 상세로 간다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free]));
      await pump(tester);

      await tester.tap(find.text('프로필 자세히 보기'));
      await tester.pumpAndSettle();

      expect(find.text('10b 상세'), findsOneWidget);
      expect(calls('card_detail_open'), ['card_detail_open:free']);
    });
  });

  group('paid_card_view — 유료 카드 칸이 보였다', () {
    testWidgets('열 수 있는 사람이 있으면 offered', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));

      await pump(tester);

      expect(calls('paid_card_view'), ['paid_card_view:offered']);
    });

    testWidgets('지금 열 사람이 없으면 empty', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: PaidCardEmpty()));

      await pump(tester);

      expect(calls('paid_card_view'), ['paid_card_view:empty']);
    });

    testWidgets('유료 카드 칸이 없으면 남기지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free]));

      await pump(tester);

      expect(calls('paid_card_view'), isEmpty);
    });

    testWidgets('칸이 그대로인 채 다시 읽혀도 다시 세지 않고, 모양이 바뀌면(offered → empty) 한 번 더 센다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      await pump(tester);
      await container.read(todayCardsViewModelProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(calls('paid_card_view'), ['paid_card_view:offered']);

      cards.today = const Success(TodayCards(cards: [_free], paidCard: PaidCardEmpty()));
      await container.read(todayCardsViewModelProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(calls('paid_card_view'), ['paid_card_view:offered', 'paid_card_view:empty']);
    });
  });

  group('paid_card_sheet_open — 열기 확인 시트가 떴다', () {
    Future<void> tapOpen(WidgetTester tester) async {
      await tester.ensureVisible(find.text('50으로 열기'));
      await tester.tap(find.text('50으로 열기'));
      await tester.pumpAndSettle();
    }

    testWidgets('하트가 충분해 확인 시트가 뜨면 한 번 남긴다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      await pump(tester);

      await tapOpen(tester);

      expect(find.text('이 사람을 지금 열어 볼까요?'), findsOneWidget);
      expect(calls('paid_card_sheet_open'), ['paid_card_sheet_open']);
    });

    testWidgets('하트가 모자라 "하트가 모자라요" 시트가 먼저 뜨면 확인 시트가 아니라서 남기지 않는다', (tester) async {
      me = FakeMeRepository(Success(_profile(3)));
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      await pump(tester);

      await tapOpen(tester);

      expect(find.text('하트가 모자라요'), findsOneWidget);
      expect(calls('paid_card_sheet_open'), isEmpty);
    });

    testWidgets('안내 시트(ⓘ)는 열기 확인이 아니라서 남기지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('paid-card-info')));
      await tester.pumpAndSettle();

      expect(calls('paid_card_sheet_open'), isEmpty);
    });
  });

  testWidgets('이벤트 줄에 카드 id · 상대 id · 제안 id · 닉네임이 한 글자도 들어가지 않는다', (tester) async {
    cards.today = const Success(TodayCards(cards: [_free, _bought], paidCard: _offer));
    await pump(tester);
    await tester.tap(find.text('프로필 자세히 보기').first);
    await tester.pumpAndSettle();

    final joined = analytics.calls.join('\n');
    for (final secret in ['card-free', 'card-bought', 'profile-secret', 'offer-secret', '여우비', '토끼']) {
      expect(joined, isNot(contains(secret)), reason: secret);
    }
  });
}
