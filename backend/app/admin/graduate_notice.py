"""졸업생 인증 승인 · 반려 결과 알림 문구(결정 D13 · D15). 보내는 길은 heart_task_notice.send_result_notice 를 그대로 쓴다 —
알림함 한 줄 + 푸시, 실패해도 결정을 되돌리지 않는다.

kind 는 기존 verification_result 를 재사용한다(알림 종류 check · 앱 enum 변경 0). 단 push.py 가 이 종류를 한 장으로 합쳐 보여 주므로
결과가 연달아 오면 마지막 것만 보인다 — 허용한다. data 에는 route · state · reason 만 싣는다(사진 경로 · 번호 · 이메일 · 닉네임 금지)."""
from app.admin.heart_task_notice import ResultNotice

# 앱 · 관리자 웹이 같은 글자를 쓴다(DB check 의 반려 사유 코드와 같다, D10).
REASON_TEXT = {
    "unreadable": "사진이 잘 안 보여요",
    "not_certificate": "졸업증명서가 아니에요",
    "unverifiable": "확인할 수 없는 번호예요",
    "school_unsupported": "아직 지원하지 않는 학교예요",
}


def result_notice(status: str, reason: str | None) -> ResultNotice:
    """승인이면 다음 할 일(학과 입력)을, 반려면 사유를 본문에 둔다. 사유가 모르는 값이면(DB 가 막아 정상에선 없다)
    "다시 신청해 주세요"만 말하고 data 에 reason 을 뺀다."""
    if status == "approved":
        return ResultNotice("verification_result", "졸업생 인증이 끝났어요", "학과 정보를 입력하고 시작해 보세요",
                            {"route": "graduate_verification", "state": "approved"})
    data = {"route": "graduate_verification", "state": "rejected"}
    text = REASON_TEXT.get(reason or "")
    if text is None:
        return ResultNotice("verification_result", "졸업생 인증이 반려됐어요", "다시 신청해 주세요", data)
    return ResultNotice("verification_result", "졸업생 인증이 반려됐어요", f"{text} · 다시 신청해 주세요",
                        {**data, "reason": reason})
