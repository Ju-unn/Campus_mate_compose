import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/acceptance_detail_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 받은 신청 한 건마다 하나. 들어올 때마다 새로 읽는다(autoDispose) — 그사이 기한이 지났거나 상대가 사라졌을 수 있다.
final acceptanceDetailViewModelProvider =
    NotifierProvider.autoDispose.family<AcceptanceDetailViewModel, AcceptanceDetailUiState, String>(
  AcceptanceDetailViewModel.new,
);

/// 받은 신청 · 프로필 보기(pen `o4QqYR`)의 읽기만 맡는다. 거절 · 수락은 받은 신청 목록 뷰모델의 `respond` 를 그대로 쓴다 —
/// 연타 방지 · 성사 닉네임(12 화면 재료) · 목록 다시 읽기가 거기 있다. Riverpod 3 의 family 는 인자를 생성자로 받는다.
class AcceptanceDetailViewModel extends Notifier<AcceptanceDetailUiState> {
  AcceptanceDetailViewModel(this._cardId);

  final String _cardId;

  @override
  AcceptanceDetailUiState build() {
    Future.microtask(_load);
    return const AcceptanceDetailUiState();
  }

  Future<void> _load() async {
    final result = await ref.read(cardRepositoryProvider).fetchAcceptanceDetail(_cardId);
    // 응답을 기다리는 동안 화면을 떠나면 autoDispose 로 이미 버려졌다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (detail) => AcceptanceDetailUiState(isLoading: false, detail: detail),
      onFailure: (failure) => AcceptanceDetailUiState(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }
}
