import hashlib
import json
import logging
from unittest.mock import AsyncMock

import httpx
import pytest

from app.matching.repository import MatchingRepository
from app.matching.taste import PROMPT, resolve_word_ids, split_taste, taste_fields


def _answer(content: str | None) -> type:
    message = type("M", (), {"content": content})()
    return type("R", (), {"choices": [type("C", (), {"message": message})()]})()


def _client(*contents: str | None) -> AsyncMock:
    """chat 호출마다 차례로 contents 를 돌려준다. 예외 객체를 섞으면 그 호출은 실패한다."""
    client = AsyncMock()
    client.chat.completions.create.side_effect = [
        c if isinstance(c, Exception) else _answer(c) for c in contents
    ]
    return client


def _split(like=(), dislike=(), style=(), style_dislike=()) -> str:
    return json.dumps({"like": list(like), "dislike": list(dislike), "style": list(style), "style_dislike": list(style_dislike)})


# --- 지시문 -----------------------------------------------------------------------------------

def test_prompt_is_the_v5_split_text_verbatim():
    """운영반영_계획_10-30 부록의 v5 지시문을 글자 그대로 쓴다. 지시문이 바뀌면 실험 숫자(AUC 0.97)가 더는 이 코드의 것이 아니다 —
    일부러 바꿀 때는 새 실험을 거친 뒤 이 지문(해시)도 함께 바꾼다."""
    assert hashlib.sha256(PROMPT.encode("utf-8")).hexdigest() == (
        "9af241ec08d3032822e59aeaac372ce032ae7a89454eafe1b0590e19f685ea96"
    )
    assert PROMPT.startswith("너는 소개팅 앱 글을 읽고 '취향'과 '성향'으로 나누는 도우미야.")
    assert PROMPT.endswith('JSON 하나만 출력해: {"like": [], "dislike": [], "style": [], "style_dislike": []}')


# --- split_taste ------------------------------------------------------------------------------

async def test_split_taste_asks_gpt_4o_mini_for_json_with_the_prompt():
    client = _client(_split(like=["등산"]))

    await split_taste(client, "등산 좋아해요")

    kwargs = client.chat.completions.create.call_args.kwargs
    assert kwargs["model"] == "gpt-4o-mini"
    assert kwargs["temperature"] == 0
    assert kwargs["response_format"] == {"type": "json_object"}
    assert kwargs["messages"] == [{"role": "system", "content": PROMPT}, {"role": "user", "content": "등산 좋아해요"}]
    assert kwargs["timeout"] == httpx.Timeout(15.0, connect=5.0)  # facets 와 같다 — 사용자 저장 요청이 기다린다


async def test_split_taste_keeps_only_like_and_dislike():
    """성향(style)은 쓰지 않는다 — 버린다(10-29 최종 추천: 부딪힘은 취향 칸만)."""
    client = _client(_split(like=["등산"], dislike=["술"], style=["공감"], style_dislike=["낯가림"]))

    assert await split_taste(client, "글") == {"like": ["등산"], "dislike": ["술"]}


async def test_split_taste_trims_blanks_duplicates_and_caps_each_list_at_six():
    client = _client(_split(like=[" 등산 ", "", "  ", "카페", "등산", *[f"w{i}" for i in range(10)]], dislike=["술  자리", 7, None]))

    result = await split_taste(client, "글")

    assert result["like"] == ["등산", "카페", "w0", "w1", "w2", "w3"]
    assert result["dislike"] == ["술 자리"]


async def test_split_taste_drops_words_longer_than_the_dictionary_allows():
    """사전 단어는 1~40글자(check) — 긴 문장이 새면 insert 하나가 통째로 깨진다."""
    client = _client(_split(like=["가" * 41, "가" * 40]))

    assert await split_taste(client, "글") == {"like": ["가" * 40], "dislike": []}


async def test_split_taste_drops_an_item_found_in_both_like_and_dislike():
    """한 글 안에서 좋아함 · 싫어함에 같이 나온 항목은 모순이라 둘 다 뺀다(exp_v5.clean)."""
    client = _client(_split(like=["술", "등산"], dislike=["술", "게임"]))

    assert await split_taste(client, "글") == {"like": ["등산"], "dislike": ["게임"]}


@pytest.mark.parametrize("word", ["흡연", "담배", "전자담배", "비흡연자", "연상", "연하", "연상이면 좋아요", "나이", "키", "큰 키", "키 큰 사람"])
async def test_split_taste_drops_smoking_age_and_height_words(word):
    """흡연 · 나이 · 키는 앱 칸(흡연 ×0.5 · 선호 나이 · 키 범위)이 맡는다 — 글에서도 세면 두 번 센다(exp_v5.excluded)."""
    client = _client(_split(like=[word, "등산"], dislike=[word, "게임"]))

    assert await split_taste(client, "글") == {"like": ["등산"], "dislike": ["게임"]}


