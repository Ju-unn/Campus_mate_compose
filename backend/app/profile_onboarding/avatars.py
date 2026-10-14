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

# 아바타 다시 만들기 값(최초 1회 무료). 2026-10-14 사용자 피드백 6 으로 20하트(종전 spec "아바타 재생성 10하트").
# 위 5회 실패 보상 하트와는 따로 정한 값이다 — 하나를 바꿔도 다른 쪽은 그대로다.
AVATAR_REGEN_HEARTS = 20


def avatar_regen_cost(ready_count: int) -> int:
    """지금까지 완성된(ready) 아바타 수로 이번 한 장의 값을 정한다(ERD 12줄 — 무료 여부는 성공 건수로 센다).

    0 은 온보딩 첫 생성이라 무료, 1 은 "최초 1회 무료" 다시 만들기, 그 뒤로 AVATAR_REGEN_HEARTS. 기본 아바타(is_fallback)도
    한 장으로 센다 — 05-12d 가 "다시 만들 수 있어요" 라고 약속한 그 한 번이다. 실패는 세지 않으니 무료 차례에
    실패하면 다음에도 무료다. GET /me/profile · POST 다시 만들기 · 워커가 **이 함수 하나**를 본다."""
    return 0 if ready_count <= 1 else AVATAR_REGEN_HEARTS

# "만드는 중" 이 이보다 오래 남아 있으면 죽은 작업으로 본다(계획서 "10분 기준선").
# 워커가 통째로 죽거나(배포 재시작·OOM) 큐가 240초에 요청을 끊으면 CancelledError 는 BaseException 이라
# 워커 안에서 못 잡는다 — 이 정리가 유일한 복구 길이다. **POST 와 상태 조회가 같은 값을 본다.**
# 둘이 어긋나면 "조회는 실패라는데 POST 는 아직 만드는 중이라고 튕기는" 잠긴 상태가 생긴다.
STALE_PENDING_AFTER = timedelta(minutes=10)

# 화풍 참고 그림 1장을 같이 보낸다(2026-09-25 사용자 결정 B) — 지시문만으로는 원하는 화풍이 나오지 않았다(운영 00019).
# 참고 그림은 frontend/assets/images/person-f1-blind-v1.png(목표 그림)를 1024x1280 JPEG(품질 90)로 줄인 것이다
# (2.4MB → 약 326KB). 요청마다 같이 올라가는 파일이라 작을수록 낫다. 프롬프트 v2-8 시험이 이 파일로 돌았다.
# 파일이 없으면 import 에서 바로 터진다 — 배포 이미지에 안 들어간 것을 요청마다 실패로 알아채는 것보다 낫다.
_STYLE_REFERENCE_BYTES = (Path(__file__).parent / "avatar_style_reference.jpg").read_bytes()

# 2026-10-14 사용자 결정: 점·선 얼굴 + 선명한 화풍(v2-8). 참고 그림은 화풍만 참고하고, 배경은 첫 사진 것만 쓴다
# (v2-7 시험에서 실내·단색 배경 사진 4장이 모두 참고 그림의 계단·벚꽃·건물로 바뀌었다). 머리말(PREAMBLE)이
# 이미지 역할을 정하고(첫 장 = 변환할 사진, 둘째 장 = 화풍 참고일 뿐 내용·배경 복사 금지) 본문(MAIN)이 화풍을 정한다.
# 두 문자열은 시험한 문구를 그대로 옮겼다 — 고치면 다시 시험한다(해시는 test_avatars.py 가 고정).
# 시험 기록(결과·v2-7 → v2-8 변경 요약)은 저장소 밖 출시준비/아바타_시험_1013/v3/프롬프트_v3.md 10절이다.
_STYLE_PROMPT_PREAMBLE = (
    "You are given two images. The FIRST image is the user photo to transform. The SECOND image is a "
    "STYLE reference only. Copy only its way of drawing: the face (flat skin, tiny dot nose, small oval "
    "eyes, thin short eyebrows, thin curved smile, soft blush circles with a few tiny strokes, and a "
    "partial thin dark-brown outline only around the face, neck and collar), its crisp, detailed hair, "
    "its knit and fabric texture, and its clean, sharp illustrated look. NEVER use its content: not its "
    "person, identity, hairstyle or clothing, and NEVER its scenery, background, buildings, trees, "
    "stairs, lamp posts, cherry blossoms, sky or the colors of its setting. Recreate ONLY the FIRST "
    "image's own person, hairstyle, outfit, pose, background and setting.\n\n"
)

