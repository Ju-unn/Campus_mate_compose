"""15e 실제 사진 한 번에 저장(계획서 2-2). 칸 배치 검사 자체는 test_photo_layout.py 가 본다."""
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
from google.cloud import vision

from tests.me.test_me_profile import AUTH_HEADERS, PROFILE_ID, _wire, overrides  # noqa: F401 — autouse 픽스처
from app.core.deps import get_vision_client
from app.main import app

KEPT_A = {"id": "aaaaaaaa-0000-0000-0000-000000000001", "storage_path": f"{PROFILE_ID}/a.jpg", "position": 0}
KEPT_B = {"id": "aaaaaaaa-0000-0000-0000-000000000002", "storage_path": f"{PROFILE_ID}/b.jpg", "position": 1}
DROP_C = {"id": "aaaaaaaa-0000-0000-0000-000000000003", "storage_path": f"{PROFILE_ID}/c.jpg", "position": 2}
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 32
_PHOTO_FILES = "/storage/v1/object/profile-photos/"


def _vision(safe: bool) -> AsyncMock:
    # spec 을 준다 — 비동기 클라이언트에 없는 메서드를 부르면 테스트가 잡아야 한다(test_photos.py 와 같은 이유).
    client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
    level = 1 if safe else 5  # VERY_UNLIKELY / VERY_LIKELY
    client.batch_annotate_images.return_value = SimpleNamespace(responses=[SimpleNamespace(
        error=SimpleNamespace(message=""),
        safe_search_annotation=SimpleNamespace(adult=level, violence=1),
    )])
    return client


def _put(rows, layout, avatar_source=0, files=(), safe=True, seen=None):
    """layout 은 파이썬 목록으로 받아 JSON 문자열로 보낸다. seen 에 가드 뒤 요청을 쌓는다."""
    seen = [] if seen is None else seen

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        # 표 이름(경로)과 메서드로 가른다 — 쿼리 문자열 조각으로 가르지 않는다(profile_id=eq. 안에 id=eq. 가 있다).
        if request.url.path.endswith("/rest/v1/profile_photos"):
            if request.method == "GET":
                return httpx.Response(200, json=rows)
            return httpx.Response(201 if request.method == "POST" else 204)
        if request.url.path.startswith(_PHOTO_FILES):
            return httpx.Response(200, json={"Key": "profile-photos/x"})
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})

    vision_client = _vision(safe)
    app.dependency_overrides[get_vision_client] = lambda: vision_client
    return _wire(handler).put(
        "/me/photos",
        headers=AUTH_HEADERS,
        data={"layout": json.dumps(layout), "avatar_source": str(avatar_source)},
        files=[("photos", (f"p{i}.jpg", data, "image/jpeg")) for i, data in enumerate(files)],
    )


def _one(seen, method: str, fragment: str) -> httpx.Request:
    matches = [r for r in seen if r.method == method and fragment in r.url.path]
    assert len(matches) == 1, [f"{r.method} {r.url}" for r in matches]
    return matches[0]


def _label(request: httpx.Request) -> str | None:
    if request.url.path.startswith(_PHOTO_FILES):
        return {"POST": "upload", "DELETE": "delete-file"}.get(request.method)
    if request.url.path.endswith("/rest/v1/profile_photos"):
        return {"DELETE": "delete-rows", "PATCH": "clear-source", "POST": "upsert"}.get(request.method)
    return None


def _storage_writes(seen) -> list[httpx.Request]:
    return [r for r in seen if r.url.path.startswith(_PHOTO_FILES)]


def _db_writes(seen) -> list[httpx.Request]:
    return [r for r in seen if "/rest/v1/" in r.url.path and r.method != "GET"]


