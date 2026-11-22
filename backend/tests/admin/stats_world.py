"""D4(통계 · 상태판 · 매칭 현황) 시험이 쓰는 Supabase 가짜. AdminWorld(관문 · 작업 기록)를 그대로 상속하고 새 읽기 DB 함수(RPC)만 먼저 가로챈다.

admin_world.py · conftest.py 는 고치지 않는다(D2b 창이 같은 파일을 고치는 중이라 충돌을 피한다). 시험 모듈이 이 파일의
`world` 픽스처를 다시 정의해 쓴다. 요청은 경로 + 본문 키로 가른다 — 메모 reference_backend_test_mock_traps ①.
"""
import json

import httpx

from admin_world import AdminWorld

D4_RPCS = ("admin_stats_overview", "admin_stats_daily", "admin_unknown_domains", "admin_universities_status",
           "admin_health", "admin_matching_summary", "admin_matching_daily", "admin_matching_pairs",
           "admin_matching_requests")
# 메뉴 대기 건수(11-17)가 count=exact 로 세는 표.
COUNTED_TABLES = ("graduate_verification_requests", "inquiries")
# 매칭 목록 DB 함수의 커서 칸(시각, id) — 진짜 함수처럼 최근 순으로 커서 뒤 p_limit 줄만 준다.
CURSOR_KEYS = {"admin_matching_pairs": ("matched_at", "match_id"), "admin_matching_requests": ("requested_at", "card_id")}


class StatsWorld(AdminWorld):
    """RPC 이름 → 돌려줄 JSON 은 rpc_results[이름](기본 []), 오류는 rpc_error_code · rpc_error_message(D2 와 같은 약속),
    경로 하나를 통째로 실패시키려면 table_status[경로] = 상태 코드. 건수 세기(Prefer: count=exact)는 content_ranges[표](기본 `*/0`)."""

    def __init__(self) -> None:
        super().__init__()
        self.content_ranges: dict[str, str] = {}

    def handle(self, request: httpx.Request) -> httpx.Response:
        table = request.url.path.removeprefix("/rest/v1/")
        if request.method == "GET" and table in COUNTED_TABLES and "count=exact" in request.headers.get("prefer", ""):
            self.requests.append(request)
            return httpx.Response(200, json=[], headers={"Content-Range": self.content_ranges.get(table, "*/0")})
        name = request.url.path.removeprefix("/rest/v1/rpc/")
        if request.method != "POST" or not request.url.path.startswith("/rest/v1/rpc/") or name not in D4_RPCS:
            return super().handle(request)
        self.requests.append(request)
        self.rpcs.append((name, json.loads(request.content)))
        if request.url.path in self.table_status:
            return httpx.Response(self.table_status[request.url.path], json={})
        if self.rpc_error_code:
            return httpx.Response(400, json={"code": self.rpc_error_code, "message": self.rpc_error_message})
        rows = self.rpc_results.get(name, [])
        if name in CURSOR_KEYS and isinstance(rows, list):
            rows = _after_cursor(rows, CURSOR_KEYS[name], json.loads(request.content))
        return httpx.Response(200, json=rows)


def _after_cursor(rows: list[dict], keys: tuple[str, str], body: dict) -> list[dict]:
    at, key = keys
    ordered = sorted(rows, key=lambda r: (r[at], r[key]), reverse=True)
    if body.get("p_before_at") is not None:
        cursor = (body["p_before_at"], body["p_before_id"])
        ordered = [r for r in ordered if (r[at], r[key]) < cursor]
    return ordered[:body["p_limit"]]
