/// 학생증 사진과 대조할 실명 값 객체(설계 §7.3, `profile_private.real_name`).
final class RealName {
  RealName._(this._value);

  final String _value;

  static RealName? tryParse(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.length > 30) {
      return null;
    }
    return RealName._(normalized);
  }

  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) => other is RealName && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}
