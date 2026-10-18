"""D4(통계 · 상태판 · 매칭 현황) 시험이 쓰는 Supabase 가짜. AdminWorld(관문 · 작업 기록)를 그대로 상속하고 새 읽기 DB 함수(RPC)만 먼저 가로챈다.

admin_world.py · conftest.py 는 고치지 않는다(D2b 창이 같은 파일을 고치는 중이라 충돌을 피한다). 시험 모듈이 이 파일의
`world` 픽스처를 다시 정의해 쓴다. 요청은 경로 + 본문 키로 가른다 — 메모 reference_backend_test_mock_traps ①.
"""
import json

import httpx

from admin_world import AdminWorld

D4_RPCS = ("admin_stats_overview", "admin_stats_daily", "admin_unknown_domains", "admin_universities_status",
           "admin_health", "admin_matching_summary", "admin_matching_daily", "admin_matching_pairs")


class StatsWorld(AdminWorld):
    """RPC 이름 → 돌려줄 JSON 은 rpc_results[이름](기본 []), 오류는 rpc_error_code · rpc_error_message(D2 와 같은 약속),
    경로 하나를 통째로 실패시키려면 table_status[경로] = 상태 코드."""

    def handle(self, request: httpx.Request) -> httpx.Response:
        name = request.url.path.removeprefix("/rest/v1/rpc/")
        if request.method != "POST" or not request.url.path.startswith("/rest/v1/rpc/") or name not in D4_RPCS:
            return super().handle(request)
        self.requests.append(request)
        self.rpcs.append((name, json.loads(request.content)))
        if request.url.path in self.table_status:
            return httpx.Response(self.table_status[request.url.path], json={})
        if self.rpc_error_code:
            return httpx.Response(400, json={"code": self.rpc_error_code, "message": self.rpc_error_message})
        return httpx.Response(200, json=self.rpc_results.get(name, []))
