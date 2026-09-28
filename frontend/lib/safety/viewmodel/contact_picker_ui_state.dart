import 'package:campus_mate/safety/model/device_contacts.dart';

/// 8d 차단할 연락처 선택의 상태.
class ContactPickerUiState {
  const ContactPickerUiState({
    this.contacts = const [],
    this.selectedIds = const {},
    this.query = '',
    this.isLoading = true,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  /// 기기에서 읽은 전체(번호 있는 사람만). 검색은 [visible] 이 거른다.
  final List<DeviceContact> contacts;

  /// 검색으로 안 보이게 된 사람도 선택은 남는다.
  final Set<String> selectedIds;
  final String query;
  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;

  /// 서버 저장과 이름표 저장이 끝났다 — 화면이 닫힌다.
  final bool completed;

  /// 이름에 검색어가 들어간 사람만(초성 검색 없음).
  List<DeviceContact> get visible {
    final keyword = query.trim();
    return [for (final contact in contacts) if (contact.name.contains(keyword)) contact];
  }

  int get selectedCount => selectedIds.length;

  bool get canSubmit => selectedIds.isNotEmpty && !isSubmitting;

  /// [errorMessage] 는 넘기지 않으면 지워진다 — 다음 동작을 하면 지난 문구는 사라져야 한다.
  ContactPickerUiState copyWith({
    List<DeviceContact>? contacts,
    Set<String>? selectedIds,
    String? query,
    bool? isLoading,
    bool? isSubmitting,
    String? errorMessage,
    bool? completed,
  }) {
    return ContactPickerUiState(
      contacts: contacts ?? this.contacts,
      selectedIds: selectedIds ?? this.selectedIds,
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      completed: completed ?? this.completed,
    );
  }
}
