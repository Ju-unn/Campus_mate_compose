"""PostgREST 의 offset · limit · `Prefer: count=exact` 흉내(관리자 목록 번호 쪽 시험이 같이 쓴다).

정렬 · 필터는 부르는 가짜가 끝낸 rows 를 넘긴다. 건수를 셀 때 offset 이 전체보다 크면 진짜 PostgREST 처럼 416(건수 없음)이다.
"""
import httpx


def page_response(request: httpx.Request, rows: list) -> httpx.Response:
    params = request.url.params
    offset = int(params.get("offset", "0"))
    counting = "count=exact" in request.headers.get("prefer", "")
    if counting and offset > len(rows):
        return httpx.Response(416, json={"code": "PGRST103", "message": "Requested range not satisfiable"})
    shown = rows[offset:]
    if "limit" in params:
        shown = shown[:int(params["limit"])]
    if not counting:
        return httpx.Response(200, json=shown)
    span = f"{offset}-{offset + len(shown) - 1}" if shown else "*"
    return httpx.Response(200, json=shown, headers={"Content-Range": f"{span}/{len(rows)}"})
