"""관리자 공지 길(할 일 21, 보안 기준 21-1 · 21-3 · 21-4). 그림은 코드로 만든 단색 이미지만 쓴다.

관리자 가짜(admin_world)는 그대로 두고, 이 파일에서만 Storage(community-notices) · 공지 DB 함수 · polls 읽기를 앞에서 받는다.
"""
import io
import json

import httpx
import pytest
from PIL import Image

from admin_world import ADMIN, STRANGER, bearer
from app.core import errors

NOTICE = "55555555-5555-5555-5555-555555555555"
OBJECT_PREFIX = "/storage/v1/object/community-notices/"
ADMIN_HEADERS = bearer(sub=ADMIN, aal="aal2")


class NoticeSide:
    """공지 길이 부르는 곳의 가짜. 모르는 요청은 관리자 가짜(world.handle)로 넘긴다."""

    def __init__(self, fallback):
        self.fallback = fallback
        self.uploads: list[httpx.Request] = []
        self.deletes: list[list[str]] = []
        self.rpcs: list[tuple[str, dict]] = []
        self.upload_status = 200
        self.delete_status = 200
        self.rpc_status = 200
        self.rpc_error: dict | None = None
        self.rpc_raises: Exception | None = None
        self.deleted_image: str | None = f"{NOTICE}.jpg"
        self.rows: list[dict] = []
        self.list_requests: list[httpx.Request] = []

    def handle(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.startswith(OBJECT_PREFIX) and request.method == "POST":
            self.uploads.append(request)
            return httpx.Response(self.upload_status, json={})
        if path == "/storage/v1/object/community-notices" and request.method == "DELETE":
            self.deletes.append(json.loads(request.content)["prefixes"])
            return httpx.Response(self.delete_status, json={})
        if path in ("/rest/v1/rpc/admin_create_notice", "/rest/v1/rpc/admin_delete_notice"):
            name, body = path.rsplit("/", 1)[-1], json.loads(request.content)
            self.rpcs.append((name, body))
            if self.rpc_raises is not None:
                raise self.rpc_raises
            if self.rpc_error is not None:
                return httpx.Response(400, json=self.rpc_error)
            if self.rpc_status >= 400:
                return httpx.Response(self.rpc_status, json={})
            if name == "admin_create_notice":
                return httpx.Response(200, json={"id": body["p_id"]})
            return httpx.Response(200, json={"id": body["p_id"], "image_path": self.deleted_image})
        if path == "/rest/v1/polls" and request.method == "GET":
            self.list_requests.append(request)
            return httpx.Response(200, json=self.rows)
        return self.fallback(request)


@pytest.fixture(autouse=True)
def side(world) -> NoticeSide:
    # conftest 의 client 가 world.handle 로 전송기를 만들기 전에 바꿔 끼운다(autouse 가 먼저 돈다).
    notice_side = NoticeSide(world.handle)
    world.handle = notice_side.handle
    return notice_side


def _image(fmt: str = "PNG", size=(40, 30), **options) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, (20, 120, 220)).save(buffer, format=fmt, **options)
    return buffer.getvalue()


def _create(client, *, title="서비스 점검 안내", body="오늘 밤 점검해요", image: bytes | None = None,
            filename="notice.png", content_type="image/png", headers=ADMIN_HEADERS):
    files = {"image": (filename, image, content_type)} if image is not None else None
    return client.post("/admin/notices", data={"title": title, "body": body}, files=files, headers=headers)


# 관문 (보안 기준 21-1) ----------------------------------------------------------------

def _call(client, method: str, headers: dict):
    if method == "GET":
        return client.get("/admin/notices", headers=headers)
    if method == "POST":
        return client.post("/admin/notices", data={"title": "t", "body": "b"},
                           files={"image": ("a.png", _image(), "image/png")}, headers=headers)
    return client.request("DELETE", f"/admin/notices/{NOTICE}", json={"reason": "r"}, headers=headers)


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
def test_no_token_is_401(client, side, method):
    response = _call(client, method, {})

    assert response.status_code == 401
    assert response.json()["detail"] == errors.LOGIN_REQUIRED
    assert (side.uploads, side.rpcs, side.list_requests) == ([], [], [])


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
def test_without_the_second_factor_is_403_mfa_required(client, side, method):
    response = _call(client, method, bearer(sub=ADMIN, aal="aal1"))

    assert (response.status_code, response.json()["detail"]) == (403, "mfa_required")
    assert (side.uploads, side.rpcs, side.list_requests) == ([], [], [])


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
def test_a_plain_user_is_403_not_admin(client, world, side, method):
    world.caller = STRANGER

    response = _call(client, method, bearer(sub=STRANGER, aal="aal2"))

    assert (response.status_code, response.json()["detail"]) == (403, "not_admin")
    assert (side.uploads, side.rpcs, side.list_requests) == ([], [], [])


# 만들기 ----------------------------------------------------------------------------

