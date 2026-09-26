import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final communityFeedViewModelProvider =
    NotifierProvider<CommunityFeedViewModel, CommunityFeedUiState>(CommunityFeedViewModel.new);

/// 하루 첫 투표 보상 토스트(DESIGN §8.10 — 하루 한 번 10하트). pen 에 문구가 있으면 그것으로 바꾼다.
const String pollRewardMessage = '하트 10개를 받았어요';

/// 15d 피드. **실시간 구독은 쓰지 않는다** — 당겨서 새로 고침과 투표 응답으로 충분하다.
class CommunityFeedViewModel extends Notifier<CommunityFeedUiState> {
  Future<void>? _inFlight;

  @override
  CommunityFeedUiState build() {
    Future.microtask(refresh);
    return const CommunityFeedUiState();
  }

  Future<void> refresh() => _inFlight ??= _loadFirst().whenComplete(() => _inFlight = null);

  Future<void> _loadFirst() async {
    final result = await ref.read(communityRepositoryProvider).fetchPolls();
    state = result.when(
      // 새 상태로 갈아 끼운다 — 지난 오류 문구를 지우려면 copyWith 로는 안 된다.
      onSuccess: (page) => CommunityFeedUiState(
        isLoading: false,
        polls: page.polls,
        hasMore: page.hasMore,
        votingIds: state.votingIds,
      ),
      onFailure: (failure) => state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 목록 끝에 가까워지면 화면이 부른다. 겹쳐 불려도 한 번만 간다. 실패하면 조용히 멈추고 다음 스크롤에 다시 간다.
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.polls.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);
    final last = state.polls.last;
    final result = await ref
        .read(communityRepositoryProvider)
        .fetchPolls(before: last.createdAt, beforeId: last.id);
    state = result.when(
      onSuccess: (page) {
        // 새로 고침과 겹치면 같은 글이 두 번 올 수 있다 — id 로 거른다.
        final seen = state.polls.map((poll) => poll.id).toSet();
        return state.copyWith(
          isLoadingMore: false,
          hasMore: page.hasMore,
          polls: [...state.polls, ...page.polls.where((poll) => !seen.contains(poll.id))],
        );
      },
      onFailure: (_) => state.copyWith(isLoadingMore: false),
    );
  }

  /// 투표. 화면이 띄울 토스트 문구를 돌려준다(없으면 null).
  Future<String?> vote(String pollId, PollChoice choice) async {
    if (state.votingIds.contains(pollId)) return null;
    state = state.copyWith(votingIds: {...state.votingIds, pollId});
    final result = await ref.read(communityRepositoryProvider).vote(pollId, choice);
    final message = await result.when<Future<String?>>(
      onSuccess: (outcome) async {
        _replace(outcome.poll);
        return outcome.rewarded ? pollRewardMessage : null;
      },
      onFailure: (failure) async {
        // 다른 기기에서 이미 투표했거나(409) 글이 사라졌을 수 있다(404) — 그 글만 다시 읽어 서버에 맞춘다.
        await _reloadOne(pollId);
        return failure.toDisplayMessage();
      },
    );
    state = state.copyWith(votingIds: {...state.votingIds}..remove(pollId));
    return message;
  }

  /// 내 글 지우기. 성공하면 null, 실패하면 문구.
  Future<String?> delete(String pollId) async {
    final result = await ref.read(communityRepositoryProvider).deletePoll(pollId);
    return result.when(
      onSuccess: (_) {
        _remove(pollId);
        return null;
      },
      onFailure: (failure) => failure.toDisplayMessage(),
    );
  }

  Future<void> _reloadOne(String pollId) async {
    final result = await ref.read(communityRepositoryProvider).fetchPoll(pollId);
    result.when(
      onSuccess: _replace,
      onFailure: (failure) {
        // 서버가 "없다" 고 답한 것만 뺀다. 연결 실패로 빼면 멀쩡한 글이 사라진다.
        if (failure is ServerRejectedFailure) _remove(pollId);
      },
    );
  }

  void _replace(Poll poll) =>
      state = state.copyWith(polls: [for (final p in state.polls) p.id == poll.id ? poll : p]);

  void _remove(String pollId) =>
      state = state.copyWith(polls: state.polls.where((poll) => poll.id != pollId).toList());
}
