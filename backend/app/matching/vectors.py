import asyncio
import logging
from uuid import UUID

from openai import AsyncOpenAI

from app.matching.embeddings import embed
from app.matching.facets import extract_facets
from app.matching.repository import MatchingRepository
from app.matching.sentences import self_sentence, want_sentence
from app.matching.survey_vector import survey_vector
from app.matching.taste import EMPTY_SPLIT, no_taste_fields, split_taste, taste_fields

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
        sentences = {
            "self_embedding": self_sentence(materials),
            "want_embedding": want_sentence(materials),
        }
        # 빈 문장은 OpenAI 에 보내지 않고 payload 에서도 뺀다 — 기본정보 단계에서는 "원해" 재료가
        # 아직 없고, 빈 칸을 보내면 upsert 가 전에 저장한 벡터를 덮어쓴다.
        filled = {column: text for column, text in sentences.items() if text}
        # 글 정리는 사용자가 쓴 원문만 읽는다(템플릿의 학과 · 얼굴상은 다른 점수가 본다). 빈 글은 임베딩처럼 뺀다.
        originals = {"self_facets": materials.get("bio"), "want_facets": materials.get("ideal_note")}
        to_extract = {column: text.strip() for column, text in originals.items() if (text or "").strip()}
        # 글 속 취향 나누기(10-30)는 같은 두 글을 읽는다. 같은 gather 에 넣어 사용자 저장 요청이 기다리는 시간을 늘리지 않는다.
        # 빈 글은 OpenAI 를 부르지 않고 빈 결과([])로 둔다.
        taste_sides = {"self": materials.get("bio"), "want": materials.get("ideal_note")}
        to_split = {side: text.strip() for side, text in taste_sides.items() if (text or "").strip()}
        embeddings, *rest = await asyncio.gather(
            embed(openai_client, list(filled.values())),
            *(extract_facets(openai_client, text) for text in to_extract.values()),
            *(split_taste(openai_client, text) for text in to_split.values()),
        )
        facets, splits = rest[: len(to_extract)], rest[len(to_extract):]

        fields = {"self_survey": vector, "shyness_score": shyness}
        fields.update(zip(filled, embeddings))
        fields.update(zip(to_extract, facets))
        fields.update(await _taste_fields(
            repo, openai_client, profile_id,
            {**{side: EMPTY_SPLIT for side in taste_sides}, **dict(zip(to_split, splits))},
        ))
        await repo.save_vectors(profile_id, **fields)
    except Exception:  # noqa: BLE001 — 벡터 실패가 사용자 저장을 깨지 않게 한다
        _logger.exception("매칭 벡터 재생성 실패: profile_id=%s", profile_id)


async def _taste_fields(
    repo: MatchingRepository, openai_client: AsyncOpenAI, profile_id: UUID | str, splits: dict[str, dict | None]
) -> dict:
    """취향 단어 4칸. 단어 번호를 못 정해도(사전 · 임베딩 실패) 임베딩 · 설문 · 글 정리 저장은 그대로 하고 4칸만 null 로 둔다 —
    null 은 "부딪힘 검사 안 함"이라 지금과 같다. 로그에는 profile_id 와 예외 종류만 남긴다(예외 문구에 단어가 든 URL 이 실릴 수 있다)."""
    try:
        return await taste_fields(repo, openai_client, splits)
    except Exception as exc:  # noqa: BLE001 — 취향 실패가 벡터 저장을 깨지 않게 한다
        _logger.error("취향 단어 번호 정하기 실패: profile_id=%s %s", profile_id, type(exc).__name__)
        return no_taste_fields()
