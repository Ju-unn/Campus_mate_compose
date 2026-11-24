/// 3c 단계에서 사용자가 직접 입력하는 학번 값 객체(설계 §7.3).
///
/// 학부 입학 연도 끝 두 자리(예: 21)라 반각 숫자 정확히 2자리만 받는다.
/// 앱은 2자리, 서버(`student_verification/schemas.py`)는 옛 앱 호환으로 1~3자리를 받고
/// 1.0.7 공개 뒤 2자리로 조인다(할 일 #9 A안).
/// 전각 숫자(２１)가 새지 않도록 `\d` 가 아니라 서버와 같은 `[0-9]` 로 쓴다.
final class StudentNumber {
  StudentNumber._(this._value);

  static final RegExp _pattern = RegExp(r'^[0-9]{2}$');

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
