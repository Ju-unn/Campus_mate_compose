import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/poll.dart';

/// 15d 피드 상태. 17c 상세 · 17b 쓰기도 이 목록을 본다.
/// [polls] 는 **지금 탭** 목록이다 — 탭별로 쌓아 두지 않고 탭을 바꿀 때마다 새로 받는다.
class CommunityFeedUiState {
  const CommunityFeedUiState({
    this.tab = PollFeedTab.all,
    this.isLoading = true,
    this.polls = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.votingIds = const {},
    this.errorMessage,
  });

  /// 지금 고른 탭(pen `XfcKQ`). 처음은 전체(사용자 결정).
  final PollFeedTab tab;
  final bool isLoading;
  final List<Poll> polls;
  final bool hasMore;
  final bool isLoadingMore;

  /// 투표 응답을 기다리는 글. 이 글의 버튼은 꺼 둔다(되돌릴 수 없는 투표가 두 번 가지 않게).
  final Set<String> votingIds;
  final String? errorMessage;

  CommunityFeedUiState copyWith({
    bool? isLoading,
    List<Poll>? polls,
    bool? hasMore,
    bool? isLoadingMore,
    Set<String>? votingIds,
    String? errorMessage,
  }) {
    return CommunityFeedUiState(
      tab: tab,
      isLoading: isLoading ?? this.isLoading,
      polls: polls ?? this.polls,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      votingIds: votingIds ?? this.votingIds,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
