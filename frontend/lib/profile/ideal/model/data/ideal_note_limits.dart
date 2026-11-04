/// "이런 사람이 좋아요" 화면 상한(06-2a, 2026-10-14 사용자 결정 "추천대로"). 서버 상한(1000자)보다 작다. 코드포인트로 센다.
/// 최소 10자 규칙은 그대로다(`IdealNoteUiState.minLength`).
const int idealNoteMaxLength = 300;

/// 엔터로 만드는 줄 상한 — 06-2a 칸 maxLines 와 같다.
const int idealNoteMaxLines = 6;
