import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/viewmodel/contact_block_list_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/contact_block_list_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_contact_blocks.dart';

void main() {
  late FakeContactBlockRepository repository;
  late FakeContactNameStore nameStore;
  late ProviderContainer container;

  setUp(() {
    repository = FakeContactBlockRepository()
      ..blocks = Success([contactBlockFixture('b1'), contactBlockFixture('b2')]);
    nameStore = FakeContactNameStore({'b1': const ContactLabel(name: '엄마', maskedNumber: '010-****-2841')});
    container = ProviderContainer(
      overrides: [
        contactBlockRepositoryProvider.overrideWithValue(repository),
        contactNameStoreProvider.overrideWithValue(nameStore),
      ],
    );
    addTearDown(container.dispose);
  });

  ContactBlockListViewModel viewModel() => container.read(contactBlockListViewModelProvider.notifier);
  ContactBlockListUiState state() => container.read(contactBlockListViewModelProvider);

  Future<ContactBlockListUiState> opened() async {
    container.listen(contactBlockListViewModelProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    return state();
  }

  test('list rows pair server ids with stored labels, unknown label is null', () async {
    final loaded = await opened();

    expect(loaded.isLoading, isFalse);
    expect(loaded.rows.map((row) => row.blockId), ['b1', 'b2']);
    expect(loaded.rows.map((row) => row.label?.name), ['엄마', null]);
    expect(loaded.rows.first.createdAt, DateTime(2026, 9, 27, 14));
  });

  test('fetch failure shows message and no rows', () async {
    repository.blocks = const FailureResult(NetworkFailure());

    final loaded = await opened();

    expect(loaded.isLoading, isFalse);
    expect(loaded.rows, isEmpty);
    expect(loaded.errorMessage, '네트워크 연결을 확인해 주세요');
  });

  test('load again reads the server once more', () async {
    await opened();
    repository.blocks = Success([contactBlockFixture('b3'), contactBlockFixture('b1')]);

    await viewModel().load();

    expect(repository.fetchCount, 2);
    expect(state().rows.map((row) => row.blockId), ['b3', 'b1']);
  });

  test('remove deletes on server then local name and drops row', () async {
    await opened();

    await viewModel().remove('b1');

    expect(repository.removed, ['b1']);
    expect(nameStore.labels, isEmpty);
    expect(state().rows.map((row) => row.blockId), ['b2']);
  });

  test('name file remove failure still drops the row, the server already unblocked', () async {
    nameStore.failRemove = true;
    await opened();

    await viewModel().remove('b1');

    expect(repository.removed, ['b1']);
    expect(state().rows.map((row) => row.blockId), ['b2']);
    expect(state().errorMessage, isNull);
  });

  test('remove failure keeps row and local name, shows message', () async {
    repository.removeResult = const FailureResult(ServerUnavailableFailure());
    await opened();

    await viewModel().remove('b1');

    expect(nameStore.labels.keys, ['b1']);
    expect(state().rows.map((row) => row.blockId), ['b1', 'b2']);
    expect(state().errorMessage, '잠시 뒤 다시 시도해 주세요');
  });
}
