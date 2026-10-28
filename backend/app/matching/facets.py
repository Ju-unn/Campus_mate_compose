"""글 정리(10-28 0번 — 사용자 결정): 자기소개 · "이런 사람이 좋아요" 원문을 GPT 가 정해진 칸으로 나눠 저장하고,
점수는 칸끼리 맞는지로 낸다. 임베딩은 "카페 좋아요" ↔ "카페 없으면 좋겠어요" 를 0.91 로 같게 봐서(부정을 못 가림)
글 점수 50% 중 5% 를 이 정리에 준다. 칸은 설문 · 태그 · MBTI · 얼굴에 없는 것만 골랐다 — 같은 정보를 두 번 세지 않으려고.
실험 · 근거는 바탕화면 매칭_유사도/재검증_10-28(exp_extract.py · 실험7 시트)."""

import json
import logging
import statistics

import httpx
from openai import AsyncOpenAI

_logger = logging.getLogger(__name__)

PLACES = ["카페", "맛집", "야외", "운동", "전시공연", "집"]
TALK = ["깊은대화", "가벼운수다", "유머"]
VALUES = ["배려", "존중", "성장", "즐거움"]

_PROMPT = f"""너는 소개팅 앱 글을 읽고 정해진 칸에 정리하는 도우미야. 글에 **분명히 적힌 것만** 골라. 짐작하거나 지어내지 마.
반대로 말한 것(싫다, 없으면 좋겠다, 부담스럽다, 안 한다)은 반드시 dislike 에 넣어.
JSON 하나만 출력해:
{{"like_places": [], "dislike_places": [], "talk": null, "values": []}}
- like_places / dislike_places: {PLACES} 중에서. 데이트나 함께하는 활동으로 좋다/싫다고 한 곳.
- talk: {TALK} 중 하나 또는 null. 대화 스타일이 적혀 있을 때만.
- values: {VALUES} 중 여러 개. 배려=상대를 챙김 · 다정함, 존중=각자 시간 · 서두르지 않음, 성장=목표 · 서로 응원, 즐거움=재미 · 웃음 · 활발함."""

# 임베딩과 같은 이유로 짧게 끊는다(embeddings.EMBEDDING_TIMEOUT) — 사용자 저장 요청이 이 호출을 기다린다.
_TIMEOUT = httpx.Timeout(15.0, connect=5.0)


async def extract_facets(openai_client: AsyncOpenAI, text: str) -> dict | None:
    """글 하나를 칸으로 정리한다. 실패하거나 답을 못 읽으면 None — 점수에서는 "모름"(중립)이다."""
    try:
        response = await openai_client.chat.completions.create(
            model="gpt-4o-mini", temperature=0, response_format={"type": "json_object"},
            messages=[{"role": "system", "content": _PROMPT}, {"role": "user", "content": text}],
            timeout=_TIMEOUT,
        )
        answer = json.loads(response.choices[0].message.content or "")
        if not isinstance(answer, dict):
            raise ValueError("정리 답이 객체가 아니다")
    except Exception:  # noqa: BLE001 — 정리 실패가 임베딩 저장을 깨지 않게 한다
        _logger.exception("글 정리 실패")
        return None
    # 목록 밖의 말은 버린다 — GPT 가 칸 이름을 지어내도 점수에 들어오지 않게.
    return {
        "like_places": [p for p in answer.get("like_places") or [] if p in PLACES],
        "dislike_places": [p for p in answer.get("dislike_places") or [] if p in PLACES],
        "talk": answer.get("talk") if answer.get("talk") in TALK else None,
        "values": [v for v in answer.get("values") or [] if v in VALUES],
    }


def facet_fit(want: dict | None, me: dict | None) -> float:
    """원함(want) 칸이 상대(me) 칸과 얼마나 맞나 0~1. 원함이 비었거나 어느 쪽이든 정리가 없으면 0.5(중립 — 순위를 가르지 않음).
    장소: 원한 곳 중 상대가 좋아한 비율(원한 곳이 없으면 1) − 0.5 × 부딪힘(내가 원한 곳을 상대가 싫어함 · 내가 싫은 곳을 상대가 좋아함).
    대화: 같으면 1, 상대가 안 적었으면 0.5, 다르면 0. 가치: 원한 것 중 상대에게 있는 비율. 적힌 칸끼리 평균."""
    if want is None or me is None:
        return 0.5
    parts = []
    if want["like_places"] or want["dislike_places"]:
        hit = len(set(want["like_places"]) & set(me["like_places"]))
        clash = (len(set(want["like_places"]) & set(me["dislike_places"]))
                 + len(set(want["dislike_places"]) & set(me["like_places"])))
        # "싫어함"만 적었으면 맞춰야 할 "좋아함"이 없으니 1 에서 시작하고 부딪힘만 뺀다.
        liked = hit / len(want["like_places"]) if want["like_places"] else 1.0
        parts.append(max(0.0, liked - 0.5 * clash))
    if want["talk"]:
        parts.append(1.0 if me["talk"] == want["talk"] else 0.5 if me["talk"] is None else 0.0)
    if want["values"]:
        parts.append(len(set(want["values"]) & set(me["values"])) / len(want["values"]))
    return statistics.mean(parts) if parts else 0.5