@pytest.mark.parametrize("word", ["키보드", "키스", "연애", "나이트클럽"])
async def test_split_taste_keeps_words_that_only_look_like_the_excluded_ones(word):
    """제외는 '키'(정확히) · '나이'(정확히) 일 때뿐이다 — 키보드 · 나이트클럽까지 지우지 않는다."""
    client = _client(_split(like=[word]))

    assert await split_taste(client, "글") == {"like": [word], "dislike": []}


async def test_split_taste_tries_once_more_when_the_first_call_fails():
    client = _client(TimeoutError("slow"), _split(like=["등산"]))

    assert await split_taste(client, "글") == {"like": ["등산"], "dislike": []}
    assert client.chat.completions.create.await_count == 2


async def test_split_taste_tries_once_more_when_the_answer_is_not_json():
    client = _client("이건 JSON 이 아니다", _split(dislike=["술"]))

    assert await split_taste(client, "글") == {"like": [], "dislike": ["술"]}


@pytest.mark.parametrize("bad", ["not json", "[]", '"x"', "", None, '{"like": "등산", "dislike": []}'])
async def test_split_taste_is_none_after_two_failures(bad):
    client = _client(bad, bad)

    assert await split_taste(client, "글") is None
    assert client.chat.completions.create.await_count == 2  # 한 번만 다시 부른다 — 세 번째는 없다


async def test_split_taste_missing_lists_are_empty_not_a_failure():
    client = _client("{}")

    assert await split_taste(client, "글") == {"like": [], "dislike": []}
    assert client.chat.completions.create.await_count == 1


async def test_split_taste_failure_is_logged_without_the_text(caplog):
    client = _client(Exception("down"), Exception("down"))

    with caplog.at_level(logging.WARNING, logger="app.matching.taste"):
        await split_taste(client, "아주 사적인 자기소개 문장")

    assert "아주 사적인 자기소개 문장" not in caplog.text


# --- 단어 사전 --------------------------------------------------------------------------------

class FakeDictionary:
    """taste_words 를 흉내 내는 PostgREST. 요청 모양(키)을 보고 가른다 — URL 부분 문자열로 가르지 않는다."""

    def __init__(self, existing: dict[str, int] | None = None):
        self.rows: dict[str, dict] = {w: {"id": i, "word": w} for w, i in (existing or {}).items()}
        self.next_id = max((existing or {"": 100}).values()) + 1
        self.requests: list[httpx.Request] = []
        self.stolen_before_insert: dict[str, int] = {}  # 우리가 넣기 직전에 다른 요청이 먼저 넣은 단어
        self.status = 200

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.status >= 400:
            return httpx.Response(self.status, json={"message": "boom"})
        assert request.url.path == "/rest/v1/taste_words"
        if request.method == "GET":
            wanted = _parse_in(request.url.params["word"])
            return httpx.Response(200, json=[self.rows[w] for w in wanted if w in self.rows])
        body = json.loads(request.content)
        for word, taken in self.stolen_before_insert.items():
            self.rows[word] = {"id": taken, "word": word}
        for row in body:
            if row["word"] not in self.rows:  # on_conflict=word + ignore-duplicates
                self.rows[row["word"]] = {"id": self.next_id, "word": row["word"]}
                self.next_id += 1
        return httpx.Response(201)

    def posts(self) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == "POST"]


def _parse_in(value: str) -> list[str]:
    assert value.startswith("in.(") and value.endswith(")")
    inner = value[4:-1]
    words, current, quoted, escaped = [], "", False, False
    for ch in inner:
        if escaped:
            current, escaped = current + ch, False
        elif ch == "\\" and quoted:
            escaped = True
        elif ch == '"':
            quoted = not quoted
        elif ch == "," and not quoted:
            words.append(current)
            current = ""
        else:
            current += ch
    return [*words, current]


def _repo(fake: FakeDictionary) -> MatchingRepository:
    client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handler))
    return MatchingRepository("https://x.supabase.co/rest/v1", "service-key", client)


def fake_embedder() -> AsyncMock:
    """입력 단어마다 512차원 하나씩(첫 값에 글자 수) 돌려주는 임베딩 가짜. 입력 목록을 calls 에 쌓는다."""
    client = AsyncMock()
    client.calls = []

    async def create(model, dimensions, input, timeout=None):
        client.calls.append(list(input))
        return type("R", (), {"data": [type("D", (), {"embedding": [float(len(w))] + [0.0] * 511})() for w in input]})()

    client.embeddings.create.side_effect = create
    return client


async def test_resolve_word_ids_embeds_only_the_new_words():
    fake = FakeDictionary({"등산": 1})
    client = fake_embedder()

    ids = await resolve_word_ids(_repo(fake), client, ["등산", "카페"])

    assert ids == {"등산": 1, "카페": fake.rows["카페"]["id"]}
    assert client.calls == [["카페"]]  # 사전에 있는 단어는 다시 임베딩하지 않는다
    [post] = fake.posts()
    assert [r["word"] for r in json.loads(post.content)] == ["카페"]
    assert len(json.loads(post.content)[0]["embedding"]) == 512


