import 'package:campus_mate/safety/model/safety_repository.dart';

/// 16f 차단 목록의 상태.
class BlockListUiState {
  const BlockListUiState({
    this.isLoading = true,
    this.blocks = const [],
    this.errorMessage,
    this.unblockingProfileId,
  });

  final bool isLoading;
  final List<BlockedUser> blocks;
  final String? errorMessage;

  /// 해제 요청이 가 있는 줄. 그 줄 버튼을 멈추고, 끝날 때까지 다른 해제도 받지 않는다.
  final String? unblockingProfileId;

  /// [errorMessage] 와 [unblockingProfileId] 는 넘기지 않으면 지워진다 —
  /// 둘 다 "지금 이 동작" 에만 붙는 값이라 다음 상태로 넘어가면 없어져야 한다.
  BlockListUiState copyWith({
    bool? isLoading,
    List<BlockedUser>? blocks,
    String? errorMessage,
    String? unblockingProfileId,
  }) {
    return BlockListUiState(
      isLoading: isLoading ?? this.isLoading,
      blocks: blocks ?? this.blocks,
      errorMessage: errorMessage,
      unblockingProfileId: unblockingProfileId,
    );
  }
}
