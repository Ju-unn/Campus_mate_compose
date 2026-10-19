"""홈 "지금 함께 있는 사람들" 레일(GET /home/people): 실제 가입자 아바타를 서버가 줄이기만 한 JPEG 만 준다(블러 없음,
사용자 결정 10-17 — 아바타는 실사진이 아닌 AI 일러스트이고 카드에서도 공개된다).

가짜 PostgREST 는 경로와 쿼리 키로만 가른다(URL 문자열 일부로 가르지 않는다). 사람 목록 조회는 PostgREST 처럼
status · auto_hidden_at · gender · id(neq) 필터와 last_active_at 내림차순 · limit 을 실제로 적용한다 — 서버가 필터를 빠뜨리면
걸러져야 할 사람이 그대로 내려온다. 응답에는 누구인지 알 단서가 없으니, 누가 뽑혔는지는 Storage 에서 받아 간 원본
경로(`{profile_id}/a.png`)로 본다.

내 성별의 반대 성별만 나온다(사용자 요청 2026-10-18) — 기본 세계는 내가 남자(`my_gender="male"`)이고 후보는 여자다."""
import base64
import io
import logging
import random
import re
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageOps

import app.cards.paid_preview as paid_preview
import app.home.router as home_router
from app.core.deps import get_client, get_settings
from app.main import app
from app.settings import Settings

ME = "11111111-1111-1111-1111-111111111111"
AUTH = {"Authorization": "Bearer valid-token"}
AVATAR_OBJECT = "/storage/v1/object/avatars/"
NOW = datetime(2026, 10, 15, 12, 0, tzinfo=timezone.utc)
# PostgREST db-max-rows — 넘는 줄은 오류 없이 조용히 잘린다.
DB_MAX_ROWS = 1000


def _png() -> bytes:
    """아바타 원본 대신 쓰는 작은 무늬 그림(모두 같은 그림). 결과(224×280)보다 커서 실제로 줄어든다."""
    gradient = Image.linear_gradient("L").resize((448, 560))
    image = Image.merge("RGB", [gradient, gradient.rotate(90), gradient.rotate(180)])
    out = io.BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


AVATAR = _png()


def _settings() -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )


def _id(i: int) -> str:
    return f"00000000-0000-0000-0000-{i:012d}"


def _avatar(profile_id: str, name: str = "a", status: str = "ready", is_fallback: bool = False,
            created_at: str = "2026-10-01T00:00:00+00:00") -> dict:
    return {"storage_path": f"{profile_id}/{name}.png", "status": status, "is_fallback": is_fallback,
            "created_at": created_at}


def _person(i: int, **overrides) -> dict:
    """프로필 한 줄. 번호가 작을수록 최근에 활동했다. 응답에 새면 안 되는 칸(닉네임 · 학교 · 성별)도 일부러 담는다."""
    profile_id = overrides.pop("id", _id(i))
    return {
        "id": profile_id, "nickname": f"숨은닉{i}", "gender": "female",
        "universities": {"name": "숨은대학교"}, "status": "active", "auto_hidden_at": None,
        "matching_paused": False, "last_active_at": (NOW - timedelta(minutes=i)).isoformat(),
        "profile_avatars": [_avatar(profile_id)],
        **overrides,
    }


def _path(person: dict) -> str:
    return f"{person['id']}/a.png"


def _people(count: int, start: int = 1) -> list[dict]:
    return [_person(i) for i in range(start, start + count)]


def _in(value: str) -> list[str]:
    return value.removeprefix("in.(").removesuffix(")").split(",")


