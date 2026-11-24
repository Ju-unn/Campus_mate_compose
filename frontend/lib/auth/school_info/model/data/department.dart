import 'package:campus_mate/common/input_rules.dart';

/// 3c 단계에서 사용자가 직접 입력하는 학과 값 객체(설계 §7.3).
final class Department {
  Department._(this._value);

  final String _value;

  /// 서버 `is_valid_department` 와 같은 규칙(`common/input_rules.dart`)에 맞을 때만 값이 있다. 기준은 서버다.
  static Department? tryParse(String raw) {
    if (!isValidDepartment(raw)) {
      return null;
    }
    return Department._(raw.trim());
  }

  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) => other is Department && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}
