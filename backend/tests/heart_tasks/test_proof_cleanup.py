import json
from datetime import datetime, timedelta

import httpx

from app.core.time import SEOUL
from app.heart_tasks.cleanup import purge_reviewed_proofs
from app.heart_tasks.repository import HeartTaskRepository
from app.heart_tasks.storage import HeartProofStorage

NOW = datetime(2026, 12, 1, 4, 0, tzinfo=SEOUL)
ROWS = [{"id": "a1", "storage_path": "p1/a1.jpg"}, {"id": "a2", "storage_path": "p2/a2.png"}]


def _parts(handler, seen: list[httpx.Request]):
    def wrapped(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)
    client = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return (HeartTaskRepository("https://x.supabase.co/rest/v1", "service-key", client),
            HeartProofStorage("https://x.supabase.co/storage/v1", "service-key", client))


def _handler(rows: list[dict], delete_status: int = 200):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET" and request.url.path.endswith("/heart_task_submissions"):
            return httpx.Response(200, json=rows)
        if request.method == "DELETE" and request.url.path.endswith("/object/heart-task-proofs"):
            return httpx.Response(delete_status, json=[])
        if request.method == "PATCH" and request.url.path.endswith("/heart_task_submissions"):
            return httpx.Response(204)
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


async def test_deletes_files_first_then_clears_paths():
    seen: list[httpx.Request] = []
    assert await purge_reviewed_proofs(*_parts(_handler(ROWS), seen), NOW) == 2

    methods = [r.method for r in seen]
    assert methods == ["GET", "DELETE", "PATCH"]
    assert json.loads(seen[1].content) == {"prefixes": ["p1/a1.jpg", "p2/a2.png"]}
    assert seen[2].url.params["id"] == "in.(a1,a2)"
    assert json.loads(seen[2].content) == {"storage_path": None}


async def test_asks_only_for_rows_reviewed_60_days_ago_with_a_file():
    seen: list[httpx.Request] = []
    await purge_reviewed_proofs(*_parts(_handler([]), seen), NOW)
    params = seen[0].url.params
    assert params["reviewed_at"] == f"lt.{(NOW - timedelta(days=60)).isoformat()}"
    assert params["storage_path"] == "not.is.null"
    assert params["select"] == "id,storage_path"
    # 오래된 것부터 100개씩 — 한도가 빠지면 경로 비우기 주소가 한도 없이 길어진다.
    assert (params["order"], params["limit"]) == ("reviewed_at", "100")


async def test_nothing_expired_touches_nothing_else():
    seen: list[httpx.Request] = []
    assert await purge_reviewed_proofs(*_parts(_handler([]), seen), NOW) == 0
    assert [r.method for r in seen] == ["GET"]


async def test_file_delete_failure_keeps_paths_for_tomorrow():
    # 경로를 먼저 비우면 파일을 다시 찾을 길이 없다 — 삭제가 실패하면 PATCH 하지 않는다.
    seen: list[httpx.Request] = []
    assert await purge_reviewed_proofs(*_parts(_handler(ROWS, delete_status=500), seen), NOW) == 0
    assert "PATCH" not in [r.method for r in seen]
