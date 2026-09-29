import 'package:campus_mate/friend_review/model/friend_review_errors.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 같은 목록 뷰가 가져오는 세 곳(20c 내가 받은 리뷰 · 20e 내가 쓴 리뷰 · 14c/14d 상대에게 쓴 리뷰).
enum FriendReviewListSource { about, received, written }

/// [FriendReviewListSource.about] 만 `profileId` 를 쓴다(14c/14d). `received` · `written` 은 본인 것이라 필요 없다.
/// 15 지인 리뷰 칸도 같은 인자로 개수를 읽는다 — 20e 에서 지우면 15 로 돌아왔을 때 개수가 이미 줄어 있다.
final friendReviewListViewModelProvider = NotifierProvider.autoDispose.family<
    FriendReviewListViewModel,
    FriendReviewListUiState,
    ({FriendReviewListSource source, String? profileId})>(FriendReviewListViewModel.new);

/// 20c · 20e · 14c/14d 리뷰 목록. 보는 곳이 없어졌다 다시 생기면 새로 읽는다 — 그사이 리뷰가 늘었을 수 있다.
/// 15 가 같은 목록을 쥐고 있으면 버려지지 않으므로 20c · 20e 는 들어올 때 [refresh] 를 부른다(검토 필수 1).
class FriendReviewListViewModel extends Notifier<FriendReviewListUiState> {
  FriendReviewListViewModel(this._args);

  final ({FriendReviewListSource source, String? profileId}) _args;

  /// 지우는 중인 리뷰 → 그 요청. 같은 리뷰를 또 지우라고 하면 새로 보내지 않고 이것을 돌려준다.
  final Map<String, Future<String?>> _deleting = {};

  /// 지운 리뷰. 지우기 전에 나간 읽기가 늦게 오면 옛 목록에 섞여 있다 — 되살리지 않는다(재검토 권고 1).
  final Set<String> _removed = {};

  @override
  FriendReviewListUiState build() {
    Future.microtask(_load);
    return const FriendReviewListUiState();
  }

  Future<void> _load() async {
    final repository = ref.read(friendReviewRepositoryProvider);
    final result = switch (_args.source) {
      FriendReviewListSource.about => await repository.fetchAbout(_args.profileId!),
      FriendReviewListSource.received => await repository.fetchReceived(),
      FriendReviewListSource.written => await repository.fetchWritten(),
    };
    // 응답을 기다리는 동안 화면을 떠나면 autoDispose 로 이미 버려졌다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (reviews) => FriendReviewListUiState(
        isLoading: false,
        reviews: [for (final review in reviews) if (!_removed.contains(review.id)) review],
      ),
      // 다시 읽다 실패하면 보던 목록을 그대로 둔다 — 멀쩡한 목록을 오류 화면으로 바꾸지 않는다.
      onFailure: (failure) => state.reviews.isNotEmpty
          ? state
          : FriendReviewListUiState(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 목록을 둔 채 다시 읽는다(깜빡임 없음). 처음 읽는 중이면 그 결과를 기다리면 되니 또 보내지 않는다.
  Future<void> refresh() async {
    if (!state.isLoading) await _load();
  }

  /// 20e 내가 쓴 리뷰 지우기. 성공이면 목록에서 빼고 null, 실패면 보여 줄 문구(카드는 그대로).
  /// 404(그새 없어짐)는 문구를 돌려주되 목록에서도 뺀다.
  Future<String?> delete(String reviewId) =>
      // 콜백이 remove 의 반환값(바로 이 Future)을 돌려주면 whenComplete 가 자기를 기다려 멈춘다 — 블록으로 버린다.
      _deleting[reviewId] ??= _delete(reviewId).whenComplete(() {
        _deleting.remove(reviewId);
      });

  Future<String?> _delete(String reviewId) async {
    final result = await ref.read(friendReviewRepositoryProvider).delete(reviewId);
    final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
    if ((failure == null || isReviewGone(failure)) && ref.mounted) {
      _removed.add(reviewId);
      state = FriendReviewListUiState(
        isLoading: false,
        reviews: [for (final review in state.reviews) if (review.id != reviewId) review],
      );
    }
    return failure?.toDisplayMessage();
  }
}
