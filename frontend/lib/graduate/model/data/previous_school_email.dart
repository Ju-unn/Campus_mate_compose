/// 졸업생 신청의 "이전 학교 메일"(선택). **형식만** 본다 — 이 값은 관리자 화면의 중복 점검에만 쓰이고
/// 옛 학교가 어디든 받는다. 서버 `applicant_router.py` 의 `_EMAIL` · 254자 상한과 같은 규칙이다.
/// 빈 입력은 "값 없음" 이라 null — 화면이 비어 있음과 형식 오류를 가르려면 입력이 비었는지 먼저 본다.
class PreviousSchoolEmail {
  const PreviousSchoolEmail._(this._value);

  final String _value;

  static const int _maxLength = 254;
  static final RegExp _shape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static PreviousSchoolEmail? tryParse(String input) {
    final value = input.trim().toLowerCase();
    if (value.isEmpty || value.length > _maxLength || !_shape.hasMatch(value)) {
      return null;
    }
    return PreviousSchoolEmail._(value);
  }

  /// 서버에 싣는 값(앞뒤 공백 없음 · 소문자).
  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) => other is PreviousSchoolEmail && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}
