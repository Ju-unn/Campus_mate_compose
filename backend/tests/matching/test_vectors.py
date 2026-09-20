import json
from unittest.mock import AsyncMock

import httpx

from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors

PROFILE_ID = "11111111-1111-1111-1111-111111111111"


def _repo(handler) -> MatchingRepository:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return MatchingRepository("https://x.supabase.co/rest/v1", "service-key", client)


def _materials_handler(saved: list[dict]):
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/profiles" in url and request.method == "GET":
            return httpx.Response(200, json=[{
                "major": "컴퓨터공학과", "major_field": None, "mbti": "ENFP",
                "animal_type": "dog", "impression_type": "kind", "bio": "등산 좋아해요.",
                "preferred_animal_types": ["cat"], "preferred_impression_types": ["chic"],
                "ideal_note": "말 잘 통하는 사람이요.",
            }])
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
