import httpx
from openai import AsyncOpenAI

# 512차원은 설계 §6.3 표에 확정돼 있다. text-embedding-3-small 은 dimensions 파라미터로 줄여 받을 수 있고,
# 줄여도 상위 차원이 잘리는 게 아니라 정규화된 축소 벡터가 온다(OpenAI 문서).
EMBEDDING_MODEL = "text-embedding-3-small"
EMBEDDING_DIMENSIONS = 512

# 프로필 수정(PATCH /me/profile)과 온보딩이 요청 안에서 임베딩을 기다린다. SDK 기본은 600초라 OpenAI 가 느리면
# 사용자 요청이 그만큼 매달린다. 문장 두 개 임베딩은 보통 1초 안이라 전체 15초(연결 5초)면 넉넉하다.
# 다시 시도는 없다(get_openai_client 가 max_retries=0) — 시간이 지나면 refresh_vectors 가 로그만 남기고 저장은 그대로 둔다.
# 클라이언트가 아니라 이 호출에만 건다: 같은 클라이언트가 아바타 이미지 편집(오래 걸림)도 부른다.
EMBEDDING_TIMEOUT = httpx.Timeout(15.0, connect=5.0)


async def embed(openai_client: AsyncOpenAI, texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    response = await openai_client.embeddings.create(
        model=EMBEDDING_MODEL, dimensions=EMBEDDING_DIMENSIONS, input=texts, timeout=EMBEDDING_TIMEOUT
    )
    return [item.embedding for item in response.data]
