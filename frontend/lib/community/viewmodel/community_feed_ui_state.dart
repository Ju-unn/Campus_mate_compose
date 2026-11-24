import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/data/community_item.dart';

/// 15d 피드 상태. 17c 상세 · 17b 쓰기도 이 목록을 본다.
/// [items] 는 **지금 탭** 목록이다(투표 · 게시물이 섞여 있다) — 탭별로 쌓아 두지 않고 탭을 바꿀 때마다 새로 받는다.
class CommunityFeedUiState {
  const CommunityFeedUiState({
    this.tab = CommunityFeedTab.all,
    this.isLoading = true,
    this.items = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.votingIds = const {},
    this.error,
  });

  /// 지금 고른 탭(pen `XfcKQ` + 카테고리 셋). 처음은 전체(사용자 결정).
  final CommunityFeedTab tab;
  final bool isLoading;
  final List<CommunityItem> items;
  final bool hasMore;
  final bool isLoadingMore;

  /// 투표 응답을 기다리는 글. 이 글의 버튼은 꺼 둔다(되돌릴 수 없는 투표가 두 번 가지 않게).
  final Set<String> votingIds;
  final Failure? error;

  CommunityFeedUiState copyWith({
    bool? isLoading,
    List<CommunityItem>? items,
    bool? hasMore,
    bool? isLoadingMore,
    Set<String>? votingIds,
    Failure? error,
  }) {
    return CommunityFeedUiState(
      tab: tab,
      isLoading: isLoading ?? this.isLoading,
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      votingIds: votingIds ?? this.votingIds,
      error: error ?? this.error,
    );
  }
}
