from openai import AsyncOpenAI

# 512차원은 설계 §6.3 표에 확정돼 있다. text-embedding-3-small 은 dimensions 파라미터로 줄여 받을 수 있고,
# 줄여도 상위 차원이 잘리는 게 아니라 정규화된 축소 벡터가 온다(OpenAI 문서).
EMBEDDING_MODEL = "text-embedding-3-small"
EMBEDDING_DIMENSIONS = 512


async def embed(openai_client: AsyncOpenAI, texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    response = await openai_client.embeddings.create(
        model=EMBEDDING_MODEL, dimensions=EMBEDDING_DIMENSIONS, input=texts
    )
    return [item.embedding for item in response.data]
