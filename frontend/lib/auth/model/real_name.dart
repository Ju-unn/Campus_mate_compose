/// 학생증 사진과 대조할 실명 값 객체(설계 §7.3, `profile_private.real_name`).
final class RealName {
  RealName._(this._value);

  final String _value;

  static RealName? tryParse(String raw) {
    final normalized = raw.trim();
    // 서버 student_verification/schemas.py·router.py 의 Form(min_length=2, max_length=30) 과 하한·상한을 맞춘다
    // (2026-09-20 분석담당 리뷰 제안 1 — 1글자 실명은 OCR 부분문자열 대조를 사실상 무력화한다).
    if (normalized.length < 2 || normalized.length > 30) {
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
