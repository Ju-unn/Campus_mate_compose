import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_vote_notice.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final communityFeedViewModelProvider =
    NotifierProvider<CommunityFeedViewModel, CommunityFeedUiState>(CommunityFeedViewModel.new);

/// 15d 피드 — 투표 · 게시물(할 일 19). **실시간 구독은 쓰지 않는다** — 당겨서 새로 고침과 투표 응답으로 충분하다.
class CommunityFeedViewModel extends Notifier<CommunityFeedUiState> {
  /// 진행 중인 첫 쪽 요청과 그 탭. 겹쳐 불리면 **같은 탭일 때만** 이 요청을 함께 기다린다 —
  /// 다른 탭 요청을 돌려주면 앞 탭 글이 지금 탭에 뜬다.
  ({CommunityFeedTab tab, Future<void> done})? _inFlight;

  @override
  CommunityFeedUiState build() {
    // 만들자마자 버려졌으면(로그아웃) 읽지 않는다 — 버려진 ref 를 쓰면 던진다.
    Future.microtask(() => ref.mounted ? refresh() : null);
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
  Future<void> selectTab(CommunityFeedTab tab) {
    if (tab == state.tab) return Future.value();
    state = CommunityFeedUiState(tab: tab, votingIds: state.votingIds);
    return refresh();
  }

  /// 글을 올린 뒤: 전체 탭으로 옮겨 새로 받는다 — 방금 올린 글이 맨 위에 보인다(사용자 결정).
  Future<void> showAllAfterPosting() =>
      state.tab == CommunityFeedTab.all ? refresh() : selectTab(CommunityFeedTab.all);

  Future<void> _loadFirst(CommunityFeedTab tab) async {
    final result = await ref.read(communityRepositoryProvider).fetchFeed(tab: tab);
    // 받는 사이 로그아웃으로 버려졌거나 탭을 바꿨으면 버린다 — 버려진 상태를 건드리면 던지고, 앞 탭 목록이 지금 탭 자리에 뜨면 안 된다.
    if (!ref.mounted || state.tab != tab) return;
    state = result.when(
      // 새 상태로 갈아 끼운다 — 지난 오류 문구를 지우려면 copyWith 로는 안 된다.
      onSuccess: (page) => CommunityFeedUiState(
        tab: tab,
        isLoading: false,
        items: page.items,
        hasMore: page.hasMore,
        votingIds: state.votingIds,
      ),
      onFailure: (failure) => state.copyWith(isLoading: false, error: failure),
    );
  }

  /// 목록 끝에 가까워지면 화면이 부른다. 겹쳐 불려도 한 번만 간다. 실패하면 조용히 멈추고 다음 스크롤에 다시 간다.
  /// 인기 탭은 참여 수 순 한 쪽뿐이라 부르지 않는다 — 시각 커서로 자르면 순서가 엉킨다(서버도 422 로 막는다).
  Future<void> loadMore() async {
    final tab = state.tab;
    if (!state.hasMore || state.isLoadingMore || state.items.isEmpty || !tab.pages()) return;
    state = state.copyWith(isLoadingMore: true);
    final last = state.items.last;
    final result = await ref
        .read(communityRepositoryProvider)
        .fetchFeed(tab: tab, before: (createdAt: last.createdAt, id: last.id));
    // 받는 사이 로그아웃으로 버려졌거나 탭을 바꿨으면 버린다 — 앞 탭의 다음 쪽이 지금 탭 목록 뒤에 붙으면 안 된다.
    if (!ref.mounted || state.tab != tab) return;
    state = result.when(
      onSuccess: (page) {
        // 새로 고침과 겹치면 같은 글이 두 번 올 수 있다 — id 로 거른다.
        final seen = state.items.map((item) => item.id).toSet();
        return state.copyWith(
          isLoadingMore: false,
          hasMore: page.hasMore,
          items: [...state.items, ...page.items.where((item) => !seen.contains(item.id))],
        );
      },
      onFailure: (_) => state.copyWith(isLoadingMore: false),
    );
  }

  /// 투표. 화면이 토스트로 알릴 것을 돌려준다(없으면 null). 하루 첫 투표 보상은 5하트다(DESIGN §8.10, 2026-10-16 사용자 확정 · 종전 10).
  Future<PollVoteNotice?> vote(String pollId, PollChoice choice) async {
    if (state.votingIds.contains(pollId)) return null;
    state = state.copyWith(votingIds: {...state.votingIds, pollId});
    final result = await ref.read(communityRepositoryProvider).vote(pollId, choice);
    // 보내는 사이 로그아웃으로 버려졌으면 늦게 온 답은 버린다 — 상태 · ref 를 건드리면 던진다. 알릴 화면도 없다.
    if (!ref.mounted) return null;
    final notice = await result.when<Future<PollVoteNotice?>>(
      onSuccess: (outcome) async {
        _replaceVoted(outcome.poll);
        // 사용 통계 `poll_vote` — 서버가 투표를 받아 준 뒤에만. 질문 id · 고른 보기 · 보상 여부는 싣지 않는다.
        ref.read(analyticsServiceProvider).logPollVote();
        if (!outcome.rewarded) return null;
        // 하트가 들어왔다 — 홈 칩 · 하트 스토어 · 설정이 읽는 잔액(내 프로필)을 다시 읽게 한다.
        ref.invalidate(myProfileProvider);
        return const PollVoteNotice.reward();
      },
      onFailure: (failure) async {
        // 다른 기기에서 이미 투표했거나(409) 글이 사라졌을 수 있다(404) — 그 글만 다시 읽어 서버에 맞춘다.
        await _reloadOne(pollId);
        return PollVoteNotice.failed(failure);
      },
    );
    if (!ref.mounted) return null;
    state = state.copyWith(votingIds: {...state.votingIds}..remove(pollId));
    return notice;
  }

  /// 내 글(투표 · 게시물) 지우기. 성공하면 null, 실패하면 그 이유.
  Future<Failure?> delete(String itemId) async {
    final result = await ref.read(communityRepositoryProvider).deleteItem(itemId);
    return result.when(
      onSuccess: (_) {
        // 지우는 사이 로그아웃으로 버려졌으면 목록은 없다 — 지워진 것은 그대로 알린다.
        if (ref.mounted) _remove(itemId);
        return null;
      },
      onFailure: (failure) => failure,
    );
  }

  Future<void> _reloadOne(String pollId) async {
    final result = await ref.read(communityRepositoryProvider).fetchItem(pollId);
    if (!ref.mounted) return;
    result.when(
      onSuccess: _replace,
      onFailure: (failure) {
        // 서버가 "없다" 고 답한 것만 뺀다. 연결 실패로 빼면 멀쩡한 글이 사라진다.
        if (failure is ServerRejectedFailure) _remove(pollId);
      },
    );
  }

  /// 상세에서 댓글을 쓰거나 지운 뒤 피드 카드의 "댓글 N" 을 맞춘다. 피드에 없는 글이면 아무 일도 없다.
  void updateCommentCount(String itemId, int count) => state = state.copyWith(
        items: [for (final item in state.items) item.id == itemId ? item.withCommentCount(count) : item],
      );

  void _replace(CommunityItem fresh) =>
      state = state.copyWith(items: [for (final item in state.items) item.id == fresh.id ? fresh : item]);

  /// 투표 응답(옛 카드 모양)을 그 줄에 얹는다 — 카테고리는 줄 값을 지킨다([CommunityItem.withVote]).
  void _replaceVoted(Poll voted) => state = state.copyWith(
        items: [for (final item in state.items) item.id == voted.id ? item.withVote(voted) : item],
      );

  void _remove(String itemId) =>
      state = state.copyWith(items: state.items.where((item) => item.id != itemId).toList());
}
