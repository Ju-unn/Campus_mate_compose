import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/model/data/poll_vote_notice.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/community/viewmodel/poll_detail_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 글 하나당 하나. 화면을 닫으면 버려진다.
final pollDetailViewModelProvider =
    NotifierProvider.autoDispose.family<PollDetailViewModel, PollDetailUiState, String>(PollDetailViewModel.new);

/// 17c 투표 상세. **pollId 만으로 열린다** — 푸시 알림에서 피드를 거치지 않고 들어와도 `fetchPoll` 로 글을 읽는다.
/// 피드가 이미 그 글을 들고 있으면 그 값으로 먼저 그려 깜박이지 않게 하고, 뒤에서 한 번 더 읽어 댓글 수를 맞춘다.
class PollDetailViewModel extends Notifier<PollDetailUiState> {
  PollDetailViewModel(this._pollId);

  final String _pollId;

  /// **서버에서 받은** 마지막 댓글. 더 보기 커서다 — 내가 방금 보낸 댓글은 목록 끝에 붙지만 커서는 되지 않는다
  /// (되면 아직 안 읽은 사이 댓글을 건너뛴다).
  PollComment? _lastFetched;

  /// 읽는 중(첫 쪽 · 이어 읽기)에 새 댓글 푸시가 왔다는 표시. 읽기가 끝나면 한 번 더 읽는다 — 버리면 다음 푸시까지 안 보인다.
  bool _appendPending = false;

  @override
  PollDetailUiState build() {
    final inFeed = _fromFeed();
    unawaited(Future.microtask(() async {
      await (_loadPoll(), _loadComments()).wait;
    }));
    return PollDetailUiState(poll: inFeed, isLoadingPoll: inFeed == null);
  }

  /// 피드가 이미 떠 있을 때만 거기서 꺼낸다 — 알림 한 번에 피드 전체를 읽게 만들지 않는다.
  Poll? _fromFeed() {
    if (!ref.exists(communityFeedViewModelProvider)) return null;
    return ref.read(communityFeedViewModelProvider).polls.where((poll) => poll.id == _pollId).firstOrNull;
  }

  /// 아래로 당겨 새로 고침 · 오류 화면의 "다시 시도". 글과 댓글 첫 쪽을 늘 다시 읽는다(사용자 11-11 「당기면 갱신」).
  /// 보이던 글 · 댓글은 받는 동안 그대로 두고, 실패해도 이미 보이는 것은 지우지 않는다(피드 새로 고침과 같다).
  Future<void> refresh() async {
    await (_loadPoll(), _loadComments()).wait;
  }

  /// 내 글에 새 댓글이 달렸다는 푸시를 받았을 때(상세가 열려 있다). **화면 상태를 비우지 않는다** — 글 값 · 이미 읽은 댓글 ·
  /// 입력줄 · 스크롤 자리를 그대로 두고, 댓글 수(글)를 맞추고 새 댓글만 끝에 붙인다.
  /// 끝까지 읽은 목록이면 마지막으로 받은 줄 다음부터 읽고, 아직 더 읽을 게 남았으면 스크롤 때 이어 읽는다.
  /// 백그라운드 읽기라 실패해도 조용하다(오류를 띄우지 않는다).
  Future<void> refreshForNewComment() async {
    await (_loadPoll(), _appendNewComments()).wait;
  }

  Future<void> _appendNewComments() async {
    final last = _lastFetched;
    if (state.isLoadingComments || state.isLoadingMoreComments) {
      _appendPending = true;
      return;
    }
    // 첫 쪽을 못 읽은 상태는 "다시 시도" 가 처음부터 읽는다. 더 읽을 게 남았으면 스크롤 때 이어 읽는다.
    if (state.commentsError != null || state.hasMoreComments) return;
    final result = await ref
        .read(communityRepositoryProvider)
        .fetchComments(_pollId, after: last?.createdAt, afterId: last?.id);
    if (!ref.mounted) return;
    result.when(
      onSuccess: (page) {
        _lastFetched = page.comments.lastOrNull ?? last;
        state = state.copyWith(hasMoreComments: page.hasMore, comments: _merge(state.comments, page.comments));
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadPoll() async {
    if (state.poll == null) state = state.copyWith(isLoadingPoll: true, pollError: null);
    final result = await ref.read(communityRepositoryProvider).fetchPoll(_pollId);
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (poll) => state.copyWith(poll: poll, isLoadingPoll: false, pollError: null),
      // 글이 이미 보이면 조용히 넘어간다 — 댓글 수가 조금 낡을 뿐이다.
      onFailure: (failure) => state.poll == null
          ? state.copyWith(isLoadingPoll: false, pollError: failure)
          : state.copyWith(isLoadingPoll: false),
    );
  }

  /// 읽는 중에 온 푸시가 있었으면 지금 한 번 읽는다.
  Future<void> _runPendingAppend() async {
    if (!_appendPending || !ref.mounted) return;
    _appendPending = false;
    await _appendNewComments();
  }

  /// 첫 쪽을 읽어 목록을 갈아 끼운다. 새로 고침이면 보이던 목록을 읽는 동안 그대로 둔다(화면은 목록이 비었을 때만 스피너).
  Future<void> _loadComments() async {
    final before = state.comments;
    state = state.copyWith(isLoadingComments: true, commentsError: null);
    final result = await ref.read(communityRepositoryProvider).fetchComments(_pollId);
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (page) {
        _lastFetched = page.comments.lastOrNull;
        // 읽는 사이 붙은 댓글(방금 보낸 것 · 이어 읽은 쪽)은 받은 첫 쪽에 없어도 남긴다 — 커서는 받은 첫 쪽 끝이라 이어 읽기가 맞춘다.
        final addedMeanwhile = state.comments.where((comment) => !before.contains(comment));
        return state.copyWith(
          isLoadingComments: false,
          comments: _merge(page.comments, addedMeanwhile.toList()),
          hasMoreComments: page.hasMore,
          moreError: null,
        );
      },
      // 이미 보이는 목록이 있으면 조용히 둔다 — 글 다시 읽기 실패와 같다.
      onFailure: (failure) => state.comments.isEmpty
          ? state.copyWith(isLoadingComments: false, commentsError: failure)
          : state.copyWith(isLoadingComments: false),
    );
    await _runPendingAppend();
  }

  /// 목록 끝 가까이 내리면 화면이 부른다(인스타처럼 버튼 없이 다음 10개). 겹쳐 불려도 한 번만 간다 —
  /// 읽는 중 · 더 없음 · 앞 요청이 실패한 채(다시 시도를 눌러야 한다)면 아무것도 하지 않는다.
  Future<void> loadMore() async {
    final last = _lastFetched;
    if (!state.hasMoreComments || state.isLoadingMoreComments || state.moreError != null || last == null) return;
    state = state.copyWith(isLoadingMoreComments: true);
    final result = await ref.read(communityRepositoryProvider).fetchComments(_pollId, after: last.createdAt, afterId: last.id);
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (page) {
        _lastFetched = page.comments.lastOrNull ?? last;
        return state.copyWith(
          isLoadingMoreComments: false,
          hasMoreComments: page.hasMore,
          comments: _merge(state.comments, page.comments),
        );
      },
      onFailure: (failure) => state.copyWith(isLoadingMoreComments: false, moreError: failure),
    );
    await _runPendingAppend();
  }

