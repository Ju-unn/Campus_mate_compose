import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/viewmodel/block_list_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16f 에 들어올 때마다 새로 읽는다. 다른 화면(신고 · 14e)에서 차단이 늘었을 수 있다.
final blockListViewModelProvider =
    NotifierProvider.autoDispose<BlockListViewModel, BlockListUiState>(BlockListViewModel.new);

/// 16f 차단 목록. 해제는 되돌릴 수 없고 대화도 돌아오지 않는다(확인 시트는 화면 몫).
class BlockListViewModel extends Notifier<BlockListUiState> {
  @override
  BlockListUiState build() {
    Future.microtask(_load);
    return const BlockListUiState();
  }

  Future<void> _load() async {
    final result = await ref.read(safetyRepositoryProvider).fetchBlocks();
    // 응답을 기다리는 동안 16f 를 떠나면 autoDispose 로 이미 버려졌다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (blocks) => state.copyWith(isLoading: false, blocks: blocks),
      onFailure: (failure) =>
          state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 성공하면 그 줄만 뺀다. 목록을 다시 읽지 않는다 — 서버가 준 순서(최신순)는 한 줄 빠져도 그대로다.
  Future<void> unblock(String profileId) async {
    if (state.unblockingProfileId != null) return;
    state = state.copyWith(unblockingProfileId: profileId);
    final result = await ref.read(safetyRepositoryProvider).unblock(profileId);
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) => state.copyWith(
        blocks: state.blocks.where((user) => user.profileId != profileId).toList(),
      ),
      onFailure: (failure) => state.copyWith(errorMessage: failure.toDisplayMessage()),
    );
  }
}
