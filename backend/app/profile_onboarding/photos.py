from google.cloud import vision

# Vision Likelihood enum: UNKNOWN=0 VERY_UNLIKELY=1 UNLIKELY=2 POSSIBLE=3 LIKELY=4 VERY_LIKELY=5
_REJECT_THRESHOLD = 4  # LIKELY 이상이면 거부(사전 결정, project_slice2_decisions_2026-09-19)


async def check_safe_search(vision_client: vision.ImageAnnotatorAsyncClient, image_bytes: bytes) -> bool:
    # 비동기 클라이언트에는 safe_search_detection 편의 메서드가 없다(동기 클라이언트 전용) — 원본 RPC 를 직접 부른다.
    response = await vision_client.batch_annotate_images(
        requests=[
            {
                "image": vision.Image(content=image_bytes),
                "features": [{"type_": vision.Feature.Type.SAFE_SEARCH_DETECTION}],
            }
        ]
    )
    result = response.responses[0]
    if result.error.message:
        raise RuntimeError(result.error.message)
    annotation = result.safe_search_annotation
    return annotation.adult < _REJECT_THRESHOLD and annotation.violence < _REJECT_THRESHOLD