def test_swapping_two_kept_photos_moves_positions_only():
    seen = []
    response = _put([KEPT_A, KEPT_B], [{"keep": KEPT_B["id"]}, {"keep": KEPT_A["id"]}], avatar_source=0, seen=seen)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    upsert = _one(seen, "POST", "/rest/v1/profile_photos")
    assert upsert.url.params["on_conflict"] == "id"
    assert "resolution=merge-duplicates" in upsert.headers["prefer"]
    assert json.loads(upsert.content) == [
        {"id": KEPT_B["id"], "profile_id": PROFILE_ID, "storage_path": KEPT_B["storage_path"],
         "position": 0, "is_avatar_source": True},
        {"id": KEPT_A["id"], "profile_id": PROFILE_ID, "storage_path": KEPT_A["storage_path"],
         "position": 1, "is_avatar_source": False},
    ]
    assert _storage_writes(seen) == []  # 업로드도 삭제도 없다
    # 빠진 사진이 없으면 행 지우기도 없다.
    assert [r for r in seen if r.method == "DELETE"] == []


def test_replacing_one_photo_uploads_it_and_deletes_the_dropped_file_last():
    seen = []
    response = _put([KEPT_A, KEPT_B, DROP_C], [{"keep": KEPT_A["id"]}, {"new": 0}], files=[JPEG], seen=seen)

    assert response.status_code == 200
    # 순서: 업로드 → 빠진 행 지우기 → 원본 내리기 → upsert → 빠진 파일 지우기(계획서 2-2 ④~⑧). 빠진 사진은 B · C 두 장이다.
    order = [_label(r) for r in seen if _label(r)]
    assert order == ["upload", "delete-rows", "clear-source", "upsert", "delete-file", "delete-file"]
    delete_rows = _one(seen, "DELETE", "/rest/v1/profile_photos")
    assert delete_rows.url.params["id"] == f"in.({KEPT_B['id']},{DROP_C['id']})"
    assert delete_rows.url.params["profile_id"] == f"eq.{PROFILE_ID}"   # 남의 행에는 안 닿는다
    deleted_files = [r.url.path.removeprefix(_PHOTO_FILES) for r in seen
                     if r.method == "DELETE" and r.url.path.startswith(_PHOTO_FILES)]
    assert deleted_files == [KEPT_B["storage_path"], DROP_C["storage_path"]]
    # 새 행은 방금 올린 파일을 가리킨다.
    upload_path = _one(seen, "POST", _PHOTO_FILES).url.path.removeprefix(_PHOTO_FILES)
    rows = json.loads(_one(seen, "POST", "/rest/v1/profile_photos").content)
    assert rows[1]["storage_path"] == upload_path and upload_path.startswith(f"{PROFILE_ID}/")


def test_a_failed_file_delete_still_returns_success(caplog):
    """⑧(빠진 파일 지우기)이 500 을 줘도 ⑤~⑦ 저장은 이미 끝났다 — 200 을 주고 로그만 남긴다."""
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path.endswith("/rest/v1/profile_photos"):
            if request.method == "GET":
                return httpx.Response(200, json=[KEPT_A, KEPT_B, DROP_C])
            return httpx.Response(201 if request.method == "POST" else 204)
        if request.url.path.startswith(_PHOTO_FILES):
            if request.method == "DELETE":
                return httpx.Response(500, json={"message": "boom"})
            return httpx.Response(200, json={"Key": "profile-photos/x"})
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})

    vision_client = _vision(True)
    app.dependency_overrides[get_vision_client] = lambda: vision_client
    with caplog.at_level("WARNING", logger="app.me.router"):
        response = _wire(handler).put(
            "/me/photos",
            headers=AUTH_HEADERS,
            data={"layout": json.dumps([{"keep": KEPT_A["id"]}, {"new": 0}]), "avatar_source": "0"},
            files=[("photos", ("p0.jpg", JPEG, "image/jpeg"))],
        )

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    # 행 쓰기는 이미 끝났다 — 삭제 실패가 저장 자체를 되돌리지 않는다.
    assert _one(seen, "POST", "/rest/v1/profile_photos")
    assert any("사진 삭제" in r.getMessage() for r in caplog.records)


def test_an_unsafe_new_photo_changes_nothing():
    seen = []
    response = _put([KEPT_A, KEPT_B], [{"keep": KEPT_A["id"]}, {"new": 0}], files=[JPEG], safe=False, seen=seen)

    assert response.status_code == 422
    assert response.json() == {"detail": "부적절한 사진은 올릴 수 없어요"}
    assert _storage_writes(seen) == [] and _db_writes(seen) == []


