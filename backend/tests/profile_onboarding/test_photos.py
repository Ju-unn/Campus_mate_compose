from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from google.cloud import vision

from app.profile_onboarding.photos import PhotoVerdict, check_photo


def vision_response(adult: int = 1, violence: int = 1, text: str = "", error_message: str = "") -> SimpleNamespace:
    """batch_annotate_images 의 응답 모양 — 이미지 하나당 responses 한 칸.
    글자가 있으면 text_annotations[0].description 이 인식된 전체 글자다(student_verification/ocr.py 와 같은 모양)."""
    return SimpleNamespace(
        responses=[
            SimpleNamespace(
                error=SimpleNamespace(message=error_message),
                safe_search_annotation=SimpleNamespace(adult=adult, violence=violence),
                text_annotations=[SimpleNamespace(description=text)] if text else [],
            )
        ]
    )


def make_client(adult: int = 1, violence: int = 1, text: str = "", error_message: str = "") -> AsyncMock:
    """spec 을 주지 않으면 없는 메서드까지 만들어 내서 오타·API 불일치를 테스트가 못 잡는다
    (2026-09-25 운영: 비동기 클라이언트에 없는 safe_search_detection 을 불러 500)."""
    client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
    client.batch_annotate_images.return_value = vision_response(adult, violence, text, error_message)
    return client


async def test_check_photo_rejects_likely_adult_content():
    assert await check_photo(make_client(adult=4), b"fake-image-bytes", source="onboarding") is PhotoVerdict.NOT_SAFE  # LIKELY


async def test_check_photo_rejects_likely_violent_content():
    assert await check_photo(make_client(violence=5), b"fake-image-bytes", source="onboarding") is PhotoVerdict.NOT_SAFE  # VERY_LIKELY


async def test_check_photo_accepts_clean_photo():
    client = make_client()  # VERY_UNLIKELY, 글자 없음

    assert await check_photo(client, b"fake-image-bytes", source="onboarding") is PhotoVerdict.SAFE
    client.batch_annotate_images.assert_awaited_once()


async def test_check_photo_raises_on_vision_error():
    # 응답이 비어도 판정 필드는 0(UNKNOWN)이라 그냥 두면 실패한 검사가 "안전"으로 통과한다.
    client = make_client(adult=0, violence=0, error_message="429 quota exceeded")

    with pytest.raises(RuntimeError, match="429 quota exceeded"):
        await check_photo(client, b"fake-image-bytes", source="onboarding")


async def test_check_photo_asks_safe_search_and_text_in_one_request():
    # 요청 수를 늘리지 않는다 — 한 이미지에 기능 두 개를 같이 묻는다(Vision 은 기능마다 1건으로 센다).
    client = make_client()

    await check_photo(client, b"fake-image-bytes", source="onboarding")

    client.batch_annotate_images.assert_awaited_once()
    requests = client.batch_annotate_images.await_args.kwargs["requests"]
    assert len(requests) == 1
    assert {f["type_"] for f in requests[0]["features"]} == {
        vision.Feature.Type.SAFE_SEARCH_DETECTION,
        vision.Feature.Type.TEXT_DETECTION,
    }


# 문서형 사진(학생증 · 신분증 · 글자 많은 캡처) -------------------------------------------------

async def test_check_photo_rejects_a_photo_with_a_lot_of_text():
    text = "가" * 12 + "\n" + "A" * 12  # 공백 · 줄바꿈 빼고 24자

    assert await check_photo(make_client(text=text), b"img", source="onboarding") is PhotoVerdict.DOCUMENT


async def test_check_photo_does_not_count_spaces_and_line_breaks():
    # 23자 사이사이에 공백 22개 + 줄바꿈 — 공백을 세면 24자를 넘어 거절된다.
    text = " ".join("가" * 23) + "\n"

    assert await check_photo(make_client(text=text), b"img", source="onboarding") is PhotoVerdict.SAFE


async def test_check_photo_rejects_a_student_id_keyword_with_a_little_text():
    assert await check_photo(make_client(text="학생증 홍길동 20"), b"img", source="onboarding") is PhotoVerdict.DOCUMENT  # 8자


async def test_check_photo_lets_a_keyword_alone_through():
    assert await check_photo(make_client(text="학생증 홍길동 2"), b"img", source="onboarding") is PhotoVerdict.SAFE  # 7자


async def test_check_photo_matches_english_keywords_in_any_case_and_across_lines():
    # 인식기는 "ID CARD" 를 두 줄로 끊거나 소문자로 줄 수 있다.
    assert await check_photo(make_client(text="Id\ncard 2024"), b"img", source="onboarding") is PhotoVerdict.DOCUMENT
    assert await check_photo(make_client(text="Student 1234"), b"img", source="onboarding") is PhotoVerdict.DOCUMENT
    assert await check_photo(make_client(text="DRIVER LIC"), b"img", source="onboarding") is PhotoVerdict.DOCUMENT


async def test_check_photo_lets_short_text_like_a_tshirt_logo_through():
    assert await check_photo(make_client(text="NIKE"), b"img", source="onboarding") is PhotoVerdict.SAFE
    # 키워드가 없으면 8자를 넘어도 24자 전까지는 통과한다(간판 · 티셔츠 문구).
    assert await check_photo(make_client(text="JUST DO IT\nSEOUL CAFE"), b"img", source="onboarding") is PhotoVerdict.SAFE


async def test_check_photo_keeps_the_unsafe_verdict_first():
    # 부적절하면서 글자도 많은 사진은 종전 문구(부적절)로 막는다.
    client = make_client(adult=5, text="학생증 홍길동 2024 서울대학교 컴퓨터공학과")

    assert await check_photo(client, b"img", source="onboarding") is PhotoVerdict.NOT_SAFE


# 거절 로그 — 배포 뒤 임계값을 다듬을 재료. 글자 원문 · 이미지 · 식별자는 남기지 않는다(COMMON §3) ----------------------

async def test_a_document_rejection_logs_counts_but_not_the_text(caplog):
    text = "학생증 홍길동 20241234"  # 공백 빼고 14자, 키워드 있음

    with caplog.at_level("WARNING", logger="app.profile_onboarding.photos"):
        await check_photo(make_client(text=text), b"img", source="me")

    [record] = caplog.records
    message = record.getMessage()
    assert "verdict=document" in message and "chars=14" in message
    assert "keyword_rule=True" in message and "source=me" in message
    for leak in ("학생증", "홍길동", "20241234"):
        assert leak not in caplog.text


async def test_an_unsafe_rejection_logs_its_verdict_and_a_safe_photo_logs_nothing(caplog):
    with caplog.at_level("INFO", logger="app.profile_onboarding.photos"):
        await check_photo(make_client(text="NIKE"), b"img", source="onboarding")
        assert caplog.records == []
        await check_photo(make_client(adult=5), b"img", source="onboarding")

    [record] = caplog.records
    assert "verdict=not_safe chars=0 keyword_rule=False source=onboarding" in record.getMessage()
