import json
import logging
from collections.abc import Callable
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient
from google.cloud import vision

from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS
from app.core import errors
from app.student_verification.matching import REVIEW_REASON_LABELS
from app.core.deps import get_client, get_settings, get_vision_client_factory
from app.main import app
from app.settings import Settings
from app.student_verification.router import fetch_verification_status

PROFILE_ID = UUID("11111111-1111-1111-1111-111111111111")
JPEG = b"\xff\xd8\xff" + b"fake-student-id-bytes"
PNG = b"\x89PNG\r\n\x1a\n" + b"fake-student-id-bytes"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}


@pytest.fixture(autouse=True)
def overrides():
    app.dependency_overrides[get_settings] = lambda: Settings(
            supabase_url="https://x.supabase.co",
            supabase_service_role_key="service-key",
            auth_hook_signing_secret="whsec_test",
            discord_webhook_url="https://discord.com/api/webhooks/test",
            google_cloud_project="campus-mate-test",
            openai_api_key="sk-test",
            phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )
    yield
    app.dependency_overrides.clear()


def _vision_client(ocr_text: str) -> AsyncMock:
    # spec 을 주지 않으면 없는 메서드까지 만들어 내서 API 불일치를 테스트가 못 잡는다.
    client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
    client.batch_annotate_images.return_value = SimpleNamespace(
        responses=[
            SimpleNamespace(
                error=SimpleNamespace(message=""),
                text_annotations=[SimpleNamespace(description=ocr_text)],
            )
        ]
    )
    return client


def _wire(
    gate_row: dict,
    ocr_text: str = "",
    reject_reason: str | None = None,
    fails: Callable[[httpx.Request], bool] = lambda request: False,
    consented: bool = True,
) -> tuple[list[httpx.Request], AsyncMock]:
    """목 트랜스포트와 목 Vision 클라이언트를 라우터에 주입하고, 나간 요청 목록을 돌려준다."""
    sent: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        url = str(request.url)
        if fails(request):
            return httpx.Response(500, json={"message": "boom"})
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": str(PROFILE_ID)})
        if "/storage/v1/" in url:
            return httpx.Response(200, json={"Key": "student-id-temp/x.jpg"})
        if "discord.com" in url:
            return httpx.Response(204)
        if "/rest/v1/student_verification_attempts" in url and request.method == "GET":
            return httpx.Response(200, json=[{"reject_reason": reject_reason}])
        # 가입 동의(02-c)는 3b 앞 관문이다. 여기 테스트는 이번 판 동의를 마친 사용자다(동의 전은 tests/consents).
        if "/rest/v1/user_consents" in url and request.method == "GET":
            if not consented:
                return httpx.Response(200, json=[])
            return httpx.Response(200, json=[{"kind": k, "version": CONSENT_VERSION} for k in sorted(REQUIRED_KINDS)])
        if "/rest/v1/profiles" in url and request.method == "GET":
            return httpx.Response(200, json=[gate_row])
        return httpx.Response(200, json=[])

    app.dependency_overrides[get_client] = lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    vision_client = _vision_client(ocr_text)
    # 제공자가 "만드는 함수"를 돌려주는 자리라 람다가 두 겹이다(core/deps.get_vision_client_factory).
    app.dependency_overrides[get_vision_client_factory] = lambda: lambda: vision_client
    return sent, vision_client


# 소셜 로그인 전환: 여기 사람은 학교 메일 확인을 마쳤다(전은 school_email_verified_at=None 으로 따로 본다).
SCHOOL_EMAIL_VERIFIED_AT = "2026-10-01T00:00:00+00:00"


def _gate_row(status: str = "none", department: str | None = None,
              school_email_verified_at: str | None = SCHOOL_EMAIL_VERIFIED_AT) -> dict:
    return {"student_verification": status, "department": department, "universities": {"name": "서울대학교"},
            "school_email_verified_at": school_email_verified_at}


def _submit(
    real_name: str = "홍길동",
    photo: bytes = JPEG,
    headers: dict = AUTH_HEADERS,
    # 실제 Flutter 클라이언트(http.MultipartFile.fromPath)가 보내는 값 — 확장자를 보지 않는다.
    part_content_type: str = "application/octet-stream",
):
    return TestClient(app).post(
        "/student-verification",
        files={"photo": ("student-id.jpg", photo, part_content_type)},
        data={"real_name": real_name},
        headers=headers,
    )


