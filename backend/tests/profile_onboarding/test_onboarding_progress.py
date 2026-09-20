from app.profile_onboarding.onboarding_progress import next_step

_EMPTY_PROFILE = {
    "nickname": None, "phone_set": False, "kakao_id_set": False,
    "photo_count": 0, "has_avatar_source": False, "avatar_ready": False,
    "animal_type": None, "impression_type": None,
    "interest_tags": [], "my_traits": [],
    "survey_answer_count": 0, "religion": None, "is_smoker": None,
    "preferred_age_min": None, "preferred_animal_types": [], "preferred_impression_types": [],
    "ideal_traits": [], "ideal_note_seen": False, "bio": None,
}


def test_next_step_starts_at_basic_info():
    assert next_step(_EMPTY_PROFILE) == "basic_info"


def test_next_step_moves_to_kakao_id_after_basic_info():
    profile = {**_EMPTY_PROFILE, "nickname": "가나", "phone_set": True}
    assert next_step(profile) == "kakao_id"


def test_next_step_moves_through_photos_avatar_appearance():
    profile = {**_EMPTY_PROFILE, "nickname": "가나", "phone_set": True, "kakao_id_set": True}
    assert next_step(profile) == "photos"

    profile = {**profile, "photo_count": 2, "has_avatar_source": True}
    assert next_step(profile) == "avatar"

    profile = {**profile, "avatar_ready": True}
    assert next_step(profile) == "appearance_type"


def test_next_step_is_complete_when_everything_filled():
    profile = {
        "nickname": "가나", "phone_set": True, "kakao_id_set": True,
        "photo_count": 2, "has_avatar_source": True, "avatar_ready": True,
        "animal_type": "dog", "impression_type": "kind",
        "interest_tags": ["a", "b", "c"], "my_traits": ["a", "b", "c"],
        "survey_answer_count": 9, "religion": "none", "is_smoker": False,
        "preferred_age_min": 20, "preferred_animal_types": [], "preferred_impression_types": [],
        "ideal_traits": ["a", "b", "c"], "ideal_note_seen": True, "bio": "안녕하세요",
    }
    assert next_step(profile) == "complete"
