import asyncio
import json
import logging
from unittest.mock import AsyncMock

import httpx
import pytest
from openai import APITimeoutError

from app.matching import vectors
from app.matching.repository import MatchingRepository
from app.matching.taste import PROMPT
from app.matching.vectors import refresh_vectors
from tests.matching.test_taste import FakeDictionary, fake_embedder

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


# --- 글 속 취향 단어(10-30) ---------------------------------------------------------------------

def _with_dictionary(saved: list[dict], dictionary: FakeDictionary, profile: dict | None = None):
    base = _materials_handler(saved, profile)

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/rest/v1/taste_words":
            return dictionary.handler(request)
        return base(request)

    return handler


_TASTE_COLUMNS = ("self_like_words", "self_dislike_words", "want_like_words", "want_dislike_words")


async def test_refresh_vectors_saves_the_four_taste_columns_with_the_embeddings(monkeypatch):
    """자기소개(bio) → self_*, "이런 사람이 좋아요"(ideal_note) → want_*. 단어는 사전 번호로 저장하고 임베딩 · 글 정리와 같은 한 번의 저장에 담는다."""
    saved: list[dict] = []
    read: list[str] = []
    dictionary = FakeDictionary({"등산": 1, "술": 2, "영화": 3})

    async def fake_split(client, text):
        read.append(text)
        return {"등산 좋아해요.": {"like": ["등산"], "dislike": ["술"]},
                "말 잘 통하는 사람이요.": {"like": ["영화", "여행"], "dislike": []}}[text]

    monkeypatch.setattr(vectors, "split_taste", fake_split)
    client = fake_embedder()

    await refresh_vectors(_repo(_with_dictionary(saved, dictionary)), client, PROFILE_ID)

    assert sorted(read) == ["등산 좋아해요.", "말 잘 통하는 사람이요."]
    assert len(saved) == 1
    new_id = dictionary.rows["여행"]["id"]
    assert saved[0]["self_like_words"] == [1] and saved[0]["self_dislike_words"] == [2]
    assert saved[0]["want_like_words"] == [3, new_id] and saved[0]["want_dislike_words"] == []
    assert len(saved[0]["self_embedding"]) == 512 and len(saved[0]["want_embedding"]) == 512
    assert client.calls[-1] == ["여행"]  # 새 단어만 임베딩한다


async def test_refresh_vectors_runs_the_taste_split_in_the_same_gather_as_the_embeddings(monkeypatch):
    """사용자 저장 요청이 이 호출을 기다린다 — 임베딩 · 글 정리(둘) · 취향 나누기(둘)가 차례가 아니라 동시에 돈다.
    다섯 개가 한 문(barrier)에서 서로를 기다리게 해, 하나라도 뒤에 두면 멈춘다."""
    barrier = asyncio.Barrier(5)

    async def meet():
        await asyncio.wait_for(barrier.wait(), timeout=3)

    async def fake_split(client, text):
        await meet()
        return {"like": [], "dislike": []}

    async def fake_facets(client, text):
        await meet()
        return None

    monkeypatch.setattr(vectors, "split_taste", fake_split)
    monkeypatch.setattr(vectors, "extract_facets", fake_facets)
    saved: list[dict] = []
    client = fake_embedder()
    original = client.embeddings.create.side_effect

    async def embed_after_meeting(**kwargs):
        await meet()
        return await original(**kwargs)

    client.embeddings.create.side_effect = embed_after_meeting

    await refresh_vectors(_repo(_with_dictionary(saved, FakeDictionary())), client, PROFILE_ID)

    assert len(saved) == 1 and "self_embedding" in saved[0]


async def test_refresh_vectors_leaves_the_taste_columns_null_when_a_split_fails(monkeypatch):
    """나누기가 실패하면(None) 그 글의 두 칸만 null — 부딪힘 검사를 하지 않는다. 옛 단어가 새 글 옆에 남지 않게 null 로 덮고, 다른 글과 임베딩 저장은 그대로 한다."""
    saved: list[dict] = []
    dictionary = FakeDictionary({"영화": 3})

    async def fake_split(client, text):
        return None if text.startswith("등산") else {"like": ["영화"], "dislike": []}

    monkeypatch.setattr(vectors, "split_taste", fake_split)

    await refresh_vectors(_repo(_with_dictionary(saved, dictionary)), fake_embedder(), PROFILE_ID)

    assert saved[0]["self_like_words"] is None and saved[0]["self_dislike_words"] is None
    assert saved[0]["want_like_words"] == [3] and saved[0]["want_dislike_words"] == []
    assert len(saved[0]["self_embedding"]) == 512 and len(saved[0]["want_embedding"]) == 512
    assert saved[0]["shyness_score"] == -0.5