def _calls(sent: list[httpx.Request], method: str, fragment: str) -> list[httpx.Request]:
    return [r for r in sent if r.method == method and fragment in str(r.url)]


def _uploaded_path(sent: list[httpx.Request]) -> str:
    upload = _calls(sent, "POST", "/storage/v1/object/student-id-temp/")[0]
    return str(upload.url).split("/object/student-id-temp/")[1]


def _review_warning(caplog: pytest.LogCaptureFixture) -> str:
    """사람 재검토로 넘어간 이유를 적은 WARNING 한 줄."""
    return next(r.getMessage() for r in caplog.records if "사람 재검토로 넘긴다: reason=" in r.getMessage())


def _discord_content(sent: list[httpx.Request]) -> str:
    return json.loads(_calls(sent, "POST", "discord.com")[0].content)["content"]


# --- POST /student-verification ---------------------------------------------


def test_submit_returns_verified_when_ocr_matches():
    sent, vision_client = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동 2021123456")

    response = _submit()

    assert response.status_code == 200
    assert response.json() == {"status": "verified"}
    vision_client.batch_annotate_images.assert_awaited_once()
    # 업로드 → 실명 → 시도 기록(pending) → 상태 pending → 상태 verified 가 모두 나간다.
    upload = _calls(sent, "POST", "/storage/v1/object/student-id-temp/")[0]
    assert upload.url.host == "x.supabase.co"
    assert str(upload.url).startswith(f"https://x.supabase.co/storage/v1/object/student-id-temp/{PROFILE_ID}/")
    assert upload.content == JPEG
    assert json.loads(_calls(sent, "POST", "/profile_private")[0].content)["real_name"] == "홍길동"
    attempt = json.loads(_calls(sent, "POST", "/student_verification_attempts")[0].content)
    assert attempt["result"] == "pending"
    assert attempt["profile_id"] == str(PROFILE_ID)
    patched = [json.loads(r.content)["student_verification"] for r in _calls(sent, "PATCH", "/rest/v1/profiles")]
    assert patched == ["pending", "verified"]
    assert _calls(sent, "POST", "discord.com") == []


def test_submit_returns_pending_and_notifies_discord_when_ocr_does_not_match():
    sent, vision_client = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 김철수")

    response = _submit()

    assert response.status_code == 200
    assert response.json() == {"status": "pending"}
    vision_client.batch_annotate_images.assert_awaited_once()
    patched = [json.loads(r.content)["student_verification"] for r in _calls(sent, "PATCH", "/rest/v1/profiles")]
    assert patched == ["pending"]
    assert len(_calls(sent, "POST", "discord.com")) == 1


def test_submit_marks_attempt_row_verified_on_the_verified_path():
    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동")

    response = _submit()

    assert response.json() == {"status": "verified"}
    patch = _calls(sent, "PATCH", "/student_verification_attempts")[0]
    assert dict(patch.url.params) == {"profile_id": f"eq.{PROFILE_ID}", "file_path": f"eq.{_uploaded_path(sent)}"}
    assert json.loads(patch.content) == {"result": "verified", "reviewed_at": "now()"}


def test_submit_deletes_the_photo_from_storage_when_auto_verified():
    # SQL 트리거가 아니라 FastAPI 가 직접 지운다 — `delete from storage.objects`는 메타 행만 지우고
    # 실제 파일은 고아로 남는다(2026-09-20 분석담당 리뷰).
    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동")

    response = _submit()

    assert response.json() == {"status": "verified"}
    deletion = _calls(sent, "DELETE", "/storage/v1/object/student-id-temp/")
    assert len(deletion) == 1
    assert str(deletion[0].url).endswith(f"/object/student-id-temp/{_uploaded_path(sent)}")
    assert _calls(sent, "POST", "discord.com") == []


def test_submit_still_returns_verified_and_notifies_discord_when_storage_delete_fails():
    # 삭제 실패로 응답 자체를 실패시키면 이미 끝난 인증까지 무효가 된다 — 고아 파일 알림만 보낸다.
    def delete_fails(request: httpx.Request) -> bool:
        return request.method == "DELETE" and "/storage/v1/object/student-id-temp/" in str(request.url)

    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동", fails=delete_fails)

    response = _submit()

    assert response.status_code == 200
    assert response.json() == {"status": "verified"}
    assert len(_calls(sent, "DELETE", "/storage/v1/object/student-id-temp/")) == 1
    assert len(_calls(sent, "POST", "discord.com")) == 1