class _World:
    def __init__(self, people, blocks=(), phones=None, contact_blocks=(), verification="verified",
                 missing=(), broken=(), my_gender="male"):
        self.people = list(people)
        self.my_gender = my_gender                  # 내 프로필의 성별(None 이면 비어 있다)
        self.blocks = list(blocks)                  # (blocker_id, blocked_id)
        self.phones = phones or {}                  # profile_id → phone_hmac (키 버전은 모두 1)
        self.contact_blocks = list(contact_blocks)  # (owner_id, contact_hmac)
        self.verification = verification
        self.missing = set(missing)                 # Storage 에 없는 원본(404)
        self.broken = set(broken)                   # 그림이 아닌 원본
        self.downloads: list[str] = []
        self.people_queries: list[httpx.QueryParams] = []

    def handle(self, request: httpx.Request) -> httpx.Response:
        path, params = request.url.path, request.url.params
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": ME})
        if path.startswith(AVATAR_OBJECT) and request.method == "GET":
            key = path.removeprefix(AVATAR_OBJECT)
            self.downloads.append(key)
            if key in self.missing:
                return httpx.Response(404, json={"error": "not_found"})
            return httpx.Response(200, content=b"not an image" if key in self.broken else AVATAR,
                                  headers={"Content-Type": "image/png"})
        table = path.removeprefix("/rest/v1/")
        if table == "profiles" and "student_verification" in params.get("select", ""):
            return httpx.Response(200, json=[{"student_verification": self.verification, "department": "컴공",
                                              "school_email_verified_at": "2026-10-01T00:00:00+00:00"}])
        if table == "profiles" and params.get("select") == "gender":
            # 내 성별 읽기 — 내 행만 묻는다.
            return httpx.Response(200, json=[{"gender": self.my_gender}] if params.get("id") == f"eq.{ME}" else [])
        if table == "profiles":
            return httpx.Response(200, json=self._query_people(params))
        if table == "blocks":
            return httpx.Response(200, json=self._blocks(params["or"])[:DB_MAX_ROWS])
        if table == "profile_private":
            return httpx.Response(200, json=[
                {"profile_id": i, "phone_hmac": self.phones[i], "phone_hmac_key_version": 1}
                for i in _in(params["profile_id"]) if i in self.phones])
        if table == "contact_blocks":
            return httpx.Response(200, json=self._contact_blocks(params))
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})

    def _query_people(self, params: httpx.QueryParams) -> list[dict]:
        """PostgREST 가 하는 만큼만 흉내 낸다 — 받은 필터만 적용하고, 칸은 select 와 상관없이 다 준다."""
        self.people_queries.append(params)
        rows = self.people
        if params.get("status") == "eq.active":
            rows = [r for r in rows if r["status"] == "active"]
        if params.get("auto_hidden_at") == "is.null":
            rows = [r for r in rows if r["auto_hidden_at"] is None]
        if params.get("matching_paused") == "is.false":
            rows = [r for r in rows if r["matching_paused"] is False]
        if params.get("gender", "").startswith("eq."):
            rows = [r for r in rows if r["gender"] == params["gender"].removeprefix("eq.")]
        if params.get("id", "").startswith("neq."):
            rows = [r for r in rows if r["id"] != params["id"].removeprefix("neq.")]
        if params.get("order") == "last_active_at.desc":
            rows = sorted(rows, key=lambda r: r["last_active_at"], reverse=True)
        if "limit" in params:
            rows = rows[:int(params["limit"])]
        return rows

    def _blocks(self, condition: str) -> list[dict]:
        """두 가지 물음만 안다 — 후보 id 로 묻는 양방향 차단, 그리고 내 차단 전부(cards fetch_block_partner_ids).
        어느 쪽이든 응답은 DB_MAX_ROWS 에서 잘린다."""
        rows = [{"blocker_id": a, "blocked_id": b} for a, b in self.blocks]
        among = re.fullmatch(r"\(and\(blocker_id\.eq\.([^,]+),blocked_id\.in\.\(([^)]*)\)\),"
                             r"and\(blocked_id\.eq\.([^,]+),blocker_id\.in\.\(([^)]*)\)\)\)", condition)
        if among:
            me, blocked, me_again, blockers = among.groups()
            return [r for r in rows if (r["blocker_id"] == me and r["blocked_id"] in blocked.split(","))
                    or (r["blocked_id"] == me_again and r["blocker_id"] in blockers.split(","))]
        assert condition == f"(blocker_id.eq.{ME},blocked_id.eq.{ME})", condition
        return [r for r in rows if ME in (r["blocker_id"], r["blocked_id"])]

    def _contact_blocks(self, params: httpx.QueryParams) -> list[dict]:
        owner = params["owner_id"]
        if owner.startswith("eq."):   # ① 내가 막은 번호 중 상대 번호
            wanted = set(_in(params["contact_hmac"]))
            return [{"contact_hmac": h, "key_version": 1} for o, h in self.contact_blocks
                    if o == owner.removeprefix("eq.") and h in wanted]
        owners = set(_in(owner))       # ② 상대가 내 번호를 막았다
        mine = params["contact_hmac"].removeprefix("eq.")
        return [{"owner_id": o} for o, h in self.contact_blocks if o in owners and h == mine]


