import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/data/acceptance.dart';
import 'package:campus_mate/matching/model/data/rejected_card.dart';
import 'package:campus_mate/matching/model/repository/card_repository.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/rejected_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase, ProviderListenable;

final rejectedCardsViewModelProvider =
    NotifierProvider<RejectedCardsViewModel, RejectedCardsUiState>(RejectedCardsViewModel.new);

/// 카드 대기 화면의 [거절한 카드 다시 보기] 입구는 7일 안 거절이 있을 때만 보인다. 읽는 중 · 읽기 실패는 숨긴다.
/// 되돌릴 수 있는지 · 7일은 서버가 판단해 목록에서 뺀다 — 앱은 목록이 비었는지만 본다.
final hasRejectedCardsProvider = Provider<bool>(
  (ref) => !ref.watch(rejectedCardsViewModelProvider.select((state) => state.cards.isEmpty)),
);

/// 이미 만들어진 목록만 조용히 다시 읽는다 — 카드 · 받은 신청을 거절한 직후와 앱 복귀 때 카드 대기 입구가 낡지 않게.
/// 안 만들어졌으면 처음 볼 때 읽으니 서버 호출이 늘지 않는다. `ref` 와 `ProviderContainer` 를 둘 다 받는다.
void refreshRejectedCardsIfRead(
  T Function<T>(ProviderListenable<T>) read,
  bool Function(ProviderBase<Object?>) exists,
) {
  if (exists(rejectedCardsViewModelProvider)) {
    unawaited(read(rejectedCardsViewModelProvider.notifier).refresh(quiet: true));
  }
}

/// 거절한 카드(1.0.7 #20). 줄마다 [다시 신청하기] — 내 카드 거절은 [reapply](→ 보낸 신청), 받은 신청 거절은 [undo](→ 바로 매칭).
/// 읽는 방식은 받은 신청([AcceptancesViewModel])과 같다 — 만들어지면 읽고, 조용한 읽기 · 읽는 중 합치기.
/// 확인 팝업 · 화면 이동은 화면 몫이다 — 이 뷰모델은 보낸 결과를 돌려줄 뿐 상태에 남기지 않는다.
class RejectedCardsViewModel extends Notifier<RejectedCardsUiState> {
  Future<void>? _inFlight;

  /// 진행 중인 읽기에 조용하지 않은 호출이 합쳐졌다 — 끝난 뒤 조용하지 않게 한 번 더 읽는다(받은 신청과 같다).
  bool _readAgain = false;

  /// 줄을 뺄 때마다 오른다. 빼기 전에 시작한 읽기의 답은 뺀 줄이 든 옛 목록이라, 그리지 않고 한 번 더 읽는다.
  int _generation = 0;

  @override
  RejectedCardsUiState build() {
    // 만들자마자 버려졌으면(로그아웃) 읽지 않는다 — 버려진 ref 를 쓰면 던진다.
    Future.microtask(() => ref.mounted ? refresh(quiet: true) : null);
    return const RejectedCardsUiState();
  }