def test_submit_leaves_attempt_row_pending_on_the_no_match_path():
    # 사람이 재검토할 행이라 result 는 pending 그대로 둔다.
    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 김철수")

    response = _submit()

    assert response.json() == {"status": "pending"}
    assert _calls(sent, "PATCH", "/student_verification_attempts") == []


def test_verified_stays_verified_when_the_orphan_notice_fails(caplog):
    """확정을 쓴 뒤의 뒷정리는 결과를 되돌리지 못한다.

    사진 삭제가 실패해 고아 알림을 보내는데 그 알림까지 터지면, 종전에는 DB 는 verified 인데
    응답과 사유가 confirm_failed 로 나갔다(2026-09-26 분석 권고1).
    """

    def storage_or_discord_fails(request: httpx.Request) -> bool:
        url = str(request.url)
        return (request.method == "DELETE" and "/storage/v1/" in url) or "discord.com" in url

    sent, _ = _wire(
        _gate_row("none"), ocr_text="서울대학교 학생증 홍길동", fails=storage_or_discord_fails
    )

    with caplog.at_level(logging.WARNING, logger="app.student_verification.router"):
        response = _submit()

    assert response.json() == {"status": "verified"}
    patched = [json.loads(r.content)["student_verification"] for r in _calls(sent, "PATCH", "/rest/v1/profiles")]
    assert patched == ["pending", "verified"]
    assert [r for r in caplog.records if "reason=" in r.getMessage()] == []


def test_verified_path_logs_no_review_warning(caplog):
    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동")

    with caplog.at_level(logging.WARNING, logger="app.student_verification.router"):
        assert _submit().json() == {"status": "verified"}

    assert [r.getMessage() for r in caplog.records if r.levelno >= logging.WARNING] == []
    assert _calls(sent, "POST", "discord.com") == []


@pytest.mark.parametrize(
    ("ocr_text", "reason"),
    [
        ("서울대학교 학생증 김철수", "name_not_found"),
        ("미국대학교 학생증 홍길동", "school_not_found"),
        ("부산대학교 학생증 김철수", "both_not_found"),
        ("", "no_text"),
    ],
)
def test_submit_logs_why_it_went_to_human_review(caplog, ocr_text, reason):
    # 왜 사람이 봐야 하는지 로그 한 줄로 남긴다(2026-09-26 사용자 결정).
    sent, _ = _wire(_gate_row("none"), ocr_text=ocr_text)

    with caplog.at_level(logging.WARNING, logger="app.student_verification.router"):
        assert _submit().json() == {"status": "pending"}

    logged = _review_warning(caplog)
    assert f"reason={reason}" in logged
    assert f"profile_id={PROFILE_ID}" in logged
    assert "school=서울대학교" in logged
    assert f"ocr_chars={len(ocr_text)}" in logged
    # 문구 자체는 test_discord_notifier 가 통째로 못 박는다 — 여기서는 "그 사유가 나갔는지"만 본다.
    assert REVIEW_REASON_LABELS[reason] in _discord_content(sent)


def test_submit_logs_vision_failure_as_its_own_reason(caplog):
    # "대조가 어긋났다"와 "아예 못 물어봤다"는 손볼 곳이 다르다 — 같은 pending 이라도 갈라 적는다.
    sent, vision_client = _wire(_gate_row("none"))
    vision_client.batch_annotate_images.side_effect = RuntimeError("429 quota exceeded")

    with caplog.at_level(logging.WARNING, logger="app.student_verification.router"):
        assert _submit().json() == {"status": "pending"}

    assert "reason=vision_error" in _review_warning(caplog)
    assert REVIEW_REASON_LABELS["vision_error"] in _discord_content(sent)


def test_submit_logs_confirm_failure_as_its_own_reason(caplog):
    def is_verified_patch(request: httpx.Request) -> bool:
        return (
            request.method == "PATCH"
            and "/rest/v1/profiles" in str(request.url)
            and json.loads(request.content).get("student_verification") == "verified"
        )

    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동", fails=is_verified_patch)

    with caplog.at_level(logging.WARNING, logger="app.student_verification.router"):
        assert _submit().json() == {"status": "pending"}

    assert "reason=confirm_failed" in _review_warning(caplog)
    assert REVIEW_REASON_LABELS["confirm_failed"] in _discord_content(sent)


