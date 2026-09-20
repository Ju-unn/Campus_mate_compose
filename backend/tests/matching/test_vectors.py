import json
from unittest.mock import AsyncMock

import httpx

from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors

PROFILE_ID = "11111111-1111-1111-1111-111111111111"


def _repo(handler) -> MatchingRepository:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return MatchingRepository("https://x.supabase.co/rest/v1", "service-key", client)


def _materials_handler(saved: list[dict], profile: dict | None = None):
    materials = {
        "major": "컴퓨터공학과", "major_field": None, "mbti": "ENFP",
        "animal_type": "dog", "impression_type": "kind", "bio": "등산 좋아해요.",
        "preferred_animal_types": ["cat"], "preferred_impression_types": ["chic"],
        "ideal_note": "말 잘 통하는 사람이요.",
        **(profile or {}),
    }

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/profiles" in url and request.method == "GET":
            return httpx.Response(200, json=[materials])
        if "/survey_answers" in url:
            return httpx.Response(200, json=[{"axis": 1, "value": 1.0}, {"axis": 2, "value": -0.5}])
        if "/profile_vectors" in url:
            saved.append(json.loads(request.content))
            return httpx.Response(201, json=[])
        return httpx.Response(200, json=[])

    return handler


async def test_refresh_vectors_saves_all_three_vectors():
    saved: list[dict] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.return_value = type("R", (), {"data": [
        type("D", (), {"embedding": [0.1] * 512})(), type("D", (), {"embedding": [0.2] * 512})(),
    ]})()

    await refresh_vectors(_repo(_materials_handler(saved)), openai_client, PROFILE_ID)

    assert len(saved) == 1
    assert len(saved[0]["self_survey"]) == 8
    assert saved[0]["shyness_score"] == -0.5
    assert len(saved[0]["self_embedding"]) == 512
    assert len(saved[0]["want_embedding"]) == 512


async def test_refresh_vectors_swallows_openai_failure():
    """임베딩이 죽어도 사용자의 저장은 이미 끝났다 — 여기서 예외를 올리면 200 이 500 이 된다."""
    saved: list[dict] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.side_effect = Exception("openai down")

    await refresh_vectors(_repo(_materials_handler(saved)), openai_client, PROFILE_ID)

    assert saved == []


async def test_refresh_vectors_skips_empty_sentence():
    """기본정보 단계에서는 "원해" 재료가 없다 — 빈 문장을 OpenAI 에 보내지도, 빈 칸을 저장하지도 않는다.

    빈 칸을 payload 에서 빼야 upsert 가 전에 저장한 want_embedding 을 지우지 않는다."""
    saved: list[dict] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.return_value = type("R", (), {"data": [
        type("D", (), {"embedding": [0.1] * 512})(),
    ]})()
    handler = _materials_handler(saved, {
        "preferred_animal_types": [], "preferred_impression_types": [], "ideal_note": None,
    })

    await refresh_vectors(_repo(handler), openai_client, PROFILE_ID)

    assert openai_client.embeddings.create.call_args.kwargs["input"] == [
        "나는 컴퓨터공학과 학생이다. MBTI는 ENFP다. 얼굴은 강아지상이고 선한 인상이다. 등산 좋아해요."
    ]
    assert len(saved[0]["self_embedding"]) == 512
    assert "want_embedding" not in saved[0]
