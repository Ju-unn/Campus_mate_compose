/// 서버 `core/text.py` `ZERO_WIDTH` 와 같은 목록. 이것만 있는 글은 서버가 빈 글로 거절한다.
final RegExp _zeroWidth = RegExp('[​‌‍⁠﻿]');

/// 서버 본문 · 선택지 검사(`body_text(max)` · `SafeLine` + `visible`)를 앱이 **미리** 흉내 낸 것 — 기준은 서버다.
/// 서버와 같게 앞뒤 공백을 깎은 뒤 코드 포인트로 재고, 0폭 문자 · 공백만이면 빈 글이다.
/// 제어 문자 검사는 입력칸이 막고 서버가 끝까지 본다. 투표 질문 · 게시물 본문 · 선택지가 같이 쓴다.
bool fitsServerText(String text, int maxLength) {
  final trimmed = text.trim();
  return trimmed.replaceAll(_zeroWidth, '').trim().isNotEmpty && trimmed.runes.length <= maxLength;
}
