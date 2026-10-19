import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/viewmodel/contact_picker_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/contact_picker_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_contact_blocks.dart';

void main() {
  late FakeDeviceContactSource source;
  late FakeContactBlockRepository repository;
  late FakeContactNameStore nameStore;
  late ProviderContainer container;

  setUp(() {
    source = FakeDeviceContactSource(granted: true, contacts: const [momContact, siblingContact]);
    repository = FakeContactBlockRepository();
    nameStore = FakeContactNameStore();
    container = ProviderContainer(
      overrides: [
        deviceContactSourceProvider.overrideWithValue(source),
        contactBlockRepositoryProvider.overrideWithValue(repository),
        contactNameStoreProvider.overrideWithValue(nameStore),
      ],
    );
    addTearDown(container.dispose);
  });

  ContactPickerViewModel viewModel() => container.read(contactPickerViewModelProvider.notifier);
  ContactPickerUiState state() => container.read(contactPickerViewModelProvider);

  Future<ContactPickerUiState> opened() async {
    container.listen(contactPickerViewModelProvider, (_, _) {});
    // build() 의 microtask 가 끝나야 연락처가 들어온다.
    await Future<void>.delayed(Duration.zero);
    return state();
  }

  test('opening loads device contacts, nothing selected, cannot submit', () async {
    final loaded = await opened();

    expect(loaded.isLoading, isFalse);
    expect(loaded.visible.map((contact) => contact.name), ['엄마', '동생']);
    expect(loaded.selectedCount, 0);
    expect(loaded.canSubmit, isFalse);
  });

  test('limited access shows the notice flag, full access does not', () async {
    source.limited = true;
    expect((await opened()).isLimited, isTrue);
  });

  test('full access keeps the notice flag off', () async {
    expect((await opened()).isLimited, isFalse);
  });

  test('reading the permission state throws: no notice, contacts still load', () async {
    source.limited = true;
    source.limitedError = Exception('channel down');

    final loaded = await opened();

    expect(loaded.isLimited, isFalse);
    expect(loaded.visible, hasLength(2));
    expect(loaded.errorMessage, isNull);
  });

  test('loading again after settings picks up the new state and list, keeps the selection that still exists', () async {
    source.limited = true;
    source.contacts = const [momContact];
    await opened();
    viewModel().toggle(momContact.id);

    source.limited = false;
    source.contacts = const [momContact, siblingContact];
    await viewModel().load();

    expect(state().isLimited, isFalse);
    expect(state().contacts, hasLength(2));
    expect(state().selectedIds, {momContact.id});
  });

  test('loading again drops a selection that is no longer readable', () async {
    await opened();
    viewModel().toggle(siblingContact.id);

    source.contacts = const [momContact];
    await viewModel().load();

    expect(state().selectedCount, 0);
    expect(state().canSubmit, isFalse);
  });

  test('overlapping reads: a slower older read finishing last does not overwrite the newest list', () async {
    final gates = [Completer<List<DeviceContact>>(), Completer<List<DeviceContact>>()];
    final gated = _GatedContactSource(gates);
    container = ProviderContainer(overrides: [
      deviceContactSourceProvider.overrideWithValue(gated),
      contactBlockRepositoryProvider.overrideWithValue(repository),
      contactNameStoreProvider.overrideWithValue(nameStore),
    ]);
    addTearDown(container.dispose);
    await opened(); // 첫 읽기가 gates[0] 에서 멈춘다.
    final newer = viewModel().load(); // 두 번째 읽기(설정에서 돌아옴)가 gates[1] 에서 멈춘다.
    await Future<void>.delayed(Duration.zero);

    gates[1].complete(const [momContact, siblingContact]);
    await newer;
    gates[0].complete(const [momContact]); // 먼저 시작한 옛 읽기가 나중에 끝난다.
    await Future<void>.delayed(Duration.zero);

    expect(state().contacts.map((contact) => contact.name), ['엄마', '동생']);
  });

  test('openSettings asks the device source once', () async {
    await opened();

    await viewModel().openSettings();

    expect(source.openSettingsCount, 1);
  });

  test('reading contacts throws: stop loading and show message', () async {
    source.fetchError = Exception('permission revoked');

    final loaded = await opened();

    expect(loaded.isLoading, isFalse);
    expect(loaded.contacts, isEmpty);
    expect(loaded.errorMessage, '알 수 없는 오류가 발생했습니다');
  });

  test('toggle selects and unselects', () async {
    await opened();

    viewModel().toggle(momContact.id);
    expect(state().selectedIds, {momContact.id});
    expect(state().selectedCount, 1);
    expect(state().canSubmit, isTrue);

    viewModel().toggle(momContact.id);
    expect(state().selectedIds, isEmpty);
  });

  test('search filters by name, keeps selection', () async {
    await opened();
    viewModel().toggle(momContact.id);

    viewModel().search(' 동 ');

    expect(state().visible.map((contact) => contact.name), ['동생']);
    expect(state().selectedIds, {momContact.id});
    expect(state().selectedCount, 1);
  });

  test('submit sends every number of selected contacts and stores names by returned id', () async {
    repository.addResult = const Success(['b1', null, 'b3']);
    await opened();
    viewModel()
      ..toggle(momContact.id)
      ..toggle(siblingContact.id);

    await viewModel().submit();

    expect(repository.added.single, ['010-1111-2841', '02-123-4567', '010-2222-7710']);
    expect(nameStore.labels.keys, ['b1', 'b3']);
    expect(nameStore.labels['b1']!.name, '엄마');
    expect(nameStore.labels['b1']!.maskedNumber, '010-****-2841');
    expect(nameStore.labels['b3']!.name, '동생');
    expect(nameStore.labels['b3']!.maskedNumber, '010-****-7710');
    expect(state().completed, isTrue);
    expect(state().isSubmitting, isFalse);
  });

  test('submit follows device order, not the order of tapping', () async {
    await opened();
    viewModel()
      ..toggle(siblingContact.id)
      ..toggle(momContact.id);

    await viewModel().submit();

    expect(repository.added.single, ['010-1111-2841', '02-123-4567', '010-2222-7710']);
  });

  test('submit with no mobile numbers shows message and stays', () async {
    repository.addResult = const Success([null]);
    source.contacts = const [DeviceContact(id: 'c-office', name: '사무실', numbers: ['02-123-4567'])];
    await opened();
    viewModel().toggle('c-office');

    await viewModel().submit();

    expect(state().completed, isFalse);
    expect(state().errorMessage, '휴대전화 번호가 있는 연락처만 차단할 수 있어요');
    expect(nameStore.labels, isEmpty);
    expect(state().selectedIds, {'c-office'});
  });

  test('submit failure keeps selection and shows failure message', () async {
    repository.addResult = const FailureResult(NetworkFailure());
    await opened();
    viewModel().toggle(momContact.id);

    await viewModel().submit();

    expect(state().completed, isFalse);
    expect(state().errorMessage, '네트워크 연결을 확인해 주세요');
    expect(state().selectedIds, {momContact.id});
    expect(nameStore.labels, isEmpty);
    expect(state().canSubmit, isTrue);
  });

  test('name file write failure still completes, block is already on the server', () async {
    nameStore.failSave = true;
    await opened();
    viewModel().toggle(momContact.id);

    await viewModel().submit();

    expect(state().completed, isTrue);
    expect(state().isSubmitting, isFalse);
  });

  test('submit while one is in flight sends only once', () async {
    await opened();
    viewModel().toggle(momContact.id);

    final first = viewModel().submit();
    expect(state().isSubmitting, isTrue);
    expect(state().canSubmit, isFalse);
    await viewModel().submit();
    await first;

    expect(repository.added, hasLength(1));
  });
}

/// fetchAll 호출 순서대로 [gates] 가 열릴 때까지 기다리는 가짜 — 읽기 둘이 겹치는 경우를 만든다.
class _GatedContactSource extends FakeDeviceContactSource {
  _GatedContactSource(this.gates) : super(granted: true);

  final List<Completer<List<DeviceContact>>> gates;
  int _calls = 0;

  @override
  Future<List<DeviceContact>> fetchAll() => gates[_calls++].future;
}
