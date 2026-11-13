"""모든 경로는 로그인 관문 뒤에 있거나, 스스로 문을 지키는 공개 허용 목록에 있다.

새 경로를 관문(get_caller · get_verified_caller · get_admin_caller) 없이 열면 여기서 걸린다. 일부러 연 경로라면
그 경로가 무엇으로 문을 지키는지 확인한 뒤 PUBLIC 에 더한다.
"""
from app.admin.caller import get_admin_caller
from app.core.deps import get_caller, get_verified_caller
from app.main import app

GATES = {get_caller, get_verified_caller, get_admin_caller}
# 관문 없이 열려 있는 경로와 그 문.
PUBLIC = {
    ("GET", "/health"),                          # 살아 있는지만 답한다
    ("GET", "/app/version"),                     # 로그인 전에 보는 최소 앱 버전
    ("POST", "/hooks/before-user-created"),      # Supabase 가입 훅 — 웹훅 서명
    ("POST", "/hooks/verification-reviewed"),    # 학생증 검토 트리거(pg_net) — 공유 비밀
    ("POST", "/billing/apple/notifications"),    # 애플 서버 알림 — 애플 서명(JWS)
    ("POST", "/batch/daily-cards"),              # 아래 배치 넷과 작업 하나는 구글 OIDC 토큰
    ("POST", "/batch/chat-gate"),
    ("POST", "/batch/cleanup"),
    ("POST", "/batch/billing-voided"),
    ("POST", "/tasks/avatar-generate"),
}


def _routes(routes, context=None):
    """(전체 경로, 경로 객체). FastAPI 는 include 한 라우터를 한 겹 싸서 들고 있다(original_router) — app.routes 한 겹만 보면
    /health 하나뿐이라 안으로 내려간다. 관리자 라우터처럼 include 가 겹치면 앞머리(prefix)는 include_context 가 이어 붙인다."""
    for route in routes:
        included = getattr(route, "original_router", None)
        if included is None:
            yield (context.path_for(route) if context else route.path), route
        else:
            inner = route.include_context
            yield from _routes(included.routes, context.combine(inner) if context else inner)


def _calls(dependant):
    for sub in dependant.dependencies:
        yield sub.call
        yield from _calls(sub)


def test_every_route_is_behind_a_gate_or_on_the_public_list():
    gated, open_routes = 0, set()
    for path, route in _routes(app.routes):
        if GATES & set(_calls(route.dependant)):
            gated += 1
        else:
            open_routes |= {(method, path) for method in route.methods}

    assert gated > 100  # 안쪽 라우터까지 실제로 훑었다
    assert open_routes == PUBLIC


def test_every_admin_route_is_behind_the_admin_gate():
    """로그인만 확인하는 관문(get_caller · get_verified_caller)으로는 관리자 경로를 열 수 없다."""
    admin = [(path, route) for path, route in _routes(app.routes) if path.startswith("/admin")]

    assert len(admin) > 20  # 관리자 경로를 실제로 읽었다
    assert [path for path, route in admin if get_admin_caller not in set(_calls(route.dependant))] == []
