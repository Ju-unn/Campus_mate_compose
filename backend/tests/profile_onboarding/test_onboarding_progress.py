from app.profile_onboarding.onboarding_progress import next_step

_EMPTY_PROFILE = {
    "nickname": None, "phone_set": False, "kakao_id_set": False,
    "photo_count": 0, "has_avatar_source": False, "avatar_ready": False,
    "animal_type": None, "impression_type": None,
    "interest_tags": [], "my_traits": [],
    "survey_answer_count": 0, "religion": None, "is_smoker": None,
    "preferred_age_min": None, "preferred_animal_types": [], "preferred_impression_types": [],
    "ideal_traits": [], "ideal_note": "", "bio": None,
}


def test_next_step_starts_at_basic_info():
    assert next_step(_EMPTY_PROFILE) == "basic_info"


def test_next_step_moves_to_kakao_id_after_basic_info():
    profile = {**_EMPTY_PROFILE, "nickname": "가나", "phone_set": True}
    assert next_step(profile) == "kakao_id"


def test_next_step_moves_from_photos_straight_to_appearance():
    """아바타는 만드는 동안 다음 질문을 이어 가므로(2026-09-25 사용자 결정) 결과 확인이 성향 질문 뒤로 갔다.
    원본 사진 지정은 여전히 photos 단계 조건이다 — 작업 등록은 04-3(photos 의 마지막 화면)에서 한다."""
    profile = {**_EMPTY_PROFILE, "nickname": "가나", "phone_set": True, "kakao_id_set": True}
    assert next_step(profile) == "photos"

    profile = {**profile, "photo_count": 2, "has_avatar_source": True}
    assert next_step(profile) == "appearance_type"


def test_next_step_asks_for_the_avatar_after_the_survey():
    profile = {
        **_EMPTY_PROFILE, "nickname": "가나", "phone_set": True, "kakao_id_set": True,
        "photo_count": 2, "has_avatar_source": True,
        "animal_type": "dog", "impression_type": "kind",
        "interest_tags": ["a", "b", "c"], "my_traits": ["a", "b", "c"],
        "survey_answer_count": 9, "religion": "none", "is_smoker": False,
    }
    # 아직 만드는 중(avatar_ready=False)이면 결과 화면에서 기다린다.
    assert next_step(profile) == "avatar"

    # 이미 아바타가 있는 사람은 이 단계를 지나칠 뿐이다 — 데이터 이관이 없다.
    assert next_step({**profile, "avatar_ready": True}) == "ideal_conditions"


def test_next_step_is_complete_when_everything_filled():
    profile = {
        "nickname": "가나", "phone_set": True, "kakao_id_set": True,
        "photo_count": 2, "has_avatar_source": True, "avatar_ready": True,
        "animal_type": "dog", "impression_type": "kind",
        "interest_tags": ["a", "b", "c"], "my_traits": ["a", "b", "c"],
        "survey_answer_count": 9, "religion": "none", "is_smoker": False,
        "preferred_age_min": 20, "preferred_animal_types": ["cat"], "preferred_impression_types": ["kind"],
        "ideal_traits": ["a", "b", "c"], "ideal_note": "말 잘 통하는 사람", "bio": "안녕하세요",
    }
    assert next_step(profile) == "complete"


def test_next_step_stays_on_ideal_conditions_until_face_and_impression_are_picked():
    """얼굴상·인상은 선택 입력이 아니다(2026-09-20 사용자 결정) — 나이만 저장되면 아직 그 단계다."""
    profile = {
        **_EMPTY_PROFILE, "nickname": "가나", "phone_set": True, "kakao_id_set": True,
        "photo_count": 2, "has_avatar_source": True, "avatar_ready": True,
        "animal_type": "dog", "impression_type": "kind",
        "interest_tags": ["a", "b", "c"], "my_traits": ["a", "b", "c"],
        "survey_answer_count": 9, "religion": "none", "is_smoker": False,
        "preferred_age_min": 20,
    }
    assert next_step(profile) == "ideal_conditions"

    profile = {**profile, "preferred_animal_types": ["cat"], "preferred_impression_types": ["kind"]}
    assert next_step(profile) == "ideal_traits"


def test_next_step_stays_on_ideal_note_until_it_is_written():
    """건너뛰기가 없어졌다 — 빈 글도, 10자 미만도 "아직 안 썼다"로 본다(2026-09-21 사용자 결정)."""
    profile = {
        **_EMPTY_PROFILE, "nickname": "가나", "phone_set": True, "kakao_id_set": True,
        "photo_count": 2, "has_avatar_source": True, "avatar_ready": True,
        "animal_type": "dog", "impression_type": "kind",
        "interest_tags": ["a", "b", "c"], "my_traits": ["a", "b", "c"],
        "survey_answer_count": 9, "religion": "none", "is_smoker": False,
        "preferred_age_min": 20, "preferred_animal_types": ["cat"], "preferred_impression_types": ["kind"],
        "ideal_traits": ["a", "b", "c"],
    }
    assert next_step(profile) == "ideal_note"

    # 9자(공백 뗀 길이)는 저장 기준에 못 미치니 아직 같은 단계다.
    assert next_step({**profile, "ideal_note": "  말이잘통하는사람요  "}) == "ideal_note"

    assert next_step({**profile, "ideal_note": "말 잘 통하는 사람"}) == "bio"
