from app.matching.sentences import self_sentence, want_sentence


def test_self_sentence_follows_the_kim_cheolsu_example():
    """설계 §6.7 의 예시 앞 3문장은 템플릿이 만들고, 자기소개 원문은 그대로 이어붙인다."""
    sentence = self_sentence({
        "major": "컴퓨터공학과", "major_field": "engineering", "mbti": "ENFP",
        "animal_type": "dog", "impression_type": "kind",
        "bio": "주말마다 산 타고 내려와서 맛집 찾아다니는 게 낙이에요.",
    })

    assert sentence == (
        "나는 컴퓨터공학과, 공대 계열 학생이다. MBTI는 ENFP다. "
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
