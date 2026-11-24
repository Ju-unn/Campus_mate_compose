import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.cards.push import FcmSender
from app.cards.repository import CardRepository
from app.cards.router import get_sender
from app.community import comment_push
from app.community.comment_push import notify_post_author
from app.community.notice_image import notice_image_url
from app.community.repository import (
    COMMENT_PAGE_SIZE, NOTICE_PAGE_SIZE, POLL_PAGE_SIZE, Category, CommunityRepository, FeedTab, PollTab)
from app.core import errors
from app.core.cursor import check_cursor
from app.core.deps import Caller, get_now, get_verified_caller
from app.core.text import SafeLine, body_text, visible

logger = logging.getLogger(__name__)

router = APIRouter()

# 응답에 싣는 칸. DB 함수가 author_id 를 주지 않지만 칸이 늘어도 새지 않게 여기서 한 번 더 고른다(익명).
_POLL_KEYS = ("id", "question", "option_a_label", "option_b_label", "created_at",
              "a_count", "b_count", "my_choice", "is_mine", "comment_count")
# 댓글 한 줄. 작성자 id 는 어디에도 없고, 누구인지는 alias_no(익명N) · is_post_author(글쓴이) · is_mine 으로만 알린다.
# add_poll_comment 가 푸시용으로 함께 주는 poll_author_id · poll_question 도 여기서 걸러져 앱 응답에 나가지 않는다.
_COMMENT_KEYS = ("id", "body", "created_at", "alias_no", "is_post_author", "is_mine", "can_delete")


# 새 길(/community/feed · /items) 한 줄. 투표 칸은 poll 안에 묶고 게시물이면 poll 이 null 이다. 작성자 칸은 없다(익명).
_ITEM_KEYS = ("id", "kind", "category", "text", "created_at", "is_mine", "comment_count")
_ITEM_POLL_KEYS = ("option_a_label", "option_b_label", "a_count", "b_count", "my_choice")


def _pick(row: dict, keys: tuple[str, ...]) -> dict:
    """DB 줄에서 내보낼 칸만 고른다 — 옛 투표 카드 · 새 글 줄 · 댓글이 같이 쓴다. 고르지 않은 칸(author_id 등)은 나가지 않는다."""
    return {key: row[key] for key in keys}


def _card(row: dict) -> dict:
    return _pick(row, _POLL_KEYS)


def _item(row: dict) -> dict:
    return {**_pick(row, _ITEM_KEYS), "poll": _pick(row, _ITEM_POLL_KEYS) if row["kind"] == "poll" else None}


# 공지(할 일 21) 한 줄. 작성자 칸은 없다 — 앱은 "CampusMate 운영자" 로 그린다. 그림은 우리 버킷 주소로만 만든다.
_NOTICE_KEYS = ("id", "title", "text", "created_at", "comment_count")
# NEW 배지: 서버 시계로 7일 안(사용자 「7일이내 new 배지」).
NOTICE_NEW_WINDOW = timedelta(days=7)


def _notice(row: dict, supabase_url: str, now: datetime) -> dict:
    return {**_pick(row, _NOTICE_KEYS), "image_url": notice_image_url(supabase_url, row["image_path"]),
            "is_new": now - datetime.fromisoformat(row["created_at"]) < NOTICE_NEW_WINDOW}


def _notice_item(row: dict, supabase_url: str) -> dict:
    """상세(/community/items/{id})의 공지 — 투표 · 게시물과 같은 칸 + title · image_url. 카테고리를 쓰지 않는다."""
    return {"id": row["id"], "kind": "notice", "category": None, "text": row["text"], "created_at": row["created_at"],
            "is_mine": False, "comment_count": row["comment_count"], "poll": None,
            "title": row["title"], "image_url": notice_image_url(supabase_url, row["image_path"])}


def _comment(row: dict) -> dict:
    return _pick(row, _COMMENT_KEYS)


def _repo(caller: Caller) -> CommunityRepository:
    return CommunityRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)


@dataclass(frozen=True)
class _Wording:
    not_found: str
    push_title: str


# 옛 길(/community/polls…, 1.0.6)은 그때 문구 그대로, 새 길(/community/items…)은 투표 · 게시물을 함께 부르는 문구(사용자 확정 11-24).
# compat(1.0.6): 옛 길 문구 · 푸시 제목 — MIN_APP_VERSION 1.0.7 뒤 삭제
_OLD_WORDING = _Wording(errors.POLL_NOT_FOUND, comment_push.TITLE)
_NEW_WORDING = _Wording(errors.COMMUNITY_ITEM_NOT_FOUND, comment_push.ITEM_TITLE)