async def test_refresh_vectors_keeps_everything_else_when_the_word_ids_fail(monkeypatch, caplog):
    """사전이 죽어 단어 번호를 못 정해도 임베딩 · 설문 · 글 정리 저장은 그대로 한다(4칸만 null). 실패 로그에는 profile_id 만 남는다."""
    saved: list[dict] = []
    dictionary = FakeDictionary()
    dictionary.status = 500

    async def fake_split(client, text):
        return {"like": ["등산"], "dislike": []}

    async def fake_facets(client, text):
        return {"like_places": ["카페"], "dislike_places": [], "talk": None, "values": []}

    monkeypatch.setattr(vectors, "split_taste", fake_split)
    monkeypatch.setattr(vectors, "extract_facets", fake_facets)

    with caplog.at_level(logging.ERROR, logger="app.matching.vectors"):
        await refresh_vectors(_repo(_with_dictionary(saved, dictionary)), fake_embedder(), PROFILE_ID)

    assert len(saved) == 1
    assert [saved[0][c] for c in _TASTE_COLUMNS] == [None] * 4
    assert len(saved[0]["self_embedding"]) == 512 and saved[0]["self_facets"]["like_places"] == ["카페"]
    assert saved[0]["self_survey"] and saved[0]["shyness_score"] == -0.5
    assert PROFILE_ID in caplog.text and "등산" not in caplog.text


async def test_refresh_vectors_empty_texts_give_empty_taste_arrays_without_calling_openai(monkeypatch):
    """빈 글은 OpenAI 를 부르지 않고 []다 — 글을 지운 사람의 옛 단어가 남지 않고, "나누기를 마쳤고 항목이 없음"과 "아직 안 함(null)"이 갈린다."""
    saved: list[dict] = []
    called = []

    async def fake_split(client, text):
        called.append(text)
        return {"like": [], "dislike": []}

    monkeypatch.setattr(vectors, "split_taste", fake_split)
    handler = _with_dictionary(saved, FakeDictionary(), {
        "bio": "  ", "ideal_note": None, "preferred_animal_types": [], "preferred_impression_types": [],
    })
    client = fake_embedder()

    await refresh_vectors(_repo(handler), client, PROFILE_ID)

    assert called == []
    client.chat.completions.create.assert_not_called()
    assert [saved[0][c] for c in _TASTE_COLUMNS] == [[], [], [], []]


async def test_refresh_vectors_reads_the_split_through_the_real_prompt():
    """가짜 없이 끝에서 끝까지: chat 이 취향 지시문(PROMPT)으로 불리면 나누기 답을, 글 정리 지시문으로 불리면 정리 답을 돌려준다."""
    saved: list[dict] = []
    dictionary = FakeDictionary()
    client = fake_embedder()

    def chat(**kwargs):
        system = kwargs["messages"][0]["content"]
        body = ({"like": ["등산"], "dislike": ["술", "흡연"], "style": ["공감"], "style_dislike": []}
                if system == PROMPT else {"like_places": ["야외"], "dislike_places": [], "talk": None, "values": []})
        message = type("M", (), {"content": json.dumps(body)})()
        return type("R", (), {"choices": [type("C", (), {"message": message})()]})()

    client.chat.completions.create.side_effect = chat

    await refresh_vectors(_repo(_with_dictionary(saved, dictionary)), client, PROFILE_ID)

    ids = {w: r["id"] for w, r in dictionary.rows.items()}
    assert set(ids) == {"등산", "술"}  # 흡연 · 성향(공감)은 사전에도 들어가지 않는다
    assert saved[0]["self_like_words"] == [ids["등산"]] and saved[0]["self_dislike_words"] == [ids["술"]]
    assert saved[0]["want_like_words"] == [ids["등산"]]
    assert saved[0]["self_facets"]["like_places"] == ["야외"]
