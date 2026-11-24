"""내 글에 댓글이 달리면 글쓴이에게 푸시 한 건(사용자 결정 2026-11-10 「보냄 + 알림 설정에 끄기 칸」).

문구에는 댓글 본문도 작성자 정보도 넣지 않는다(익명) — 질문 앞부분만. 갈 곳은 data.route="poll" + poll_id.
스위치(notification_settings.poll_comment)·정지 · 탈퇴 · 조용한 시간은 push.notify 가 본다. 여기서는 notify 앞의 두 가지만 가른다:
본인 댓글, 같은 글 10분 묶음.
"""
from datetime import datetime, timedelta

from app.cards.push import notify
from app.community.repository import CommunityRepository

# 같은 글에 같은 글쓴이에게는 10분에 한 번만(사용자 요청). 기준은 알림함(notifications)의 마지막 poll_comment 줄이다 —
# 새 표 · 칸 없이 알림함이 이미 "무엇을 언제 알렸나" 를 남기고, 스위치를 껐거나 밤이어도(푸시는 안 가도) 줄은 남기 때문이다.
# shortcut: 읽고 쓰는 사이 틈에 동시에 온 두 댓글은 둘 다 통과한다(푸시가 한 번 더 간다), 한 글에 초당 여러 댓글이 달리면 DB 잠금으로 올린다.
COALESCE_WINDOW = timedelta(minutes=10)
# compat(1.0.6): 옛 길 댓글 푸시 제목 — MIN_APP_VERSION 1.0.7 뒤 삭제(ITEM_TITLE 만 남긴다)
TITLE = "내 질문에 새 댓글이 달렸어요"
# 새 길(/community/items/{id}/comments)로 단 댓글 — 투표 · 게시물 공통(사용자 확정 2026-11-24, 할 일 19).
# 옛 길(/community/polls/{id}/comments, 1.0.6)은 위 TITLE 그대로. 어느 길인지는 부르는 쪽(router)이 title 로 넘긴다.
ITEM_TITLE = "내 글에 새 댓글이 달렸어요"
QUESTION_PREVIEW_CHARS = 20


def _preview(question: str) -> str:
    return question if len(question) <= QUESTION_PREVIEW_CHARS else question[:QUESTION_PREVIEW_CHARS] + "…"


async def notify_post_author(community: CommunityRepository, cards, sender, *, poll_id, poll_author_id,
                             question: str, commenter_id, now: datetime, title: str = TITLE) -> None:
    """부르는 쪽(router)이 예외를 삼킨다 — 댓글은 이미 저장됐다."""
    if str(poll_author_id) == str(commenter_id):
        return
    if await community.has_notification_since(poll_author_id, poll_id, now - COALESCE_WINDOW):
        return
    await notify(cards, sender, poll_author_id, "poll_comment", title, _preview(question),
                 {"route": "poll", "poll_id": str(poll_id)}, now=now)