def test_review_log_never_carries_the_real_name_or_the_ocr_text(caplog):
    # 개인정보다 — 사유·학교 이름·글자 수까지만 남긴다(설계 §7.3).
    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 김철수 2021123456")

    with caplog.at_level(logging.WARNING, logger="app.student_verification.router"):
        _submit(real_name="홍길동")

    logged = _review_warning(caplog)
    assert "홍길동" not in logged
    assert "김철수" not in logged
    assert "2021123456" not in logged
    assert _uploaded_path(sent) not in logged


def test_submit_uploads_with_content_type_derived_from_magic_bytes():
    # 클라이언트가 보낸 application/octet-stream 을 그대로 넘기면 버킷의 mime 허용목록에 걸린다.
    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동")

    _submit()

    assert _calls(sent, "POST", "/storage/v1/")[0].headers["content-type"] == "image/jpeg"


def test_submit_uploads_png_with_png_content_type():
    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동")

    _submit(photo=PNG)

    assert _calls(sent, "POST", "/storage/v1/")[0].headers["content-type"] == "image/png"


def test_submit_falls_back_to_pending_when_final_status_patch_fails():
    # verified PATCH 가 깨지면 상태가 pending 에 갇히는데 verified 경로는 디스코드를 부르지 않아 아무도 모른다.
    def is_verified_patch(request: httpx.Request) -> bool:
        return (
            request.method == "PATCH"
            and "/rest/v1/profiles" in str(request.url)
            and json.loads(request.content).get("student_verification") == "verified"
        )

    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 학생증 홍길동", fails=is_verified_patch)

    response = _submit()

    assert response.status_code == 200
    assert response.json() == {"status": "pending"}
    assert len(_calls(sent, "POST", "discord.com")) == 1


def test_submit_falls_back_to_pending_when_vision_fails():
    # Vision 이 죽었다고 500 을 내면 상태가 pending 으로 굳어 재제출이 409 로 막힌다 — 사람 재검토로 넘긴다.
    sent, vision_client = _wire(_gate_row("none"))
    vision_client.batch_annotate_images.side_effect = RuntimeError("429 quota exceeded")

    response = _submit()

    assert response.status_code == 200
    assert response.json() == {"status": "pending"}
    assert len(_calls(sent, "POST", "discord.com")) == 1


def test_submit_does_not_swallow_programming_errors_from_vision():
    # Vision 장애만 "사람 재검토"로 넘긴다 — 우리 코드 버그(예: 없는 메서드 호출)까지 묻으면
    # 자동 인증이 영영 안 되는데도 아무도 모른다. 테스트·스테이징에서 500 으로 드러나야 한다.
    _, vision_client = _wire(_gate_row("none"))
    vision_client.batch_annotate_images.side_effect = AttributeError("no such method")

    with pytest.raises(AttributeError):
        _submit()


@pytest.mark.parametrize("verification", ["verified", "pending", "rejected"])
def test_submit_is_403_with_the_status_header_for_a_suspended_account(verification):
    # 결정 9(10-01 · 10-03 대장): 정지 중엔 바꾸지 못한다 — 사진 업로드 · OCR · 디스코드 알림 전에 막는다.
    # 409(검토 중 · 이미 인증)보다 먼저다 — 헤더 없는 409 면 앱이 정지 안내로 못 간다.
    sent, vision_client = _wire({**_gate_row(verification), "status": "suspended"}, ocr_text="서울대학교 홍길동")

    response = _submit()

    assert response.status_code == 403
    assert response.json()["detail"] == errors.ACCOUNT_SUSPENDED
    assert response.headers["X-Account-Status"] == "suspended"
    vision_client.batch_annotate_images.assert_not_awaited()
    assert _calls(sent, "POST", "/storage/v1/") == []
    assert _calls(sent, "POST", "/student_verification_attempts") == []


def test_submit_returns_409_while_review_is_pending():
    sent, vision_client = _wire(_gate_row("pending"), ocr_text="서울대학교 홍길동")

    response = _submit()

    assert response.status_code == 409
    vision_client.batch_annotate_images.assert_not_awaited()
    assert _calls(sent, "POST", "/storage/v1/") == []
    assert _calls(sent, "POST", "/student_verification_attempts") == []


