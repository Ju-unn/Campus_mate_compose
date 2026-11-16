"""아바타 원본 얼굴 기준 자르기 — 설계 docs/superpowers/specs/2026-11-16-avatar-face-framing-design.md 6절."""
import asyncio
import io
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from google.cloud import vision
from PIL import Image

from app.profile_onboarding import face_framing
from app.profile_onboarding.face_framing import FACE_CENTER_Y, FACE_HEIGHT_RATIO, MAX_TOP_PAD, crop_box, frame_on_face

# 전신 사진 속 작은 얼굴(1080×1440 안 높이 120) — 자른 높이는 120 ÷ FACE_HEIGHT_RATIO, 폭은 그 2/3(반올림으로 ±1).
_SMALL_FACE = (490, 200, 590, 320)
_CROP_HEIGHT = round(120 / FACE_HEIGHT_RATIO)


def _jpeg(size: tuple[int, int], exif_orientation: int | None = None, top_color: str | None = None) -> bytes:
    buffer = io.BytesIO()
    exif = Image.Exif()
    if exif_orientation:
        exif[274] = exif_orientation
    image = Image.new("RGB", size, "gray")
    if top_color:
        image.paste(Image.new("RGB", (size[0], 40), top_color), (0, 0))
    image.save(buffer, "JPEG", exif=exif)
    return buffer.getvalue()


def _face(box: tuple[int, int, int, int], confidence: float = 0.9) -> SimpleNamespace:
    left, top, right, bottom = box
    vertices = [SimpleNamespace(x=x, y=y) for x, y in ((left, top), (right, top), (right, bottom), (left, bottom))]
    return SimpleNamespace(detection_confidence=confidence, bounding_poly=SimpleNamespace(vertices=vertices))


def _client(*faces: SimpleNamespace, error_message: str = "") -> AsyncMock:
    # spec 을 준다 — 없는 메서드를 부르면 시험이 잡는다(test_photos.py 와 같은 이유).
    client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
    client.batch_annotate_images.return_value = SimpleNamespace(
        responses=[SimpleNamespace(error=SimpleNamespace(message=error_message), face_annotations=list(faces))]
    )
    return client


def _size(data: bytes) -> tuple[int, int]:
    return Image.open(io.BytesIO(data)).size


def _assert_crop_size(data: bytes) -> None:
    width, height = _size(data)
    assert height == _CROP_HEIGHT
    assert abs(width - _CROP_HEIGHT * 2 / 3) <= 1


# --- 상자 계산 ---------------------------------------------------------------


def test_small_face_in_a_full_body_photo_gets_the_head_and_shoulders_box():
    left, top, right, bottom = crop_box((1080, 1440), _SMALL_FACE)

    assert (right - left) / (bottom - top) == pytest.approx(2 / 3, abs=0.01)
    assert 120 / (bottom - top) == pytest.approx(FACE_HEIGHT_RATIO, abs=0.01)
    assert (260 - top) / (bottom - top) == pytest.approx(FACE_CENTER_Y, abs=0.01)
    assert (left + right) / 2 == pytest.approx(540, abs=1)


@pytest.mark.parametrize(
    ("face", "edge", "expected"),
    [
        ((0, 600, 100, 720), 0, 0),  # 왼쪽 끝 얼굴 → left == 0
        ((1000, 600, 1080, 720), 2, 1080),  # 오른쪽 끝 얼굴 → right == 그림 폭
        ((490, 1300, 590, 1420), 3, 1440),  # 아래쪽 끝 얼굴 → bottom == 그림 높이
    ],
)
def test_a_face_at_an_edge_keeps_the_box_inside_the_photo(face, edge, expected):
    # 상자가 밖으로 나가면 Pillow 가 그 칸을 검정 띠로 채운다 — 크기는 그대로 두고 안으로 민다.
    box = crop_box((1080, 1440), face)

    assert box[edge] == expected
    assert box[0] >= 0 and box[2] <= 1080 and box[3] <= 1440


def test_a_head_at_the_top_edge_gets_empty_space_above_up_to_the_limit():
    # 머리가 사진 위 끝에 붙은 전신 사진(11-16 운영) — 위를 비워서라도 얼굴을 내린다. 한도를 넘게는 비우지 않는다.
    _, top, _, bottom = crop_box((789, 1993), (293, 0, 514, 258))

    assert top < 0
    assert -top <= MAX_TOP_PAD * (bottom - top) + 1


