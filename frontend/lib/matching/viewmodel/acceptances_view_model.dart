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

  /// [quiet] 은 앱 복귀·화면 진입 때 자동으로 읽는 경우다 — 실패해도 이미 보이는 줄을 그대로 두고
  /// 오류 줄을 새로 띄우지 않는다. 사용자가 당겨서 새로고침하거나 처음 읽을 때만 오류를 보인다.
  Future<void> refresh({bool quiet = false}) =>
      _inFlight ??= _load(quiet: quiet).whenComplete(() => _inFlight = null);

  Future<void> _load({required bool quiet}) async {
    final result = await ref.read(cardRepositoryProvider).fetchAcceptances();
    // 목록을 다시 읽는다고 해서 방금 성사된 매칭이나 사용자가 읽어야 할 문구를 지우지는 않는다 —
    // [respond] 가 목록 갱신으로 끝나기 때문에 여기서 지우면 둘 다 화면에 닿지 못한다.
    state = result.when(
      onSuccess: (list) => state.copyWith(
        isLoading: false,
        acceptances: list,
        // 답을 보내는 중에 목록 읽기가 끝나도 보내는 중 표시를 지우지 않는다(연타 방지).
        respondingCardId: state.respondingCardId,
        matchedNickname: state.matchedNickname,
        matchedMatchId: state.matchedMatchId,
        errorMessage: state.errorMessage,
      ),
      // 첫 읽기(isLoading)는 quiet 여도 스켈레톤을 끝내야 한다 — build() 의 첫 읽기와 합쳐지는 경우도 같다.
      onFailure: (failure) => quiet && !state.isLoading
          ? state
          : state.copyWith(
              isLoading: false,
              respondingCardId: state.respondingCardId,
              matchedNickname: state.matchedNickname,
              matchedMatchId: state.matchedMatchId,
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
        matchedMatchId: outcome.matched ? outcome.matchId : null,
      ),
      onFailure: (failure) =>
          state.copyWith(respondingCardId: null, errorMessage: failure.toDisplayMessage()),
    );
    // 성공이든 실패든(410 만료 포함) 목록은 서버 기준으로 다시 맞춘다.
    await refresh();
  }

  /// 12 화면으로 한 번 보낸 뒤에는 상태에서 지운다 — 목록에 돌아왔을 때 또 튀지 않게.
  void consumeMatched() => state = state.copyWith(matchedNickname: null, matchedMatchId: null);
}
