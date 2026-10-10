from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
from openai import AsyncOpenAI

from app.matching.embeddings import EMBEDDING_DIMENSIONS, EMBEDDING_MODEL, EMBEDDING_TIMEOUT, embed


async def test_embed_sends_both_sentences_in_one_call():
    """문장 2개를 한 번의 호출로 보낸다 — 호출 수와 지연을 반으로 줄인다."""
    client = AsyncMock()
    client.embeddings.create.return_value = SimpleNamespace(
        data=[SimpleNamespace(embedding=[0.1] * 512), SimpleNamespace(embedding=[0.2] * 512)]
    )

    vectors = await embed(client, ["나는 ...", "원해 ..."])

    client.embeddings.create.assert_awaited_once_with(
        model=EMBEDDING_MODEL, dimensions=EMBEDDING_DIMENSIONS, input=["나는 ...", "원해 ..."],
        timeout=EMBEDDING_TIMEOUT,
    )
    assert [len(v) for v in vectors] == [512, 512]


async def test_embed_returns_nothing_for_empty_input():
    """빈 문장은 임베딩하지 않는다 — 의미 없는 벡터에 요금을 내지 않는다."""
    client = AsyncMock()

    assert await embed(client, []) == []
    client.embeddings.create.assert_not_awaited()


async def test_embed_request_carries_an_explicit_timeout_over_the_wire():
    """진짜 SDK 에 가짜 전송 계층만 끼워, 실제로 나가는 요청의 시간 제한이 15초(연결 5초)인지 본다.

    SDK 기본값은 600초다 — OpenAI 가 느리면 PATCH /me/profile 과 온보딩이 요청 안에서 10분을 기다린다."""
    seen: list[dict] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.extensions["timeout"])
        return httpx.Response(200, json={"object": "list", "model": EMBEDDING_MODEL, "usage": {"prompt_tokens": 1, "total_tokens": 1},
                                         "data": [{"object": "embedding", "index": 0, "embedding": [0.1] * 512}]})

    client = AsyncOpenAI(api_key="test-key", max_retries=0,
                         http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))

    await embed(client, ["나는 ..."])

    assert seen == [{"connect": 5.0, "read": 15.0, "write": 15.0, "pool": 15.0}]