@pytest.fixture
def wire():
    # 미리보기 캐시는 프로세스에 하나라 시험끼리 섞이지 않게 앞뒤로 비운다.
    paid_preview.clear_cache()

    def build(world: _World, seed: int = 0) -> TestClient:
        http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
        app.dependency_overrides[get_settings] = lambda: _settings()
        app.dependency_overrides[get_client] = lambda: http
        app.dependency_overrides[home_router.get_rng] = lambda: random.Random(seed)
        return TestClient(app, raise_server_exceptions=False)

    yield build
    app.dependency_overrides.clear()
    paid_preview.clear_cache()


def _people_of(client: TestClient) -> list[str]:
    response = client.get("/home/people", headers=AUTH)
    assert response.status_code == 200
    return response.json()["people"]


# 응답 모양 ------------------------------------------------------------------------------------

def test_each_person_is_a_jpeg_twice_the_size_of_the_tile(wire):
    world = _World(_people(12))

    people = _people_of(wire(world))

    assert len(people) == 12
    for preview in people:
        image_bytes = base64.b64decode(preview)
        assert image_bytes[:3] == b"\xff\xd8\xff"
        assert image_bytes != AVATAR
        with Image.open(io.BytesIO(image_bytes)) as image:
            # 레일 사람 칸(pen `O5FCD9`)은 112×140 이다. 블러가 없어 기기 배율에서 뭉개지지 않게 2배로 준다(앱은 칸에 덮어 그린다).
            assert image.size == (224, 280)


def _shrunk_only(original: bytes) -> bytes:
    """가운데를 4:5 로 잘라 224×280 으로 줄이기만 한 JPEG(품질 50) — 섞기(블러)가 없다."""
    with Image.open(io.BytesIO(original)) as image:
        small = ImageOps.fit(image.convert("RGB"), (224, 280), Image.Resampling.BOX)
    out = io.BytesIO()
    small.save(out, "JPEG", quality=50, optimize=True)
    return out.getvalue()


def test_the_rail_picture_is_the_avatar_only_shrunk_not_blurred(wire):
    """블러를 없앴다(사용자 결정 10-17) — 받은 그림은 원본을 줄이기만 한 것과 바이트까지 같다."""
    people = _people_of(wire(_World(_people(12))))

    assert {base64.b64decode(preview) for preview in people} == {_shrunk_only(AVATAR)}


def test_the_rail_size_and_no_blur_are_pinned(wire, monkeypatch):
    """반경 0(블러 없음)과 실제로 넘기는 크기 · 반경을 둘 다 못 박는다."""
    calls = []
    real = home_router.cached_preview

    async def spy(storage, path, size, radius):
        calls.append((size, radius))
        return await real(storage, path, size, radius)

    monkeypatch.setattr(home_router, "cached_preview", spy)

    _people_of(wire(_World(_people(12))))

    assert home_router.HOME_PEOPLE_BLUR_RADIUS == 0
    assert calls == [((224, 280), 0)] * 12


def test_the_response_has_only_pictures_and_nothing_points_at_anyone(wire):
    """id · 저장소 경로 · 공개 주소 · 닉네임 · 학교 · 성별 — 응답 어디에도 없다. 응답은 people 하나뿐이다."""
    world = _World(_people(12))

    response = wire(world).get("/home/people", headers=AUTH)

    body = response.json()
    assert set(body) == {"people"}
    assert all(isinstance(preview, str) for preview in body["people"])
    # base64 글자 안에 우연히 같은 글자가 있을 수 있어 그림 값은 빼고 본다.
    text = response.text
    for preview in body["people"]:
        text = text.replace(preview, "")
    for leak in ("00000000-0000", "avatars/", "a.png", "storage/v1", "supabase.co",
                 "숨은닉", "숨은대학교", "female", "male", ME):
        assert leak not in text


