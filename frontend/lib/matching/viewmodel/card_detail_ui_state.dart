import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_repository.dart';

/// 10b 상세 화면(`TORAs`)의 상태. 조각 2 의 `*_ui_state.dart` 들과 같은 모양이다 —
/// [errorMessage] 는 [copyWith] 에서 덮어쓰기라 null 로도 지워진다.
class CardDetailUiState {
  const CardDetailUiState({
    this.detail,
    this.isSubmitting = false,
    this.decided = false,
    this.decision,
    this.errorMessage,
  });

  final CardDetail? detail;
  final bool isSubmitting;
  final bool decided;
  final CardDecision? decision;
  final String? errorMessage;

  /// 화면이 성향 바 9개를 그릴 때 쓴다. 아직 못 읽었으면 빈 목록이다.
  List<double> get survey => detail?.survey ?? const [];

  CardDetailUiState copyWith({
    CardDetail? detail,
    bool? isSubmitting,
    bool? decided,
    CardDecision? decision,
    String? errorMessage,
  }) {
    return CardDetailUiState(
      detail: detail ?? this.detail,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      decided: decided ?? this.decided,
      decision: decision ?? this.decision,
      errorMessage: errorMessage,
    );
  }
}
