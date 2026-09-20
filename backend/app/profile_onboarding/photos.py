from google.cloud import vision

# Vision Likelihood enum: UNKNOWN=0 VERY_UNLIKELY=1 UNLIKELY=2 POSSIBLE=3 LIKELY=4 VERY_LIKELY=5
_REJECT_THRESHOLD = 4  # LIKELY 이상이면 거부(사전 결정, project_slice2_decisions_2026-09-19)


async def check_safe_search(vision_client: vision.ImageAnnotatorAsyncClient, image_bytes: bytes) -> bool:
    response = await vision_client.safe_search_detection(image=vision.Image(content=image_bytes))
    annotation = response.safe_search_annotation
    return annotation.adult < _REJECT_THRESHOLD and annotation.violence < _REJECT_THRESHOLD