def test_only_ids_and_avatar_rows_are_read(wire):
    """다른 프로필 칸은 읽지도 않는다."""
    world = _World(_people(12))

    _people_of(wire(world))

    [query] = world.people_queries
    assert query["select"] == "id,profile_avatars(storage_path,status,is_fallback,created_at)"


# 누가 레일에 나오나 --------------------------------------------------------------------------

FILLERS = 11


@pytest.mark.parametrize("special", [
    _person(99, status="suspended"),
    _person(99, status="withdrawn"),
    _person(99, auto_hidden_at="2026-10-10T00:00:00+00:00"),
    # 매칭을 멈춘 사람은 지금 사람을 만나지 않겠다는 뜻이라 홈에도 얼굴을 내보내지 않는다(안전한 쪽).
    _person(99, matching_paused=True),
    _person(99, id=ME),
    _person(99, profile_avatars=[]),
    _person(99, profile_avatars=[_avatar(_id(99), status="pending")]),
    _person(99, profile_avatars=[_avatar(_id(99), status="failed")]),
    _person(99, profile_avatars=[_avatar(_id(99), is_fallback=True)]),
    # 지금 쓰는(가장 최근 ready) 아바타가 기본 그림이면 옛 아바타가 있어도 빠진다 — 이제 안 쓰는 얼굴을 꺼내지 않는다.
    _person(99, profile_avatars=[_avatar(_id(99), created_at="2026-09-01T00:00:00+00:00"),
                                 _avatar(_id(99), "fallback", is_fallback=True)]),
], ids=["suspended", "withdrawn", "auto_hidden", "matching_paused", "me", "no_avatar", "only_pending",
        "only_failed", "fallback", "latest_ready_is_fallback"])
def test_people_who_should_not_appear_are_left_out(wire, special):
    fillers = _people(FILLERS)
    world = _World([*fillers, special])

    people = _people_of(wire(world))

    assert len(people) == FILLERS
    assert sorted(world.downloads) == sorted(_path(p) for p in fillers)


def test_the_latest_ready_avatar_is_used_even_when_a_newer_one_is_still_being_made(wire):
    special = _person(99, profile_avatars=[
        _avatar(_id(99), "old", created_at="2026-09-01T00:00:00+00:00"),
        _avatar(_id(99), "current", created_at="2026-09-20T00:00:00+00:00"),
        _avatar(_id(99), "making", status="pending", created_at="2026-10-14T00:00:00+00:00"),
    ])
    world = _World([*_people(FILLERS), special])

    people = _people_of(wire(world))

    assert len(people) == FILLERS + 1
    assert f"{_id(99)}/current.png" in world.downloads
    assert f"{_id(99)}/old.png" not in world.downloads


@pytest.mark.parametrize("blocks", [[(ME, _id(99))], [(_id(99), ME)]], ids=["i_blocked", "blocked_me"])
def test_blocked_people_either_way_are_left_out(wire, blocks):
    fillers = _people(FILLERS)
    world = _World([*fillers, _person(99)], blocks=blocks)

    people = _people_of(wire(world))

    assert len(people) == FILLERS
    assert f"{_id(99)}/a.png" not in world.downloads


@pytest.mark.parametrize("block", [(ME, _id(99)), (_id(99), ME)], ids=["i_blocked", "blocked_me"])
def test_a_block_after_a_thousand_others_still_leaves_the_person_out(wire, block):
    """내 차단 전부를 읽으면 PostgREST db-max-rows(1000)에서 조용히 잘려 1000줄 뒤의 차단 상대가 레일에 뜬다 —
    그래서 후보 id 로만 묻는다(후보 60명 × 양방향이라 많아야 120줄)."""
    fillers = _people(FILLERS)
    others = [(ME, f"99999999-0000-0000-0000-{i:012d}") for i in range(DB_MAX_ROWS + 200)]
    world = _World([*fillers, _person(99)], blocks=[*others, block])

    people = _people_of(wire(world))

    assert len(people) == FILLERS
    assert f"{_id(99)}/a.png" not in world.downloads


