from datetime import datetime

from app.core.postgrest import PostgrestRepository

PLAY_STORE, APP_STORE = "play_store", "app_store"


class BillingRepository(PostgrestRepository):
    """purchases 쓰기는 DB 함수 둘(grant_store_purchase · refund_store_purchase)만 한다. 여기서는 부르기만.
    이름 · 인자는 마이그레이션(20261013010100_billing_purchases.sql)과 글자까지 같다."""

    async def grant_store_purchase(self, profile_id, product_id: str, token_hash: str, order_id: str | None,
                                   purchased_at: datetime, *, is_test: bool, store: str = PLAY_STORE) -> dict:
        response = await self._post("rpc/grant_store_purchase", json={
            "p_profile_id": str(profile_id), "p_store": store, "p_product_id": product_id,
            "p_token_hash": token_hash, "p_order_id": order_id,
            "p_purchased_at": purchased_at.isoformat(), "p_is_test": is_test,
        })
        response.raise_for_status()
        return response.json()

    async def refund_store_purchase(self, token_hash: str, *, store: str = PLAY_STORE) -> dict:
        response = await self._post("rpc/refund_store_purchase", json={"p_store": store, "p_token_hash": token_hash})
        response.raise_for_status()
        return response.json()

    async def purge(self, older_than: datetime) -> int:
        """보관 기간(결정 I-2)이 지난 결제 기록과, 계정이 지워진 시험 결제(I-9)를 지운다. 지운 행 수."""
        response = await self._client.delete(
            f"{self._postgrest_url}/purchases",
            params={"or": f"(purchased_at.lt.{older_than.isoformat()},and(is_test.is.true,profile_id.is.null))",
                    "select": "id"},
            headers=self._with_prefer("return=representation"),
        )
        response.raise_for_status()
        return len(response.json())

    async def has_purchase_of_at_least(self, profile_id, min_hearts: int) -> bool:
        """첫 구매 보너스 자격을 잃었는가 — min_hearts 이상 상품을 산 적이 있다(환불된 것도 센다, status 로 거르지 않는다).
        DB 함수 grant_store_purchase 의 ② 와 같은 규칙: 마이그레이션 20261112000000_first_purchase_bonus_100_tier.sql."""
        response = await self._get("purchases", params={
            "profile_id": f"eq.{profile_id}", "heart_amount": f"gte.{min_hearts}", "select": "id", "limit": "1"})
        response.raise_for_status()
        return bool(response.json())
