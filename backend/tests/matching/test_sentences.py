from app.matching.sentences import self_sentence, want_sentence


def test_self_sentence_follows_the_kim_cheolsu_example():
    """설계 §6.7 의 예시 앞 문장은 템플릿이 만들고, 자기소개 원문은 그대로 이어붙인다. MBTI 는 계수로만 비교한다
    (내 MBTI 를 글에 넣으면 상대 "원해" 글에 짝이 없어 잡음이 된다 — 10-28 사용자 결정)."""
    sentence = self_sentence({
        "major": "컴퓨터공학과", "major_field": "engineering", "mbti": "ENFP",
        "animal_type": "dog", "impression_type": "kind",
        "bio": "주말마다 산 타고 내려와서 맛집 찾아다니는 게 낙이에요.",
    })

    assert sentence == (
        "나는 컴퓨터공학과, 공대 계열 학생이다. "
        "얼굴은 강아지상이고 선한 인상이다. "
        "주말마다 산 타고 내려와서 맛집 찾아다니는 게 낙이에요."
    )


def test_self_sentence_skips_missing_pieces():
    """계열 입력 화면이 아직 없고 MBTI 는 '모름'이 허용된다 — 빈 자리는 문장에서 통째로 뺀다."""
    sentence = self_sentence({
        "major": "컴퓨터공학과", "major_field": None, "mbti": None,
        "animal_type": "dog", "impression_type": "kind", "bio": "",
    })

    assert sentence == "나는 컴퓨터공학과 학생이다. 얼굴은 강아지상이고 선한 인상이다."


def test_want_sentence_joins_animal_types_with_korean_particle():
    sentence = want_sentence({
        "preferred_animal_types": ["cat", "fox"],
        "preferred_impression_types": ["chic"],
        "ideal_note": "말이 잘 통하는 사람이 제일 좋아요.",
    })

    assert sentence == "고양이상이나 여우상, 시크한 인상이 좋다. 말이 잘 통하는 사람이 제일 좋아요."


def test_want_sentence_is_empty_when_nothing_was_entered():
    assert want_sentence(
        {"preferred_animal_types": [], "preferred_impression_types": [], "ideal_note": ""}
    ) == ""


def test_want_sentence_joins_impressions_with_or_form_of_the_adjective():
    """"부드러운이나 시크한 인상" 은 틀린 말이다 — 형용사는 "부드럽거나 시크한 인상" 으로 잇는다."""
    sentence = want_sentence({
        "preferred_animal_types": ["dog", "hamster", "wolf"],
        "preferred_impression_types": ["tofu", "chic"],
        "ideal_note": "",
    })

    assert sentence == "강아지상이나 햄스터상이나 늑대상, 부드럽거나 시크한 인상이 좋다."


def test_want_sentence_joins_three_impressions():
    sentence = want_sentence({
        "preferred_animal_types": [], "preferred_impression_types": ["arab", "kind", "innocent"], "ideal_note": "",
    })

    assert sentence == "이국적이거나 선하거나 청순한 인상이 좋다."
