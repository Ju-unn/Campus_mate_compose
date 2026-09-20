import logging
from uuid import UUID

from openai import AsyncOpenAI

from app.matching.embeddings import embed
from app.matching.repository import MatchingRepository
from app.matching.sentences import self_sentence, want_sentence
from app.matching.survey_vector import survey_vector

_logger = logging.getLogger(__name__)


async def refresh_vectors(
    repo: MatchingRepository, openai_client: AsyncOpenAI, profile_id: UUID | str
) -> None:
    """설문·문장 벡터를 다시 만들어 저장한다(설계 §6.3 "수정하면 즉시 재생성").

    호출자는 이미 사용자의 글을 저장한 뒤다. 여기서 실패해도 그 저장을 되돌리지 않고 로그만 남긴다 —
    벡터가 없는 프로필은 match_candidates 의 `is not null` 조건에서 후보로만 빠지고, 다음 저장이나
    온보딩 완료 시점의 전체 재생성이 메운다."""
    try:
        materials = await repo.fetch_vector_materials(profile_id)
        vector, shyness = survey_vector(materials.get("survey_answers") or {})
        sentences = [self_sentence(materials), want_sentence(materials)]
        # 두 문장 다 비면 임베딩을 부르지 않는다(온보딩 초반). 설문만이라도 저장한다.
        embeddings = await embed(openai_client, sentences) if any(sentences) else []

        fields = {"self_survey": vector, "shyness_score": shyness}
        if embeddings:
            fields["self_embedding"] = embeddings[0]
            fields["want_embedding"] = embeddings[1]
        await repo.save_vectors(profile_id, **fields)
    except Exception:  # noqa: BLE001 — 벡터 실패가 사용자 저장을 깨지 않게 한다
        _logger.exception("매칭 벡터 재생성 실패: profile_id=%s", profile_id)
