/// 3c 단계에서 사용자가 직접 입력하는 학번 값 객체(설계 §7.3).
final class StudentNumber {
  StudentNumber._(this._value);

  final String _value;

  static StudentNumber? tryParse(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.length > 20) {
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
