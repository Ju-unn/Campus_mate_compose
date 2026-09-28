import 'package:campus_mate/safety/model/contact_name_store.dart';

/// 16b 한 줄. [label] 이 null 이면 이 기기에 이름이 없다(앱을 다시 깔았거나 파일이 깨졌다).
class ContactBlockRow {
  const ContactBlockRow({required this.blockId, required this.label, required this.createdAt});

  final String blockId;
  final ContactLabel? label;
  final DateTime createdAt;
}

/// 16b 연락처 차단 관리의 상태.
class ContactBlockListUiState {
  const ContactBlockListUiState({this.rows = const [], this.isLoading = true, this.errorMessage});

  final List<ContactBlockRow> rows;
  final bool isLoading;
  final String? errorMessage;

  /// [errorMessage] 는 넘기지 않으면 지워진다.
  ContactBlockListUiState copyWith({List<ContactBlockRow>? rows, bool? isLoading, String? errorMessage}) {
    return ContactBlockListUiState(
      rows: rows ?? this.rows,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}
