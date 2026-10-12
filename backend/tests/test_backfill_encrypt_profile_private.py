"""한 번 쓰는 백필(M1 → M2 사이): 옛 평문 real_name · kakao_id 를 *_enc 열로 옮기고 복호화 값으로 맞는지 센다."""
import json

import httpx

from scripts.backfill_encrypt_profile_private import ProfilePrivateEncryptionBackfill, main

KEY = "enc-key"
# 백필 조회 조건: 평문이 있는데 그 enc 가 빈 행(열마다 따로).
NEEDS_FILL = "(and(real_name.not.is.null,real_name_enc.is.null),and(kakao_id.not.is.null,kakao_id_enc.is.null))"


def _db() -> dict[str, dict[str, str | None]]:
    # 가짜 암호문은 평문 그대로 둔다(키 확인은 handler 가 한다). profile_id 는 정렬 순서만 뜻이 있다.
    return {
        "p1": {"real_name": "김하나", "kakao_id": "kakao1", "real_name_enc": None, "kakao_id_enc": None},
        "p2": {"real_name": "이둘", "kakao_id": None, "real_name_enc": None, "kakao_id_enc": None},
        # 이중 쓰기로 실명 enc 만 먼저 들어간 행 — 카카오만 채운다.
        "p3": {"real_name": "박셋", "kakao_id": "kakao3", "real_name_enc": "박셋", "kakao_id_enc": None},
        "p4": {"real_name": "최넷", "kakao_id": "kakao4", "real_name_enc": "최넷", "kakao_id_enc": "kakao4"},
        # 빈 문자열은 not.is.null 에 걸리지만 DB 함수가 아무것도 안 한다 — 매번 골라져도 끝나야 한다.
        "p5": {"real_name": "", "kakao_id": None, "real_name_enc": None, "kakao_id_enc": None},
        "p6": {"real_name": None, "kakao_id": None, "real_name_enc": None, "kakao_id_enc": None},
    }


def _fake(db: dict, sent: list[httpx.Request]):
    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        params = request.url.params
        path = request.url.path
        if path == "/rest/v1/rpc/backfill_profile_private_encryption":
            body = json.loads(request.content)
            assert body["p_key"] == KEY
            row = db[body["p_profile"]]
            # 마이그레이션 함수와 같은 규칙: enc 가 비었고 평문이 빈 값이 아닐 때만 쓴다.
            for field in ("real_name", "kakao_id"):
                if row[f"{field}_enc"] is None and row[field]:
                    row[f"{field}_enc"] = row[field]
            return httpx.Response(204)
        if path == "/rest/v1/rpc/decrypt_profile_private":
            body = json.loads(request.content)
            assert body["p_key"] == KEY
            row = db[body["p_profile"]]
            return httpx.Response(200, json=[{"real_name": row["real_name_enc"], "kakao_id": row["kakao_id_enc"]}])
        assert path == "/rest/v1/profile_private" and request.method == "GET"
        assert params["order"] == "profile_id.asc"
        after = params.get("profile_id", "gt.").removeprefix("gt.")
        if "or" in params:
            assert params["or"] == NEEDS_FILL and params["select"] == "profile_id"
            picked = [pid for pid in sorted(db) if pid > after and any(
                db[pid][f] is not None and db[pid][f"{f}_enc"] is None for f in ("real_name", "kakao_id"))]
            rows = [{"profile_id": pid} for pid in picked]
        else:
            assert params["select"] == "profile_id,real_name,kakao_id"
            rows = [{"profile_id": pid, "real_name": db[pid]["real_name"], "kakao_id": db[pid]["kakao_id"]}
                    for pid in sorted(db) if pid > after]
        return httpx.Response(200, json=rows[:int(params["limit"])])

    return httpx.MockTransport(handler)


async def test_backfill_pages_by_profile_id_fills_only_missing_and_is_safe_to_rerun():
    db = _db()
    sent: list[httpx.Request] = []
    async with httpx.AsyncClient(transport=_fake(db, sent)) as client:
        job = ProfilePrivateEncryptionBackfill("https://x.supabase.co/rest/v1", "service-key", client, KEY)
        first = await job.run(page=2)
        again = await job.run(page=2)

    # p1 · p2 · p3 · p5 를 부른다(p4 는 다 채워졌고 p6 은 평문이 없다). 쪽 크기 2 라 두 쪽 넘게 넘겨야 다 본다.
    assert first == 4
    # 다시 돌리면 빈 문자열 행(p5)만 또 골라진다 — DB 함수가 아무것도 안 하니 안전하다.
    assert again == 1
    assert {pid: (r["real_name_enc"], r["kakao_id_enc"]) for pid, r in db.items()} == {
        "p1": ("김하나", "kakao1"), "p2": ("이둘", None), "p3": ("박셋", "kakao3"),
        "p4": ("최넷", "kakao4"), "p5": (None, None), "p6": (None, None),
    }
    rpc = [r for r in sent if r.url.path.endswith("/rpc/backfill_profile_private_encryption")]
    assert [json.loads(r.content)["p_profile"] for r in rpc] == ["p1", "p2", "p3", "p5", "p5"]
    # 키는 JSON 바디로만 — URL(접근 로그)에는 없다.
    assert all(KEY not in str(r.url) for r in sent)


async def test_main_prints_counts_only_and_exits_zero_when_decrypted_values_match(capsys):
    db = _db()
    sent: list[httpx.Request] = []
    async with httpx.AsyncClient(transport=_fake(db, sent)) as client:
        job = ProfilePrivateEncryptionBackfill("https://x.supabase.co/rest/v1", "service-key", client, KEY)
        code = await main(job, page=2)

    out = capsys.readouterr().out
    assert code == 0
    # 빈 문자열 평문은 "평문 있음" 으로 세지 않는다.
    assert out.split() == [
        "requested=4",
        "real_name_plain=4", "real_name_enc=4", "real_name_mismatch=0",
        "kakao_id_plain=3", "kakao_id_enc=3", "kakao_id_mismatch=0",
    ]
    assert all(KEY not in str(r.url) for r in sent)


async def test_main_exits_nonzero_on_mismatch_without_printing_values_or_ids(capsys):
    db = _db()
    # 이중 쓰기 중 enc 쓰기가 실패해 옛 값이 남은 행 — 백필은 enc 가 있으면 덮지 않으니 검증이 잡아야 한다.
    db["p4"]["kakao_id_enc"] = "kakao-old"
    # 평문은 비웠는데 enc 가 남은 행 — M2 뒤 지운 값이 되살아난다.
    db["p6"]["real_name_enc"] = "유령"
    async with httpx.AsyncClient(transport=_fake(db, [])) as client:
        job = ProfilePrivateEncryptionBackfill("https://x.supabase.co/rest/v1", "service-key", client, KEY)
        code = await main(job, page=2)

    out = capsys.readouterr().out
    assert code != 0
    assert "real_name_mismatch=1" in out.split() and "kakao_id_mismatch=1" in out.split()
    values = {v for row in db.values() for v in row.values() if v} | set(db)
    assert not any(value in out for value in values)
