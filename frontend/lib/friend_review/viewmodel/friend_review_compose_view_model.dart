import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_errors.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/model/friend_review_tags.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_compose_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 추천으로 이어진 상대 한 명당 하나(20b). 열 때마다 새로 물어본다 — 그사이 다른 기기에서 이미 썼을 수 있다.
final friendReviewComposeViewModelProvider = NotifierProvider.autoDispose
    .family<FriendReviewComposeViewModel, FriendReviewComposeUiState, String>(
  FriendReviewComposeViewModel.forProfile,
);

/// 20f 친구 코드로 확인한 상대 한 명당 하나(20b). 확인 결과로 머리를 그리고 저장은 코드로 보낸다 — 서버가 다시 찾는다.
final friendCodeReviewComposeViewModelProvider = NotifierProvider.autoDispose
    .family<FriendReviewComposeViewModel, FriendReviewComposeUiState, FriendCodeMatch>(
  FriendReviewComposeViewModel.forCode,
);

/// 20b 지인 리뷰 작성 시트. Riverpod 3 의 family 는 인자를 생성자로 받는다 — 대상은 둘 중 하나다:
/// 추천 연결(profile id, 열 때 `fetchTarget`) 또는 친구 코드(확인 결과, 서버에 다시 묻지 않는다).
class FriendReviewComposeViewModel extends Notifier<FriendReviewComposeUiState> {
  FriendReviewComposeViewModel.forProfile(String revieweeId) : _revieweeId = revieweeId, _friend = null;

  FriendReviewComposeViewModel.forCode(FriendCodeMatch friend) : _revieweeId = null, _friend = friend;

  final String? _revieweeId;
  final FriendCodeMatch? _friend;

  @override
  FriendReviewComposeUiState build() {
    final friend = _friend;
    if (friend != null) return FriendReviewComposeUiState(isLoading: false, nickname: friend.nickname);
    Future.microtask(_load);
    return const FriendReviewComposeUiState();
  }

  Future<void> _load() async {
    final result = await ref.read(friendReviewRepositoryProvider).fetchTarget(_revieweeId!);
    // 응답을 기다리는 동안 시트를 닫으면 autoDispose 로 이미 버려졌다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (target) => state.copyWith(isLoading: false, nickname: target.nickname),
      onFailure: (failure) => isAlreadyWritten(failure)
          ? state.copyWith(isLoading: false, alreadyWritten: true)
          : state.copyWith(isLoading: false, loadError: failure.toDisplayMessage()),
    );
  }

  /// 이미 골랐으면 뺀다. 아니면 [friendReviewMaxTags] 까지만 뒤에 붙이고, 다 찼으면 무시한다.
  void toggleTag(String tag) {
    final selected = state.selected;
    if (selected.contains(tag)) {
      state = state.copyWith(selected: selected.where((t) => t != tag).toList());
    } else if (selected.length < friendReviewMaxTags) {
      state = state.copyWith(selected: [...selected, tag]);
    }
  }

  void setComment(String comment) => state = state.copyWith(comment: comment);

  /// 보내는 중이거나 이미 보냈으면 아무 것도 하지 않는다 — 한 번 더 눌러도 한 번만 나간다.
  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(isSubmitting: true);
    final result = await _create();
    // 응답을 기다리는 동안 시트를 닫으면 autoDispose 로 이미 버려졌다. 서버에는 이미 갔으니 여기서 끝낸다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) => state.copyWith(isSubmitting: false, submitted: true),
      // 409("이미 리뷰를 남겼어요") · 404 · 429 도 그 밖의 실패도 같은 방식으로 보여준다 — 계획서에 재시도 · 수정 화면이 없다.
      onFailure: (failure) => state.copyWith(isSubmitting: false, submitError: friendReviewFailureMessage(failure)),
    );
  }

  Future<Result<void>> _create() {
    final repository = ref.read(friendReviewRepositoryProvider);
    final friend = _friend;
    if (friend != null) {
      return repository.createReviewByCode(friendCode: friend.code, tags: state.selected, comment: state.comment);
    }
    return repository.create(revieweeId: _revieweeId!, tags: state.selected, comment: state.comment);
  }
}
