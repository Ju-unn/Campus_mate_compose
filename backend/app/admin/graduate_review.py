"""관리자 졸업생 인증 검수(계획서 2026-10-19-graduate-verification Task 5). 목록 · 한 건 · 승인 · 반려. 모든 경로는 get_admin_caller 뒤에 있다.

사진은 비공개 버킷의 5분 서명 URL 로만 내려가고, 응답에 storage_path · 해시 · 학번은 싣지 않는다. 결정된 신청은 사진 · 글자 인식 값 ·
이전 학교 메일이 이미 없다(평문은 결정 즉시 지운다).

순서는 인증샷 검수(heart_task_review._review)와 같다: 줄 읽기(없으면 404) → DB 함수(승인 · 반려 + 작업 기록 한 트랜잭션)
→ 사진 삭제(실패해도 결정은 그대로, 매시 배치가 다시 지운다) → 결과 알림(실패해도 결정은 그대로) → 응답.

중복 점검은 읽기 전용이다 — 이전 학교 메일 해시로 school_email_claims · signup_blocks 를 읽기만 하고 아무것도 쓰지 않는다.
번호 · 이메일 · 학번 · 해시 · 사진 경로는 로그에 남기지 않는다(신청 id 와 profile_id 만)."""
import logging
from datetime import datetime
from typing import Literal
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.admin.caller import AdminCaller, get_admin_caller
from app.admin.graduate_notice import result_notice
from app.admin.graduate_repository import GraduateAdminRepository
from app.admin.heart_task_notice import send_result_notice
from app.admin.repository import NOT_FOUND
from app.admin.request_ip import request_ip
from app.cards.push import FcmSender
from app.cards.router import get_sender
from app.core import errors
from app.core.deps import get_now
from app.graduate_verification.document_reader import read_certificate
from app.graduate_verification.hashing import (
    hash_document_number, hash_student_number, normalize_document_number, normalize_student_number,
)
from app.graduate_verification.repository import GraduateRequestRepository
from app.graduate_verification.retention import delete_photo
from app.graduate_verification.storage import GraduateCertStorage
from app.signup_policy import IDENTITY_KEY_VERSION, SignupPolicy, hash_email

router = APIRouter(prefix="/graduate-requests")
logger = logging.getLogger(__name__)

PHOTO_URL_TTL_SECONDS = 300
HistoryStatus = Literal["pending", "approved", "rejected", "cancelled"]
RejectReason = Literal["unreadable", "not_certificate", "unverifiable", "school_unsupported"]


class ApproveBody(BaseModel):
    university_id: UUID
    # 관리자가 발급 기관 사이트에서 확인한 번호(D9: 승인 때 필수). 정규화 뒤 영숫자 4~40자가 아니면 422.
    document_number: str = Field(min_length=4, max_length=40)
    # 서류에 학번이 찍혀 있을 때만(D5). 있으면 해시가 재가입 제한 · 중복 방지에 쓰인다.
    student_number: str | None = Field(default=None, min_length=1, max_length=20)


class RejectBody(BaseModel):
    reason: RejectReason


def _repo(caller: AdminCaller) -> GraduateAdminRepository:
    return GraduateAdminRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _request_repo(caller: AdminCaller) -> GraduateRequestRepository:
    return GraduateRequestRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _storage(caller: AdminCaller) -> GraduateCertStorage:
    return GraduateCertStorage(caller.settings.storage_url, caller.settings.supabase_service_role_key, caller.client)


def _attempt_no(row: dict) -> int:
    """이 신청이 그 사람의 몇 번째 신청인가(오래된 순, 1부터)."""
    mine = (row.get("profile") or {}).get("all_requests") or []
    return 1 + sum(1 for other in mine if other["created_at"] < row["created_at"])


def _summary(row: dict) -> dict:
    # 닉네임 · 학교 이름은 결정된 줄에도 보인다. 탈퇴한 계정이면 둘 다 null 이다.
    person = row.get("profile") or {}
    shown = person.get("status") != "withdrawn"
    return {
        "id": row["id"], "status": row["status"], "reason": row["reason"], "created_at": row["created_at"],
        "decided_at": row["decided_at"], "attempt_no": _attempt_no(row), "profile_id": row["profile_id"],
        "nickname": person.get("nickname") if shown else None,
        "university_name": (person.get("universities") or {}).get("name") if shown else None,
    }


async def _photo_url(caller: AdminCaller, row: dict) -> str | None:
    """대기 줄만 사진을 보여 준다. Storage 가 서명을 못 하면 None — 500 이 아니라 "사진 없음" 이다."""
    if row["status"] != "pending" or not row["photo_path"]:
        return None
    try:
        return await _storage(caller).create_signed_url(row["photo_path"], PHOTO_URL_TTL_SECONDS)
    # 200 인데 signedURL 이 없거나(KeyError) 본문이 JSON 이 아닌(ValueError) 답도 그 사진만 없는 것으로 본다.
    except (httpx.HTTPError, KeyError, ValueError):
        logger.warning("졸업생 인증 사진 서명 URL 실패 request=%s", row["id"])
        return None


