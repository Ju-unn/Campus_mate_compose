"""M2(20261012010000) 뒤의 profile_private 흉내 — 평문 real_name · kakao_id 열이 없다.

서버가 그 열을 select · 필터 · 쓰기 본문 어디에든 쓰면 PostgREST 처럼 400(42703)으로 답한다. 가짜 DB 가 이 함수를
먼저 거치면, 서버가 평문 열을 다시 쓰기 시작하는 순간 시험이 깨진다(e2e/fake_private.py 와 같은 규칙)."""
import json

import httpx

PLAINTEXT_COLUMNS = ("real_name", "kakao_id")


def plaintext_gone(request: httpx.Request) -> httpx.Response | None:
    """profile_private 요청이 없어진 평문 열을 쓰면 42703 응답, 아니면 None."""
    if not request.url.path.endswith("/rest/v1/profile_private"):
        return None
    params = request.url.params
    body = json.loads(request.content) if request.content else {}
    rows = body if isinstance(body, list) else [body]
    named = [c.strip() for c in params.get("select", "").split(",")] + list(params) + [k for row in rows for k in row]
    if any(name in PLAINTEXT_COLUMNS for name in named):
        return httpx.Response(400, json={"code": "42703", "message": "column profile_private.real_name does not exist"})
    return None
