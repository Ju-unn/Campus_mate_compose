import 'package:campus_mate/profile/model/profile_enums.dart';

/// `기타` 한 줄 글의 상한(pen s8u4Y 는 글자 수 표시 없음, 30 은 2026-09-28 대장 결정).
/// 서버 `ACQUISITION_NOTE_MAX_LENGTH` 와 같은 값이다 — 바꾸면 두 곳을 같이 바꾼다.
const acquisitionNoteMaxLength = 30;

/// 유입경로 화면(DESIGN.md 화면 20d)의 상태. 선택 화면이라 건너뛸 수 있다.
class AcquisitionUiState {
  const AcquisitionUiState({
    this.channel,
    this.note = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final AcquisitionChannel? channel;
  final String note;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  bool get isOther => channel == AcquisitionChannel.other;

  /// 서버로 보낼 글 — `기타` 가 아니면 적어 둔 글이 있어도 보내지 않는다.
  String? get noteToSend => isOther ? note.trim() : null;

  /// 활성 조건(pen k4ym5O 에 비활성 변형이 없어 2026-09-28 대장 결정): 칩 하나를 골라야 하고, `기타` 면 한 글자 이상 적어야 한다.
  bool get canSubmit => channel != null && !isSubmitting && (!isOther || note.trim().isNotEmpty);

  /// [errorMessage] 는 넘기지 않으면 지운다. [channel] 은 한 번 고르면 비울 일이 없다.
  AcquisitionUiState copyWith({
    AcquisitionChannel? channel,
    String? note,
    bool? isSubmitting,
    String? errorMessage,
    bool? completed,
  }) {
    return AcquisitionUiState(
      channel: channel ?? this.channel,
      note: note ?? this.note,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      completed: completed ?? this.completed,
    );
  }
}
