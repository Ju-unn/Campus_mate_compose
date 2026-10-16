import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final communityFeedViewModelProvider =
    NotifierProvider<CommunityFeedViewModel, CommunityFeedUiState>(CommunityFeedViewModel.new);

/// 하루 첫 투표 보상 토스트(DESIGN §8.10 — 하루 한 번 5하트, 2026-10-16 사용자 확정 · 종전 10). pen 에 문구가 있으면 그것으로 바꾼다.
const String pollRewardMessage = '하트 5개를 받았어요';

/// 15d 피드. **실시간 구독은 쓰지 않는다** — 당겨서 새로 고침과 투표 응답으로 충분하다.
class CommunityFeedViewModel extends Notifier<CommunityFeedUiState> {
  /// 진행 중인 첫 쪽 요청과 그 탭. 겹쳐 불리면 **같은 탭일 때만** 이 요청을 함께 기다린다 —
  /// 다른 탭 요청을 돌려주면 앞 탭 글이 지금 탭에 뜬다.
  ({PollFeedTab tab, Future<void> done})? _inFlight;

  @override
  CommunityFeedUiState build() {
    Future.microtask(refresh);
    return const CommunityFeedUiState();
  }

  /// 지금 탭 첫 쪽을 다시 받는다(당겨서 새로 고침 · 다시 시도 · 탭 전환).
  Future<void> refresh() {
    final tab = state.tab;
    if (_inFlight case (tab: final pendingTab, :final done) when pendingTab == tab) return done;
    late final Future<void> done;
    // 앞 탭 요청이 늦게 끝나도 지금 탭의 진행 중 표시는 지우지 않는다.
    done = _loadFirst(tab).whenComplete(() {
      if (identical(_inFlight?.done, done)) _inFlight = null;
    });
    _inFlight = (tab: tab, done: done);
    return done;
  }

  /// 탭 줄을 눌렀을 때. 앞 탭 목록을 지우고 불러오는 중으로 바꾼 뒤 그 탭 첫 쪽을 받는다.
  Future<void> selectTab(PollFeedTab tab) {
    if (tab == state.tab) return Future.value();
    state = CommunityFeedUiState(tab: tab, votingIds: state.votingIds);
    return refresh();
  }

  /// 글을 올린 뒤: 전체 탭으로 옮겨 새로 받는다 — 방금 올린 글이 맨 위에 보인다(사용자 결정).
  Future<void> showAllAfterPosting() => state.tab == PollFeedTab.all ? refresh() : selectTab(PollFeedTab.all);

  Future<void> _loadFirst(PollFeedTab tab) async {
    final result = await ref.read(communityRepositoryProvider).fetchPolls(tab: tab);
    // 받는 사이 탭을 바꿨으면 버린다 — 앞 탭 목록이 지금 탭 자리에 뜨면 안 된다.
    if (state.tab != tab) return;
    state = result.when(
      // 새 상태로 갈아 끼운다 — 지난 오류 문구를 지우려면 copyWith 로는 안 된다.
      onSuccess: (page) => CommunityFeedUiState(
        tab: tab,
        isLoading: false,
        polls: page.polls,
        hasMore: page.hasMore,
        votingIds: state.votingIds,
      ),
      onFailure: (failure) => state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 목록 끝에 가까워지면 화면이 부른다. 겹쳐 불려도 한 번만 간다. 실패하면 조용히 멈추고 다음 스크롤에 다시 간다.
  /// 인기 탭은 참여 수 순 한 쪽뿐이라 부르지 않는다 — 시각 커서로 자르면 순서가 엉킨다(서버도 422 로 막는다).
  Future<void> loadMore() async {
    final tab = state.tab;
    if (!state.hasMore || state.isLoadingMore || state.polls.isEmpty || tab == PollFeedTab.popular) return;
    state = state.copyWith(isLoadingMore: true);
    final last = state.polls.last;
    final result = await ref
        .read(communityRepositoryProvider)
        .fetchPolls(tab: tab, before: last.createdAt, beforeId: last.id);
    // 받는 사이 탭을 바꿨으면 버린다 — 앞 탭의 다음 쪽이 지금 탭 목록 뒤에 붙으면 안 된다.
    if (state.tab != tab) return;
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
        if (!outcome.rewarded) return null;
        // 하트가 들어왔다 — 홈 칩 · 하트 스토어 · 설정이 읽는 잔액(내 프로필)을 다시 읽게 한다.
        ref.invalidate(myProfileProvider);
        return pollRewardMessage;
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
