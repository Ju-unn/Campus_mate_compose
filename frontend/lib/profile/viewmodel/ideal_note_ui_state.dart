/// "이런 사람이 좋아요" 화면(DESIGN.md 화면 06-2a)의 상태.
/// 필수 입력이다(2026-09-20 사용자 결정 "온보딩 입력은 전부 필수") — 건너뛰기가 없다.
class IdealNoteUiState {
  const IdealNoteUiState({
    this.note = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final String note;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  /// 최소 글자 수(2026-09-21 사용자 결정). 서버 `IDEAL_NOTE_MIN_LENGTH` 와 같은 값이다.
  static const int minLength = 10;

  static const String lengthHint = '$minLength자 이상 입력해 주세요';

  /// 서버가 보는 길이와 같게 센다 — 파이썬 `len()` 은 글자(코드 포인트) 수라 `runes` 가 맞다.
  int get _trimmedLength => note.trim().runes.length;

  bool get isLongEnough => _trimmedLength >= minLength;

  /// 하단 "다음"은 보내는 중에만 끈다 — 짧을 때 누르면 저장 대신 빨간 오류로 이유를 알려준다
  /// (2026-09-27 사용자 "나", 04-1 과 같은 방식).
  bool get canSubmit => !isSubmitting;

  /// 쓰는 도중 10자에 못 미칠 때의 회색 안내 — 화면에 들어오자마자(0자) 보여주지 않는다.
  String? get lengthMessage => _trimmedLength == 0 || isLongEnough ? null : lengthHint;

  IdealNoteUiState copyWith({
    String? note,
    bool? isSubmitting,
    String? errorMessage,
    bool? completed,
  }) {
    return IdealNoteUiState(
      note: note ?? this.note,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      completed: completed ?? this.completed,
    );
  }
}
