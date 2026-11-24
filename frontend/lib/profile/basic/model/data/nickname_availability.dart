/// 닉네임 확인 답. [notAllowed] 는 서버 금지어 · 연속 글자(`reason: NICKNAME_NOT_ALLOWED`) — 진짜 중복은 [taken].
enum NicknameAvailability { available, taken, notAllowed }

/// 서버 `errors.py` CODE_NICKNAME_NOT_ALLOWED — 확인 답의 reason, 저장 422 의 code 에 같이 온다.
const String nicknameNotAllowedCode = 'NICKNAME_NOT_ALLOWED';
