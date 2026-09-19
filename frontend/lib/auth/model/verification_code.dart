/// 이메일로 받은 6자리 인증코드 값 객체 (CLAUDE.md §4 원칙 3 — 원시값 포장).
final class VerificationCode {
  VerificationCode._(this._value);

  final String _value;

  static final RegExp _pattern = RegExp(r'^\d{6}$');

  /// 형식이 올바르면 인스턴스를, 아니면 `null` 을 돌려준다.
  static VerificationCode? tryParse(String raw) {
    final normalized = raw.trim();
    if (!_pattern.hasMatch(normalized)) {
      return null;
    }
    return VerificationCode._(normalized);
  }

  /// 서버 전송 등 원시 문자열이 필요한 경계에서만 쓴다.
  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) {
    return other is VerificationCode && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;
}
