"""관리자 저장소(설계 10-18 §7 · §8 머리): 명단 확인과 작업 기록 한 줄. 기록이 실패하면 부른 요청도 실패해야 한다."""
from uuid import UUID

import httpx
import pytest
from fastapi import HTTPException

from admin_world import ADMIN, STRANGER, AdminWorld, settings
from app.admin.repository import AdminRepository


@pytest.fixture
def repo(world: AdminWorld) -> AdminRepository:
    s = settings()
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    return AdminRepository(s.postgrest_url, s.supabase_service_role_key, http)


async def test_is_admin_is_true_only_for_someone_on_the_list(repo):
    assert await repo.is_admin(UUID(ADMIN)) is True
    assert await repo.is_admin(UUID(STRANGER)) is False


async def test_record_action_sends_one_row_with_every_field(repo, world):
    await repo.record_action(
        UUID(ADMIN), "heart_task_approve",
        target_type="heart_task_submission", target_id="sub-1",
        before={"status": "submitted"}, after={"status": "approved"},
        reason="캡처 확인", ip="203.0.113.7",
    )

    (request,) = world.calls("POST", "/rest/v1/admin_actions")
    assert world.actions == [{
        "admin_user_id": ADMIN, "action": "heart_task_approve",
        "target_type": "heart_task_submission", "target_id": "sub-1",
        "before": {"status": "submitted"}, "after": {"status": "approved"},
        "reason": "캡처 확인", "ip": "203.0.113.7",
    }]
    # service_role 키로만 쓴다(표는 RLS 정책 0개 · service_role 에 select · insert 만).
    assert request.headers["apikey"] == "service-key"
    assert request.headers["Authorization"] == "Bearer service-key"


async def test_record_action_leaves_unknown_fields_null(repo, world):
    await repo.record_action(UUID(ADMIN), "private_view")

    assert world.actions == [{
        "admin_user_id": ADMIN, "action": "private_view", "target_type": None, "target_id": None,
        "before": None, "after": None, "reason": None, "ip": None,
    }]


async def test_a_record_the_db_refuses_fails_the_caller(repo, world):
    # 동작 이름 형식 · 사유 길이 check 위반(23514) — 기록 없는 조치를 막으려면 부른 쪽까지 실패가 올라가야 한다.
    world.action_insert_status, world.action_insert_code = 400, "23514"

    with pytest.raises(HTTPException) as caught:
        await repo.record_action(UUID(ADMIN), "Bad-Action")

    assert caught.value.status_code == 422


async def test_a_record_that_cannot_be_written_fails_the_caller(repo, world):
    world.action_insert_status = 503

    with pytest.raises(httpx.HTTPStatusError):
        await repo.record_action(UUID(ADMIN), "heart_task_approve")