def test_a_later_unsafe_photo_stops_the_earlier_one_from_uploading():
    # ③ 을 전부 끝낸 뒤에 ④ 다 — 둘째 장이 부적절하면 첫째 장도 올라가지 않는다.
    seen = []
    vision_client = _vision(safe=True)
    unsafe = _vision(safe=False).batch_annotate_images.return_value
    vision_client.batch_annotate_images.side_effect = [vision_client.batch_annotate_images.return_value, unsafe]

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path.endswith("/rest/v1/profile_photos") and request.method == "GET":
            return httpx.Response(200, json=[KEPT_A, KEPT_B])
        return httpx.Response(200, json={})

    app.dependency_overrides[get_vision_client] = lambda: vision_client
    response = _wire(handler).put(
        "/me/photos", headers=AUTH_HEADERS,
        data={"layout": json.dumps([{"new": 0}, {"new": 1}]), "avatar_source": "0"},
        files=[("photos", ("p0.jpg", JPEG, "image/jpeg")), ("photos", ("p1.jpg", JPEG, "image/jpeg"))],
    )

    assert response.status_code == 422
    assert _storage_writes(seen) == [] and _db_writes(seen) == []


def test_an_unreadable_new_photo_changes_nothing():
    seen = []
    response = _put([KEPT_A, KEPT_B], [{"keep": KEPT_A["id"]}, {"new": 0}], files=[b"not an image"], seen=seen)

    assert response.status_code == 400
    assert response.json() == {"detail": "사진을 다시 확인해 주세요"}
    assert _storage_writes(seen) == [] and _db_writes(seen) == []


def test_a_keep_id_that_is_not_mine_anymore_is_409():
    seen = []
    response = _put([KEPT_A], [{"keep": KEPT_A["id"]}, {"keep": KEPT_B["id"]}], seen=seen)

    assert response.status_code == 409
    assert response.json() == {"detail": "사진이 바뀌었어요, 다시 열어 주세요"}
    assert _storage_writes(seen) == [] and _db_writes(seen) == []


def test_reads_only_my_photo_rows():
    seen = []
    _put([KEPT_A, KEPT_B], [{"keep": KEPT_A["id"]}, {"keep": KEPT_B["id"]}], seen=seen)

    read = _one(seen, "GET", "/rest/v1/profile_photos")
    assert read.url.params["profile_id"] == f"eq.{PROFILE_ID}"


def test_a_broken_layout_is_422_before_reading_anything():
    seen = []
    response = _put([KEPT_A, KEPT_B], [{"keep": KEPT_A["id"]}], seen=seen)

    assert response.status_code == 422
    assert response.json() == {"detail": "입력한 값을 다시 확인해 주세요"}
    assert [r for r in seen if "/rest/v1/profile_photos" in r.url.path] == []


def test_the_avatar_source_goes_to_the_chosen_slot_only():
    seen = []
    _put([KEPT_A, KEPT_B], [{"keep": KEPT_A["id"]}, {"keep": KEPT_B["id"]}], avatar_source=1, seen=seen)

    rows = json.loads(_one(seen, "POST", "/rest/v1/profile_photos").content)
    assert [row["is_avatar_source"] for row in rows] == [False, True]
    clear = _one(seen, "PATCH", "/rest/v1/profile_photos")
    assert json.loads(clear.content) == {"is_avatar_source": False}
    assert clear.url.params["profile_id"] == f"eq.{PROFILE_ID}"


def test_new_rows_get_fresh_ids():
    seen = []
    _put([KEPT_A, KEPT_B], [{"new": 0}, {"new": 1}], files=[JPEG, JPEG], seen=seen)

    rows = json.loads(_one(seen, "POST", "/rest/v1/profile_photos").content)
    assert len({row["id"] for row in rows}) == 2
    assert {row["id"] for row in rows}.isdisjoint({KEPT_A["id"], KEPT_B["id"]})


def test_rejects_missing_login():
    assert _wire(lambda r: httpx.Response(404)).put("/me/photos").status_code == 401
