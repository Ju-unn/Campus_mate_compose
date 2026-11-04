/// 대학 이메일 값 객체 (CLAUDE.md §4 원칙 3 — 원시값 포장).
///
/// 여기서는 일반적인 이메일 형식만 검증한다. 학교 도메인 화이트리스트
/// (`university_email_domains`) 대조는 서버(FastAPI Auth Hook)가 가입 시점에
/// 한다 — ERD.md §3, `../../docs/superpowers/specs/...` §Auth Hook 절.
final class UniversityEmail {
  UniversityEmail._(this._value);

  final String _value;

  static final RegExp _pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// 형식이 올바르면 인스턴스를, 아니면 `null` 을 돌려준다.
  static UniversityEmail? tryParse(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (!_pattern.hasMatch(normalized)) {
      return null;
    }
    return UniversityEmail._(normalized);
  }

  /// 서버 전송·로깅 등 원시 문자열이 필요한 경계에서만 쓴다.
  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) {
    return other is UniversityEmail && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;
}
