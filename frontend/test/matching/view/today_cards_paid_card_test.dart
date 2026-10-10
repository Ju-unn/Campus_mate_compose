import 'dart:async';
import 'dart:io';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/paid_card.dart';
import 'package:campus_mate/matching/view/paid_card_locked.dart';
import 'package:campus_mate/matching/view/today_cards_screen.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../model/fake_card_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';

/// 오늘 탭 안의 결제 카드(pen `W0CjO` 의 `b2jvOY`, `SoMVZ` 의 `IJGRA`) 자리 · 흐름 · 이름 바꾸기 (지시문 23 B~E).
Future<void> _loadPretendard() async {
  final loader = FontLoader('Pretendard');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File('assets/fonts/Pretendard-$weight.otf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}

const _free = DailyCard(
  cardId: 'card-1',
  source: CardSource.daily,
  profile: CardProfile(profileId: 't1', nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
);
const _bought = DailyCard(
  cardId: 'card-2',
  source: CardSource.purchased,
  profile: CardProfile(profileId: 't2', nickname: '토끼', age: 24),
);
const _offer = PaidCardOffered(
  offerId: 'offer-1',
  bandCount: 7,
  reasons: [
    ReasonTag(kind: 'tendency', text: '성향이 비슷해요'),
    ReasonTag(kind: 'tags', text: '#러닝 #카페가 같아요'),
  ],
  avatarUrl: null,
  cost: 50,
);

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
  setUpAll(_loadPretendard);

  late FakeCardRepository cards;
  late FakeMeRepository me;

  setUp(() {
    cards = FakeCardRepository();
    me = FakeMeRepository(Success(_profile(320)));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(path: '/today', builder: (context, state) => const TodayCardsScreen()),
        GoRoute(path: AppRoutes.heartStore, builder: (context, state) => Scaffold(appBar: AppBar(), body: const Text('18 스토어'))),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(cards),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
          meRepositoryProvider.overrideWithValue(me),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

  group('자리 — pen `b2jvOY`: 무료 카드 바로 아래 간격 16, 가로 16 여백, 카드 목록의 마지막', () {
    testWidgets('무료 카드 아래 16, 왼쪽 16, 폭 328', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));

      await pump(tester);

      final free = rect(tester, find.text('프로필 자세히 보기').first);
      expect(find.byType(PaidCardLocked), findsOneWidget);
      final paid = rect(tester, find.byType(PaidCardLocked));
      final summary = tester.getRect(find.ancestor(of: find.text('프로필 자세히 보기'), matching: find.byType(Container)).last);
      expect(paid.top - summary.bottom, 16);
      expect(paid.left, 16);
      expect(paid.width, 328);
      expect(free.top, lessThan(paid.top));
    });

    testWidgets('산 카드가 생기면 목록 맨 아래는 여전히 결제 카드이거나(다음 제안) 산 카드다 — 결제 카드는 마지막이다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free, _bought], paidCard: _offer));

      await pump(tester);

      final lastSummary = rect(tester, find.text('토끼, 24'));
      expect(rect(tester, find.byType(PaidCardLocked)).top, greaterThan(lastSummary.bottom));
    });

    testWidgets('paid_card 가 없으면 아무것도 그리지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free]));

      await pump(tester);

      expect(find.byType(PaidCardLocked), findsNothing);
      expect(find.byType(PaidCardEmptyNotice), findsNothing);
      expect(find.text('여우비, 23'), findsOneWidget);
    });

    testWidgets('empty 이면 결제 카드 자리에 0명 안내 상자(328×48)를 같은 자리 · 같은 간격으로 그린다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: PaidCardEmpty()));

      await pump(tester);

      expect(find.byType(PaidCardLocked), findsNothing);
      final notice = rect(tester, find.byType(PaidCardEmptyNotice));
      expect(notice.size, const Size(328, 48));
      expect(notice.left, 16);
      final summary = tester.getRect(find.ancestor(of: find.text('프로필 자세히 보기'), matching: find.byType(Container)).last);
      expect(notice.top - summary.bottom, 16);
      expect(find.text('잘 맞는 새 사람이 들어오면 다시 열려요'), findsOneWidget);
    });

    testWidgets('오늘 카드를 이미 정해 대기 화면이어도 결제 카드는 그 아래에 붙는다 (추정 배치)', (tester) async {
      cards.today = Success(
        TodayCards(cards: const [], nextIssueAt: DateTime.now().add(const Duration(hours: 3)), paidCard: _offer),
      );

      await pump(tester);

      expect(find.text('오늘 카드는 확인했어요'), findsOneWidget);
      expect(find.byType(PaidCardLocked), findsOneWidget);
      expect(rect(tester, find.byType(PaidCardLocked)).top, greaterThan(rect(tester, find.text('내일 만날 사람들')).bottom));
      expect(rect(tester, find.byType(PaidCardLocked)).width, 328);
      expect(rect(tester, find.byType(PaidCardLocked)).left, 16);
    });

    testWidgets('후보 풀이 비면(11b) 서버가 offered 를 줘도 그리지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [], candidatePoolEmpty: true, paidCard: _offer));

      await pump(tester);

      expect(find.text('지금은 소개할 사람이 없어요'), findsOneWidget);
      expect(find.byType(PaidCardLocked), findsNothing);
    });

    testWidgets('화면 어디에도 궁합 % · "상위 20%" · 점수 · 학교 이름 문구가 새로 생기지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_bought], paidCard: _offer));

      await pump(tester);

      final texts = [for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(PaidCardLocked), matching: find.byType(Text)))) t.data ?? ''];
      for (final text in texts) {
        for (final banned in ['%', '상위', '궁합', '점수', '대학교']) {
          expect(text.contains(banned), isFalse, reason: '$text / $banned');
        }
      }
    });
  });

  group('물음표 → 안내 시트', () {
    testWidgets('누르면 안내 시트가 뜨고 "알겠어요" 로 닫힌다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('paid-card-info')));
      await tester.pumpAndSettle();
      expect(find.text('이렇게 정밀하게 골랐어요'), findsOneWidget);

      await tester.tap(find.text('알겠어요'));
      await tester.pumpAndSettle();

      expect(find.text('이렇게 정밀하게 골랐어요'), findsNothing);
      expect(cards.purchasedOfferIds, isEmpty);
    });
  });

  group('열기 흐름 (지시문 23 D)', () {
    Future<void> tapOpen(WidgetTester tester) async {
      await tester.ensureVisible(find.text('50으로 열기'));
      await tester.tap(find.text('50으로 열기'));
      await tester.pumpAndSettle();
    }

    testWidgets('"50으로 열기" → 확인 시트(보유 하트 320개) → "취소" 면 서버로 가지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      await pump(tester);

      await tapOpen(tester);
      expect(find.text('이 사람을 지금 열어 볼까요?'), findsOneWidget);
      expect(find.textContaining('지금 보유한 하트는 320개예요'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(cards.purchasedOfferIds, isEmpty);
      expect(find.byType(PaidCardLocked), findsOneWidget);
    });

    testWidgets('"50 쓰고 열기" → 서버로 가고, 산 카드가 목록에 들어오고 결제 카드는 사라진다. 토스트는 없다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      cards.todayAfterPurchase = const Success(TodayCards(cards: [_free, _bought]));
      await pump(tester);

      await tapOpen(tester);
      await tester.tap(find.text('50 쓰고 열기'));
      await tester.pumpAndSettle();

      expect(cards.purchasedOfferIds, ['offer-1']);
      expect(find.text('토끼, 24'), findsOneWidget);
      expect(find.byType(PaidCardLocked), findsNothing);
      expect(find.byType(AppToast), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('여는 중에는 버튼이 잠겨 두 번 눌러도 확인 시트가 또 뜨지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      cards.holdPurchase = Completer<void>();
      await pump(tester);

      await tapOpen(tester);
      await tester.tap(find.text('50 쓰고 열기'));
      // 시트가 닫히는 동안(애니메이션) 기다린다 — 닫히면 곧바로 열기 요청이 가 있고 서버 응답은 멈춰 있다.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('50으로 열기'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('이 사람을 지금 열어 볼까요?'), findsNothing);
      expect(cards.purchasedOfferIds, ['offer-1']);

      cards.holdPurchase!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('잔액을 읽는 동안 버튼이 잠겨 두 번 눌러도 확인 시트는 한 번만 뜬다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      me.holdFetch = Completer<void>();
      await pump(tester);

      await tester.ensureVisible(find.text('50으로 열기'));
      await tester.tap(find.text('50으로 열기'));
      await tester.pump();
      await tester.tap(find.text('50으로 열기'), warnIfMissed: false);
      await tester.pump();
      me.holdFetch!.complete();
      await tester.pumpAndSettle();

      expect(find.text('이 사람을 지금 열어 볼까요?'), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      // 시트를 닫으면 버튼이 다시 눌린다.
      await tester.tap(find.text('50으로 열기'));
      await tester.pumpAndSettle();
      expect(find.text('이 사람을 지금 열어 볼까요?'), findsOneWidget);
    });

    testWidgets('확인 시트를 보는 사이 제안이 다른 사람으로 바뀌면, 확인한 것과 다른 제안을 열지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      await pump(tester);

      await tapOpen(tester);
      // 시트가 떠 있는 동안 화면이 새로 읽혀 다른 사람의 제안(offer-2)이 왔다.
      cards.today = const Success(
        TodayCards(
          cards: [_free],
          paidCard: PaidCardOffered(offerId: 'offer-2', bandCount: 5, reasons: [], avatarUrl: null, cost: 50),
        ),
      );
      final container = ProviderScope.containerOf(tester.element(find.byType(TodayCardsScreen)));
      await container.read(todayCardsViewModelProvider.notifier).refresh();
      await tester.pump();
      await tester.tap(find.text('50 쓰고 열기'));
      await tester.pumpAndSettle();

      expect(cards.purchasedOfferIds, isEmpty);
    });

    testWidgets('402 → "하트가 모자라요" 시트 → 스토어로 가고, 돌아오면 잔액을 다시 읽는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      cards.purchaseResult = const FailureResult(ServerRejectedFailure(heartsNotEnoughMessage));
      await pump(tester);

      await tapOpen(tester);
      await tester.tap(find.text('50 쓰고 열기'));
      await tester.pumpAndSettle();
      expect(find.text('하트가 모자라요'), findsOneWidget);

      await tester.tap(find.text('하트 스토어로 가기'));
      await tester.pumpAndSettle();
      expect(find.text('18 스토어'), findsOneWidget);

      // 스토어에서 하트를 채웠다고 치고 뒤로 돌아온다.
      me.profile = Success(_profile(500));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapOpen(tester);

      expect(find.textContaining('지금 보유한 하트는 500개예요'), findsOneWidget);
    });

    testWidgets('402 시트에서 "닫기" 면 스토어로 가지 않는다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      cards.purchaseResult = const FailureResult(ServerRejectedFailure(heartsNotEnoughMessage));
      await pump(tester);

      await tapOpen(tester);
      await tester.tap(find.text('50 쓰고 열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();

      expect(find.text('18 스토어'), findsNothing);
      expect(find.byType(PaidCardLocked), findsOneWidget);
    });

    testWidgets('409 → 화면을 새로 읽고 토스트 "지금은 열 수 없는 카드예요"', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      cards.purchaseResult = const FailureResult(ServerRejectedFailure(paidOfferGoneMessage));
      cards.todayAfterPurchase = const Success(TodayCards(cards: [_free], paidCard: PaidCardEmpty()));
      await pump(tester);

      await tapOpen(tester);
      await tester.tap(find.text('50 쓰고 열기'));
      await tester.pumpAndSettle();

      expect(cards.fetchTodayCount, 2);
      expect(find.text('지금은 열 수 없는 카드예요'), findsOneWidget);
      expect(find.byType(AppToast), findsOneWidget);
      expect(find.byType(PaidCardLocked), findsNothing);
      expect(find.byType(PaidCardEmptyNotice), findsOneWidget);
    });

    testWidgets('그 밖의 실패 → 토스트에 실패 문구, 결제 카드는 그대로라 다시 누를 수 있다', (tester) async {
      cards.today = const Success(TodayCards(cards: [_free], paidCard: _offer));
      cards.purchaseResult = const FailureResult(NetworkFailure());
      await pump(tester);

      await tapOpen(tester);
      await tester.tap(find.text('50 쓰고 열기'));
      await tester.pumpAndSettle();

      expect(find.text(const NetworkFailure().toDisplayMessage()), findsOneWidget);
      expect(find.byType(PaidCardLocked), findsOneWidget);

      await tapOpen(tester);
      expect(find.text('이 사람을 지금 열어 볼까요?'), findsOneWidget);
    });
  });
}
