import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/model/paid_card.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final todayCardsViewModelProvider =
    NotifierProvider<TodayCardsViewModel, TodayCardsUiState>(TodayCardsViewModel.new);

/// 카운트다운이 0 이 된 뒤 아직 대기면 더 읽는 횟수와 간격([TodayCardsViewModel.refreshWhenDue]).
/// 3번 × 20초 = 0 이후 1분. 07:00 배치가 이 사람 카드를 쓰는 데 걸리는 시간에 맞춘 눈대중이다.
const int _dueRetryLimit = 3;
const Duration _dueRetryGap = Duration(seconds: 20);

/// 오늘 탭(DESIGN.md 화면 10·11·11b)의 흐름을 맡는다.
class TodayCardsViewModel extends Notifier<TodayCardsUiState> {
  Future<void>? _inFlight;

  /// [refreshWhenDue] 가 도는 중이다 — 홈 hero 와 오늘 탭이 같이 0 이 돼도 사슬은 하나다.
  bool _dueRunning = false;

  @override
  TodayCardsUiState build() {
    // 화면이 붙자마자 한 번 읽는다. 결과가 오기 전까지는 loading 이다.
    Future.microtask(refresh);
    return const TodayCardsUiState();
  }

  /// 화면 복귀·푸시 수신·당겨서 새로고침이 겹쳐도 조회는 한 번만 간다 —
  /// 늦게 끝난 응답이 먼저 끝난 응답을 덮어쓰지 않게 한다.
  Future<void> refresh() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    final result = await ref.read(cardRepositoryProvider).fetchToday();
    state = result.when(
      onSuccess: _fromToday,
      onFailure: (failure) => TodayCardsUiState(
        phase: TodayCardsPhase.failed,
        errorMessage: failure.toDisplayMessage(),
        isPurchasing: state.isPurchasing,
      ),
    );
  }

  /// 10b 에서 결정하고 돌아왔을 때. 결정한 카드가 그대로 남아 있으면 안 된다.
  Future<void> markDecided() => refresh();

  /// 다음 카드 카운트다운이 0 이 됐다(홈 hero ③ · 오늘 탭 11) — 푸시를 기다리지 않고 바로 읽는다.
  /// 0 은 07:00 배치가 시작하는 순간이라 첫 읽기는 대개 아직 대기다. 대기면 [_dueRetryGap] 간격으로 [_dueRetryLimit] 번까지만
  /// 더 읽고, 카드가 오거나(대기가 아니면) provider 가 내려가면 멈춘다. 상한이 있어 기기 시계가 빨라 기한이 늘 지나 있어도
  /// 끝없이 돌지 않는다. ponytail: 눈대중 1분 — 배치가 더 오래 걸리면 그 뒤는 지금처럼 푸시(`daily_card`)가 맡는다.
  Future<void> refreshWhenDue() async {
    if (_dueRunning) return;
    _dueRunning = true;
    try {
      await refresh();
      for (var retry = 0; retry < _dueRetryLimit && _stillWaiting; retry++) {
        await Future<void>.delayed(_dueRetryGap);
        if (!ref.mounted) return;
        await refresh();
      }
    } finally {
      _dueRunning = false;
    }
  }

  bool get _stillWaiting => ref.mounted && state.phase == TodayCardsPhase.waiting;

  TodayCardsUiState _fromToday(TodayCards today) {
    // 열기 요청이 가 있는 중에 다시 읽혀도 "진행 중" 과 아직 안 읽힌 알림은 지우지 않는다.
    final isPurchasing = state.isPurchasing;
    final notice = state.notice;
    if (today.cards.isNotEmpty) {
      return TodayCardsUiState(
        phase: TodayCardsPhase.cards,
        cards: today.cards,
        nextIssueAt: today.nextIssueAt,
        paidCard: today.paidCard,
        isPurchasing: isPurchasing,
        notice: notice,
      );
    }
    // 후보가 아예 없으면 기다려도 오지 않는다 — 기다리라고 쓰지 않는다(화면 11b). 결제 카드도 그리지 않는다.
    if (today.candidatePoolEmpty) {
      return TodayCardsUiState(
        phase: TodayCardsPhase.noCandidates,
        nextIssueAt: today.nextIssueAt,
        isPurchasing: isPurchasing,
        notice: notice,
      );
    }
    return TodayCardsUiState(
      phase: TodayCardsPhase.waiting,
      nextIssueAt: today.nextIssueAt,
      // 오늘 카드를 이미 정했어도 결제 카드는 살 수 있다(지시문 23 "모호한 것" 1).
      paidCard: today.paidCard,
      isPurchasing: isPurchasing,
      notice: notice,
    );
  }

  /// [offerId] 제안을 연다(하트 차감은 서버가 한다). 눌림이 겹쳐도 요청은 한 번이다.
  /// 사용자가 확인한 제안과 지금 화면의 제안이 다르면(확인 시트를 보는 사이 새로 읽혔다) 다른 사람을 사지 않도록 서버로 가지 않는다.
  Future<void> purchase(String offerId) async {
    final offer = state.paidCard;
    if (state.isPurchasing || offer is! PaidCardOffered) {
      return;
    }
    if (offer.offerId != offerId) {
      state = state.copyWith(notice: const PurchaseNotice(PurchaseNoticeKind.offerGone, paidOfferGoneMessage));
      return;
    }
    state = state.copyWith(isPurchasing: true);
    final result = await ref.read(cardRepositoryProvider).purchasePaidCard(offerId);
    await result.when(onSuccess: (_) => _opened(), onFailure: _rejected);
    state = state.copyWith(isPurchasing: false, notice: state.notice);
  }

  /// 산 카드를 목록에 넣으려면 서버 기준으로 다시 읽는다. 하트가 줄었으니 잔액도 다시 읽게 한다.
  Future<void> _opened() async {
    ref.invalidate(myProfileProvider);
    await _readFresh();
  }

  Future<void> _rejected(Failure failure) async {
    if (failure.isHeartsNotEnough) {
      state = state.copyWith(notice: const PurchaseNotice(PurchaseNoticeKind.heartsNotEnough));
      return;
    }
    if (failure.isPaidOfferGone) {
      await _readFresh();
      state = state.copyWith(notice: const PurchaseNotice(PurchaseNoticeKind.offerGone, paidOfferGoneMessage));
      return;
    }
    state = state.copyWith(notice: PurchaseNotice(PurchaseNoticeKind.failed, failure.toDisplayMessage()));
  }

  /// 진행 중인 읽기가 있으면 그것은 구매 **전** 에 시작했을 수 있다 — 끝나기를 기다린 뒤 새로 한 번 더 읽는다.
  Future<void> _readFresh() async {
    await _inFlight;
    await refresh();
  }

  /// 화면이 알림을 읽어 갔다. 같은 알림을 두 번 그리지 않게 비운다.
  void consumeNotice() => state = state.copyWith(notice: null);
}
