import base64
import logging
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Literal
from uuid import UUID, uuid4

import httpx
from openai import AsyncOpenAI

from app.profile_onboarding.hearts import grant_hearts
from app.profile_onboarding.storage import AvatarStorage
from app.settings import Settings
from app.student_verification.image_validation import student_id_content_type

_logger = logging.getLogger(__name__)

# "5회 연속 실패 → 기본 아바타+하트10"(project_slice2_decisions_2026-09-19). SDK 자체 재시도는 끄고
# (max_retries=0, get_openai_client 참고) 이 숫자는 우리 코드가 직접 센다 — SDK 재시도와 겹치면 안 된다
# (2026-09-20 사용자 결정).
MAX_CONSECUTIVE_FAILURES = 5

# 5회째 실패에 얹어 주는 보상 하트(project_slice2_decisions_2026-09-19). 앱에 숫자를 박지 않고
# 서버가 준 값을 그대로 쓰게 응답에도 같이 싣는다.
FALLBACK_COMPENSATION_HEARTS = 10

# "만드는 중" 이 이보다 오래 남아 있으면 죽은 작업으로 본다(계획서 "10분 기준선").
# 워커가 통째로 죽거나(배포 재시작·OOM) 큐가 240초에 요청을 끊으면 CancelledError 는 BaseException 이라
# 워커 안에서 못 잡는다 — 이 정리가 유일한 복구 길이다. **POST 와 상태 조회가 같은 값을 본다.**
# 둘이 어긋나면 "조회는 실패라는데 POST 는 아직 만드는 중이라고 튕기는" 잠긴 상태가 생긴다.
STALE_PENDING_AFTER = timedelta(minutes=10)

# 화풍 기준 그림 1장을 같이 보낸다(2026-09-25 사용자 결정 B) — 지시문만으로는 "옷·머리·배경은 그대로,
# 얼굴만 단순화" 하는 블라인드 아바타 화풍(frontend/docs/DESIGN.md §5.2)이 나오지 않았다(운영 00019).
# 원본은 design/designMaterials/person-f3-blind-v1.png 로, 실사진과 구도가 같고 덧붙인 손동작·소품이 없다.
# 모델이 입력을 짧은 변 512px 로 줄여 보므로 1122x1402 원본은 과하다 — 1024x1280 JPEG(품질 90)로 다시
# 저장해 2.3MB 를 286KB 로 줄였다. 요청마다 같이 올라가는 파일이라 작을수록 낫다.
# 파일이 없으면 import 에서 바로 터진다 — 배포 이미지에 안 들어간 것을 요청마다 실패로 알아채는 것보다 낫다.
_STYLE_REFERENCE_BYTES = (Path(__file__).parent / "avatar_style_reference.jpg").read_bytes()

# 모델이 가장 잘 따르는 언어라 영어로 적는다. 두 장을 보내므로 "두 번째는 화풍 참고일 뿐" 을 먼저 못박는다.
# 금지 목록은 운영 00019 결과에서 실제로 나온 어긋남이다 — 단색 배경으로 교체, 옷 교체, 감은 초승달 눈에
# 이가 다 보이는 웃음, 정사각형 크롭. 원본 표정이 어떻든 기준 그림의 차분한 표정으로 통일한다.
_STYLE_PROMPT = (
    "You are given two images. The FIRST image is the user photo to redraw. The SECOND image is a "
    "style reference only: never copy its person, face, hairstyle, clothing, background or props.\n"
    "Redraw the first photo in the style of the second image. Keep from the first photo: the same "
    "vertical framing and crop, the same head position and pose, the same background scene, the "
    "same clothes and their colour, the same hair shape and hair colour, and the same accessories "
    "such as earrings or glasses. Repaint the background, the clothes and the hair as a flat gouache "
    "and watercolour illustration on paper texture, with soft muted colours and visible brush "
    "texture.\n"
    "Simplify only the face, exactly like the reference: a round face with a thick dark brown "
    "outline, two tall black oval dots for open eyes, one small dot for the nose, one small closed "
    "curved smile, round pink blush patches with two or three hatch lines, short simple eyebrows "
    "and simple ears. Keep the person's own skin tone, gender presentation and facial hair from "
    "the first photo. Draw that same calm expression no matter how the person is smiling in the "
    "photo.\n"
    "Never do any of these: replace the background with a flat single colour or an empty studio "
    "backdrop; change or recolour the clothes; crop to a square; draw closed crescent eyes, a wide "
    "open mouth, teeth or an exaggerated grin; draw realistic eyes, nose, mouth or skin texture; "
    "use glossy flat-vector clipart shading; add hands, gestures, props, text, watermark, logo or "
    "frame."
)


@dataclass(frozen=True)
class AvatarResult:
    status: Literal["ready", "failed"]
    storage_path: str | None
    is_final_failure: bool = False


