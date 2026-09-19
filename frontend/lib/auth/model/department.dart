/// 3c 단계에서 사용자가 직접 입력하는 학과 값 객체(설계 §7.3).
final class Department {
  Department._(this._value);

  final String _value;

  static Department? tryParse(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.length > 30) {
      return null;
    }
    return Department._(normalized);
  }

  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) => other is Department && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}