_STYLE_PROMPT_MAIN = (
    "Transform the provided photo into a clean, crisp, high-clarity digital 2D illustration with "
    "smooth flat fills and finely detailed linework and shading, matching the visual style of the "
    "reference illustration: a deliberately simple dot-and-line face placed on an intricately drawn head of "
    "hair, detailed clothing and a sharply drawn background. This is NOT a painting: no watercolor, no gouache, no oil-paint or brush-stroke look, no painterly blur.\n\n"
    "**1. Face: only dots and lines**\n"
    "Draw the face with dots and lines only. The skin is one flat, even, clean light peach color (not orange, not yellow) with "
    "no texture, no grain, no shading, no shadow and no gradient. Eyes: two small solid black vertical ovals "
    "(matte, no highlights). Nose: the nose is a single tiny round dot like a period, exactly as in the reference illustration; never a line, curve, hook or nostril. Mouth: one thin gentle curved line forming a small "
    "smile. Eyebrows: short thin brown lines. Cheeks: two round soft pink blush circles, each with "
    "two or three short thin lines inside. Ears: simple rounded shapes with a pink inner part. Use a "
    "thin, dark-brown, slightly broken outline ONLY around the face, neck and collar edges. Do not "
    "draw any outline around the hair or the background.\n\n"
    "**2. Keep the person recognizable**\n"
    "Preserve the original person's gender, hairstyle, hair length, hair color, bangs, parting, "
    "glasses, moles or freckles (as tiny dots) and other recognizable traits. Quietly keep the "
    "person's face proportions (face width versus height, how far apart the eyes sit, how high or low they sit), the spacing and angle of the eyes, the shape and thickness of the "
    "eyebrows, the face shape and the smile character, expressed through the same simple dots and "
    "lines. Do not add realistic facial detail, so the person is recognizable as a charming simplified "
    "drawing, not as a portrait.\n\n"
    "**3. Hair: rich, individually drawn texture**\n"
    "Keep the original hairstyle, volume and silhouette. Draw the hair as many fine individual "
    "strands with thin lines, in layered clumps with subtle soft highlights and a light sheen along the strands, a few stray flyaway "
    "hairs at the crown and edges, and see-through bangs where individual strands are visible over "
    "the forehead. The hair must look richly textured, crisp and dimensional, never flat, smooth, "
    "blurry or a single solid mass.\n\n"
    "**4. Clothing and material texture**\n"
    "Preserve the original outfit exactly: color, shape, neckline, collar, folds, buttons and "
    "patterns. Render the fabric sharply with clearly visible texture: knitwear with distinct ribbing "
    "and stitch rows, woven fabrics with fine weave marks, soft folds and gentle shading in "
    "collars and sleeves, and clearly drawn buttons and seams. Clothing must be vivid and "
    "well-defined, not washed out or blurred.\n\n"
    "**5. Background: the first photo's own background, clean and sharp**\n"
    "Recreate the FIRST photo's actual background in the same positions, composition, camera angle, "
    "perspective and colors, simplified into the same clean, crisp illustrated style: for example an "
    "indoor shop with shelves, plants and posters, a plain studio wall, a dark blurred setting, or "
    "shop shelves, or an outdoor campus with its own trees and buildings, whatever the photo really "
    "shows. A plain solid-color background stays a plain solid color, and a blurred or dark "
    "background stays blurred or dark, only simplified and cleaned. Do NOT invent buildings, trees, "
    "stairs, flowers, lamp posts or sky that are not in the first photo. Keep the original weather, "
    "sky and time of day (an overcast sky stays overcast). Where the background is detailed, draw it "
    "crisp and clean, with no haze, color bleeding, wash, or uneven pigment density. Use neutral, "
    "clean lighting with gentle highlights and shadows, with no warm color grade. Keep the character "
    "as the focal point, with the face being the simplest part.\n\n"
    "**6. Finish and color**\n"
    "Use a clean, crisp digital 2D look with clean vector-like edges and smooth, opaque, even flat "
    "fills. NO paper grain, NO canvas texture, NO noise, NO watercolor, NO gouache, NO oil-paint or "
    "brush-stroke look, NO painterly blur, no bleeding, no soft or feathered edges, no wet-paint "
    "effects. Use a neutral white balance and keep the colors of the photo as they are: whites stay "
    "pure white, the sky stays a clear blue, greens stay fresh green, and skin is a clean light "
    "peach, NOT orange, NOT yellow. NO sepia, NO warm color grade, NO vintage film filter, NO "
    "golden-hour tint, NO yellowish overlay, NO aged-paper look. The whole image must look "
    "high-resolution, bright, clear and crisp.\n\n"
    "**7. Composition**\n"
    "Preserve the original framing, body position, head angle, expression, gaze direction and the "
    "placement of every object, including anything held in the hands. Exactly one person, the clear "
    "focal point. Keep the exact head turn and gaze direction. Keep the exact hair color (black stays "
    "black). Keep glasses with the exact frame shape and color, with the eyes drawn inside the lenses "
    "and the thin frame lines never covering the eyes. Keep hats, logos on hats and clothing, "
    "badges and neck straps. Keep permanent features such as moles and dimples, but remove temporary "
    "marks such as stains, dirt, scratches and food on the skin.\n\n"
    "**Negative constraints**\n"
    "No photorealism, no 3D rendering, no realistic skin pores or skin shading, no glossy eyes, no "
    "oversized sparkling eyes, no line-shaped, curved or hooked nose, no long eyelashes, no heavy eyeliner, no glamorous makeup, no "
    "exaggerated chibi proportions, no watercolor, no blurry or hazy background, no flat or blurry "
    "hair, no blurry clothing, no thick outline around hair or background, no changed outfit, no "
    "changed hairstyle, no altered pose, no added accessories or props, no extra people, no stairs, no cherry blossoms, no gothic building "
    "and no lamp post unless they are in the first photo, and no added text or logos that are not in "
    "the first photo."
)