class AvatarGenerator:
    """실패 횟수는 프로세스 안 dict 로 세지 않고 profile_avatars 테이블의 최근 연속 failed 행 개수로
    센다(재배포·다중 인스턴스에도 카운트가 유지되도록) — 아래 failure_counts 인자는 그 카운트를 호출부가
    미리 조회해 넘겨주는 자리다(테스트를 위한 의존성 주입, 실제 조회는 avatars_repository.py 몫)."""

    def __init__(self, openai_client: AsyncOpenAI, storage, failure_counts: dict[str, int]):
        self._openai_client = openai_client
        self._storage = storage
        self._failure_counts = failure_counts

    async def generate(self, profile_id: str, source_photo_bytes: bytes) -> AvatarResult:
        try:
            # 맨 bytes 를 넘기면 SDK 가 파일명·타입 없이 application/octet-stream 으로 보내 OpenAI 가 400 을 낸다 —
            # 업로드 때 쓰는 매직바이트 판별기를 그대로 쓴다. 판별이 안 되면 어차피 400 이라 아래 실패로 센다.
            content_type = student_id_content_type(source_photo_bytes)
            if content_type is None:
                raise ValueError("아바타 원본 사진의 형식을 알 수 없다")
            response = await self._openai_client.images.edit(
                model="gpt-image-1",
                image=[
                    (f"source.{content_type.removeprefix('image/')}", source_photo_bytes, content_type),
                    ("style-reference.jpg", _STYLE_REFERENCE_BYTES, "image/jpeg"),
                ],
                prompt=_STYLE_PROMPT,
                # 원본의 구도·옷·머리·액세서리를 그대로 두는 것이 이 기능의 전부다. 두 장 모두에 걸리므로
                # 첫 결과에서 기준 그림의 단발·벚꽃 같은 요소가 새어 나오면, 다음 손잡이는 기준 그림을
                # 얼굴 위주로 잘라 넣는 것이다 — low 로 내리지는 말 것(원본 유지가 통째로 무너진다).
                input_fidelity="high",
                # 표시용 사진은 전부 세로 4:5 다(DESIGN §5.2) — 지원되는 비율 중 가장 가까운 세로를 고른다.
                # 비용은 늘어난다 — 00019 는 정사각 high(약 $0.167)로 나왔는데 세로 high 는 약 $0.25 고,
                # input_fidelity=high 가 입력 이미지마다 토큰을 더 물려 2장이면 약 +$0.12 다. 장당 약
                # $0.17 → 약 $0.37 로 두 배쯤 된다(공개 가격표 기준 추정, 실청구는 아직 확인 못 했다).
                # quality 를 medium 으로 내리면 출력값은 1/4 이지만 머리카락·종이 질감이 뭉개진다.
                size="1024x1536",
                quality="high",
            )
            image_bytes = base64.b64decode(response.data[0].b64_json)
        except Exception:
            _logger.exception("아바타 생성 실패 — profile_id=%s", profile_id)
            self._failure_counts[profile_id] = self._failure_counts.get(profile_id, 0) + 1
            is_final = self._failure_counts[profile_id] >= MAX_CONSECUTIVE_FAILURES
            return AvatarResult(status="failed", storage_path=None, is_final_failure=is_final)

        self._failure_counts[profile_id] = 0
        path = f"{profile_id}/{uuid4()}.png"
        storage_path = await self._storage.upload(path, image_bytes, "image/png")
        return AvatarResult(status="ready", storage_path=storage_path)


async def apply_fallback_avatar(
    repo, storage: AvatarStorage, settings: Settings, client: httpx.AsyncClient, profile_id: UUID
) -> str:
    """5회 연속 실패 보상: 기본 아바타 복사 → `is_fallback` 행 insert → 하트 10. 복사한 경로를 돌려준다.

    **부르는 자리가 둘이다** — 워커가 5번째 생성에 실패했을 때, 그리고 POST 가 10분 정리 뒤 카운트 5 를
    봤을 때. 두 자리에 같은 순서를 적으면 한쪽만 고쳐질 것이고, 그건 하트가 두 번 나가거나 안 나가는
    길이다. 마지막 실패 행은 지우지 않는다 — 이력이 그대로 남아야 한다(행 두 줄).

    라우터가 아니라 여기 있는 이유는, 두 라우터 중 한쪽에 두면 다른 쪽이 라우터를 import 하게 되기
    때문이다. 협력자는 인자로 받는다(`AvatarGenerator` 와 같은 방식).
    """
    fallback_path = await storage.copy_fallback_avatar(profile_id)
    await repo.insert_avatar_attempt(profile_id, "ready", fallback_path, is_fallback=True)
    try:
        await grant_hearts(
            settings.postgrest_url, settings.supabase_service_role_key, client,
            profile_id=profile_id, amount=FALLBACK_COMPENSATION_HEARTS, reason="admin_adjust",
        )
    except httpx.HTTPError:
        # 하트를 못 줘도 기본 아바타 행은 **이미 들어갔다**. 여기서 터뜨리면 앱은 500 을 받고, 사람은
        # 다시 눌러도 409(이미 ready)라 영영 못 빠져나온다 — 화면만 "하트를 드렸어요" 라고 말한다.
        # 로그를 남기고 넘어간다(실명·사진 경로는 남기지 않는다 — profile_id 로 손으로 보정한다).
        _logger.exception("보상 하트 지급 실패 — 사람이 보정해야 한다 profile_id=%s", profile_id)
    return fallback_path


def get_openai_client(api_key: str) -> AsyncOpenAI:
    # max_retries=0 — SDK 자체 재시도를 끄고, 실패 카운트는 AvatarGenerator 가 직접 센다(2026-09-20 결정).
    return AsyncOpenAI(api_key=api_key, max_retries=0)
