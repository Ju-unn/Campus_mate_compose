"""글 속 취향 부딪힘(10-30 운영 반영): 자기소개 · "이런 사람이 좋아요" 원문을 GPT 가 좋아함 / 싫어함 단어로 나누고,
단어를 사전(taste_words)의 번호로 바꿔 사람에게 저장한다. 두 사람이 서로 좋아함 ↔ 싫어함에 비슷한 단어를 갖고 있으면
SQL taste_clash_candidates 가 부딪힘으로 찾고, scoring.TASTE_CLASH_PENALTY(×0.6)가 총점을 깎는다.

facets(글 정리)와 따로 두는 이유: facets 는 정해진 칸 몇 개(장소 · 대화 · 가치)로 점수를 내지만, 여기는 열린 단어를 임베딩 거리로 맞춘다.
실험 · 근거는 바탕화면 매칭_유사도/운영_시뮬레이션_10-29 · 재검증_10-28(exp_v5.py 의 excluded · clean)."""

import json
import logging

import httpx
from openai import AsyncOpenAI

from app.matching.embeddings import embed
from app.matching.repository import MatchingRepository

_logger = logging.getLogger(__name__)

# 운영반영_계획_10-30 부록의 v5 나누기 지시문 원문. 글자 하나도 바꾸지 않는다 — 실험 숫자(200명 AUC 0.97)가 이 글로 나온 것이다.
# 성향(style · style_dislike)도 같이 나누지만 저장하지 않는다: 실험에서 부딪힘은 취향 칸(like · dislike)만 썼다.
PROMPT = """너는 소개팅 앱 글을 읽고 '취향'과 '성향'으로 나누는 도우미야. 글에 **분명히 적힌 것만** 골라. 짐작하거나 지어내지 마.
- like: 글쓴이가 좋아하거나 즐겨 하는 활동 · 취미 · 음식 · 장소 · 대상. 상대를 바라는 글이면 상대와 함께 하고 싶은 활동 · 대상.
- dislike: 싫어하거나 안 하는 · 못 하는 활동 · 취미 · 음식 · 장소 · 대상. 상대를 바라는 글이면 상대에게 바라지 않는 활동 · 대상.
- style: 성격 · 말투 · 관계 맺는 방식 · 연락 방식처럼 '어떤 사람인가'를 말하는 것(예: 공감 잘하기, 천천히 관계 쌓기, 유머, 계획적).
- style_dislike: 싫어하거나 부담스러운 성격 · 관계 방식(예: 자주 연락하기, 빠른 관계 발전, 낯가림).
- 항목은 그 활동 · 대상의 가장 흔한 이름 하나를 2~6글자 명사로 써. 예: "몸 움직이기"→"운동", "산에 오르기"→"등산",
  "술 한잔하기"→"술", "무서운 영화"→"공포영화", "코인노래방"→"노래방", "강아지"→"반려동물". '좋다 · 싫다 · 안 한다' 같은 말은 빼.
- 구체적인 이름을 썼으면 그 범주 이름도 같은 목록에 하나 더 넣어. 예: 마라탕 · 떡볶이 → 매운 음식, 강아지 · 고양이 → 반려동물,
  담배 · 전자담배 · 흡연자 → 흡연, 소주 · 맥주 · 술자리 → 술, 헬스 · 필라테스 · 요가 → 운동, 텐트 · 밖에서 자기 → 캠핑, 해외여행 → 여행, 코인노래방 → 노래방.
- '피워요 · 마셔요 · 해요 · 즐겨요'처럼 하는 것은 like, '안 피워요 · 안 마셔요 · 못 해요 · 별로예요'는 dislike 다.
- '가끔 · 적당히 · 조금'처럼 정도만 말한 것은 넣지 마(좋아함도 싫어함도 아니다).
- 연상 · 연하 · 나이 · 키 · 외모처럼 상대에게 거는 조건은 넣지 마(앱이 선호 나이 · 키 칸으로 따로 본다).
- 학과 · 전공 · 학년 같은 소개 정보는 넣지 마. 한 항목에 한 가지만. 각 목록 6개까지.
예시: '담배를 피워요' → like ["흡연"]. '전자담배를 펴요' → like ["흡연"]. '담배 안 피워요' · '비흡연자예요' → dislike ["흡연"].
'술 좋아해요' → like ["술"]. '술 안 마셔요' → dislike ["술"]. '술은 가끔 먹어요' → 넣지 않음. '연상이 좋아요' → 넣지 않음.
JSON 하나만 출력해: {"like": [], "dislike": [], "style": [], "style_dislike": []}"""

# 글 정리(facets)와 같은 타임아웃 — 사용자 저장 요청이 이 호출을 기다린다. 다시 시도는 아래에서 한 번만 직접 한다(클라이언트는 max_retries=0).
_TIMEOUT = httpx.Timeout(15.0, connect=5.0)
_ATTEMPTS = 2
MAX_PER_LIST = 6
MAX_WORD_LENGTH = 40  # taste_words.word 의 check(1~40)

# 사람 칸 이름. 글 하나(bio → self, ideal_note → want)가 좋아함 · 싫어함 두 칸이 된다.
SIDE_COLUMNS = {
    "self": ("self_like_words", "self_dislike_words"),
    "want": ("want_like_words", "want_dislike_words"),
}
EMPTY_SPLIT = {"like": [], "dislike": []}  # 빈 글 — OpenAI 를 부르지 않고 "나누기를 마쳤고 항목이 없음"으로 본다