@pytest.mark.parametrize("fmt", ["JPEG", "PNG", "WEBP"])
def test_create_reencodes_the_image_to_a_server_named_jpeg(client, side, fmt):
    response = _create(client, image=_image(fmt))

    assert response.status_code == 201
    notice_id = response.json()["id"]
    (upload,) = side.uploads
    # 경로 · content-type 은 서버가 정한다(보안 기준 21-3).
    assert upload.url.path == f"{OBJECT_PREFIX}{notice_id}.jpg"
    assert upload.headers["content-type"] == "image/jpeg"
    assert upload.content.startswith(b"\xff\xd8\xff")
    (rpc,) = side.rpcs
    assert rpc == ("admin_create_notice", {
        "p_admin": ADMIN, "p_id": notice_id, "p_title": "서비스 점검 안내", "p_body": "오늘 밤 점검해요",
        # 시험 클라이언트 주소("testclient")는 IP 가 아니라 기록에 싣지 않는다(request_ip).
        "p_image_path": f"{notice_id}.jpg", "p_ip": None,
    })


def test_the_uploaded_bytes_have_no_exif_and_a_1600_long_side(client, side):
    exif = Image.Exif()
    exif[0x8825] = {1: "N", 2: (37.0, 33.0, 0.0)}  # GPSInfo
    original = _image("JPEG", size=(3200, 800), exif=exif)
    assert b"Exif" in original

    _create(client, image=original, filename="photo.jpg", content_type="image/jpeg")

    stored = side.uploads[0].content
    assert b"Exif" not in stored
    assert Image.open(io.BytesIO(stored)).size == (1600, 400)


def test_the_client_filename_and_content_type_are_ignored(client, side):
    response = _create(client, image=_image("PNG"), filename="../../evil.svg", content_type="image/svg+xml")

    assert response.status_code == 201
    assert side.uploads[0].url.path == f"{OBJECT_PREFIX}{response.json()['id']}.jpg"
    assert side.uploads[0].headers["content-type"] == "image/jpeg"


def test_create_without_an_image_uploads_nothing(client, side):
    response = _create(client)

    assert response.status_code == 201
    assert side.uploads == []
    assert side.rpcs[0][1]["p_image_path"] is None


def test_the_title_and_body_are_trimmed(client, side):
    _create(client, title="  공지  ", body="\n본문\n")

    assert (side.rpcs[0][1]["p_title"], side.rpcs[0][1]["p_body"]) == ("공지", "본문")