async def _suggested_university_ids(caller: AdminCaller, row: dict) -> list[str]:
    """OCR 이 읽은 학교 글자와 이전 학교 메일의 도메인이 가리키는 학교(D16). 중복은 뺀다. 관리자는 최종 선택만 한다."""
    ids: list[str] = []
    universities = await _request_repo(caller).fetch_university_names()
    by_name = {u["name"]: u["id"] for u in universities}
    for name in read_certificate(row["ocr_school_text"] or "", list(by_name)).school_names:
        ids.append(by_name[name])
    previous = row["previous_school_email"]
    if previous and "@" in previous:
        policy = SignupPolicy(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
        by_domain = await policy.find_university_id(previous.rpartition("@")[2])
        if by_domain:
            ids.append(by_domain)
    return list(dict.fromkeys(ids))


async def _warnings(caller: AdminCaller, row: dict) -> list[dict]:
    """읽기 전용 중복 경고. 이전 학교 메일이 이미 다른 계정 것이거나 재가입 제한 중이면 알리고, 같은 문서 번호로 이미 승인된 다른 사람이
    있으면 알린다. 신청자에게는 어떤 모양으로도 알리지 않는다(관리자 화면에만)."""
    warnings: list[dict] = []
    previous = row["previous_school_email"]
    if previous:
        email_hmac = hash_email(caller.settings.identity_hmac_key, previous)
        owner = await _repo(caller).find_claim_owner(email_hmac)
        if owner is not None:
            warnings.append({"code": "school_email_in_use", "profile_id": owner["profile_id"],
                             "profile_status": (owner.get("profiles") or {}).get("status")})
        policy = SignupPolicy(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
        if await policy.is_blocked(email_hmac):
            warnings.append({"code": "school_email_rejoin_blocked"})
    if row["document_hmac"]:
        seen = await _repo(caller).find_approved_with_document(row["document_hmac"], row["profile_id"])
        if seen is not None:
            warnings.append({"code": "document_seen", "profile_id": seen})
    return warnings


async def _detail(caller: AdminCaller, row: dict) -> dict:
    pending = row["status"] == "pending"
    history = await _repo(caller).fetch_history(row["profile_id"], row["id"])
    return {
        **_summary(row),
        "photo_url": await _photo_url(caller, row),
        # 결정된 줄은 평문이 이미 없다 — 값 없는 칸을 보이지 않고 통째로 null.
        "ocr": None if not pending else {
            "state": row["ocr_state"], "document_number": row["ocr_document_number"],
            "school_text": row["ocr_school_text"], "suggested_university_ids": await _suggested_university_ids(caller, row),
        },
        "previous_school_email": row["previous_school_email"] if pending else None,
        "warnings": await _warnings(caller, row) if pending else [],
        "history": [{"status": h["status"], "reason": h["reason"], "decided_at": h["decided_at"]} for h in history],
    }


async def _one(caller: AdminCaller, request_id: UUID) -> dict:
    row = await _repo(caller).fetch_request(request_id)
    if row is None:
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    return await _detail(caller, row)


async def _decide(
    caller: AdminCaller, request: Request, request_id: UUID, status: str, *, reason: str | None = None,
    university_id: UUID | None = None, document_hmac: bytes | None = None, student_hmac: bytes | None = None,
    sender: FcmSender, now: datetime,
) -> dict:
    """줄 읽기 → DB 함수 → 사진 삭제 → 알림 → 결정된 줄 응답. 알림 · 사진 삭제는 DB 함수가 성공한 뒤에만 가고(409 · 404 · 422 는 위에서
    올라온다) 실패해도 응답을 뒤집지 않는다."""
    repo = _repo(caller)
    row = await repo.fetch_request(request_id)
    if row is None:
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    await repo.review(caller.admin_user_id, request_id, status, reason, university_id, document_hmac, student_hmac,
                      IDENTITY_KEY_VERSION, request_ip(request))
    await delete_photo(_request_repo(caller), _storage(caller), row["id"], row["photo_path"])
    await send_result_notice(caller, sender, now, row["profile_id"], result_notice(status, reason))
    return await _one(caller, request_id)


@router.get("")
async def list_graduate_requests(
    status: HistoryStatus = "pending",
    limit: int = Query(50, ge=1, le=100),
    caller: AdminCaller = Depends(get_admin_caller),
) -> dict:
    """PostgREST 한 번으로 끝난다 — 서명 · 중복 경고는 웹이 줄을 골라 한 건을 받을 때(GET /{id}). 사진 · 평문은 싣지 않는다."""
    return {"items": [_summary(row) for row in await _repo(caller).list_requests(status, limit)]}


@router.get("/{request_id}")
async def get_graduate_request(request_id: UUID, caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    return await _one(caller, request_id)


@router.post("/{request_id}/approve")
async def approve_graduate_request(
    request_id: UUID, body: ApproveBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
    sender: FcmSender = Depends(get_sender), now: datetime = Depends(get_now),
) -> dict:
    """서버가 번호 · 학번을 해시해 DB 함수에 넘긴다 — 평문은 이 요청 본문에만 있고 저장 · 로그에 남지 않는다.
    번호는 정규화 뒤 영숫자 4~40자, 학번은 1~20자가 아니면 DB 함수를 부르지 않고 422 다."""
    secret = caller.settings.identity_hmac_key
    if normalize_document_number(body.document_number) is None:
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    student_hmac = None
    if body.student_number is not None:
        if normalize_student_number(body.student_number) is None:
            raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
        student_hmac = hash_student_number(secret, str(body.university_id), body.student_number)
    return await _decide(
        caller, request, request_id, "approved", university_id=body.university_id,
        document_hmac=hash_document_number(secret, body.document_number), student_hmac=student_hmac,
        sender=sender, now=now)


@router.post("/{request_id}/reject")
async def reject_graduate_request(
    request_id: UUID, body: RejectBody, request: Request, caller: AdminCaller = Depends(get_admin_caller),
    sender: FcmSender = Depends(get_sender), now: datetime = Depends(get_now),
) -> dict:
    return await _decide(caller, request, request_id, "rejected", reason=body.reason, sender=sender, now=now)
