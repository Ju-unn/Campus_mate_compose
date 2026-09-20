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

  /// 서버가 보는 길이와 같게 센다 — 파이썬 `len()` 은 글자(코드 포인트) 수라 `runes` 가 맞다.
  int get _trimmedLength => note.trim().runes.length;

  /// 하단 "다음"은 10자 이상 썼을 때만 켠다 — 짧은 글은 서버도 422 로 돌려보낸다.
  bool get canSubmit => _trimmedLength >= minLength && !isSubmitting;

  /// 쓰는 도중 10자에 못 미칠 때만 알려준다 — 화면에 들어오자마자 빨간 글씨를 보여주지 않는다.
  String? get lengthMessage =>
      _trimmedLength == 0 || _trimmedLength >= minLength ? null : '$minLength자 이상 입력해 주세요';

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