@pytest.mark.parametrize("contact_blocks", [[(ME, "phone-99")], [(_id(99), "phone-me")]],
                         ids=["i_blocked_their_number", "they_blocked_my_number"])
def test_contact_blocked_people_either_way_are_left_out(wire, contact_blocks):
    """지인을 막아 둔 사람의 얼굴이 그 지인 홈에 떠서는 안 된다 — 반대 방향도 같다."""
    fillers = _people(FILLERS)
    world = _World([*fillers, _person(99)], phones={ME: "phone-me", _id(99): "phone-99"},
                   contact_blocks=contact_blocks)

    people = _people_of(wire(world))

    assert len(people) == FILLERS
    assert f"{_id(99)}/a.png" not in world.downloads


# 반대 성별만 ----------------------------------------------------------------------------------

def _mixed(males: int, females: int) -> tuple[list[dict], list[dict]]:
    """남자 · 여자를 번호를 겹치지 않게 만든다. 남자가 1.., 여자가 100.. 번이다."""
    return ([_person(i, gender="male") for i in range(1, males + 1)],
            [_person(i, gender="female") for i in range(100, 100 + females)])


def test_a_man_sees_only_women(wire):
    men, women = _mixed(8, 12)
    world = _World([*men, *women], my_gender="male")

    people = _people_of(wire(world))

    assert len(people) == 12
    assert sorted(world.downloads) == sorted(_path(p) for p in women)


def test_a_woman_sees_only_men(wire):
    men, women = _mixed(12, 8)
    world = _World([*men, *women], my_gender="female")

    people = _people_of(wire(world))

    assert len(people) == 12
    assert sorted(world.downloads) == sorted(_path(p) for p in men)


@pytest.mark.parametrize("mine, shown", [("male", "female"), ("female", "male")])
def test_only_the_opposite_gender_goes_into_the_database_request(wire, mine, shown):
    world = _World(_people(12), my_gender=mine)

    wire(world).get("/home/people", headers=AUTH)

    [query] = world.people_queries
    assert query["gender"] == f"eq.{shown}"


def test_the_pool_is_filled_with_the_opposite_gender_by_the_database(wire):
    """가장 최근에 활동한 60명이 모두 남자여도 여자 6명이 풀에 든다 — 파이썬이 나중에 거르면 풀이 줄어 빈 줄이 된다."""
    men = [_person(i, gender="male") for i in range(1, 61)]
    women = [_person(i, gender="female") for i in range(100, 106)]
    world = _World([*men, *women], my_gender="male")

    people = _people_of(wire(world))

    assert len(people) == 6
    assert sorted(world.downloads) == sorted(_path(p) for p in women)


def test_a_candidate_without_a_gender_is_not_shown(wire):
    fillers = _people(FILLERS)
    world = _World([*fillers, _person(99, gender=None)])

    people = _people_of(wire(world))

    assert len(people) == FILLERS
    assert _path(_person(99)) not in world.downloads


def test_without_my_own_gender_the_list_is_empty_and_nobody_is_asked_for(wire):
    """내 성별이 비어 있으면 누구를 보여 줄지 알 수 없다 — 안전한 쪽으로 빈 줄이고 후보도 읽지 않는다."""
    world = _World(_people(12), my_gender=None)

    assert _people_of(wire(world)) == []
    assert world.people_queries == []
    assert world.downloads == []


def test_my_own_row_is_left_out_even_when_it_looks_like_the_opposite_gender(wire):
    """내 성별이 비어 있지 않아도 나는 빠진다 — 성별 필터가 아니라 id 필터가 지킨다(같은 성별인 척하는 행도 마찬가지)."""
    fillers = _people(FILLERS)
    world = _World([*fillers, _person(99, id=ME, gender="female")], my_gender="male")

    assert len(_people_of(wire(world))) == FILLERS
    assert f"{ME}/a.png" not in world.downloads