def _wording(request: Request) -> _Wording:
    """한 처리 함수에 옛 길 · 새 길을 같이 붙였을 때 어느 길로 왔는지 경로 틀(route.path)로 가른다."""
    # compat(1.0.6): 옛 길(/community/polls…) 분기 — MIN_APP_VERSION 1.0.7 뒤 삭제(_NEW_WORDING 만 남긴다)
    return _OLD_WORDING if request.scope["route"].path.startswith("/community/polls") else _NEW_WORDING


def _check_feed_cursor(before: datetime | None, before_id: UUID | None, tab: str) -> None:
    check_cursor(before, before_id)
    if tab == "popular" and before is not None:
        # 시각 커서로 참여 수 순서를 자르면 엉뚱한 글이 섞인다.
        raise HTTPException(status_code=422, detail=errors.INVALID_INPUT)


# compat(1.0.6): 옛 피드(투표만, 옛 모양) — MIN_APP_VERSION 1.0.7 뒤 삭제(새 앱은 /community/feed)
@router.get("/community/polls")
async def list_polls(before: datetime | None = None, before_id: UUID | None = None, tab: PollTab = "all",
                     caller: Caller = Depends(get_verified_caller)) -> dict:
    """15d 피드(1.0.6). 투표만 — poll_feed 가 게시물을 거른다. 최신 글부터 20개, 전체 학교(사용자 결정 1). 더 내리면 화면 맨 아래 글의
    `created_at` · `id` 를 그대로 보낸다 — 채팅 메시지와 같은 커서다.
    `tab` 은 전체 · 인기 · 내 질문 · 내 투표. 인기는 참여 수 순 한 쪽뿐이라 커서가 없고 "더 없음" 으로 답한다."""
    _check_feed_cursor(before, before_id, tab)
    rows = await _repo(caller).fetch_polls(caller.profile_id, before=before, before_id=before_id, tab=tab)
    has_more = tab != "popular" and len(rows) == POLL_PAGE_SIZE
    return {"polls": [_card(row) for row in rows], "has_more": has_more}


@router.get("/community/feed")
async def list_items(before: datetime | None = None, before_id: UUID | None = None, tab: FeedTab = "all",
                     caller: Caller = Depends(get_verified_caller)) -> dict:
    """투표 + 게시물 피드(할 일 19). 커서 · 인기 규칙은 옛 피드와 같고, 탭에 카테고리 셋(free · career · love)이 더 있다."""
    _check_feed_cursor(before, before_id, tab)
    rows = await _repo(caller).fetch_items(caller.profile_id, before=before, before_id=before_id, tab=tab)
    has_more = tab != "popular" and len(rows) == POLL_PAGE_SIZE
    return {"items": [_item(row) for row in rows], "has_more": has_more}


@router.get("/community/notices")
async def list_notices(before: datetime | None = None, before_id: UUID | None = None,
                       caller: Caller = Depends(get_verified_caller), now: datetime = Depends(get_now)) -> dict:
    """공지 목록(할 일 21) — 가리지 않은 공지 최신순 20개. 더 내리면 맨 아래 공지의 `created_at` · `id` 를 그대로 보낸다.
    피드 맨 위 띠는 첫 줄(가장 최근 공지)과 그 is_new 를 쓴다."""
    check_cursor(before, before_id)
    rows = await _repo(caller).fetch_notices(caller.profile_id, before=before, before_id=before_id)
    return {"items": [_notice(row, caller.settings.supabase_url, now) for row in rows],
            "has_more": len(rows) == NOTICE_PAGE_SIZE}


@router.get("/community/items/{item_id}")
async def get_item(item_id: UUID, caller: Caller = Depends(get_verified_caller)) -> dict:
    """투표 · 게시물 · 공지 상세. 가려진 글 · 떠난 사람의 글은 피드처럼 없다.
    투표 · 게시물이면 title · image_url 이 null 이다. 공지는 피드(community_feed)에 없어 공지 목록 함수로 따로 읽는다."""
    repo = _repo(caller)
    rows = await repo.fetch_items(caller.profile_id, item_id=item_id, limit=1)
    if rows:
        return {"item": {**_item(rows[0]), "title": None, "image_url": None}}
    if await repo.fetch_kind(item_id) != "notice":
        raise HTTPException(status_code=404, detail=errors.COMMUNITY_ITEM_NOT_FOUND)
    notices = await repo.fetch_notices(caller.profile_id, notice_id=item_id, limit=1)
    if not notices:
        raise HTTPException(status_code=404, detail=errors.COMMUNITY_NOTICE_NOT_FOUND)
    return {"item": _notice_item(notices[0], caller.settings.supabase_url)}


