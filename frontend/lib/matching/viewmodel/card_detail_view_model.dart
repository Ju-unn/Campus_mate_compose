import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/matching/model/data/card_decision.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/card_detail_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cardDetailViewModelProvider =
    NotifierProvider.family<CardDetailViewModel, CardDetailUiState, String>(
  CardDetailViewModel.new,
);

/// 10b 상세 화면(`TORAs`)의 흐름. 카드 하나마다 상태가 따로 산다.
/// Riverpod 3 의 family 는 인자를 생성자로 받는다(`FamilyNotifier` 는 없어졌다).
class CardDetailViewModel extends Notifier<CardDetailUiState> {
  CardDetailViewModel(this.cardId);

  final String cardId;

  Future<void>? _inFlight;

  @override
  CardDetailUiState build() {
    Future.microtask(load);
    return const CardDetailUiState();
  }

  /// 화면이 붙으면서 한 번, 사용자가 다시 시도하면 또 한 번 불린다 —
  /// 겹쳐 불려도 조회는 한 번만 가고 늦은 응답이 결정 상태를 덮어쓰지 않는다.
  Future<void> load() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    final result = await ref.read(cardRepositoryProvider).fetchCard(cardId);
    state = result.when(
      onSuccess: (detail) => CardDetailUiState(detail: detail),
      onFailure: (failure) => CardDetailUiState(errorMessage: failure.toDisplayMessage()),
    );
  }

  Future<void> decide(CardDecision decision) async {
    // 연타·중복 전송 방지. 수락이 두 번 가면 서버는 409 로 막지만 화면이 흔들린다.
    if (state.isSubmitting || state.decided) {
      return;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).decide(cardId, decision);
    state = result.when(
      onSuccess: (_) => state.copyWith(isSubmitting: false, decided: true, decision: decision),
      onFailure: (failure) =>
          state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
    // 사용 통계 `chat_request_sent` — 서버가 수락(= 대화 신청)을 받아 준 뒤에만. 거절은 신청이 아니다.
    if (state.decided && decision == CardDecision.accept) {
      ref.read(analyticsServiceProvider).logChatRequestSent();
    }
    if (state.decided && decision == CardDecision.reject) {
      _logPass();
    }
  }

  /// 사용 통계 `card_pass`. 상세는 카드 id 만 알아서 출처는 오늘 탭이 읽어 둔 목록에서 찾는다 — 못 찾으면 지어내지 않고 남기지 않는다.
  void _logPass() {
    // 오늘 탭 뷰모델이 아직 없으면(상세만 단독으로 열린 경우) 만들지 않는다 — 만들면 목록 조회가 따라 나간다.
    if (!ref.exists(todayCardsViewModelProvider)) return;
    final cards = ref.read(todayCardsViewModelProvider).cards;
    final card = cards.where((candidate) => candidate.cardId == cardId).firstOrNull;
    if (card == null) return;
    ref.read(analyticsServiceProvider).logCardPass(card.source.origin);
  }
}
