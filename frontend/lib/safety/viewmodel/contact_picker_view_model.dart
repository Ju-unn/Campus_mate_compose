import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/viewmodel/contact_picker_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 8d 에 들어올 때마다 기기 연락처를 새로 읽는다.
final contactPickerViewModelProvider =
    NotifierProvider.autoDispose<ContactPickerViewModel, ContactPickerUiState>(ContactPickerViewModel.new);

/// 고른 번호가 전부 휴대전화가 아니라 서버가 하나도 저장하지 않은 경우. pen 에 없는 상태다.
const String noMobileNumberMessage = '휴대전화 번호가 있는 연락처만 차단할 수 있어요';

/// 번호 하나와 그 번호로 저장될 이름표. 서버 응답 id 와 같은 자리끼리 짝짓는다.
typedef _PickedNumber = ({String number, ContactLabel label});

/// 8d 차단할 연락처 선택. 번호 원문은 서버로만 가고, 이름은 서버가 저장한 뒤 기기 파일에만 남는다.
class ContactPickerViewModel extends Notifier<ContactPickerUiState> {
  @override
  ContactPickerUiState build() {
    Future.microtask(load);
    return const ContactPickerUiState();
  }

  Future<void> load() async {
    final contacts = await _readContacts();
    if (!ref.mounted) return;
    state = contacts == null
        ? state.copyWith(isLoading: false, errorMessage: const UnknownFailure().toDisplayMessage())
        : state.copyWith(isLoading: false, contacts: contacts);
  }

  /// 권한이 도중에 꺼지면 패키지가 예외를 던진다 — 로딩에 멈춰 있지 않게 null 로 바꾼다.
  Future<List<DeviceContact>?> _readContacts() async {
    try {
      return await ref.read(deviceContactSourceProvider).fetchAll();
    } on Exception {
      return null;
    }
  }

  void search(String query) => state = state.copyWith(query: query);

  void toggle(String contactId) {
    final selected = {...state.selectedIds};
    if (!selected.remove(contactId)) selected.add(contactId);
    state = state.copyWith(selectedIds: selected);
  }

  /// 선택한 사람의 번호를 기기 순서대로 펴서 한 번에 보낸다. 한 사람에게 휴대전화가 둘이면 16b 에 두 줄이 된다.
  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(isSubmitting: true);
    final picked = _pickedNumbers();
    final nameStore = ref.read(contactNameStoreProvider);
    final result = await ref.read(contactBlockRepositoryProvider).add([for (final item in picked) item.number]);
    if (!ref.mounted) return;
    await result.when<Future<void>>(
      onSuccess: (ids) => _saveLabels(nameStore, _labelsById(ids, picked)),
      onFailure: (failure) async => _fail(failure.toDisplayMessage()),
    );
  }

  void _fail(String message) => state = state.copyWith(isSubmitting: false, errorMessage: message);

  List<_PickedNumber> _pickedNumbers() => [
        for (final contact in state.contacts)
          if (state.selectedIds.contains(contact.id))
            for (final number in contact.numbers)
              (number: number, label: ContactLabel(name: contact.name, maskedNumber: maskPhoneNumber(number))),
      ];

  /// 서버가 null 로 돌려준 자리(휴대전화가 아닌 번호)는 뺀다.
  static Map<String, ContactLabel> _labelsById(List<String?> ids, List<_PickedNumber> picked) => {
        for (var i = 0; i < ids.length && i < picked.length; i++) ?ids[i]: picked[i].label,
      };

  /// 이름표 저장은 서버 성공 뒤에만 한다. 파일 쓰기가 실패해도 차단은 이미 서버에 있다 —
  /// 16b 에서 "이전에 차단한 연락처"로 보일 뿐이라 완료로 친다(버튼이 도는 채로 멈추지 않게).
  Future<void> _saveLabels(ContactNameStore nameStore, Map<String, ContactLabel> labels) async {
    if (labels.isEmpty) return _fail(noMobileNumberMessage);
    try {
      await nameStore.saveAll(labels);
    } on Exception {
      // 위 설명대로 삼킨다.
    }
    if (!ref.mounted) return;
    state = state.copyWith(isSubmitting: false, completed: true);
  }
}
