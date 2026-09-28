import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/viewmodel/contact_block_list_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16b 에 들어올 때마다 새로 읽는다.
final contactBlockListViewModelProvider =
    NotifierProvider.autoDispose<ContactBlockListViewModel, ContactBlockListUiState>(ContactBlockListViewModel.new);

/// 16b 연락처 차단 관리. 서버는 id 와 등록일만 주고, 이름은 기기 파일에서 짝짓는다.
class ContactBlockListViewModel extends Notifier<ContactBlockListUiState> {
  @override
  ContactBlockListUiState build() {
    Future.microtask(load);
    return const ContactBlockListUiState();
  }

  /// 8d 에서 더 차단하고 돌아왔을 때도 부른다. 다시 읽다 실패하면 보던 줄은 그대로 둔다.
  Future<void> load() async {
    final (labels, result) =
        await (ref.read(contactNameStoreProvider).load(), ref.read(contactBlockRepositoryProvider).fetch()).wait;
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (blocks) => state.copyWith(isLoading: false, rows: [
        for (final block in blocks)
          ContactBlockRow(blockId: block.id, label: labels[block.id], createdAt: block.createdAt),
      ]),
      onFailure: (failure) => state.copyWith(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 서버에서 지운 뒤에만 기기 이름표도 지운다 — 서버가 실패했는데 이름부터 지우면 남은 줄이 이름을 잃는다.
  Future<void> remove(String blockId) async {
    final nameStore = ref.read(contactNameStoreProvider);
    final result = await ref.read(contactBlockRepositoryProvider).remove(blockId);
    final failure = result.when<Failure?>(onSuccess: (_) => null, onFailure: (failure) => failure);
    if (failure == null) await _forgetName(nameStore, blockId);
    if (!ref.mounted) return;
    state = failure == null
        ? state.copyWith(rows: [for (final row in state.rows) if (row.blockId != blockId) row])
        : state.copyWith(errorMessage: failure.toDisplayMessage());
  }

  /// 이름 파일 쓰기가 실패해도 해제는 이미 서버에서 끝났다 — 줄은 빼야 한다. 남은 이름표는 서버가 그 id 를
  /// 다시 주지 않으니 화면에 나오지 않는다(8d `_saveLabels` 와 같은 처리).
  static Future<void> _forgetName(ContactNameStore nameStore, String blockId) async {
    try {
      await nameStore.remove(blockId);
    } on Exception {
      // 위 설명대로 삼킨다.
    }
  }
}
