import 'package:campus_mate/friend_review/model/friend_review.dart';

/// 20b 작성 시트 하나의 상태.
class FriendReviewComposeUiState {
  const FriendReviewComposeUiState({
    this.isLoading = true,
    this.target,
    this.alreadyWritten = false,
    this.loadError,
    this.selected = const [],
    this.comment = '',
    this.isSubmitting = false,
    this.submitted = false,
    this.submitError,
  });

  final bool isLoading;
  final ReviewTarget? target;

  /// 열기 전 물음(`fetchTarget`)이 409 — 시트를 띄우지 않고 토스트로 안내할 근거(계획서 P3).
  final bool alreadyWritten;

  /// [alreadyWritten] 이 아닌 다른 실패(네트워크 등) 문구.
  final String? loadError;

  /// 고른 순서 그대로 — submit 이 이 순서로 보낸다.
  final List<String> selected;
  final String comment;
  final bool isSubmitting;
  final bool submitted;

  /// 보내기 실패 문구(409 포함, 전부 같은 방식으로 보여준다).
  final String? submitError;

  /// 태그를 하나 이상 골랐고, 보내는 중이 아니고, 아직 끝나지 않았을 때.
  bool get canSubmit => selected.isNotEmpty && !isSubmitting && !submitted;

  /// [loadError] · [submitError] 는 넘기지 않으면 지워진다 — 다음 시도에서 지난 실패 문구가 남지 않는다.
  FriendReviewComposeUiState copyWith({
    bool? isLoading,
    ReviewTarget? target,
    bool? alreadyWritten,
    String? loadError,
    List<String>? selected,
    String? comment,
    bool? isSubmitting,
    bool? submitted,
    String? submitError,
  }) {
    return FriendReviewComposeUiState(
      isLoading: isLoading ?? this.isLoading,
      target: target ?? this.target,
      alreadyWritten: alreadyWritten ?? this.alreadyWritten,
      loadError: loadError,
      selected: selected ?? this.selected,
      comment: comment ?? this.comment,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitted: submitted ?? this.submitted,
      submitError: submitError,
    );
  }
}
