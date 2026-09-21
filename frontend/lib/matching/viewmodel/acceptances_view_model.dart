import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final acceptancesViewModelProvider =
    NotifierProvider<AcceptancesViewModel, AcceptancesUiState>(AcceptancesViewModel.new);

/// 받은 수락함(DESIGN.md 화면 13 상단 섹션). 7일 만료 판정은 서버가 하고 앱은 목록을 그대로 그린다.
class AcceptancesViewModel extends Notifier<AcceptancesUiState> {
  Future<void>? _inFlight;

  @override
  AcceptancesUiState build() {
    Future.microtask(refresh);
    return const AcceptancesUiState();
  }

  Future<void> refresh() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    final result = await ref.read(cardRepositoryProvider).fetchAcceptances();
    // 목록을 다시 읽는다고 해서 방금 성사된 매칭이나 사용자가 읽어야 할 문구를 지우지는 않는다 —
    // [respond] 가 목록 갱신으로 끝나기 때문에 여기서 지우면 둘 다 화면에 닿지 못한다.
    state = result.when(
      onSuccess: (list) => state.copyWith(
        isLoading: false,
        acceptances: list,
        matchedNickname: state.matchedNickname,
        errorMessage: state.errorMessage,
      ),
      onFailure: (failure) => state.copyWith(
        isLoading: false,
        matchedNickname: state.matchedNickname,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
  }

  Future<void> respond(String cardId, CardDecision decision) async {
    if (state.respondingCardId != null) {
      return;
    }
    // 화면이 12 로 넘어간 뒤 뒤로 돌아와도 같은 매칭이 또 뜨지 않게 미리 비운다.
    final nickname = state.nicknameOf(cardId);
    state = state.copyWith(respondingCardId: cardId, errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).respondToAcceptance(cardId, decision);
    state = result.when(
      onSuccess: (outcome) => state.copyWith(
        respondingCardId: null,
        matchedNickname: outcome.matched ? nickname : null,
      ),
      onFailure: (failure) =>
          state.copyWith(respondingCardId: null, errorMessage: failure.toDisplayMessage()),
    );
    // 성공이든 실패든(410 만료 포함) 목록은 서버 기준으로 다시 맞춘다.
    await refresh();
  }

  /// 12 화면으로 한 번 보낸 뒤에는 상태에서 지운다 — 목록에 돌아왔을 때 또 튀지 않게.
  void consumeMatched() => state = state.copyWith(matchedNickname: null);
}
