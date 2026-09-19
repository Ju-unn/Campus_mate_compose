import httpx


class DiscordNotifier:
    def __init__(self, webhook_url: str, client: httpx.AsyncClient):
        self._webhook_url = webhook_url
        self._client = client

    async def notify_pending_review(self) -> None:
        # 사진·실명·학교명은 보내지 않는다(설계 §7.3, 2026-09-19 결정) — 담당자가 대시보드에서 직접 연다.
        response = await self._client.post(self._webhook_url, json={"content": "학생증 재검토가 1건 있어요. Supabase 대시보드에서 확인해 주세요."})
        response.raise_for_status()
