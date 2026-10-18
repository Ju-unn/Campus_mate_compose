"""관리자 작업 기록(admin_actions.ip, inet)에 남길 요청 IP."""
import ipaddress

from fastapi import Request


def _ip(value: str | None) -> str | None:
    try:
        return str(ipaddress.ip_address((value or "").strip()))
    except ValueError:
        return None


def request_ip(request: Request) -> str | None:
    """X-Forwarded-For 첫 값이 IP 면 그것, 아니면 바로 앞 연결의 주소, 둘 다 IP 가 아니면 None.
    IP 가 아닌 글자는 싣지 않는다 — inet 칸에 넣으면 검수 자체가 22P02 로 실패한다."""
    # shortcut: 첫 값은 사용자가 꾸밀 수 있음 — 감사 참고용이지 보안 판단에 쓰지 않는다, 필요해지면 Cloud Run 앞단 기준 오른쪽 값으로
    forwarded = request.headers.get("x-forwarded-for")
    return _ip(forwarded.split(",")[0] if forwarded else None) or _ip(request.client.host if request.client else None)
