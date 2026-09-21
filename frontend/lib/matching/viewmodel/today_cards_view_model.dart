import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final todayCardsViewModelProvider =
    NotifierProvider<TodayCardsViewModel, TodayCardsUiState>(TodayCardsViewModel.new);

/// 오늘 탭(DESIGN.md 화면 10·11·11b)의 흐름을 맡는다.
class TodayCardsViewModel extends Notifier<TodayCardsUiState> {
  Future<void>? _inFlight;

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
      ),
    );
  }

  /// 10b 에서 결정하고 돌아왔을 때. 결정한 카드가 그대로 남아 있으면 안 된다.
  Future<void> markDecided() => refresh();

  TodayCardsUiState _fromToday(TodayCards today) {
    if (today.cards.isNotEmpty) {
      return TodayCardsUiState(
        phase: TodayCardsPhase.cards,
        cards: today.cards,
        nextIssueAt: today.nextIssueAt,
      );
    }
    return TodayCardsUiState(
      // 후보가 아예 없으면 기다려도 오지 않는다 — 기다리라고 쓰지 않는다(화면 11b).
      phase: today.candidatePoolEmpty ? TodayCardsPhase.noCandidates : TodayCardsPhase.waiting,
      nextIssueAt: today.nextIssueAt,
    );
  }
}
