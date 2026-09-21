import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/card_detail_ui_state.dart';
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
  }
}