_STYLE_PROMPT = _STYLE_PROMPT_PREAMBLE + _STYLE_PROMPT_MAIN


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
                # 2026-10-14 사용자 결정. 시험(사진 4장)에서 장당 약 20초, 입력 약 3,600~3,800 · 출력 1,372 토큰
                # → 장당 약 $0.07(입력 $8 · 출력 $30 / 100만 토큰 가격표 기준 추정, 실청구는 아직 확인 못 했다).
                # 옛 gpt-image-1 + input_fidelity=high 는 약 $0.37 이었다.
                model="gpt-image-2.5-flare",
                image=[
                    (f"source.{content_type.removeprefix('image/')}", source_photo_bytes, content_type),
                    ("style-reference.jpg", _STYLE_REFERENCE_BYTES, "image/jpeg"),
                ],
                prompt=_STYLE_PROMPT,
                # input_fidelity 는 넣지 않는다 — 이 모델은 키만 있어도 400 invalid_input_fidelity_model 이다.
                # 원본(구도·옷·머리) 유지는 모델 기본 동작과 프롬프트 7절이 맡는다.
                # 표시용 사진은 전부 세로 4:5 다(DESIGN §5.2) — 지원되는 비율 중 가장 가까운 세로를 고른다.
                size="1024x1536",
                # 시험은 high 로만 돌았다(출력 토큰이 high 에서도 1,372 라 실제 차이는 확인 못 했다).
                quality="high",
            )
            # 응답 모양은 gpt-image-1 과 같다 — 시험 스크립트도 data[0].b64_json 을 읽었고 1024x1536 PNG 가 나왔다.
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
