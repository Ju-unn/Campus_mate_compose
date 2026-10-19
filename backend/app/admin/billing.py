"""관리자 결제 조회(설계 10-18 §8-5, 화면 A8). 읽기만 한다 — 하트를 주는 일은 사용자 상세의 하트 조정이다.

경로 이름은 e2e/area4_extra.py 의 하트 환급 · 구매 금지어에 걸리지 않게 지었다(orders · shortfall · summary · daily).
시험 결제(is_test)는 매출 · 그래프 · 못 거둔 하트에서 빠지고(DB 함수), 주문 번호로 직접 찾을 때만 보인다.
주문 번호는 GET 쿼리가 아니라 본문으로 받는다(요청 로그에 남지 않게 — 설계 §14-3 과 같은 이유).
"""
import re
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from app.admin.billing_repository import AdminBillingRepository
from app.admin.caller import AdminCaller, get_admin_caller
from app.core import errors
from app.core.time import SEOUL

router = APIRouter(prefix="/billing")

ORDER_RESULTS = 10
# 구글 주문 번호(GPA.1234-5678-9012-34567) · 애플 거래 번호(숫자). 글자를 좁혀 두면 PostgREST 필터 문법이 끼어들 틈이 없다.
_ORDER = re.compile(r"[A-Za-z0-9._-]{1,64}")


class OrderSearchBody(BaseModel):
    # 제약 없이 받고 핸들러가 직접 검사한다 — 기본 422 가 입력을 되돌리지 않게.
    order: str


def _repo(caller: AdminCaller) -> AdminBillingRepository:
    return AdminBillingRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


def _today() -> date:
    """한국 시간의 오늘(시험에서 덮는다)."""
    return datetime.now(SEOUL).date()


def _order(row: dict) -> dict:
    granted = row["heart_amount"] + row["bonus_hearts"]
    refunded_with_owner = row["status"] == "refunded" and row["profiles"] is not None
    return {
        "id": row["id"], "store": row["store"], "product_id": row["product_id"], "store_order_id": row["store_order_id"],
        "status": row["status"], "is_test": row["is_test"], "heart_amount": row["heart_amount"],
        "bonus_hearts": row["bonus_hearts"], "granted_hearts": granted, "clawed_back_hearts": row["clawed_back_hearts"],
        # 계정이 지워진 구매는 회수할 사람이 없어 모자람으로 세지 않는다(refund_store_purchase 와 같은 규칙).
        "shortfall_hearts": granted - (row["clawed_back_hearts"] or 0) if refunded_with_owner else 0,
        "price_krw": row["price_krw"], "purchased_at": row["purchased_at"], "granted_at": row["granted_at"],
        "refunded_at": row["refunded_at"],
        "profile": None if row["profiles"] is None else {"id": row["profiles"]["id"], "nickname": row["profiles"]["nickname"]},
    }


def _day(row: dict) -> dict:
    return {"date": row["day"], "revenue_krw": row["revenue_krw"], "order_count": row["order_count"],
            "refunded_krw": row["refunded_krw"]}


@router.post("/orders/search")
async def search_orders(body: OrderSearchBody, caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    order = body.order.strip()
    if not _ORDER.fullmatch(order):
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)
    return {"items": [_order(row) for row in await _repo(caller).find_orders(order, ORDER_RESULTS)]}


@router.get("/shortfall")
async def get_shortfall(limit: int = Query(100, ge=1, le=500), caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    return {"items": await _repo(caller).billing_shortfall(limit)}


@router.get("/daily")
async def get_daily(days: int = Query(30, ge=1, le=90), caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    return {"days": [_day(row) for row in await _repo(caller).billing_daily(days)]}


@router.get("/summary")
async def get_summary(caller: AdminCaller = Depends(get_admin_caller)) -> dict:
    """한국 시간 이번 달 1일부터 오늘까지의 합(= 오늘의 일수만큼 그래프 함수를 불러 더한다). 숫자만 — 문구는 화면 몫."""
    today = _today()
    rows = await _repo(caller).billing_daily(today.day)
    return {"month": f"{today:%Y-%m}", "revenue_krw": sum(r["revenue_krw"] for r in rows),
            "order_count": sum(r["order_count"] for r in rows), "refunded_krw": sum(r["refunded_krw"] for r in rows)}
