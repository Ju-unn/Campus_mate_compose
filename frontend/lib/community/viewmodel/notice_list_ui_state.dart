import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/notice.dart';

/// 공지 목록(17g `unXUa`) 상태 — 피드 맨 위 띠(17 `ahtJd`)도 이 상태의 첫 줄을 쓴다(요청 하나로 둘 다 그린다).
class NoticeListUiState {
  const NoticeListUiState({
    this.isLoading = true,
    this.items = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.error,
  });

  final bool isLoading;

  /// 최신순(서버 순서 그대로).
  final List<Notice> items;
  final bool hasMore;
  final bool isLoadingMore;

  /// 첫 쪽을 못 읽었고 보여 줄 공지가 없을 때만 채운다. 띠는 이 값을 보지 않는다 — 실패하면 띠가 없을 뿐 피드는 그대로다.
  final Failure? error;

  /// 피드 띠에 올릴 가장 최근 공지. 없으면 띠를 그리지 않는다.
  Notice? get latest => items.firstOrNull;

  NoticeListUiState copyWith({List<Notice>? items, bool? hasMore, bool? isLoadingMore}) {
    return NoticeListUiState(
      isLoading: isLoading,
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
    );
  }
}
