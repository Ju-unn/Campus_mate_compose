import logging
from uuid import UUID

import httpx
from fastapi import HTTPException

from app.signup_policy import IDENTITY_KEY_VERSION, bytea_literal, hash_phone

_logger = logging.getLogger(__name__)


async def set_encrypted_phone_number(
    postgrest_url: str,
    service_role_key: str,
    client: httpx.AsyncClient,
    profile_id: UUID,
    phone_number: str,
    encryption_key: str,
    *,
    identity_key: str,
) -> None:
    # 암호화 자체는 DB 안(pgcrypto pgp_sym_encrypt)에서 한다 — 여기서는 RPC 를 부르는 얇은 wrapper 다.
    # 키는 JSON 바디로만 넘긴다. URL 쿼리스트링에 넣으면 웹서버 접근 로그에 그대로 남는다(2026-09-20 사용자 승인 조건).
    # 지인 차단용 HMAC 도 같이 넘긴다(조각 6 B4). 해시 키는 DB 에 들이지 않고 여기서 떠서 값만 보낸다.
    # 입력은 저장하는 E.164 값 그대로다 — 연락처 등록(safety)이 같은 모양을 해시해야 대조가 맞는다.
    response = await client.post(
        f"{postgrest_url}/rpc/set_phone_number",
        json={
            "p_profile_id": str(profile_id), "p_phone": phone_number, "p_key": encryption_key,
            "p_phone_hmac": bytea_literal(hash_phone(identity_key, phone_number)),
            "p_phone_hmac_key_version": IDENTITY_KEY_VERSION,
        },
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        },
    )
    response.raise_for_status()


def _headers(service_role_key: str) -> dict[str, str]:
    return {
        "apikey": service_role_key,
        "Authorization": f"Bearer {service_role_key}",
        "Content-Type": "application/json",
    }


async def set_encrypted_real_name(
    postgrest_url: str, service_role_key: str, client: httpx.AsyncClient,
    profile_id: UUID, real_name: str, encryption_key: str,
) -> None:
    # 실명 enc 열 쓰기(이중 쓰기 기간 — 옛 평문 열은 따로 쓴다). DB 함수가 행이 없으면 만든다(upsert).
    # 전화번호와 같은 규칙 — 키는 JSON 바디로만 넘긴다.
    response = await client.post(
        f"{postgrest_url}/rpc/set_real_name",
        json={"p_profile": str(profile_id), "p_real_name": real_name, "p_key": encryption_key},
        headers=_headers(service_role_key),
    )
    response.raise_for_status()


async def set_encrypted_kakao_id(
    postgrest_url: str, service_role_key: str, client: httpx.AsyncClient,
    profile_id: UUID, kakao_id: str, encryption_key: str,
) -> None:
    # DB 함수는 UPDATE 전용이다 — 부르는 쪽이 먼저 ensure_private_row 로 행을 보장한다.
    response = await client.post(
        f"{postgrest_url}/rpc/set_kakao_id",
        json={"p_profile": str(profile_id), "p_kakao_id": kakao_id, "p_key": encryption_key},
        headers=_headers(service_role_key),
    )
    response.raise_for_status()


async def decrypt_profile_private(
    postgrest_url: str, service_role_key: str, client: httpx.AsyncClient,
    profile_id: UUID | str, encryption_key: str,
) -> dict[str, str | None]:
    """enc 열을 복호화한 {real_name, kakao_id}. 행이 없거나 enc 가 비어 있으면 그 칸은 None 이다."""
    response = await client.post(
        f"{postgrest_url}/rpc/decrypt_profile_private",
        json={"p_profile": str(profile_id), "p_key": encryption_key},
        headers=_headers(service_role_key),
    )
    response.raise_for_status()
    data = response.json() if response.content else None
    # 행 목록이 기본이지만 한 행(객체)이나 빈 응답도 견딘다.
    row = data[0] if isinstance(data, list) and data else data if isinstance(data, dict) else {}
    return {"real_name": row.get("real_name"), "kakao_id": row.get("kakao_id")}


async def write_best_effort(field: str, profile_id: UUID | str, write) -> None:
    """이중 쓰기 기간의 enc 쓰기. 평문이 진실이므로 실패해도 요청을 실패시키지 않는다 — 백필이 메운다.

    로그에는 필드 이름과 profile_id 와 예외 종류만 남긴다(값 · 키 · URL 은 싣지 않는다)."""
    try:
        await write()
    except (httpx.HTTPError, HTTPException) as exc:
        # HTTPException: ensure_private_row 가 쓰는 공통 변환(core/http)이 제약 위반을 4xx 로 바꿔 던진다.
        _logger.warning("profile_private enc 쓰기 실패 → 평문만 저장됨 field=%s profile_id=%s error=%s",
                        field, profile_id, type(exc).__name__)
