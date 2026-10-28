import json
from unittest.mock import AsyncMock

import pytest

from app.matching.facets import extract_facets, facet_fit

CAFE_LOVER = {"like_places": ["카페"], "dislike_places": [], "talk": None, "values": []}
CAFE_HATER = {"like_places": [], "dislike_places": ["카페"], "talk": None, "values": []}
NOTHING = {"like_places": [], "dislike_places": [], "talk": None, "values": []}


def _client(content: str | None) -> AsyncMock:
    client = AsyncMock()
    message = type("M", (), {"content": content})()
    client.chat.completions.create.return_value = type("R", (), {"choices": [type("C", (), {"message": message})()]})()
    return client


def test_facet_fit_is_one_when_the_wanted_place_is_liked():
    assert facet_fit(CAFE_LOVER, CAFE_LOVER) == 1.0


def test_facet_fit_is_zero_when_the_wanted_place_is_disliked():
    """임베딩은 "카페 좋아요" ↔ "카페 없으면 좋겠어요" 를 0.91 로 같게 본다 — 정리 칸은 반대로 읽는다(10-28 실험 6/6)."""
    assert facet_fit(CAFE_LOVER, CAFE_HATER) == 0.0


def test_facet_fit_only_disliking_a_place_is_full_marks_unless_the_partner_likes_it():
    """원함에 "싫어함"만 적었으면 맞춰야 할 "좋아함"이 없다 — 부딪히지 않는 상대는 1, 그곳을 좋아하는 상대만 깎는다."""
    assert facet_fit(CAFE_HATER, NOTHING) == 1.0
    assert facet_fit(CAFE_HATER, CAFE_HATER) == 1.0
    assert facet_fit(CAFE_HATER, CAFE_LOVER) == 0.5


def test_facet_fit_averages_places_talk_and_values():
    want = {"like_places": ["카페", "야외"], "dislike_places": [], "talk": "깊은대화", "values": ["배려", "존중"]}
    me = {"like_places": ["카페"], "dislike_places": [], "talk": None, "values": ["배려"]}

    # 장소 1/2 · 대화(상대가 안 적음) 0.5 · 가치 1/2
    assert facet_fit(want, me) == 0.5


def test_facet_fit_is_neutral_when_nothing_is_wanted_or_known():
    """원함이 비었거나 정리가 아직 없으면(실패 · 백필 전) 0.5 — 순위를 가르지 않는다."""
    assert facet_fit(NOTHING, CAFE_LOVER) == 0.5
    assert facet_fit(None, CAFE_LOVER) == 0.5
    assert facet_fit(CAFE_LOVER, None) == 0.5


async def test_extract_facets_keeps_only_the_allowed_choices():
    client = _client(json.dumps({"like_places": ["카페", "노래방"], "dislike_places": ["집"],
                                 "talk": "토론", "values": ["배려", "돈"]}))

    assert await extract_facets(client, "카페 좋아요. 집에만 있는 건 싫어요.") == {
        "like_places": ["카페"], "dislike_places": ["집"], "talk": None, "values": ["배려"],
    }
    kwargs = client.chat.completions.create.call_args.kwargs
    assert kwargs["model"] == "gpt-4o-mini"
    assert kwargs["temperature"] == 0
    assert kwargs["response_format"] == {"type": "json_object"}


@pytest.mark.parametrize("content", [None, "", "not json", "[1, 2]"])
async def test_extract_facets_gives_none_for_an_unreadable_answer(content):
    assert await extract_facets(_client(content), "카페 좋아요.") is None


async def test_extract_facets_gives_none_when_openai_fails():
    client = AsyncMock()
    client.chat.completions.create.side_effect = TimeoutError("slow")

    assert await extract_facets(client, "카페 좋아요.") is None
