/// 가입용 휴대폰 번호 규칙(04-1 · 출시준비 `전화번호_인증_방법_가격.md` §3-1 · §3-2 A·B·C). 서버도 같은 규칙으로 다시 본다.
///
/// **가입 · 번호 입력에만 쓴다.** 연락처 차단(16b · 8d)에는 쓰지 않는다 — 친구 번호는 모양이 어떻든 그대로 등록한다(§3-6).
/// 일부러 막지 않는 것(§3-3): 가운데만 1234, 끝만 0000 · 1234 · 1111, 가운데 0000(D) — 진짜 번호가 많다.
abstract final class SignupPhoneNumber {
  /// 010 + 8자리(옛 011 · 016~019 는 받지 않는다, §8 결정 1 추천안).
  static final RegExp _shape = RegExp(r'^010\d{8}$');

  /// C — "누가 봐도 가짜" 인 뒤 8자리 목록.
  static const Set<String> _knownFakes = {'12341234', '12341111', '11112222', '12121212', '00001234', '12340000'};

  /// [digits] 는 하이픈을 뺀 숫자만이다.
  static bool accepts(String digits) {
    if (!_shape.hasMatch(digits)) {
      return false;
    }
    final tail = digits.substring(3);
    return !_isSameDigit(tail) && !_isStraight(tail) && !_knownFakes.contains(tail);
  }

  /// A — 전부 같은 숫자(00000000 · 11111111 …).
  static bool _isSameDigit(String tail) => tail.split('').toSet().length == 1;

  /// B — 한 줄로 이어지는 순서(12345678 · 87654321 …). 9 다음 0 으로 돌아가는 것은 순서로 보지 않는다.
  static bool _isStraight(String tail) {
    final steps = {for (var i = 1; i < tail.length; i++) tail.codeUnitAt(i) - tail.codeUnitAt(i - 1)};
    return steps.length == 1 && steps.single.abs() == 1;
  }
}
