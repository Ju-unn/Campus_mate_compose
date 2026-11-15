import logging
from datetime import timedelta
from enum import Enum

from google.cloud import vision

from app.core import errors
from app.core.rate_window import SlidingWindow

_logger = logging.getLogger(__name__)

# 사진 검사(Vision) 사람당 24시간 상한 — 온보딩 올리기 · 15-7 교체가 한 몫을 같이 쓴다(새 사진 한 장 = 한 번). 사진을 계속
# 올려 Vision 비용을 키우는 길을 막는다(10-18 보안 점검). 온보딩은 4장이라 다시 고르기를 여러 번 해도 넉넉하다.
# Vision 을 부르기 **직전에** 잡는다 — 부적절 · 문서로 막힌 장도 이미 과금됐으니 센다. 창의 한계(인스턴스별)는 core/rate_window.
PHOTO_CHECK_DAILY_LIMIT = 30
PHOTO_CHECKS = SlidingWindow(PHOTO_CHECK_DAILY_LIMIT, timedelta(hours=24), errors.PHOTO_CHECK_DAILY_LIMIT)

# Vision Likelihood enum: UNKNOWN=0 VERY_UNLIKELY=1 UNLIKELY=2 POSSIBLE=3 LIKELY=4 VERY_LIKELY=5
_REJECT_THRESHOLD = 4  # LIKELY 이상이면 거부(사전 결정, project_slice2_decisions_2026-09-19)

# 문서형 사진(학생증 · 신분증) 거르기 — 사용자 결정 2026-10-16 "B(안내 + 서버 검사)". 아바타 원본으로 쓰면 그림이 이상하다.
# 글자 수는 인식된 전체 글자에서 공백 · 줄바꿈을 뺀 수다. 서버 배포만으로 고칠 수 있게 아래 값만 바꾼다.
# 글자 수만으로 막는 규칙(24자 이상)은 뺐다(사용자 결정 2026-11-15) — 간판 · 포스터 · 현수막이 배경인 평범한 사진이
# 64~130자로 잡혀 가입이 막혔다. 글자만 있는 캡처는 앱의 얼굴 검사가 먼저 거른다.
# 아래 낱말이 있고 글자가 이만큼 되면 문서로 본다(낱말만 찍힌 로고 · 굿즈는 통과).
DOCUMENT_KEYWORD_MIN_CHARS = 8
# 공백 없이 대문자로 적는다 — 인식 글자도 공백을 빼고 대문자로 바꿔 견준다("ID\ncard" 도 IDCARD 로 잡힌다).
# UNIVERSITY · 대학교는 넣지 않는다 — 학교 이름이 박힌 과잠 · 후드 사진이 흔하다.
DOCUMENT_KEYWORDS = (
    "학생증", "신분증", "주민등록", "운전면허", "여권", "외국인등록",
    "STUDENT", "IDCARD", "DRIVER", "PASSPORT",
)
# Vision 이미지 라벨 — 글자가 적게 잡힌 신분증(흐림 · 반사 · 기울기)도 그림 모양으로 잡는다(사용자 질문 10-16 "학생증 · 신분증을 거르면").
# 10-16 실측: 학생증풍 시험 사진이 "Identity document" 0.82 를 받았다. 0.5 는 시작값 — 잘못 막힌 신고가 오면 올린다.
# "Document" · "Paper" · "Paper Product" 는 포스터 · 메뉴판 · 벽지 · 책에도 붙어 넣지 않는다.
DOCUMENT_LABELS = ("Identity document",)
DOCUMENT_LABEL_MIN_SCORE = 0.5
# 라벨은 점수 순으로 잘려 온다(기본 10개) — 얼굴 · 머리 라벨이 많은 사진에서 문서 라벨이 밀려나지 않게 넉넉히 받는다.
_LABEL_MAX_RESULTS = 15


class PhotoVerdict(Enum):
    SAFE = "safe"
    NOT_SAFE = "not_safe"
    DOCUMENT = "document"


# 막힌 사진의 422 본문. 두 업로드 경로(POST /profile-onboarding/photos · PUT /me/photos)가 같이 쓴다.
REJECTION_BODIES = {
    PhotoVerdict.NOT_SAFE: {"detail": errors.PHOTO_NOT_SAFE},
    PhotoVerdict.DOCUMENT: {"detail": errors.PHOTO_LOOKS_LIKE_DOCUMENT, "code": errors.CODE_PHOTO_LOOKS_LIKE_DOCUMENT},
}


async def check_photo(
    vision_client: vision.ImageAnnotatorAsyncClient, image_bytes: bytes, *, source: str
) -> PhotoVerdict:
    """부적절(성인 · 폭력)과 문서형을 Vision 한 요청으로 같이 본다. 기능마다 1건으로 과금된다(글자 인식 · 라벨이 사진당 1건씩 더).
    source 는 거절 로그에 남길 경로 이름(onboarding · me)이다."""
    # 비동기 클라이언트에는 safe_search_detection 편의 메서드가 없다(동기 클라이언트 전용) — 원본 RPC 를 직접 부른다.
    response = await vision_client.batch_annotate_images(
        requests=[
            {
                "image": vision.Image(content=image_bytes),
                "features": [
                    {"type_": vision.Feature.Type.SAFE_SEARCH_DETECTION},
                    {"type_": vision.Feature.Type.TEXT_DETECTION},
                    {"type_": vision.Feature.Type.LABEL_DETECTION, "max_results": _LABEL_MAX_RESULTS},
                ],
            }
        ]
    )
    result = response.responses[0]
    if result.error.message:
        raise RuntimeError(result.error.message)
    # 첫 칸이 인식된 전체 글자다(student_verification/ocr.py 와 같다). 글자가 없으면 빈 목록이다.
    texts = result.text_annotations
    compact = "".join(texts[0].description.split()).upper() if texts else ""
    keyword_rule = len(compact) >= DOCUMENT_KEYWORD_MIN_CHARS and any(word in compact for word in DOCUMENT_KEYWORDS)
    label_rule = any(
        label.description in DOCUMENT_LABELS and label.score >= DOCUMENT_LABEL_MIN_SCORE for label in result.label_annotations
    )
    annotation = result.safe_search_annotation
    if annotation.adult >= _REJECT_THRESHOLD or annotation.violence >= _REJECT_THRESHOLD:
        verdict = PhotoVerdict.NOT_SAFE
    elif keyword_rule or label_rule:
        verdict = PhotoVerdict.DOCUMENT
    else:
        return PhotoVerdict.SAFE
    # 배포 뒤 임계값을 다듬을 재료. 글자 원문 · 라벨 이름 · 점수 · 이미지 · 프로필 id 는 남기지 않는다(COMMON §3) — 수와 참거짓만.
    _logger.warning("사진 거절 verdict=%s chars=%d keyword_rule=%s source=%s label_rule=%s",
                    verdict.value, len(compact), keyword_rule, source, label_rule)
    return verdict
