/// 답장 받을 메일 모양. 서버 `reasons.py` 의 `REPLY_EMAIL` 과 같은 규칙이다 — 공백 · 줄바꿈(헤더 주입)뿐 아니라 쉼표 · 세미콜론 ·
/// 꺾쇠 · 괄호 · 따옴표 · 제어문자 · 비ASCII(한글 등)도 막아 Reply-To 에 주소가 둘 이상 들어가지 않게 한다.
/// 서버가 거절할 값을 앱이 미리 막는 용도라, 서버 규칙을 바꾸면 여기도 같이 바꾼다.
const int replyEmailMaxLength = 254;

final RegExp _replyEmail = RegExp(
  r'^[^\s@,;:<>()\[\]"\\\x00-\x1f\x7f-\u{10ffff}]+@'
  r'[^\s@,;:<>()\[\]"\\\x00-\x1f\x7f-\u{10ffff}]+\.'
  r'[^\s@,;:<>()\[\]"\\\x00-\x1f\x7f-\u{10ffff}]+$',
  unicode: true,
);

/// 앞뒤 공백은 서버가 잘라서 보므로 같게 자르고 본다.
bool isValidReplyEmail(String email) {
  final trimmed = email.trim();
  return trimmed.length <= replyEmailMaxLength && _replyEmail.hasMatch(trimmed);
}

/// 로그인 계정의 메일을 "답장 받을 메일" 칸에 미리 채울 값으로 고른다. 채우면 안 되면 null.
/// 애플의 가림 주소(privaterelay)는 운영팀이 보낸 답장이 전달되지 않을 수 있어 채우지 않는다.
String? prefillReplyEmail(String? accountEmail) {
  if (accountEmail == null || !isValidReplyEmail(accountEmail) || accountEmail.endsWith('@privaterelay.appleid.com')) {
    return null;
  }
  return accountEmail.trim();
}
