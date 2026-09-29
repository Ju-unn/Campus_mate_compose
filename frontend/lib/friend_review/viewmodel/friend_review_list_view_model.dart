import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 같은 목록 뷰가 가져오는 두 곳(20c 내가 받은 리뷰 · 14c/14d 상대에게 쓴 리뷰).
enum FriendReviewListSource { about, received }

/// [FriendReviewListSource.about] 만 `profileId` 를 쓴다(14c/14d). `received` 는 본인 것이라 필요 없다.
final friendReviewListViewModelProvider = NotifierProvider.autoDispose.family<
    FriendReviewListViewModel,
    FriendReviewListUiState,
    ({FriendReviewListSource source, String? profileId})>(FriendReviewListViewModel.new);

/// 20c · 14c/14d 리뷰 목록. 들어올 때마다 새로 읽는다 — 그사이 리뷰가 늘었을 수 있다.
class FriendReviewListViewModel extends Notifier<FriendReviewListUiState> {
  FriendReviewListViewModel(this._args);

  final ({FriendReviewListSource source, String? profileId}) _args;

  @override
  FriendReviewListUiState build() {
    Future.microtask(_load);
    return const FriendReviewListUiState();
  }

  Future<void> _load() async {
    final repository = ref.read(friendReviewRepositoryProvider);
    final result = _args.source == FriendReviewListSource.about
        ? await repository.fetchAbout(_args.profileId!)
        : await repository.fetchReceived();
    // 응답을 기다리는 동안 화면을 떠나면 autoDispose 로 이미 버려졌다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (reviews) => FriendReviewListUiState(isLoading: false, reviews: reviews),
      onFailure: (failure) =>
          FriendReviewListUiState(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }
}