  /// 목록 끝 오류의 "다시 시도".
  Future<void> retryLoadMore() {
    state = state.copyWith(moreError: null);
    return loadMore();
  }

  /// 이미 있는 댓글(내가 방금 보낸 것)은 한 번만 두고, 시각 순으로 맞춘다 — 같은 시각이면 id 순(서버 커서와 같다).
  List<PollComment> _merge(List<PollComment> have, List<PollComment> fetched) {
    final byId = {for (final comment in [...have, ...fetched]) comment.id: comment};
    return byId.values.toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
  }

  /// 댓글 보내기. 성공이면 null, 실패면 이유(글은 그대로 두고 화면이 입력칸에 되돌린다).
  /// 보내는 중에 또 부르거나 공백뿐이면 아무것도 하지 않는다.
  Future<Failure?> send(String text) async {
    final body = text.trim();
    if (body.isEmpty || state.isSending) return null;
    state = state.copyWith(isSending: true);
    final result = await ref.read(communityRepositoryProvider).addComment(_pollId, body);
    if (!ref.mounted) return null;
    return result.when(
      onSuccess: (comment) {
        // 푸시로 읽어 온 목록이 이미 내 댓글을 들고 있을 수 있다(응답보다 먼저 도착) — 그때는 숫자도 이미 서버 값이다.
        final alreadyThere = state.comments.any((existing) => existing.id == comment.id);
        state = state.copyWith(isSending: false, comments: _merge(state.comments, [comment]));
        if (!alreadyThere) _setCommentCount(_countNow() + 1);
        return null;
      },
      onFailure: (failure) {
        state = state.copyWith(isSending: false);
        return failure;
      },
    );
  }

  /// 댓글 지우기. 서버가 "없다" 고 답하면(이미 지워졌다) 목록에서는 뺀다. 연결 실패면 그대로 둔다.
  Future<Failure?> deleteComment(String commentId) async {
    final result = await ref.read(communityRepositoryProvider).deleteComment(commentId);
    if (!ref.mounted) return null;
    return result.when(
      onSuccess: (_) {
        _remove(commentId);
        return null;
      },
      onFailure: (failure) {
        if (failure is ServerRejectedFailure) _remove(commentId);
        return failure;
      },
    );
  }

  void _remove(String commentId) {
    state = state.copyWith(comments: state.comments.where((comment) => comment.id != commentId).toList());
    _setCommentCount(_countNow() - 1);
  }

  int _countNow() => state.poll?.commentCount ?? 0;

  /// 헤더 숫자를 맞추고, 피드에 같은 글이 있으면 그 카드의 숫자도 맞춘다.
  void _setCommentCount(int count) {
    final poll = state.poll;
    if (poll == null) return;
    final next = count < 0 ? 0 : count;
    state = state.copyWith(poll: poll.withCommentCount(next));
    if (ref.exists(communityFeedViewModelProvider)) {
      ref.read(communityFeedViewModelProvider.notifier).updateCommentCount(_pollId, next);
    }
  }

  /// 투표는 피드 뷰모델이 한다(분석 이벤트 · 하트 잔액 · 실패 때 다시 읽기가 거기 있다). 끝나면 이 글을 맞춘다 —
  /// 피드에 없던 글(알림으로 들어옴)이면 다시 읽는다.
  Future<PollVoteNotice?> vote(PollChoice choice) async {
    if (state.isVoting) return null;
    state = state.copyWith(isVoting: true);
    final notice = await ref.read(communityFeedViewModelProvider.notifier).vote(_pollId, choice);
    if (!ref.mounted) return notice;
    final inFeed = _fromFeed();
    if (inFeed == null) {
      await _loadPoll();
      if (!ref.mounted) return notice;
    } else {
      // 댓글 수는 이 화면이 더 새 값이다.
      state = state.copyWith(poll: inFeed.withCommentCount(_countNow()));
    }
    state = state.copyWith(isVoting: false);
    return notice;
  }
}