_EXCLUDED_PARTS = ("흡연", "담배", "연상", "연하")
_EXCLUDED_WORDS = {"나이", "키", "큰 키", "키 큰 사람"}


def excluded(word: str) -> bool:
    """앱에 칸이 있는 조건(흡연 ×0.5 · 선호 나이 · 키 범위)은 글 부딪힘에서 뺀다 — 두 번 세지 않으려고(exp_v5.excluded)."""
    return any(part in word for part in _EXCLUDED_PARTS) or word in _EXCLUDED_WORDS


def _words(value) -> list[str]:
    """목록 하나를 단어로 정리한다: 문자열만, 공백 정리, 빈 값 · 사전에 못 넣는 긴 말 · 중복 제거. 목록이 아니면 실패(ValueError)."""
    if value is None:
        return []
    if not isinstance(value, list):
        raise ValueError("나누기 답의 목록이 목록이 아니다")
    words: list[str] = []
    for item in value:
        word = " ".join(item.split()) if isinstance(item, str) else ""
        if word and len(word) <= MAX_WORD_LENGTH and word not in words:
            words.append(word)
    return words


def _parse(content: str | None) -> dict:
    answer = json.loads(content or "")
    if not isinstance(answer, dict):
        raise ValueError("나누기 답이 객체가 아니다")
    like, dislike = _words(answer.get("like")), _words(answer.get("dislike"))
    both = set(like) & set(dislike)  # 한 글 안의 모순(좋아함 · 싫어함에 같이 나옴)은 둘 다 뺀다(exp_v5.clean)

    def keep(words: list[str]) -> list[str]:
        return [w for w in words if w not in both and not excluded(w)][:MAX_PER_LIST]

    return {"like": keep(like), "dislike": keep(dislike)}


async def split_taste(openai_client: AsyncOpenAI, text: str) -> dict | None:
    """글 하나를 {"like": [...], "dislike": [...]} 로 나눈다. 실패하거나 답을 못 읽으면 한 번만 다시 부르고, 그래도 안 되면 None —
    None 인 사람은 부딪힘 검사를 하지 않는다(지금과 같음). 성향(style)은 버린다."""
    for attempt in range(1, _ATTEMPTS + 1):
        try:
            response = await openai_client.chat.completions.create(
                model="gpt-4o-mini", temperature=0, response_format={"type": "json_object"},
                messages=[{"role": "system", "content": PROMPT}, {"role": "user", "content": text}],
                timeout=_TIMEOUT,
            )
            return _parse(response.choices[0].message.content)
        except Exception as exc:  # noqa: BLE001 — 나누기 실패가 임베딩 저장을 깨지 않게 한다
            # 글(사적인 자기소개)이 로그에 새지 않게 예외 종류만 남긴다.
            _logger.warning("취향 나누기 실패(%d/%d): %s", attempt, _ATTEMPTS, type(exc).__name__)
    return None


async def resolve_word_ids(
    repo: MatchingRepository, openai_client: AsyncOpenAI, words: list[str]
) -> dict[str, int]:
    """단어 → 사전 번호. 사전에 없는 단어만 임베딩해(글과 같은 모델 · 512차원) 넣고, 넣은 뒤 다시 읽는다.
    두 사람이 같은 새 단어를 동시에 넣어도 unique + ignore-duplicates 로 하나만 남고, 다시 읽으면 이긴 쪽 번호를 받는다."""
    unique = list(dict.fromkeys(words))
    if not unique:
        return {}
    ids = await repo.fetch_taste_word_ids(unique)
    # 정렬해서 넣는다 — 두 요청이 겹치는 새 단어를 서로 다른 순서로 넣으면 unique 잠금끼리 교착할 수 있다.
    missing = sorted(w for w in unique if w not in ids)
    if missing:
        embeddings = await embed(openai_client, missing)
        if len(embeddings) != len(missing):
            raise ValueError("단어 수와 임베딩 수가 다르다")
        await repo.add_taste_words(dict(zip(missing, embeddings)))
        ids.update(await repo.fetch_taste_word_ids(missing))
        if any(w not in ids for w in missing):
            raise LookupError("사전에 넣은 단어를 다시 읽지 못했다")
    return ids


def no_taste_fields() -> dict:
    """나누기를 못 했을 때 저장할 값 — 네 칸 모두 null(검사 안 함). 옛 글의 단어가 새 글 옆에 남지 않게 덮는다."""
    return {column: None for columns in SIDE_COLUMNS.values() for column in columns}


async def taste_fields(
    repo: MatchingRepository, openai_client: AsyncOpenAI, splits: dict[str, dict | None]
) -> dict:
    """splits = {"self": 나누기 결과 | None, "want": ...} → profile_vectors 4칸. 나누기를 못 한 쪽(None)은 그 두 칸이 null 이다.
    사전이나 임베딩이 실패하면 예외를 올린다 — 부르는 쪽(refresh_vectors)이 4칸을 null 로 두고 나머지 저장을 이어 간다."""
    ids = await resolve_word_ids(
        repo, openai_client,
        [word for split in splits.values() if split for kind in ("like", "dislike") for word in split[kind]],
    )
    fields = no_taste_fields()
    for side, (like_column, dislike_column) in SIDE_COLUMNS.items():
        split = splits[side]
        if split is not None:
            fields[like_column] = [ids[w] for w in split["like"]]
            fields[dislike_column] = [ids[w] for w in split["dislike"]]
    return fields
