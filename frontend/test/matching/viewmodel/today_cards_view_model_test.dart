import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/paid_card.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

const _profile = CardProfile(profileId: 't1', nickname: '여우비', age: 23);
const _card = DailyCard(cardId: 'card-1', source: CardSource.daily, profile: _profile);
const _bought = DailyCard(cardId: 'card-2', source: CardSource.purchased, profile: _profile);
const _offer = PaidCardOffered(
  offerId: 'offer-1',
  bandCount: 7,
  reasons: [ReasonTag(kind: 'tendency', text: '성향이 비슷해요')],
  preview: null,
  cost: 50,
);

void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository();
    container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  Future<TodayCardsUiState> load() async {
    await container.read(todayCardsViewModelProvider.notifier).refresh();
    return container.read(todayCardsViewModelProvider);
  }

  test('카드가 있으면 카드 상태가 된다', () async {
    repository.today = const Success(TodayCards(cards: [_card]));

    final state = await load();

    expect(state.phase, TodayCardsPhase.cards);
    expect(state.cards.single.cardId, 'card-1');
  });

  test('카드가 없고 다음 지급일이 있으면 대기 상태다 (화면 11)', () async {
    repository.today = Success(TodayCards(cards: const [], nextIssueAt: DateTime(2026, 9, 24, 7)));

    final state = await load();

    expect(state.phase, TodayCardsPhase.waiting);
  });

  test('후보 풀이 비었으면 대기가 아니라 "소개할 사람 없음"이다 (화면 11b)', () async {
    repository.today = Success(
      TodayCards(cards: const [], nextIssueAt: DateTime(2026, 9, 24, 7), candidatePoolEmpty: true),
    );

    final state = await load();

    expect(state.phase, TodayCardsPhase.noCandidates);
  });

  test('실패하면 오류 문구를 들고 실패 상태가 된다', () async {
    repository.today = const FailureResult(NetworkFailure());

    final state = await load();

    expect(state.phase, TodayCardsPhase.failed);
    expect(state.errorMessage, const NetworkFailure().toDisplayMessage());
  });

  test('결정하면 목록을 다시 읽는다 — 카드가 사라진 화면을 남기지 않는다', () async {
    repository.today = const Success(TodayCards(cards: [_card]));
    await load();

    await container.read(todayCardsViewModelProvider.notifier).markDecided();

    expect(repository.fetchTodayCount, 2);
  });

  // 카운트다운이 0 이 됐을 때(홈 hero ③ · 오늘 탭 11). 07:00 배치와 같은 순간이라 첫 읽기는 대개 아직 대기다.
  // 시간을 흘려야 해서 testWidgets(가짜 시계)로 돈다.
  group('refreshWhenDue — 0 이 된 뒤 다시 읽기', () {
    final waiting = Success(TodayCards(cards: const [], nextIssueAt: DateTime(2026, 10, 15, 7)));
    TodayCardsViewModel viewModel() => container.read(todayCardsViewModelProvider.notifier);

    testWidgets('바로 한 번 읽고, 아직 대기면 20초 간격으로 3번까지만 더 읽는다', (tester) async {
      repository.today = waiting;
      await load();
      expect(repository.fetchTodayCount, 1);

      unawaited(viewModel().refreshWhenDue());
      await tester.pump();
      expect(repository.fetchTodayCount, 2);
      await tester.pump(const Duration(seconds: 19));
      expect(repository.fetchTodayCount, 2);
      for (final expected in [3, 4, 5]) {
        await tester.pump(const Duration(seconds: 20));
        expect(repository.fetchTodayCount, expected);
      }
      await tester.pump(const Duration(minutes: 5));
      expect(repository.fetchTodayCount, 5);
    });

    testWidgets('카드가 오면 거기서 멈춘다', (tester) async {
      repository.today = waiting;
      await load();

      unawaited(viewModel().refreshWhenDue());
      await tester.pump();
      repository.today = const Success(TodayCards(cards: [_card]));
      await tester.pump(const Duration(seconds: 20));
      expect(repository.fetchTodayCount, 3);
      expect(container.read(todayCardsViewModelProvider).phase, TodayCardsPhase.cards);

      await tester.pump(const Duration(minutes: 5));
      expect(repository.fetchTodayCount, 3);
    });

    testWidgets('도는 중에 또 불려도(홈 · 오늘 탭이 같이 0) 읽기 사슬은 하나다', (tester) async {
      repository.today = waiting;
      await load();

      unawaited(viewModel().refreshWhenDue());
      unawaited(viewModel().refreshWhenDue());
      await tester.pump();
      expect(repository.fetchTodayCount, 2);
      await tester.pump(const Duration(seconds: 20));
      expect(repository.fetchTodayCount, 3);
      await tester.pump(const Duration(minutes: 5));
      expect(repository.fetchTodayCount, 5);
    });

    testWidgets('같은 기한이면 사슬이 끝난 뒤 다시 불려도(탭을 오가며 카운트다운이 다시 붙음) 더 읽지 않는다', (tester) async {
      repository.today = waiting;
      await load();
      unawaited(viewModel().refreshWhenDue());
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect(repository.fetchTodayCount, 5);

      unawaited(viewModel().refreshWhenDue());
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect(repository.fetchTodayCount, 5);
    });

    testWidgets('새 기한의 0 에서는 다시 돈다', (tester) async {
      repository.today = waiting;
      await load();
      unawaited(viewModel().refreshWhenDue());
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect(repository.fetchTodayCount, 5);

      repository.today = Success(TodayCards(cards: const [], nextIssueAt: DateTime(2026, 10, 18, 7)));
      await load();
      expect(repository.fetchTodayCount, 6);
      unawaited(viewModel().refreshWhenDue());
      await tester.pump();
      expect(repository.fetchTodayCount, 7);
      await tester.pump(const Duration(minutes: 5));
      expect(repository.fetchTodayCount, 10);
    });

    testWidgets('provider 가 내려가면 남은 재시도는 가지 않는다', (tester) async {
      final own = FakeCardRepository()..today = waiting;
      final short = ProviderContainer(overrides: [cardRepositoryProvider.overrideWithValue(own)]);
      await short.read(todayCardsViewModelProvider.notifier).refresh();

      unawaited(short.read(todayCardsViewModelProvider.notifier).refreshWhenDue());
      await tester.pump();
      expect(own.fetchTodayCount, 2);
      short.dispose();
      await tester.pump(const Duration(minutes: 5));
      expect(own.fetchTodayCount, 2);
    });
  });

  group('결제 카드(지시문 23 A4)', () {
    TodayCardsViewModel viewModel() => container.read(todayCardsViewModelProvider.notifier);

    test('paid_card 를 상태에 담는다 — 카드 단계 아래에 추가로 그린다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: _offer));

      final state = await load();

      expect(state.phase, TodayCardsPhase.cards);
      expect(state.paidCard, _offer);
    });

    test('오늘 카드를 이미 정했어도(대기 단계) 결제 카드는 그대로 담긴다 (지시문 "모호한 것" 1)', () async {
      repository.today = Success(TodayCards(cards: const [], nextIssueAt: DateTime(2026, 9, 24, 7), paidCard: _offer));

      final state = await load();

      expect(state.phase, TodayCardsPhase.waiting);
      expect(state.paidCard, _offer);
    });

    test('후보 풀이 비었으면(11b) 결제 카드를 담지 않는다 (지시문 "모호한 것" 2)', () async {
      repository.today = const Success(TodayCards(cards: [], candidatePoolEmpty: true, paidCard: _offer));

      final state = await load();

      expect(state.phase, TodayCardsPhase.noCandidates);
      expect(state.paidCard, isNull);
    });

    test('구매에 성공하면 목록을 다시 읽어 산 카드를 넣고, 알림은 없다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: _offer));
      repository.todayAfterPurchase = const Success(TodayCards(cards: [_card, _bought]));
      await load();

      await viewModel().purchase('offer-1');

      final state = container.read(todayCardsViewModelProvider);
      expect(repository.purchasedOfferIds, ['offer-1']);
      expect(repository.fetchTodayCount, 2);
      expect(state.cards.map((c) => c.cardId), ['card-1', 'card-2']);
      expect(state.paidCard, isNull);
      expect(state.isPurchasing, isFalse);
      expect(state.notice, isNull);
    });

    test('진행 중에 또 누르면 서버 호출은 한 번뿐이다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: _offer));
      final hold = Completer<void>();
      repository.holdPurchase = hold;
      await load();

      final first = viewModel().purchase('offer-1');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(todayCardsViewModelProvider).isPurchasing, isTrue);
      await viewModel().purchase('offer-1');
      hold.complete();
      await first;

      expect(repository.purchasedOfferIds, ['offer-1']);
    });

    test('402 면 목록은 그대로 두고 "하트 부족" 알림을 올린다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: _offer));
      repository.purchaseResult = const FailureResult(ServerRejectedFailure(heartsNotEnoughMessage));
      await load();

      await viewModel().purchase('offer-1');

      final state = container.read(todayCardsViewModelProvider);
      expect(state.notice!.kind, PurchaseNoticeKind.heartsNotEnough);
      expect(state.paidCard, _offer);
      expect(state.isPurchasing, isFalse);
      expect(repository.fetchTodayCount, 1);
    });

    test('409 면 화면을 다시 읽고 "지금은 열 수 없는 카드예요" 알림을 올린다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: _offer));
      repository.purchaseResult = const FailureResult(ServerRejectedFailure(paidOfferGoneMessage));
      repository.todayAfterPurchase = const Success(TodayCards(cards: [_card], paidCard: PaidCardEmpty()));
      await load();

      await viewModel().purchase('offer-1');

      final state = container.read(todayCardsViewModelProvider);
      expect(repository.fetchTodayCount, 2);
      expect(state.paidCard, isA<PaidCardEmpty>());
      expect(state.notice!.kind, PurchaseNoticeKind.offerGone);
      expect(state.isPurchasing, isFalse);
    });

    test('그 밖의 실패는 일반 실패 알림이고 목록은 그대로다 — 다시 누를 수 있다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: _offer));
      repository.purchaseResult = const FailureResult(NetworkFailure());
      await load();

      await viewModel().purchase('offer-1');
      final failed = container.read(todayCardsViewModelProvider);
      expect(failed.notice!.kind, PurchaseNoticeKind.failed);
      expect(failed.notice!.message, const NetworkFailure().toDisplayMessage());
      expect(failed.paidCard, _offer);

      // 실패 뒤 재시도 — 같은 제안 번호로 다시 간다.
      repository.purchaseResult = const Success('card-2');
      repository.todayAfterPurchase = const Success(TodayCards(cards: [_card, _bought]));
      await viewModel().purchase('offer-1');

      expect(repository.purchasedOfferIds, ['offer-1', 'offer-1']);
      expect(container.read(todayCardsViewModelProvider).cards, hasLength(2));
    });

    test('알림을 읽어 갔으면 비운다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: _offer));
      repository.purchaseResult = const FailureResult(NetworkFailure());
      await load();
      await viewModel().purchase('offer-1');

      viewModel().consumeNotice();

      expect(container.read(todayCardsViewModelProvider).notice, isNull);
    });

    test('확인한 제안과 지금 화면의 제안이 다르면 서버로 가지 않고 "지금은 열 수 없는 카드예요" 알림을 올린다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: _offer));
      await load();

      await viewModel().purchase('offer-old');

      final state = container.read(todayCardsViewModelProvider);
      expect(repository.purchasedOfferIds, isEmpty);
      expect(state.notice!.kind, PurchaseNoticeKind.offerGone);
      expect(state.isPurchasing, isFalse);
    });

    test('열 수 있는 결제 카드가 없으면(empty · null) 구매는 서버로 가지 않는다', () async {
      repository.today = const Success(TodayCards(cards: [_card], paidCard: PaidCardEmpty()));
      await load();

      await viewModel().purchase('offer-1');

      expect(repository.purchasedOfferIds, isEmpty);
    });
  });
}
