/// 3c 단계에서 사용자가 직접 입력하는 학번 값 객체(설계 §7.3).
///
/// 반각 숫자 1~3자리만 받는다 — 서버 `student_verification/schemas.py` 의 `[0-9]{1,3}` 과 같은 규칙(10-29 사용자 결정).
/// 전각 숫자(２１)가 새지 않도록 `\d` 가 아니라 서버와 같은 `[0-9]` 로 쓴다.
final class StudentNumber {
  StudentNumber._(this._value);

  static final RegExp _pattern = RegExp(r'^[0-9]{1,3}$');

  final String _value;

  static StudentNumber? tryParse(String raw) {
    final normalized = raw.trim();
    if (!_pattern.hasMatch(normalized)) {
      return null;
    }
    return StudentNumber._(normalized);
  }

  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) => other is StudentNumber && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}