# compat(1.0.6): 옛 상세(투표만, 옛 모양) — MIN_APP_VERSION 1.0.7 뒤 삭제(새 앱은 /community/items/{id})
@router.get("/community/polls/{poll_id}")
async def get_poll(poll_id: UUID, caller: Caller = Depends(get_verified_caller)) -> dict:
    """17c 상세. 가려진 글 · 떠난 사람의 글은 피드처럼 없다."""
    rows = await _repo(caller).fetch_polls(caller.profile_id, poll_id=poll_id, limit=1)
    if not rows:
        raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
    return {"poll": _card(rows[0])}


# 앱 pollQuestionMaxLength · pollOptionMaxLength, DB polls_* check 와 같은 값이다.
QUESTION_MAX_LENGTH = 80
OPTION_MAX_LENGTH = 6


class PollRequest(BaseModel):
    # 운영자 글 칸(kind · title · image …)을 넣어 보내면 422 — 공지는 관리자 길만 만든다(보안 기준 21-2).
    # 1.0.6 은 question · option_a_label · option_b_label 셋만 보내 막히지 않는다(tests/community/test_community_notices.py).
    model_config = ConfigDict(extra="forbid")
    # 질문은 여러 줄 칸이다 — 지금 앱(17b)의 질문 상자가 줄바꿈을 받는다. 게시물 본문 · 댓글과 같은 본문 검사를 길이만 달리해 쓴다.
    # 선택지는 앱이 줄바꿈을 막는 한 줄 칸이다(core/text.py).
    question: body_text(QUESTION_MAX_LENGTH)
    option_a_label: SafeLine = Field(default="찬성", min_length=1, max_length=OPTION_MAX_LENGTH)
    option_b_label: SafeLine = Field(default="반대", min_length=1, max_length=OPTION_MAX_LENGTH)
    # 할 일 19 에 더한 선택 칸. 1.0.6 은 이 칸을 모른다 — 없으면 자유(free), 세 값 밖이면 422.
    # compat(1.0.6): category 없으면 free — MIN_APP_VERSION 1.0.7 뒤 삭제(기본값을 빼 필수 칸으로)
    category: Category = "free"

    @field_validator("option_a_label", "option_b_label")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not visible(stripped):  # 0폭 문자만이어도 빈칸이다
            raise ValueError("빈칸뿐인 값은 올릴 수 없다")
        return stripped

    @model_validator(mode="after")
    def _options_differ(self) -> "PollRequest":
        if self.option_a_label == self.option_b_label:
            raise ValueError("두 선택지가 같다")
        return self


class VoteRequest(BaseModel):
    choice: Literal["a", "b"]


@router.post("/community/polls", status_code=201)
async def create_poll(body: PollRequest, caller: Caller = Depends(get_verified_caller)) -> dict:
    """17b. 한국 시간 하루 10개(사용자 결정 3, 게시물과 합산) — 넘으면 429."""
    poll_id = await _repo(caller).create_item(
        caller.profile_id, kind="poll", category=body.category, text=body.question,
        option_a=body.option_a_label, option_b=body.option_b_label, limit_detail=errors.POLL_DAILY_LIMIT)
    return {"id": poll_id}


# DB polls_question_length check(게시물 1~500)와 같은 값이다.
POST_MAX_LENGTH = 500


class PostRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")  # PollRequest 와 같은 이유(보안 기준 21-2)
    category: Category
    body: body_text(POST_MAX_LENGTH)


@router.post("/community/posts", status_code=201)
async def create_post(body: PostRequest, caller: Caller = Depends(get_verified_caller)) -> dict:
    """게시물 올리기(글만 · 익명 · 제목 없음). 하루 10개는 투표와 합산 — 넘으면 429."""
    post_id = await _repo(caller).create_item(
        caller.profile_id, kind="post", category=body.category, text=body.body,
        limit_detail=errors.COMMUNITY_DAILY_LIMIT)
    return {"id": post_id}


@router.post("/community/polls/{poll_id}/votes")
async def vote(poll_id: UUID, body: VoteRequest, caller: Caller = Depends(get_verified_caller)) -> dict:
    """투표는 되돌릴 수 없다. 하루 첫 투표면 5하트(주 15 상한) — `rewarded` 로 알려 앱이 토스트를 띄운다."""
    repo = _repo(caller)
    rewarded = await repo.cast_vote(poll_id, caller.profile_id, body.choice)
    rows = await repo.fetch_polls(caller.profile_id, poll_id=poll_id, limit=1)
    if not rows:
        # 투표와 다시 읽기 사이에 글이 지워졌다. 투표도 cascade 로 사라졌으니 없는 글과 같게 답한다.
        raise HTTPException(status_code=404, detail=errors.POLL_NOT_FOUND)
    return {"poll": _card(rows[0]), "rewarded": rewarded}


