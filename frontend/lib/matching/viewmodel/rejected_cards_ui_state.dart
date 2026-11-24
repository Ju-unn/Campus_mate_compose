import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/data/rejected_card.dart';

/// 거절한 카드(대화 탭 [거절한 카드], 1.0.7 #20)의 상태.
/// [submittingCardId] 와 [error] 는 [copyWith] 에서 덮어쓰기다 — null 로도 지워져야 한다(받은 신청과 같다).
class RejectedCardsUiState {
  const RejectedCardsUiState({
    this.isLoading = true,
    this.cards = RejectedCards.empty,
    this.submittingCardId,
    this.error,
  });

  final bool isLoading;

  /// 서버 순서 그대로(최신 거절 먼저).
  final RejectedCards cards;

  /// 다시 신청 · 되돌리기를 보내는 중인 줄. 하나라도 있으면 다른 줄도 누를 수 없다(연타 방지).
  final String? submittingCardId;
  final Failure? error;

  RejectedCardsUiState copyWith({
    bool? isLoading,
    RejectedCards? cards,
    String? submittingCardId,
    Failure? error,
  }) {
    return RejectedCardsUiState(
      isLoading: isLoading ?? this.isLoading,
      cards: cards ?? this.cards,
      submittingCardId: submittingCardId,
      error: error,
    );
  }
}
