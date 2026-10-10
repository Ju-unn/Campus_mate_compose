"""notifications 표를 흉내 내는 가짜 PostgREST — 라우터 · 정리 배치 시험이 같이 쓴다.

필터 문법은 저장소가 실제로 보내는 것만 이해한다(id · profile_id 의 eq., read_at 의 is.null, created_at 의 lt.).
모르는 필터가 오면 일부러 터뜨린다 — 조용히 무시하면 소유자 검사가 빠져도 시험이 통과한다."""
import json
from datetime import datetime

import httpx

ME = "11111111-1111-1111-1111-111111111111"
OTHER = "99999999-9999-9999-9999-999999999999"
_KNOWN_FILTERS = {"id", "profile_id", "read_at", "created_at"}
_CONTROL = {"select", "order", "limit"}


def row(n: int, profile_id: str = ME, read_at: str | None = None, **overrides) -> dict:
    """n 이 클수록 최근이다 — 10월 n일 12시."""
    return {"id": f"00000000-0000-0000-0000-{n:012d}", "profile_id": profile_id, "kind": "chat_request",
            "title": f"제목{n}", "body": f"본문{n}", "data": {"route": "acceptances"},
            "created_at": f"2026-10-{n:02d}T12:00:00+00:00", "read_at": read_at, **overrides}


class FakeInbox:
    def __init__(self, rows: list[dict], fail_delete: bool = False):
        self.rows = [dict(r) for r in rows]
        self.requests: list[httpx.Request] = []
        self.fail_delete = fail_delete

    def _matching(self, params) -> list[dict]:
        unknown = {k for k in params.keys() if k not in _KNOWN_FILTERS | _CONTROL}
        assert not unknown, f"모르는 필터 {unknown}"
        out = list(self.rows)
        for key in _KNOWN_FILTERS & set(params.keys()):
            value = params[key]
            if value.startswith("eq."):
                out = [r for r in out if r[key] == value[3:]]
            elif value == "is.null":
                out = [r for r in out if r[key] is None]
            elif value.startswith("lt."):
                bound = datetime.fromisoformat(value[3:])
                out = [r for r in out if datetime.fromisoformat(r[key]) < bound]
            else:
                raise AssertionError(f"모르는 필터 값 {key}={value}")
        return out

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        params = request.url.params
        found = self._matching(params)
        if request.method == "GET":
            if "order" in params:
                assert params["order"].startswith("created_at.desc")
                found.sort(key=lambda r: (r["created_at"], r["id"]), reverse=True)
            total = len(found)
            found = found[: int(params["limit"])] if "limit" in params else found
            columns = params["select"].split(",") if "select" in params else None
            body = [{c: r[c] for c in columns} if columns and columns != ["*"] else r for r in found]
            headers = {}
            if "count=exact" in request.headers.get("prefer", ""):
                headers["Content-Range"] = f"0-0/{total}" if total else "*/0"
            return httpx.Response(200, json=body, headers=headers)
        if request.method == "PATCH":
            patch = json.loads(request.content)
            for r in found:
                r.update(patch)
            wants_rows = "return=representation" in request.headers.get("prefer", "")
            return httpx.Response(200, json=[dict(r) for r in found] if wants_rows else [])
        if request.method == "DELETE":
            if self.fail_delete:
                return httpx.Response(500, json={"message": "boom"})
            ids = {r["id"] for r in found}
            self.rows = [r for r in self.rows if r["id"] not in ids]
            # 실제 PostgREST 는 Prefer: return=representation 이 없으면 204 + 빈 본문이다.
            if "return=representation" not in request.headers.get("prefer", ""):
                return httpx.Response(204)
            return httpx.Response(200, json=[{"id": i} for i in ids])
        raise AssertionError(f"unexpected {request.method}")

    def by_id(self, n: int) -> dict:
        return next(r for r in self.rows if r["id"] == row(n)["id"])
