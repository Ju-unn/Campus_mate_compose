from app.profile_onboarding.schemas import IDEAL_NOTE_MIN_LENGTH

# 순서는 DESIGN.md §9 04-1~06-3 화면 순서를 그대로 따른다. 각 단계는 "이 단계까지 끝났다"는 최소 조건만 본다
# — 태그 개수 3~5 같은 상세 규칙은 저장 시점(Task B9 각 엔드포인트)에서 tags.validate_tag_selection 이 본다.
_STEPS = [
    ("basic_info", lambda p: p["nickname"] and p["phone_set"]),
    ("kakao_id", lambda p: p["kakao_id_set"]),
    ("photos", lambda p: p["photo_count"] >= 2 and p["has_avatar_source"]),
    ("appearance_type", lambda p: p["animal_type"] and p["impression_type"]),
    ("interests", lambda p: len(p["interest_tags"]) >= 3),
    ("my_traits", lambda p: len(p["my_traits"]) >= 3),
    ("survey", lambda p: p["survey_answer_count"] >= 9 and p["religion"] is not None and p["is_smoker"] is not None),
    ("ideal_conditions", lambda p: p["preferred_age_min"] is not None
        and p["preferred_animal_types"] and p["preferred_impression_types"]),
    ("ideal_traits", lambda p: len(p["ideal_traits"]) >= 3),
    # 최소 10자(2026-09-21 사용자 결정) — 저장 기준과 같아야 짧은 글로 넘어간 사람이 다시 이 단계로 돌아온다.
    ("ideal_note", lambda p: len((p["ideal_note"] or "").strip()) >= IDEAL_NOTE_MIN_LENGTH),
    ("bio", lambda p: p["bio"]),
    # 아바타 확인은 가입 맨 끝(06-3 뒤 · 20 앞)이다(2026-10-17 사용자 결정, 종전 09-25 "설문 뒤").
    # 만드는 동안 06-1 ~ 06-3 을 막지 않고, ready 행(5회 실패 보상의 기본 아바타 포함)이 생기면 끝난다.
    # 작업 등록은 여전히 04-3(photos 의 마지막 화면)에서 한다 — 여기서는 결과만 본다.
    ("avatar", lambda p: p["avatar_ready"]),
]


def next_step(profile: dict) -> str:
    for step_name, is_done in _STEPS:
        if not is_done(profile):
            return step_name
    return "complete"
