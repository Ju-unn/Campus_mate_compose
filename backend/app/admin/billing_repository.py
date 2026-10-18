"""관리자 결제 조회(설계 10-18 §8-5 · §8-4b)의 DB 호출. 전부 읽기만 한다 — 결제 쓰기는 기존 DB 함수 둘(grant_store_purchase ·
refund_store_purchase)뿐이다(backend/app/billing/repository.py)."""
from app.admin.repository import AdminRepository

# 토큰 해시는 일부러 고르지 않는다(화면에 필요 없다). 구매자는 닉네임까지만.
_ORDER_SELECT = ("id,store,product_id,store_order_id,status,is_test,heart_amount,bonus_hearts,clawed_back_hearts,"
                 "price_krw,purchased_at,granted_at,refunded_at,profiles(id,nickname)")


class AdminBillingRepository(AdminRepository):

    async def find_orders(self, order: str, limit: int) -> list[dict]:
        """구글 주문 번호 · 애플 거래 번호가 정확히 일치하는 구매(같은 칸 store_order_id, 인덱스 purchases_store_order_id_index). 최근 순."""
        return await self._rows("purchases", {
            "select": _ORDER_SELECT, "store_order_id": f"eq.{order}", "order": "purchased_at.desc", "limit": str(limit),
        })

    async def billing_daily(self, days: int) -> list[dict]:
        """한국 시간 하루 단위 [{day, revenue_krw, order_count, refunded_krw}] 오래된 순, 정확히 days 줄(DB 함수 admin_billing_daily)."""
        return await self._rpc("admin_billing_daily", {"p_days": days})

    async def billing_shortfall(self, limit: int) -> list[dict]:
        """환불됐는데 하트를 다 못 거둔 실제 구매, 최근 환불 순(DB 함수 admin_billing_shortfall)."""
        return await self._rpc("admin_billing_shortfall", {"p_limit": limit})