def test_submit_returns_409_when_already_verified():
    # 끝난 인증을 다시 제출하면 pending 으로 되돌아가 사진 삭제 트리거가 꼬인다 — 아무 일도 하지 않고 막는다.
    sent, vision_client = _wire(_gate_row("verified"), ocr_text="서울대학교 홍길동")

    response = _submit()

    assert response.status_code == 409
    vision_client.batch_annotate_images.assert_not_awaited()
    assert _calls(sent, "POST", "/storage/v1/") == []
    assert _calls(sent, "POST", "/student_verification_attempts") == []


def test_submit_returns_400_for_non_image_file():
    sent, vision_client = _wire(_gate_row("none"), ocr_text="서울대학교 홍길동")

    response = _submit(photo=b"not-an-image")

    assert response.status_code == 400
    vision_client.batch_annotate_images.assert_not_awaited()
    assert _calls(sent, "POST", "/storage/v1/") == []


def test_submit_returns_400_for_blank_real_name():
    sent, vision_client = _wire(_gate_row("none"), ocr_text="서울대학교 홍길동")

    response = _submit(real_name="   ")

    assert response.status_code == 400
    vision_client.batch_annotate_images.assert_not_awaited()
    assert _calls(sent, "POST", "/storage/v1/") == []
    assert _calls(sent, "POST", "/profile_private") == []


def test_submit_returns_400_when_real_name_is_one_letter_with_spaces():
    # Form(min_length=2) 는 공백까지 세서 " 김 " 이 통과한다 — 자른 뒤 길이로 다시 봐야 한다.
    sent, vision_client = _wire(_gate_row("none"), ocr_text="서울대학교 홍길동")

    response = _submit(real_name=" 김 ")

    assert response.status_code == 400
    assert response.json()["detail"] == errors.REAL_NAME_REQUIRED
    vision_client.batch_annotate_images.assert_not_awaited()
    assert _calls(sent, "POST", "/profile_private") == []


def test_submit_returns_400_when_real_name_has_digits_or_symbols():
    # 앱이 이미 막지만 여기가 신뢰 경계다 — 학생증에 없는 글자가 섞이면 OCR 대조가 어긋난다.
    sent, vision_client = _wire(_gate_row("none"), ocr_text="서울대학교 홍길동")

    response = _submit(real_name="Mary-Jane")

    assert response.status_code == 400
    assert response.json()["detail"] == errors.REAL_NAME_INVALID
    vision_client.batch_annotate_images.assert_not_awaited()
    assert _calls(sent, "POST", "/profile_private") == []


def test_submit_accepts_an_english_name_with_a_space():
    # 외국인 이름은 "Jun seok" 처럼 띄어 쓴다(2026-09-24 사용자 결정).
    sent, _ = _wire(_gate_row("none"), ocr_text="서울대학교 Jun seok")

    response = _submit(real_name="Jun seok")

    assert response.status_code == 200
    assert json.loads(_calls(sent, "POST", "/profile_private")[0].content)["real_name"] == "Jun seok"


def test_submit_returns_401_without_authorization_header():
    sent, vision_client = _wire(_gate_row("none"), ocr_text="서울대학교 홍길동")

    response = _submit(headers={})

    assert response.status_code == 401
    vision_client.batch_annotate_images.assert_not_awaited()
    assert _calls(sent, "GET", "/rest/v1/profiles") == []


# --- GET /me/verification-status --------------------------------------------


def _fetch_status(headers: dict = AUTH_HEADERS):
    return TestClient(app).get("/me/verification-status", headers=headers)


def test_status_verified_with_school_info():
    sent, _ = _wire(_gate_row("verified", department="컴퓨터공학과"))

    response = _fetch_status()

    assert response.status_code == 200
    assert response.json() == {"status": "verified", "has_school_info": True, "reject_reason": None,
                               "consent": "current", "school_email_verified": True}
    assert _calls(sent, "GET", "/student_verification_attempts") == []


def test_status_verified_without_school_info():
    _wire(_gate_row("verified", department=None))

    response = _fetch_status()

    assert response.json() == {"status": "verified", "has_school_info": False, "reject_reason": None,
                               "consent": "current", "school_email_verified": True}


def test_status_rejected_includes_reject_reason():
    sent, _ = _wire(_gate_row("rejected"), reject_reason="사진이 흐려요")

    response = _fetch_status()

    assert response.json() == {"status": "rejected", "has_school_info": False, "reject_reason": "사진이 흐려요",
                               "consent": "current", "school_email_verified": True}
    assert len(_calls(sent, "GET", "/student_verification_attempts")) == 1


