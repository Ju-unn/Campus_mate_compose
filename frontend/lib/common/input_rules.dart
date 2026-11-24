/// 앱 입력 검사 규칙 한 곳 — 가입 3c(학과) · 04-1 / 15-6(닉네임) · 05 / 16e-1(카카오톡 아이디)이 같이 쓴다.
/// 기준은 서버 코드이고 앱은 미리 보여 주기만 한다. 서버와 같은 입력 표(`backend/tests/fixtures/input_rules_cases.json`)를
/// 앱 · 서버 시험이 같이 읽어, 한쪽만 바뀌면 시험이 실패한다(앱 통과 · 서버 거절 = 가입 막힘).
library;

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/input_text.dart';

/// 닉네임을 서버에 묻기 전에 앱이 먼저 보는 모양.
enum NicknameFormat {
  /// 모양은 맞다 — 중복 · 금지어는 서버가 본다.
  valid,

  /// 한글 완성 · 영문 2~5자가 아니다(서버 `NICKNAME_PATTERN`, profile_onboarding/schemas.py).
  invalid,

  /// 같은 글자 3번 · 알파벳 순서 3글자(서버 `has_letter_run`, core/junk_text.py). 서버는 이 닉네임에 "없음" 으로만 답한다.
  notAllowed;

  /// 입력 단계에서는 자모(ㄱ · ㅏ)도 받지만(한글 입력기가 조합 중에 먼저 넣는다) 보낼 값은 완성형이어야 한다.
  static final RegExp _pattern = RegExp(r'^[가-힣a-zA-Z]{2,5}$');

  static NicknameFormat of(String nickname) {
    if (!_pattern.hasMatch(nickname)) {
      return invalid;
    }
    return InputText(nickname).hasLetterRun() ? notAllowed : valid;
  }
}

/// 서버 `is_valid_department`(student_verification/schemas.py) — 앞뒤 공백을 뺀 2~30자(하한은 0폭 문자를 뺀 길이),
/// 완성 한글 · 영문 하나 이상, 자모 낱자 · 제어 문자 · 글 방향 문자 없음, 같은 글자 3번 없음(알파벳 순서는 안 본다 —
/// "Korean Studies" 같은 실제 학과가 걸린다). 제어 문자는 공백을 떼기 전 원문으로 본다 — "컴공" 끝의 줄바꿈이 사라지지 않게.
bool isValidDepartment(String department) {
  final text = InputText(department).stripped();
  return text.visible().length() >= 2 &&
      text.length() <= 30 &&
      !InputText(department).hasBadChar(multiline: false) &&
      text.hasLetter() &&
      !text.hasJamo() &&
      !text.hasLetterRun(alphabetOrder: false);
}

/// 서버 `is_valid_kakao_id`(profile_onboarding/schemas.py) — 앞뒤 공백을 뺀 2~64자, 안쪽 공백 · 줄바꿈 · 제어 문자 ·
/// 글 방향 문자 · 0폭 문자 · 자모 낱자 없음. 같은 글자 3번은 막지 않는다(실제 아이디에 있을 수 있다).
bool isValidKakaoId(String kakaoId) {
  final text = InputText(kakaoId).stripped();
  return text.length() >= 2 &&
      text.length() <= 64 &&
      !hasKakaoIdSpace(kakaoId) &&
      !text.hasBadChar(multiline: false) &&
      !text.hasJamo();
}

/// 카카오톡 아이디 안쪽(앞뒤 공백은 보낼 때 뗀다)에 공백 · 줄바꿈 · 0폭 문자가 있다 — 칸 아래 "공백 없이 적어 주세요" 의 조건.
bool hasKakaoIdSpace(String kakaoId) => InputText(kakaoId).stripped().hasSpaceOrZeroWidth();

/// 카카오톡 아이디 칸 아래 빨간 한 줄(04-1b · 16e-1, 대장 판정 11-24 나안). 안쪽 공백은 바로 "공백 없이 적어 주세요",
/// 다른 거절 이유(1자 · 64자 넘음 · 자모 · 제어 · 글 방향 문자)는 손을 멈춘 뒤([settled]) 서버와 같은 "입력한 값을 다시
/// 확인해 주세요". 빈 칸 · 공백만은 아무것도 띄우지 않는다 — "다음" 이 꺼져 있는 것으로 충분하다.
Failure? kakaoIdFieldError(String kakaoId, {required bool settled}) {
  if (hasKakaoIdSpace(kakaoId)) {
    return const AppErrorFailure(AppError.kakaoIdSpace);
  }
  final isBlank = InputText(kakaoId).stripped().length() == 0;
  return settled && !isBlank && !isValidKakaoId(kakaoId) ? const AppErrorFailure(AppError.invalidInput) : null;
}
