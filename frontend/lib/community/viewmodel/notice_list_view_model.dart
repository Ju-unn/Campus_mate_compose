import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/viewmodel/notice_list_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 피드 띠와 공지 목록이 같이 본다 — 피드가 열려 있는 동안 살아 있어 목록을 열 때 다시 받지 않고 바로 그린다.
final noticeListViewModelProvider =
    NotifierProvider<NoticeListViewModel, NoticeListUiState>(NoticeListViewModel.new);

/// 공지(할 일 21) 목록 · 피드 띠. 서버가 최신순 20개씩 주고, 더 받기는 맨 아래 공지의 시각 · id 커서다(피드와 같다).
class NoticeListViewModel extends Notifier<NoticeListUiState> {
  /// 진행 중인 첫 쪽 요청. 겹쳐 불리면(build 의 첫 읽기 · 당겨서 새로 고침) 이 요청을 함께 기다린다.
  Future<void>? _inFlight;

  @override
  NoticeListUiState build() {
    // 만들자마자 버려졌으면(로그아웃) 읽지 않는다 — 버려진 ref 를 쓰면 던진다.
    Future.microtask(() => ref.mounted ? refresh() : null);
    return const NoticeListUiState();
  }

  /// 첫 쪽을 다시 받는다(피드 · 목록 당겨서 새로 고침, 다시 시도).
  Future<void> refresh() => _inFlight ??= _loadFirst().whenComplete(() => _inFlight = null);

  Future<void> _loadFirst() async {
    final result = await ref.read(communityRepositoryProvider).fetchNotices();
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (page) => NoticeListUiState(isLoading: false, items: page.items, hasMore: page.hasMore),
      // 이미 보이는 공지가 있으면 조용히 둔다 — 피드 새로 고침과 같다.
      onFailure: (failure) => state.items.isEmpty
          ? NoticeListUiState(isLoading: false, error: failure)
          : NoticeListUiState(isLoading: false, items: state.items, hasMore: state.hasMore),
    );
  }

  /// 목록 끝 가까이 내리면 화면이 부른다. 겹쳐 불려도 한 번만 간다. 실패하면 조용히 멈추고 다음 스크롤에 다시 간다.
  Future<void> loadMore() async {
    final last = state.items.lastOrNull;
    if (!state.hasMore || state.isLoadingMore || last == null) return;
    state = state.copyWith(isLoadingMore: true);
    final result =
        await ref.read(communityRepositoryProvider).fetchNotices(before: (createdAt: last.createdAt, id: last.id));
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (page) {
        // 새로 고침과 겹치면 같은 공지가 두 번 올 수 있다 — id 로 거른다.
        final seen = state.items.map((notice) => notice.id).toSet();
        return state.copyWith(
          isLoadingMore: false,
          hasMore: page.hasMore,
          items: [...state.items, ...page.items.where((notice) => !seen.contains(notice.id))],
        );
      },
      onFailure: (_) => state.copyWith(isLoadingMore: false),
    );
  }

  /// 공지 상세에서 댓글을 쓰거나 지운 뒤 목록 줄의 숫자를 맞춘다. 목록에 없는 공지면 아무 일도 없다.
  void updateCommentCount(String noticeId, int count) => state = state.copyWith(
        items: [for (final notice in state.items) notice.id == noticeId ? notice.withCommentCount(count) : notice],
      );
}