  /// [quiet] 은 앱 복귀 · 화면 진입 때 자동으로 읽는 경우다 — 실패해도 이미 보이는 줄을 두고 오류를 새로 띄우지 않는다.
  /// 첫 읽기(isLoading)는 quiet 여도 실패를 보인다.
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
    while (_readAgain && ref.mounted) {
      _readAgain = false;
      await _load(quiet: false);
    }
  }

  Future<void> _load({required bool quiet}) async {
    final generation = _generation;
    final result = await ref.read(cardRepositoryProvider).fetchRejectedCards();
    if (!ref.mounted) return;
    if (generation == _generation) return _apply(result, quiet: quiet);
    // 읽는 사이 줄을 뺐다 — 되살리지 않게 버리고 다시 읽는다(실패는 다시 읽은 쪽이 보인다).
    _readAgain = true;
  }

  void _apply(Result<RejectedCards> result, {required bool quiet}) {
    // 보내는 중 표시는 목록 읽기와 상관없이 그대로 둔다(연타 방지).
    final submitting = state.submittingCardId;
    state = result.when(
      onSuccess: (cards) => state.copyWith(isLoading: false, cards: cards, submittingCardId: submitting),
      onFailure: (failure) => quiet && !state.isLoading
          ? state
          : state.copyWith(isLoading: false, submittingCardId: submitting, error: failure),
    );
  }

  /// 내 카드 거절 → 다시 대화 신청. 보냈으면 참이다 — 화면이 [보낸 신청] 으로 안내한다.
  Future<bool> reapply(String cardId) async {
    final result = await _submit(cardId, (repository) => repository.reapplyCard(cardId));
    final sent = result?.when(onSuccess: (_) => true, onFailure: (_) => false) ?? false;
    // 그 줄은 [보낸 신청] 에 waiting 으로 보인다. 탭을 연 적이 없으면 refresh 가 읽지 않는다 — 열 때 읽는다.
    if (sent && ref.mounted) unawaited(ref.read(sentRequestsViewModelProvider.notifier).refresh(quiet: true));
    return sent;
  }

  /// 받은 신청에 한 거절 → 되돌려 바로 매칭. 매칭됐으면 매칭 화면(12)으로 보낼 값이다.
  /// 대화 목록은 서버의 `room_changed` 신호와 대화 탭 진입이 다시 읽는다(받은 신청 수락과 같다).
  /// 목록에 그 줄이 없으면(프로필 화면을 바로 열었다) 화면이 읽은 [nickname] 을 쓴다 — 매칭됐는데 무반응이 되지 않게.
  Future<MatchMadeArgs?> undo(String cardId, {String? nickname}) async {
    final shownNickname = state.cards.find(cardId)?.profile.nickname ?? nickname;
    final result = await _submit(cardId, (repository) => repository.undoAcceptanceRejection(cardId));
    final outcome = result?.when(onSuccess: (outcome) => outcome, onFailure: (_) => null);
    if (outcome == null || !outcome.matched || shownNickname == null) return null;
    return (nickname: shownNickname, matchId: outcome.matchId);
  }

  /// 보내는 중이면 null(연타). 버려졌으면 받은 결과만 돌려주고 상태는 건드리지 않는다.
  /// 성공은 줄을 빼고 목록을 다시 읽는다. 서버 거절(404 · 409 처럼 문구가 있는 4xx — 그 줄은 이미 빠졌거나 처리됨)은
  /// 서버 문구를 보이고 줄을 빼고 조용히 다시 읽는다. 그 밖의 실패(네트워크 · 5xx)는 오류만 올리고 줄을 둔다(대장 결정 11-24).
  Future<Result<T>?> _submit<T>(String cardId, Future<Result<T>> Function(CardRepository) send) async {
    if (state.submittingCardId != null) return null;
    state = state.copyWith(submittingCardId: cardId);
    final result = await send(ref.read(cardRepositoryProvider));
    if (!ref.mounted) return result;
    final failure = result.when<Failure?>(onSuccess: (_) => null, onFailure: (failure) => failure);
    if (failure == null) return _dropAndReread(cardId, result);
    state = state.copyWith(error: failure);
    if (failure is! ServerRejectedFailure) return result;
    return _dropAndReread(cardId, result, shown: failure);
  }

  /// 그 줄을 먼저 빼고 목록을 다시 읽는다. [shown](보일 서버 문구)이 있으면 조용히 읽고, 읽은 뒤에도 그 문구를 남긴다.
  Future<Result<T>> _dropAndReread<T>(String cardId, Result<T> result, {Failure? shown}) async {
    _generation += 1;
    state = state.copyWith(cards: state.cards.without(cardId), error: shown);
    await refresh(quiet: shown != null);
    // 다시 읽기가 성공하면 오류 칸을 지운다 — 보일 서버 문구는 읽은 뒤에 다시 올린다.
    if (shown != null && ref.mounted) state = state.copyWith(submittingCardId: state.submittingCardId, error: shown);
    return result;
  }
}
