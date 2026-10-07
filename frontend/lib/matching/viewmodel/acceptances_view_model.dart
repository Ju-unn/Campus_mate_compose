import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final acceptancesViewModelProvider =
    NotifierProvider<AcceptancesViewModel, AcceptancesUiState>(AcceptancesViewModel.new);

/// 받은 수락함(DESIGN.md 화면 13 상단 섹션). 7일 만료 판정은 서버가 하고 앱은 목록을 그대로 그린다.
class AcceptancesViewModel extends Notifier<AcceptancesUiState> {
  Future<void>? _inFlight;

  /// 진행 중인 읽기에 조용하지 않은 호출이 합쳐졌다. 그 읽기는 호출보다 먼저 시작됐으니(낡았을 수 있고,
  /// 실패해도 오류를 안 보인다) 끝난 뒤 조용하지 않게 한 번 더 읽는다. 합쳐진 호출이 몇 번이든 한 번이다.
  bool _readAgain = false;

  @override
  AcceptancesUiState build() {
    // 첫 읽기는 isLoading 이라 quiet 여도 실패를 보인다. quiet 로 불러야 화면 initState 의 조용한 읽기와
    // 합쳐질 때 다시 읽기가 생기지 않는다.
    Future.microtask(() => refresh(quiet: true));
    return const AcceptancesUiState();
  }

  /// [quiet] 은 앱 복귀·화면 진입 때 자동으로 읽는 경우다 — 실패해도 이미 보이는 줄을 그대로 두고
  /// 오류 줄을 새로 띄우지 않는다. 사용자가 당겨서 새로고침하거나 푸시·응답 뒤에 읽을 때는 오류를 보인다.
  /// 읽는 중에 불리면 그 읽기에 합쳐지고, 조용하지 않은 호출이면 끝난 뒤 한 번 더 읽은 다음에 완료된다.
  Future<void> refresh({bool quiet = false}) {
    final running = _inFlight;
    if (running == null) {
      return _inFlight = _loadAndRepeat(quiet).whenComplete(() => _inFlight = null);
    }
    _readAgain = _readAgain || !quiet;
    return running;
  }

  Future<void> _loadAndRepeat(bool quiet) async {
    await _load(quiet: quiet);
    while (_readAgain) {
      _readAgain = false;
      await _load(quiet: false);
    }
  }

  Future<void> _load({required bool quiet}) async {
    final result = await ref.read(cardRepositoryProvider).fetchAcceptances();
    // 목록을 다시 읽는다고 해서 방금 성사된 매칭을 지우지는 않는다 — [respond] 가 목록 갱신으로 끝나기 때문에
    // 여기서 지우면 12 화면으로 보낼 재료가 화면에 닿지 못한다. 오류 문구는 읽기가 성공하면 지운다.
    state = result.when(
      onSuccess: (list) => state.copyWith(
        isLoading: false,
        acceptances: list,
        // 답을 보내는 중에 목록 읽기가 끝나도 보내는 중 표시를 지우지 않는다(연타 방지).
        respondingCardId: state.respondingCardId,
        matchedNickname: state.matchedNickname,
        matchedMatchId: state.matchedMatchId,
      ),
      // 첫 읽기(isLoading)는 quiet 여도 스켈레톤을 끝내야 한다 — build() 의 첫 읽기와 합쳐지는 경우도 같다.
      onFailure: (failure) =>
          quiet && !state.isLoading ? state : _failed(failure.toDisplayMessage()),
    );
  }

  /// 오류 문구를 올린다. 로딩은 끝내고, 보내는 중 표시와 성사된 매칭은 그대로 둔다.
  AcceptancesUiState _failed(String message) => state.copyWith(
        isLoading: false,
        respondingCardId: state.respondingCardId,
        matchedNickname: state.matchedNickname,
        matchedMatchId: state.matchedMatchId,
        errorMessage: message,
      );

  Future<void> respond(String cardId, CardDecision decision) async {
    if (state.respondingCardId != null) {
      return;
    }
    // 화면이 12 로 넘어간 뒤 뒤로 돌아와도 같은 매칭이 또 뜨지 않게 미리 비운다.
    final nickname = state.nicknameOf(cardId);
    state = state.copyWith(respondingCardId: cardId, errorMessage: null);
    final result = await ref.read(cardRepositoryProvider).respondToAcceptance(cardId, decision);
    String? responseError;
    state = result.when(
      onSuccess: (outcome) => state.copyWith(
        respondingCardId: null,
        matchedNickname: outcome.matched ? nickname : null,
        matchedMatchId: outcome.matched ? outcome.matchId : null,
      ),
      onFailure: (failure) {
        responseError = failure.toDisplayMessage();
        return state.copyWith(respondingCardId: null, errorMessage: responseError);
      },
    );
    // 성공이든 실패든(410 만료 포함) 목록은 서버 기준으로 다시 맞춘다.
    await refresh();
    // 목록 읽기가 성공하면 오류 문구를 지우니, 읽어야 할 응답 실패 문구는 갱신 뒤에 다시 올린다.
    // (갱신 자체가 실패해 그 문구가 올라와 있으면 그대로 둔다.)
    final message = responseError;
    if (message != null && state.errorMessage == null) {
      state = _failed(message);
    }
  }

  /// 12 화면으로 한 번 보낸 뒤에는 상태에서 지운다 — 목록에 돌아왔을 때 또 튀지 않게.
  void consumeMatched() => state = state.copyWith(matchedNickname: null, matchedMatchId: null);
}