# compat(1.0.6): 옛 길 DELETE /community/polls/{id} 데코레이터 — MIN_APP_VERSION 1.0.7 뒤 삭제
@router.delete("/community/polls/{poll_id}", status_code=204)
@router.delete("/community/items/{poll_id}", status_code=204)
async def delete_poll(poll_id: UUID, caller: Caller = Depends(get_verified_caller),
                      wording: _Wording = Depends(_wording)) -> Response:
    if not await _repo(caller).delete_poll(poll_id, caller.profile_id):
        # 남의 글이어도 "없음" 과 똑같이 답한다 — 403 으로 가르면 그 id 가 남의 글이라는 게 샌다.
        raise HTTPException(status_code=404, detail=wording.not_found)
    return Response(status_code=204)


# DB poll_comments_body_length check 와 같은 값이다. 앱 commentMaxLength 도 같다.
COMMENT_MAX_LENGTH = 200


class CommentRequest(BaseModel):
    # 여러 줄 칸(앱 입력 바 4줄). 0폭 문자만이면 빈 댓글이다.
    body: body_text(COMMENT_MAX_LENGTH)


# compat(1.0.6): 옛 길 GET /community/polls/{id}/comments 데코레이터 — MIN_APP_VERSION 1.0.7 뒤 삭제
@router.get("/community/polls/{poll_id}/comments")
@router.get("/community/items/{poll_id}/comments")
async def list_comments(poll_id: UUID, after: datetime | None = None, after_id: UUID | None = None,
                        caller: Caller = Depends(get_verified_caller), wording: _Wording = Depends(_wording)) -> dict:
    """17c 상세의 댓글. 오래된 순 10개. 더 보려면 마지막 댓글의 `created_at` · `id` 를 `after` · `after_id` 로 그대로 보낸다.
    가려진 글 · 떠난 사람의 글은 404 다."""
    check_cursor(after, after_id)
    # 한 줄 더 받아 다음 쪽이 있는지 정확히 안다 — 딱 10개로 끝나는 글에서 빈 쪽을 한 번 더 부르지 않는다.
    rows = await _repo(caller).fetch_comments(caller.profile_id, poll_id, after=after, after_id=after_id,
                                              limit=COMMENT_PAGE_SIZE + 1, not_found=wording.not_found)
    return {"items": [_comment(row) for row in rows[:COMMENT_PAGE_SIZE]], "has_more": len(rows) > COMMENT_PAGE_SIZE}


# compat(1.0.6): 옛 길 POST /community/polls/{id}/comments 데코레이터 — MIN_APP_VERSION 1.0.7 뒤 삭제
@router.post("/community/polls/{poll_id}/comments", status_code=201)
@router.post("/community/items/{poll_id}/comments", status_code=201)
async def add_comment(poll_id: UUID, body: CommentRequest, caller: Caller = Depends(get_verified_caller),
                      sender: FcmSender = Depends(get_sender), now: datetime = Depends(get_now),
                      wording: _Wording = Depends(_wording)) -> dict:
    """댓글 쓰기. 한국 시간 하루 50개 — 넘으면 429. 처음 쓰는 사람은 이 글 안의 익명 번호를 받는다.
    글쓴이에게 푸시가 가지만(본인 댓글 · 10분 안 같은 글 · 스위치 꺼짐은 제외) 푸시가 실패해도 댓글은 201 이다.
    푸시 제목은 길로 가른다 — 새 길은 투표 · 게시물 모두 "내 글", 옛 길은 "내 질문"."""
    repo = _repo(caller)
    row = await repo.add_comment(caller.profile_id, poll_id, body.body, not_found=wording.not_found)
    try:
        cards = CardRepository(caller.settings.postgrest_url, caller.settings.supabase_service_role_key, caller.client)
        await notify_post_author(repo, cards, sender, poll_id=poll_id, poll_author_id=row["poll_author_id"],
                                 question=row["poll_question"], commenter_id=caller.profile_id, now=now,
                                 title=wording.push_title)
    except Exception:
        # 댓글은 이미 저장됐다 — 알림 한 건 때문에 201 을 놓치면 앱이 다시 보내 같은 댓글이 두 줄이 된다.
        logger.exception("댓글 푸시 실패 poll=%s comment=%s", poll_id, row["id"])
    return _comment(row)


@router.delete("/community/comments/{comment_id}", status_code=204)
async def delete_comment(comment_id: UUID, caller: Caller = Depends(get_verified_caller)) -> Response:
    """내 댓글, 또는 내 글에 달린 댓글을 지운다(행 삭제)."""
    if not await _repo(caller).delete_comment(caller.profile_id, comment_id):
        # 남의 댓글이어도 "없음" 과 똑같이 답한다 — 403 으로 가르면 그 id 가 남의 댓글이라는 게 샌다.
        raise HTTPException(status_code=404, detail=errors.POLL_COMMENT_NOT_FOUND)
    return Response(status_code=204)
