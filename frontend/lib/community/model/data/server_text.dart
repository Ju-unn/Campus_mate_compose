import 'package:campus_mate/common/input_text.dart';

/// 서버 본문 · 선택지 검사(`body_text(max)` · `SafeLine` + `visible`)를 앱이 **미리** 흉내 낸 것 — 기준은 서버다.
/// 글자 다루기는 [InputText] 한 곳(서버 `core/text.py` 를 옮긴 것)을 쓴다: 앞뒤 공백을 떼고 코드 포인트로 재며,
/// 0폭 문자 · 공백만이면 빈 글이다. 앱이 이렇게 뗀 글([serverStripped])을 보내므로 서버가 재는 글과 같다.
/// 제어 문자는 앱이 미리 막지 않는다 — 서버가 422 로 막는다. 투표 질문 · 게시물 본문 · 선택지가 같이 쓴다.
bool fitsServerText(String text, int maxLength) =>
    InputText(text).visible().length() > 0 && InputText(text).stripped().length() <= maxLength;

/// 서버에 보낼 글 — [fitsServerText] 가 잰 것과 같은 모양(앞뒤 공백만 뗌). 서버도 같은 떼기를 한 번 더 한다.
String serverStripped(String text) => InputText(text).stripped() as String;