def test_status_says_when_the_school_email_is_not_verified_yet():
    """소셜로 막 가입한 사람(학교 메일 전)도 이 응답에 닿는다 — 앱이 학교 메일 화면으로 보낸다."""
    _wire(_gate_row("none", school_email_verified_at=None))

    response = _fetch_status()

    assert response.status_code == 200
    assert response.json()["school_email_verified"] is False
    # 옛 응답을 쓰는 앱이 아직 있다 — 기존 필드는 그대로 나간다.
    assert {"status", "has_school_info", "reject_reason", "consent"} <= response.json().keys()


def test_the_gate_order_is_written_down_on_the_status_endpoint():
    """앱이 이 응답으로 다음 화면을 고른다 — 순서를 문서로 고정한다."""
    assert "정지 → 동의 → 학교 메일 → 학생증 → 학과와 학번" in fetch_verification_status.__doc__


def test_submit_answers_a_suspended_account_before_asking_for_consent():
    """정지 → 동의 순서. 동의 403 은 헤더가 없어서 먼저 나가면 앱이 정지 안내 화면으로 못 간다."""
    sent, vision_client = _wire({**_gate_row("none"), "status": "suspended"}, consented=False)

    response = _submit()

    assert response.status_code == 403
    assert response.headers["X-Account-Status"] == "suspended"
    vision_client.batch_annotate_images.assert_not_awaited()


def test_a_login_only_api_turns_a_withdrawn_account_away_with_401_and_the_header():
    """get_caller(로그인만) 쪽도 탈퇴 계정은 막는다 — 상태 한 번 조회로 가른다(편차 1)."""
    _wire({**_gate_row("verified", department="컴퓨터공학과"), "status": "withdrawn"})

    response = _fetch_status()

    assert response.status_code == 401
    assert response.json()["detail"] == "탈퇴한 계정이에요"
    assert response.headers["X-Account-Status"] == "withdrawn"


def test_a_login_only_api_still_answers_a_suspended_account():
    """정지는 get_caller 에서 막지 않는다(그대로) — 정지 안내 화면과 탈퇴가 이 문으로 들어온다."""
    _wire({**_gate_row("verified", department="컴퓨터공학과"), "status": "suspended"})

    assert _fetch_status().status_code == 200


def test_status_returns_401_without_authorization_header():
    sent, _ = _wire(_gate_row("none"))

    response = _fetch_status(headers={})

    assert response.status_code == 401
    assert _calls(sent, "GET", "/rest/v1/profiles") == []


# --- POST /school-info -------------------------------------------------------


def _post_school_info(headers: dict = AUTH_HEADERS):
    return TestClient(app).post(
        "/school-info",
        json={"department": "컴퓨터공학과", "student_number": "2021123456"},
        headers=headers,
    )


def test_school_info_saves_when_verified():
    sent, _ = _wire(_gate_row("verified"))

    response = _post_school_info()

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    patch = _calls(sent, "PATCH", "/rest/v1/profiles")[0]
    assert json.loads(patch.content) == {"major": "컴퓨터공학과", "student_number": "2021123456"}
    assert dict(patch.url.params) == {"id": f"eq.{PROFILE_ID}"}


def test_school_info_returns_403_when_not_verified():
    sent, _ = _wire(_gate_row("pending"))

    response = _post_school_info()

    assert response.status_code == 403
    assert _calls(sent, "PATCH", "/rest/v1/profiles") == []


def test_school_info_is_403_with_the_status_header_for_a_suspended_account():
    # 결정 9(B6, 10-01): 정지 계정은 학과 · 학번을 저장하지 못한다. 앱은 헤더로 정지 안내 화면을 띄운다.
    sent, _ = _wire({**_gate_row("verified"), "status": "suspended"})

    response = _post_school_info()

    assert response.status_code == 403
    assert response.json()["detail"] == errors.ACCOUNT_SUSPENDED
    assert response.headers["X-Account-Status"] == "suspended"
    assert _calls(sent, "PATCH", "/rest/v1/profiles") == []


def test_a_suspended_account_can_still_read_its_verification_status():
    # 결정 9: 인증 상태 조회는 열어 둔다 — 정지 안내 화면까지 가는 길이다.
    _wire({**_gate_row("verified", department="컴퓨터공학과"), "status": "suspended"})

    response = _fetch_status()

    assert response.status_code == 200
    assert response.json()["status"] == "verified"
