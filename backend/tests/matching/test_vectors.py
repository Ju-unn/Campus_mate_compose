import json
from unittest.mock import AsyncMock

import httpx
import pytest
from openai import APITimeoutError

from app.matching import vectors
from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors

PROFILE_ID = "11111111-1111-1111-1111-111111111111"


def _repo(handler) -> MatchingRepository:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return MatchingRepository("https://x.supabase.co/rest/v1", "service-key", client)


async def test_fetch_owner_reads_the_four_face_columns():
    """face_fit 은 내 얼굴 · 선호 4칸을 읽는다 — select 에서 빠지면 내 쪽 선호가 늘 "맞음"으로 읽힌다."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[{"id": PROFILE_ID}])

    await _repo(handler).fetch_owner(PROFILE_ID)

    columns = set(seen[0].url.params["select"].split(","))
    assert {"animal_type", "impression_type", "preferred_animal_types", "preferred_impression_types"} <= columns


async def test_fetch_owner_reads_my_text_facets_from_the_vector_row():
    """글 정리 칸은 profile_vectors 에 있다 — 한 번의 조회로 함께 읽어 profiles 칸처럼 펼친다(벡터 행이 없으면 None)."""
    seen: list[httpx.Request] = []
    facets = {"like_places": ["카페"], "dislike_places": [], "talk": None, "values": []}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[{"id": PROFILE_ID, "profile_vectors": {"self_facets": facets, "want_facets": None}}])

    owner = await _repo(handler).fetch_owner(PROFILE_ID)

    assert "profile_vectors(self_facets,want_facets)" in seen[0].url.params["select"]
    assert owner["self_facets"] == facets
    assert owner["want_facets"] is None
    assert "profile_vectors" not in owner


async def test_fetch_owner_without_a_vector_row_has_no_facets():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[{"id": PROFILE_ID, "profile_vectors": None}])

    owner = await _repo(handler).fetch_owner(PROFILE_ID)

    assert owner["self_facets"] is None and owner["want_facets"] is None


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


async def test_refresh_vectors_saves_the_text_facets_of_bio_and_ideal_note(monkeypatch):
    """글 정리는 사용자가 쓴 원문만 읽는다 — 템플릿(학과 · 얼굴상)은 이미 다른 점수가 본다(10-28 0번)."""
    saved: list[dict] = []
    read: list[str] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.return_value = type("R", (), {"data": [
        type("D", (), {"embedding": [0.1] * 512})(), type("D", (), {"embedding": [0.2] * 512})(),
    ]})()

    async def fake_extract(client, text):
        read.append(text)
        return {"like_places": [text[:2]], "dislike_places": [], "talk": None, "values": []}

    monkeypatch.setattr(vectors, "extract_facets", fake_extract)

    await refresh_vectors(_repo(_materials_handler(saved)), openai_client, PROFILE_ID)

    assert sorted(read) == ["등산 좋아해요.", "말 잘 통하는 사람이요."]
    assert saved[0]["self_facets"]["like_places"] == ["등산"]
    assert saved[0]["want_facets"]["like_places"] == ["말 "]
    assert len(saved[0]["self_embedding"]) == 512


async def test_refresh_vectors_keeps_the_embeddings_when_the_facets_fail(monkeypatch):
    """정리가 실패하면(None) 그 칸만 비운다 — 옛 글의 정리가 새 글 옆에 남지 않게 하고, 임베딩 저장은 그대로 한다."""
    saved: list[dict] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.return_value = type("R", (), {"data": [
        type("D", (), {"embedding": [0.1] * 512})(), type("D", (), {"embedding": [0.2] * 512})(),
    ]})()

    async def failing_extract(client, text):
        return None

    monkeypatch.setattr(vectors, "extract_facets", failing_extract)

    await refresh_vectors(_repo(_materials_handler(saved)), openai_client, PROFILE_ID)

    assert saved[0]["self_facets"] is None and saved[0]["want_facets"] is None
    assert len(saved[0]["want_embedding"]) == 512


async def test_refresh_vectors_skips_the_facets_when_both_texts_are_empty():
    """기본정보 단계처럼 자기소개 · "이런 사람이 좋아요"가 둘 다 비면 정리를 부르지 않고 칸도 덮어쓰지 않는다."""
    saved: list[dict] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.return_value = type("R", (), {"data": [
        type("D", (), {"embedding": [0.1] * 512})(),
    ]})()
    handler = _materials_handler(saved, {
        "bio": "  ", "ideal_note": None, "preferred_animal_types": [], "preferred_impression_types": [],
    })

    await refresh_vectors(_repo(handler), openai_client, PROFILE_ID)

    openai_client.chat.completions.create.assert_not_called()
    assert "self_facets" not in saved[0] and "want_facets" not in saved[0]
    assert len(saved[0]["self_embedding"]) == 512


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
        "나는 컴퓨터공학과 학생이다. 얼굴은 강아지상이고 선한 인상이다. 등산 좋아해요."
    ]
    assert len(saved[0]["self_embedding"]) == 512
    assert "want_embedding" not in saved[0]
    assert "want_facets" not in saved[0]  # 빈 글은 정리하지도 덮어쓰지도 않는다


@pytest.mark.parametrize("error", [TimeoutError("slow"), APITimeoutError(request=httpx.Request("POST", "https://api.openai.com/v1/embeddings"))])
async def test_refresh_vectors_swallows_an_openai_timeout(error):
    """OpenAI 가 시간 안에 못 답해도 예외를 올리지 않는다 — 사용자의 저장은 이미 끝났다."""
    saved: list[dict] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.side_effect = error

    await refresh_vectors(_repo(_materials_handler(saved)), openai_client, PROFILE_ID)

    assert saved == []