@pytest.mark.parametrize(("data", "content_type"), [
    (b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', "image/png"),
    (b"<!doctype html><html><script>alert(1)</script></html>", "image/jpeg"),
    (b"GIF89a" + b"\x00" * 64, "image/gif"),
    (b"\xff\xd8\xff\xe0" + b"broken" * 40, "image/jpeg"),
], ids=["svg", "html", "gif", "깨진 jpeg"])
def test_a_file_that_is_not_jpeg_png_or_webp_is_422_image_type(client, side, data, content_type):
    response = _create(client, image=data, content_type=content_type)

    assert (response.status_code, response.json()["detail"]) == (422, "image_type")
    assert (side.uploads, side.rpcs) == ([], [])


def test_a_real_gif_is_422_image_type(client, side):
    buffer = io.BytesIO()
    Image.new("P", (10, 10), 1).save(buffer, format="GIF")

    response = _create(client, image=buffer.getvalue(), content_type="image/gif")

    assert (response.status_code, response.json()["detail"]) == (422, "image_type")


def test_more_than_10mb_is_422_image_too_large(client, side):
    response = _create(client, image=_image("JPEG") + b"\x00" * (11 * 1024 * 1024), content_type="image/jpeg")

    assert (response.status_code, response.json()["detail"]) == (422, "image_too_large")
    assert (side.uploads, side.rpcs) == ([], [])


@pytest.mark.parametrize(("title", "body"), [
    ("가" * 41, "본문"),
    ("   ", "본문"),
    ("​", "본문"),
    ("두\n줄", "본문"),
    ("제목", "가" * 2001),
    ("제목", "  "),
    ("제목", "널\x00문자"),
], ids=["제목 41자", "제목 공백", "제목 0폭", "제목 줄바꿈", "본문 2001자", "본문 공백", "본문 널"])
def test_a_bad_title_or_body_is_422_before_anything_is_uploaded(client, side, title, body):
    response = _create(client, title=title, body=body, image=_image())

    assert response.status_code == 422
    assert (side.uploads, side.rpcs) == ([], [])


def test_title_40_and_body_2000_are_allowed(client, side):
    response = _create(client, title="가" * 40, body="나" * 2000)

    assert response.status_code == 201


@pytest.mark.parametrize("failure", [
    {"rpc_status": 500},
    {"rpc_error": {"code": "23514", "message": "check"}},
    {"rpc_error": {"code": "42501", "message": "not admin"}},
], ids=["DB 500", "check 위반", "관리자 명단에서 빠짐"])
def test_when_the_db_fails_after_the_upload_the_image_is_removed(client, side, failure):
    for key, value in failure.items():
        setattr(side, key, value)

    response = _create(client, image=_image())

    assert response.status_code >= 400
    (upload,) = side.uploads
    assert side.deletes == [[upload.url.path.removeprefix(OBJECT_PREFIX)]]


@pytest.mark.parametrize("error", [httpx.ReadTimeout("t"), httpx.ConnectError("c"), httpx.RemoteProtocolError("p")],
                         ids=["시간 초과", "연결 실패", "응답 도중 끊김"])
def test_when_the_db_result_is_unknown_the_image_is_kept(client, side, caplog, error):
    # 공지가 실제로는 들어갔을 수 있다 — 그림을 지우면 그림 없는 공지(깨진 주소)가 남는다. 로그만 남긴다.
    side.rpc_raises = error

    with pytest.raises(type(error)):
        _create(client, image=_image())

    assert len(side.uploads) == 1
    assert side.deletes == []
    assert "결과를 모른다" in caplog.text


def test_when_the_upload_fails_the_db_is_not_called(client, side):
    side.upload_status = 500

    response = _create(client, image=_image())

    assert response.status_code == 500
    assert side.rpcs == []


# 지우기 ----------------------------------------------------------------------------

def test_delete_removes_the_row_then_the_image(client, side):
    response = client.request("DELETE", f"/admin/notices/{NOTICE}", json={"reason": "기간 끝"}, headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert response.json() == {"id": NOTICE}
    (rpc,) = side.rpcs
    assert rpc[0] == "admin_delete_notice"
    assert {key: rpc[1][key] for key in ("p_admin", "p_id", "p_reason")} == {"p_admin": ADMIN, "p_id": NOTICE,
                                                                             "p_reason": "기간 끝"}
    assert side.deletes == [[f"{NOTICE}.jpg"]]


def test_delete_without_an_image_does_not_touch_storage(client, side):
    side.deleted_image = None

    response = client.request("DELETE", f"/admin/notices/{NOTICE}", json={"reason": "기간 끝"}, headers=ADMIN_HEADERS)

    assert response.status_code == 200
    assert side.deletes == []


def test_a_failed_image_delete_is_only_logged(client, side):
    side.delete_status = 500

    response = client.request("DELETE", f"/admin/notices/{NOTICE}", json={"reason": "기간 끝"}, headers=ADMIN_HEADERS)

    assert response.status_code == 200


def test_delete_of_a_missing_notice_is_404(client, side):
    side.rpc_error = {"code": "CM404", "message": "notice not found"}

    response = client.request("DELETE", f"/admin/notices/{NOTICE}", json={"reason": "기간 끝"}, headers=ADMIN_HEADERS)

    assert (response.status_code, response.json()["detail"]) == (404, "not_found")
    assert side.deletes == []


def test_delete_needs_a_reason(client, side):
    response = client.request("DELETE", f"/admin/notices/{NOTICE}", json={"reason": "  "}, headers=ADMIN_HEADERS)

    assert response.status_code == 422
    assert side.rpcs == []


# 목록 ----------------------------------------------------------------------------

def _row(i: int, **overrides) -> dict:
    return {"id": f"55555555-5555-5555-5555-{i:012d}", "title": f"공지 {i}", "question": "본문", "image_path": None,
            "status": "visible", "created_at": "2026-11-24T05:00:00+00:00", **overrides}


def test_admin_list_includes_hidden_notices_and_our_bucket_urls(client, side):
    side.rows = [_row(1, status="blinded", image_path=f"55555555-5555-5555-5555-{1:012d}.jpg"), _row(2)]

    response = client.get("/admin/notices", headers=ADMIN_HEADERS)

    assert response.status_code == 200
    body = response.json()
    assert body["has_more"] is False
    first, second = body["items"]
    assert set(first) == {"id", "title", "text", "image_url", "status", "created_at"}
    assert first["status"] == "blinded"
    assert first["image_url"].endswith(f"/storage/v1/object/public/community-notices/55555555-5555-5555-5555-{1:012d}.jpg")
    assert second["image_url"] is None
    (request,) = side.list_requests
    assert request.url.params["kind"] == "eq.notice"
    assert request.url.params["order"] == "created_at.desc,id.desc"
    assert "author" not in request.url.params["select"]


def test_admin_list_pages_by_cursor(client, side):
    side.rows = [_row(i) for i in range(21)]

    response = client.get("/admin/notices", params={"before": "2026-11-24T05:00:00+00:00", "before_id": NOTICE},
                          headers=ADMIN_HEADERS)

    assert response.json()["has_more"] is True
    assert len(response.json()["items"]) == 20
    params = side.list_requests[0].url.params
    assert params["limit"] == "21"
    assert params["or"] == f"(created_at.lt.2026-11-24T05:00:00+00:00,and(created_at.eq.2026-11-24T05:00:00+00:00,id.lt.{NOTICE}))"


def test_admin_list_half_cursor_is_422(client, side):
    response = client.get("/admin/notices", params={"before_id": NOTICE}, headers=ADMIN_HEADERS)

    assert response.status_code == 422
