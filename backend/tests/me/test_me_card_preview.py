"""15-4 남이 보는 내 프로필(GET /me/card-preview). 10b · 14c 와 같은 몸통, 수락 뒤 공개 값은 없다."""
import json

import httpx

from tests.me.test_me_profile import AUTH_HEADERS, PROFILE_ID, SUPABASE_URL, _wire, overrides  # noqa: F401

# 10b 카드 상세에서 card_id 만 빠진 키 — 14c 는 여기에 match_id 를 더한다(tests/safety/test_profile_detail.py).
DETAIL_KEYS = {
    "profile", "survey", "animal_type", "impression_type", "religion", "is_smoker",
    "interests", "my_traits", "ideal_traits", "height_cm", "mbti", "student_number", "bio", "ideal_note",
}

MY_ROW = {
    "id": PROFILE_ID, "nickname": "하늘", "birth_year": 2003, "major": "컴퓨터공학과",
    "animal_type": "fox", "impression_type": "kind",
    "interest_tags": ["카페가기", "여행", "요리"], "my_traits": ["긍정적인", "성실한", "차분한"],
    "ideal_traits": ["다정한", "연락 잘하는", "솔직한"], "ideal_note": "산책 좋아하는 사람",
    "bio": "주말엔 산책해요", "status": "active", "auto_hidden_at": None,
    "universities": {"name": "서울대학교"},
    "profile_avatars": [
        {"storage_path": f"{PROFILE_ID}/old.png", "status": "ready", "created_at": "2026-09-20T10:00:00+00:00"},
        {"storage_path": f"{PROFILE_ID}/new.png", "status": "ready", "created_at": "2026-09-25T10:00:00+00:00"},
    ],
    "height_cm": 178, "mbti": "ENFP", "student_number": "22", "religion": "none", "is_smoker": False,
    # select 가 이 칸들을 달라고 하지 않지만, 행에 섞여 와도 응답에 새면 안 된다.
    "kakao_id": "sky_kakao",
    "profile_photos": [{"storage_path": f"{PROFILE_ID}/real.jpg", "position": 0}],
}
# 5번 축은 답이 없다 — 0 으로 채워진다.
SURVEY_ROWS = [{"axis": axis, "value": axis / 10} for axis in (1, 2, 3, 4, 6, 7, 8, 9)]


def _handler(seen: list[httpx.Request]):
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.method == "GET" and request.url.path.endswith("/profiles") \
                and request.url.params.get("id") == f"eq.{PROFILE_ID}":
            return httpx.Response(200, json=[MY_ROW])
        if request.method == "GET" and request.url.path.endswith("/survey_answers") \
                and request.url.params.get("profile_id") == f"eq.{PROFILE_ID}":
            return httpx.Response(200, json=SURVEY_ROWS)
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})
    return handler


def _get(seen: list[httpx.Request] | None = None, verification: str = "verified") -> httpx.Response:
    return _wire(_handler([] if seen is None else seen), verification).get("/me/card-preview", headers=AUTH_HEADERS)


def test_preview_is_the_card_detail_body_of_my_row():
    response = _get()

    assert response.status_code == 200
    assert response.json() == {
        "profile": {
            "profile_id": PROFILE_ID, "nickname": "하늘", "age": 24, "university": "서울대학교",
            "major": "컴퓨터공학과",
            "avatar_url": f"{SUPABASE_URL}/storage/v1/object/public/avatars/{PROFILE_ID}/new.png",
        },
        "survey": [0.1, 0.2, 0.3, 0.4, 0.0, 0.6, 0.7, 0.8, 0.9],
        "animal_type": "fox", "impression_type": "kind", "religion": "none", "is_smoker": False,
        "interests": ["카페가기", "여행", "요리"], "my_traits": ["긍정적인", "성실한", "차분한"],
        "ideal_traits": ["다정한", "연락 잘하는", "솔직한"],
        "height_cm": 178, "mbti": "ENFP", "student_number": "22",
        "bio": "주말엔 산책해요", "ideal_note": "산책 좋아하는 사람",
    }


def test_preview_never_carries_what_opens_only_after_both_accept():
    seen: list[httpx.Request] = []
    response = _get(seen)
    body = response.json()

    # 404 본문으로 빈손 통과하지 않게 200 과 키 모양부터 본다.
    assert response.status_code == 200 and set(body) == DETAIL_KEYS
    # 실사진 · 카카오톡 아이디는 서로 수락한 뒤에만 공개된다(14c 게이트) — 값도 키도 없다.
    dumped = json.dumps(body, ensure_ascii=False)
    assert "sky_kakao" not in dumped and "real.jpg" not in dumped
    assert not any(word in key for key in body for word in ("kakao", "photo", "phone", "real_name"))
    # 사진 서명도, 연락처 칸 조회도 하지 않는다.
    assert not [r for r in seen if "/object/sign/" in r.url.path]
    select = next(r for r in seen if r.url.path.endswith("/profiles")).url.params["select"]
    assert "kakao" not in select and "profile_photos" not in select and "profile_private" not in select


def test_preview_rejects_unverified_student():
    assert _get(verification="pending").status_code == 403
