from types import SimpleNamespace
from unittest.mock import AsyncMock

from app.matching.embeddings import EMBEDDING_DIMENSIONS, EMBEDDING_MODEL, embed


async def test_embed_sends_both_sentences_in_one_call():
    """문장 2개를 한 번의 호출로 보낸다 — 호출 수와 지연을 반으로 줄인다."""
    client = AsyncMock()
    client.embeddings.create.return_value = SimpleNamespace(
        data=[SimpleNamespace(embedding=[0.1] * 512), SimpleNamespace(embedding=[0.2] * 512)]
    )

    vectors = await embed(client, ["나는 ...", "원해 ..."])

    client.embeddings.create.assert_awaited_once_with(
        model=EMBEDDING_MODEL, dimensions=EMBEDDING_DIMENSIONS, input=["나는 ...", "원해 ..."]
    )
    assert [len(v) for v in vectors] == [512, 512]


async def test_embed_returns_nothing_for_empty_input():
    """빈 문장은 임베딩하지 않는다 — 의미 없는 벡터에 요금을 내지 않는다."""
    client = AsyncMock()

    assert await embed(client, []) == []
    client.embeddings.create.assert_not_awaited()