# 몇 명을 · 어디서 고르나 ----------------------------------------------------------------------

def _chosen(wire, world: _World, seed: int) -> set[str]:
    paid_preview.clear_cache()
    world.downloads.clear()
    assert len(_people_of(wire(world, seed))) == 12
    return set(world.downloads)


def test_twelve_are_picked_at_random_among_the_sixty_most_recently_active(wire):
    people = _people(70)
    world = _World(people)
    top_sixty = {_path(p) for p in people[:60]}

    picks = [_chosen(wire, world, seed) for seed in range(5)]

    for chosen in picks:
        assert len(chosen) == 12
        assert chosen <= top_sixty
    [query] = world.people_queries[:1]
    assert query["order"] == "last_active_at.desc"
    assert query["limit"] == "60"
    # 무작위다 — 매번 같은 사람들도, 그냥 가장 최근 12명도 아니다.
    assert len({frozenset(chosen) for chosen in picks}) > 1
    assert {_path(p) for p in people[:12]} not in picks


def test_the_same_seed_picks_the_same_people(wire):
    world = _World(_people(30))

    assert _chosen(wire, world, 7) == _chosen(wire, world, 7)


def test_fewer_than_twelve_candidates_are_all_shown(wire):
    world = _World(_people(11))

    assert len(_people_of(wire(world))) == 11


def test_four_candidates_give_an_empty_list_without_downloading(wire):
    """5명이 안 되면 빈 목록이고 앱이 예시 칸(아바타 일러스트 · 마스코트)으로 대신한다(사용자 결정 10-16)."""
    world = _World(_people(4))

    assert _people_of(wire(world)) == []
    assert world.downloads == []


def test_exactly_five_candidates_are_shown(wire):
    world = _World(_people(5))

    assert len(_people_of(wire(world))) == 5


def test_the_minimum_counts_people_after_blocks_are_taken_out(wire):
    people = _people(5)
    world = _World(people, blocks=[(ME, people[0]["id"])])

    assert _people_of(wire(world)) == []
    assert world.downloads == []


def test_the_minimum_is_five():
    assert home_router.HOME_PEOPLE_MIN == 5


# 실패 · 캐시 ----------------------------------------------------------------------------------

def test_a_failed_download_or_a_broken_image_skips_only_that_person(wire, caplog):
    people = _people(12)
    world = _World(people, missing={_path(people[0])}, broken={_path(people[1])})

    with caplog.at_level(logging.WARNING, logger="app.home.router"):
        result = _people_of(wire(world))

    assert len(result) == 10
    # 로그에는 개수만 — profile_id · 경로 · 그림 내용은 남기지 않는다(COMMON §3).
    assert "2/12" in caplog.text
    for leak in ("00000000-0000", "a.png", "avatars"):
        assert leak not in caplog.text


def test_when_every_picture_fails_the_list_is_empty_and_the_home_still_loads(wire):
    people = _people(12)
    world = _World(people, missing={_path(p) for p in people})

    assert _people_of(wire(world)) == []


def test_each_avatar_is_downloaded_only_once(wire):
    world = _World(_people(12))
    client = wire(world)

    first = _people_of(client)
    second = _people_of(client)

    assert sorted(first) == sorted(second)
    assert sorted(world.downloads) == sorted(set(world.downloads))
    assert len(world.downloads) == 12


# 관문 ----------------------------------------------------------------------------------------

@pytest.mark.parametrize("student_id", ["none", "pending", "rejected"])
def test_the_student_id_state_does_not_turn_anyone_away(wire, student_id):
    # 학생증 제거(10-17): 학교 메일 + 학과면 들어온다.
    world = _World(_people(12), verification=student_id)

    response = wire(world).get("/home/people", headers=AUTH)

    assert response.status_code == 200
    assert world.people_queries != []


def test_without_login_it_is_401(wire):
    world = _World(_people(12))

    response = wire(world).get("/home/people")

    assert response.status_code == 401
    assert world.downloads == []
