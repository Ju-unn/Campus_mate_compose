from typing import Literal

# 자동 판정이 사람 재검토(pending)로 넘어간 이유(2026-09-26 사용자 결정 — "왜 넘어갔는지 최대한 자세히").
# 로그에는 이 코드를 그대로 찍고, 디스코드 알림에는 아래 라벨을 붙인다.
ReviewReason = Literal[
    "vision_error",
    "no_text",
    "school_not_found",
    "name_not_found",
    "both_not_found",
    "confirm_failed",
]

# 디스코드로 나가는 문장이다 — 어느 쪽이 어긋났는지만 말하고 값(학교명·실명·OCR 원문)은 넣지 않는다
# (설계 §7.3, 2026-09-19 결정). 담당자가 폰으로 이 줄만 읽고 다음에 뭘 할지 알 수 있게 적는다
# (2026-09-26 분석 권고3).
REVIEW_REASON_LABELS: dict[ReviewReason, str] = {
    "vision_error": "글자 인식 기능 오류(사진 문제 아님)",
    "no_text": "사진에서 글자를 찾지 못함(흐리거나 학생증이 아님)",
    "school_not_found": "학교 이름 불일치",
    "name_not_found": "실명 불일치",
    "both_not_found": "학교 이름·실명 모두 불일치",
    "confirm_failed": "대조는 통과, 저장만 실패(대시보드에서 통과로 바꿔 주세요)",
}


def missing_from_student_id(ocr_text: str, school_name: str, real_name: str) -> ReviewReason | None:
    """학생증 글자에 학교 이름과 실명이 다 있으면 `None`, 아니면 **어느 쪽이 없는지** 돌려준다.

    종전 `matches_school_and_name` 의 bool 을 대신한다 — 재검토 사유를 남기려면 어느 쪽이 어긋났는지 알아야 한다.
    """
    normalized = _normalize(ocr_text)
    if not normalized:
        # Vision 은 답했는데 글자가 하나도 없다 — 흐리거나 학생증이 아닌 사진이다.
        return "no_text"
    has_school = _normalize(school_name) in normalized
    has_name = _normalize(real_name) in normalized
    if has_school and has_name:
        return None
    if has_school:
        return "name_not_found"
    return "school_not_found" if has_name else "both_not_found"


def _normalize(value: str) -> str:
    return "".join(value.lower().split())
