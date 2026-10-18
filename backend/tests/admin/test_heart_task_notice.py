"""인증샷 결과 알림 문구(10-18 사용자 결정 "가", pen `푸시_문구_표.png`). 글자는 pen 표 그대로다."""
import pytest

from app.admin.heart_task_notice import ResultNotice, result_notice

REASONS = {
    "date_missing": "날짜가 안 보여요",
    "not_verified": "게시글·공유가 확인되지 않아요",
    "reused": "이미 쓴 캡처예요",
}
TITLES = {"everytime_post": "에브리타임 홍보", "kakao_share": "단톡방 공유"}


def test_result_notice_texts_match_the_pen_table():
    assert result_notice("everytime_post", "approved", 40, None) == ResultNotice(
        "heart_task_approved", "에브리타임 홍보 인증이 승인됐어요", "하트 40개를 받았어요",
        {"route": "heart_tasks", "task": "everytime_post"})
    assert result_notice("kakao_share", "approved", 25, None) == ResultNotice(
        "heart_task_approved", "단톡방 공유 인증이 승인됐어요", "하트 25개를 받았어요",
        {"route": "heart_tasks", "task": "kakao_share"})
    assert result_notice("kakao_share", "rejected", 25, "reused") == ResultNotice(
        "heart_task_rejected", "단톡방 공유 인증이 반려됐어요", "이미 쓴 캡처예요 · 다시 제출해 주세요",
        {"route": "heart_task_retry", "task": "kakao_share", "reason": "reused"})


@pytest.mark.parametrize("task", TITLES)
@pytest.mark.parametrize("reason", REASONS)
def test_every_rejection_is_the_task_title_plus_the_reason_text(task, reason):
    notice = result_notice(task, "rejected", 40, reason)

    assert notice.kind == "heart_task_rejected"
    assert notice.title == f"{TITLES[task]} 인증이 반려됐어요"
    assert notice.body == f"{REASONS[reason]} · 다시 제출해 주세요"
    assert notice.data == {"route": "heart_task_retry", "task": task, "reason": reason}


def test_the_hearts_in_the_body_are_the_servers_value():
    assert result_notice("everytime_post", "approved", 25, None).body == "하트 25개를 받았어요"


@pytest.mark.parametrize("reason", [None, "blurry", ""])
def test_a_missing_or_unknown_reason_still_makes_a_plain_retry_notice(reason):
    notice = result_notice("everytime_post", "rejected", 40, reason)

    assert notice.body == "다시 제출해 주세요"
    assert "reason" not in notice.data
    assert notice.data["route"] == "heart_task_retry"


@pytest.mark.parametrize(("status", "reason"), [("approved", None), ("rejected", "date_missing"), ("rejected", None)])
def test_the_data_only_has_route_task_and_reason(status, reason):
    assert set(result_notice("kakao_share", status, 25, reason).data) <= {"route", "task", "reason"}