async def test_resolve_word_ids_makes_no_calls_when_everything_is_known():
    fake = FakeDictionary({"등산": 1, "술": 2})
    client = fake_embedder()

    ids = await resolve_word_ids(_repo(fake), client, ["등산", "술", "등산"])

    assert ids == {"등산": 1, "술": 2}
    assert client.calls == [] and fake.posts() == []
    assert len([r for r in fake.requests if r.method == "GET"]) == 1


async def test_resolve_word_ids_collapses_duplicate_words_into_one_embedding():
    client = fake_embedder()

    await resolve_word_ids(_repo(FakeDictionary()), client, ["카페", "카페", "술"])

    assert sorted(client.calls[0]) == ["술", "카페"]


async def test_resolve_word_ids_inserts_ignoring_duplicates_on_the_word_column():
    """두 사람이 같은 새 단어를 동시에 넣어도 unique 로 하나만 남는다 — 충돌이 오류가 되지 않게 on_conflict=word + ignore-duplicates."""
    fake = FakeDictionary()

    await resolve_word_ids(_repo(fake), fake_embedder(), ["카페"])

    [post] = fake.posts()
    assert post.url.params["on_conflict"] == "word"
    assert "resolution=ignore-duplicates" in post.headers["Prefer"]


async def test_resolve_word_ids_reads_again_after_inserting_so_a_concurrent_winner_is_used():
    """우리가 넣기 직전에 다른 요청이 같은 새 단어를 넣었다 — 우리 insert 는 무시되고, 다시 읽어 그쪽 번호를 쓴다."""
    fake = FakeDictionary({"등산": 1})
    fake.stolen_before_insert = {"카페": 777}

    ids = await resolve_word_ids(_repo(fake), fake_embedder(), ["등산", "카페"])

    assert ids == {"등산": 1, "카페": 777}


async def test_resolve_word_ids_quotes_words_with_filter_characters():
    fake = FakeDictionary()
    odd = ['a,b', 'c(d)', 'e"f', 'g\\h', 'i.j']

    ids = await resolve_word_ids(_repo(fake), fake_embedder(), odd)

    assert set(ids) == set(odd)  # 가짜가 따옴표 규칙대로 되읽은 것과 같다


async def test_resolve_word_ids_with_no_words_does_nothing():
    fake = FakeDictionary()
    client = fake_embedder()

    assert await resolve_word_ids(_repo(fake), client, []) == {}
    assert fake.requests == [] and client.calls == []


async def test_resolve_word_ids_raises_when_a_word_still_has_no_id():
    """넣은 뒤에도 못 찾은 단어가 있으면(있을 수 없는 일) 조용히 빼지 않고 실패로 알린다 — 호출한 쪽이 4칸을 비운다."""
    fake = FakeDictionary()
    fake.handler_orig = fake.handler

    def lossy(request: httpx.Request) -> httpx.Response:
        response = fake.handler_orig(request)
        if request.method == "POST":
            fake.rows.clear()
        return response

    fake.handler = lossy
    with pytest.raises(LookupError):
        await resolve_word_ids(_repo(fake), fake_embedder(), ["카페"])


async def test_resolve_word_ids_propagates_a_dictionary_outage():
    fake = FakeDictionary()
    fake.status = 500

    with pytest.raises(Exception):  # noqa: B017 — 어떤 형태든 올라와야 한다
        await resolve_word_ids(_repo(fake), fake_embedder(), ["카페"])


# --- taste_fields ------------------------------------------------------------------------------

EMPTY = {"like": [], "dislike": []}


async def test_taste_fields_maps_each_side_to_its_two_columns():
    fake = FakeDictionary({"등산": 1, "술": 2, "영화": 3, "게임": 4})
    splits = {"self": {"like": ["등산"], "dislike": ["술"]}, "want": {"like": ["영화"], "dislike": ["게임", "술"]}}

    fields = await taste_fields(_repo(fake), fake_embedder(), splits)

    assert fields == {
        "self_like_words": [1], "self_dislike_words": [2],
        "want_like_words": [3], "want_dislike_words": [4, 2],
    }


async def test_taste_fields_empty_splits_are_empty_arrays_without_any_call():
    """빈 글 = 빈 배열이다(null 이 아니다 — 나누기를 마쳤고 항목이 없을 뿐). 사전도 임베딩도 부르지 않는다."""
    fake = FakeDictionary()
    client = fake_embedder()

    fields = await taste_fields(_repo(fake), client, {"self": EMPTY, "want": EMPTY})

    assert fields == {"self_like_words": [], "self_dislike_words": [], "want_like_words": [], "want_dislike_words": []}
    assert fake.requests == [] and client.calls == []


async def test_taste_fields_a_failed_side_is_null_and_the_other_side_still_saves():
    fake = FakeDictionary({"등산": 1})

    fields = await taste_fields(_repo(fake), fake_embedder(), {"self": None, "want": {"like": ["등산"], "dislike": []}})

    assert fields == {
        "self_like_words": None, "self_dislike_words": None,
        "want_like_words": [1], "want_dislike_words": [],
    }