def test_a_big_selfie_face_uses_the_largest_box_that_fits():
    # 더 넓게 볼 화소가 없다 — 그림 높이를 다 쓰는 2:3 상자를 얼굴 쪽으로 옮기고, 위를 비우지 않는다.
    assert crop_box((1080, 1350), (290, 300, 790, 900)) == (90, 0, 990, 1350)


def test_no_crop_when_the_box_is_the_whole_photo():
    assert crop_box((1000, 1500), (250, 120, 750, 1020)) is None


def test_no_crop_for_a_tiny_face():
    # 얼굴 높이 20 → 자른 높이 80. 그만큼 작은 그림을 생성기에 넘기지 않고 원본을 쓴다.
    assert crop_box((1440, 1920), (700, 900, 720, 920)) is None


# --- frame_on_face -------------------------------------------------------------


async def test_crops_around_the_largest_confident_face():
    # 가장 큰 얼굴을 가운데 둔다 — "처음" 이나 "마지막" 얼굴을 고르는 구현은 작은 얼굴을 집어 원본을 돌려준다.
    client = _client(
        _face((10, 10, 40, 40)), _face(_SMALL_FACE), _face((900, 10, 930, 40)),
        _face((0, 0, 900, 900), confidence=0.2),
    )

    framed = await frame_on_face(lambda: client, _jpeg((1080, 1440)))

    _assert_crop_size(framed)


async def test_sends_the_upright_picture_to_vision():
    # 저장은 가로(1440×1080)지만 EXIF 6 이라 세워진 그림은 1080×1440 이다 — Vision 좌표가 이 방향이어야 한다.
    client = _client(_face(_SMALL_FACE))

    framed = await frame_on_face(lambda: client, _jpeg((1440, 1080), exif_orientation=6))

    sent = client.batch_annotate_images.call_args.kwargs["requests"][0]["image"].content
    assert _size(sent) == (1080, 1440)
    _assert_crop_size(framed)


async def test_fills_the_space_above_the_head_with_the_top_color():
    client = _client(_face((490, 0, 590, 120)))

    framed = await frame_on_face(lambda: client, _jpeg((1080, 1440), top_color="red"))

    red, green, blue = Image.open(io.BytesIO(framed)).getpixel((5, 2))
    assert red > 200 and green < 60 and blue < 60


@pytest.mark.parametrize(
    "client",
    [
        _client(),  # 얼굴 없음
        _client(_face(_SMALL_FACE, confidence=0.3)),  # 확신 낮음
        _client(error_message="quota"),  # Vision 이 오류를 돌려줌
    ],
)
async def test_returns_the_original_bytes_when_there_is_nothing_to_frame(client):
    photo = _jpeg((1080, 1440))

    assert await frame_on_face(lambda: client, photo) is photo


async def test_returns_the_original_bytes_when_vision_raises():
    client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
    client.batch_annotate_images.side_effect = TimeoutError()
    photo = _jpeg((1080, 1440))

    assert await frame_on_face(lambda: client, photo) is photo


async def test_returns_the_original_bytes_when_vision_does_not_answer(monkeypatch):
    # 라이브러리 기본 재시도는 최대 600초까지 다시 부른다 — 전체 시간을 묶지 않으면 워커가 240초에 끊긴다.
    monkeypatch.setattr(face_framing, "_VISION_TIMEOUT_SECONDS", 0.05)
    client = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)

    async def never_answers(*_args, **_kwargs):
        await asyncio.Event().wait()

    client.batch_annotate_images.side_effect = never_answers
    photo = _jpeg((1080, 1440))

    assert await asyncio.wait_for(frame_on_face(lambda: client, photo), 2) is photo


async def test_returns_the_original_bytes_when_the_client_cannot_be_made():
    def broken():
        raise RuntimeError("no credentials")

    photo = _jpeg((1080, 1440))

    assert await frame_on_face(broken, photo) is photo


async def test_does_not_call_vision_for_bytes_that_are_not_a_picture():
    client = _client(_face(_SMALL_FACE))

    assert await frame_on_face(lambda: client, b"not-an-image") == b"not-an-image"
    client.batch_annotate_images.assert_not_awaited()
