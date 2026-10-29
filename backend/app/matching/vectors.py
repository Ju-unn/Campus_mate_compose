import asyncio
import logging
import time
from uuid import UUID

from openai import AsyncOpenAI

from app.matching.embeddings import embed
from app.matching.facets import extract_facets
from app.matching.repository import MatchingRepository
from app.matching.sentences import self_sentence, want_sentence
from app.matching.survey_vector import survey_vector
from app.matching.taste import EMPTY_SPLIT, no_taste_fields, split_taste, taste_fields

_logger = logging.getLogger(__name__)

# shortcut: 새벽 정리 한 번에 20명, 실패가 하루 20명을 넘으면 올리거나 여러 번 돈다.
REFILL_LIMIT = 20
# 정리 요청(Cloud Run 300초) 안에 끝나게 — 한 사람은 나누기 두 번(재시도 포함 최대 약 60초)이라 그만큼 남긴다.
REFILL_BUDGET_SECONDS = 150
_clock = time.monotonic


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
        to_split = _taste_texts(materials)
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
            _with_empty(dict(zip(to_split, splits))),
        ))
        await repo.save_vectors(profile_id, **fields)
    except Exception:  # noqa: BLE001 — 벡터 실패가 사용자 저장을 깨지 않게 한다
        _logger.exception("매칭 벡터 재생성 실패: profile_id=%s", profile_id)


async def refill_taste(repo: MatchingRepository, openai_client: AsyncOpenAI) -> int:
    """나누기가 실패해 취향 단어 칸이 빈 사람을 다시 나눈다(새벽 4시 정리 배치). 시도한 사람 수.
    글이 안 바뀌면 그 사람이 다시 저장할 때까지 부딪힘 검사에서 빠지므로 매일 메운다."""
    started = _clock()
    tried = 0
    for profile_id in await repo.fetch_taste_unsplit(REFILL_LIMIT):
        if _clock() - started > REFILL_BUDGET_SECONDS:
            break  # 남은 사람은 내일 — 정리 요청이 시간 제한에 끊기지 않게
        await _refill_one(repo, openai_client, profile_id)
        tried += 1
    return tried


async def _refill_one(repo: MatchingRepository, openai_client: AsyncOpenAI, profile_id: str) -> None:
    """취향 4칸만 다시 만든다 — 임베딩 · 글 정리는 건드리지 않는다(그날 OpenAI 가 흔들려도 멀쩡한 글 정리를 null 로 덮지 않게).
    나누기가 또 실패해도 4칸 null 과 updated_at 이 저장돼 이 사람은 줄 뒤로 간다."""
    try:
        to_split = _taste_texts(await repo.fetch_vector_materials(profile_id))
        splits = await asyncio.gather(*(split_taste(openai_client, text) for text in to_split.values()))
        fields = await _taste_fields(repo, openai_client, profile_id, _with_empty(dict(zip(to_split, splits))))
        await repo.save_vectors(profile_id, **fields)
    except Exception as exc:  # noqa: BLE001 — 한 사람 실패가 다음 사람을 막지 않게. 글이 새지 않게 예외 종류만
        _logger.error("취향 단어 다시 채우기 실패: profile_id=%s %s", profile_id, type(exc).__name__)


def _taste_texts(materials: dict) -> dict[str, str]:
    """나눌 두 글(bio → self, ideal_note → want). 빈 글은 뺀다 — OpenAI 를 부르지 않고 _with_empty 가 [] 로 채운다."""
    sides = {"self": materials.get("bio"), "want": materials.get("ideal_note")}
    return {side: text.strip() for side, text in sides.items() if (text or "").strip()}


def _with_empty(splits: dict[str, dict | None]) -> dict[str, dict | None]:
    return {"self": EMPTY_SPLIT, "want": EMPTY_SPLIT, **splits}


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
