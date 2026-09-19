from google.cloud import vision


class VisionOcr:
    """Google Cloud Vision 으로 학생증 이미지에서 텍스트를 추출한다(2026-09-19 결정).
    ADC(Cloud Run 서비스 계정)로 인증하므로 별도 API 키가 없다."""

    def __init__(self, client: vision.ImageAnnotatorAsyncClient):
        self._client = client

    async def extract_text(self, image_bytes: bytes) -> str:
        # 비동기 클라이언트에는 text_detection 편의 메서드가 없다(동기 클라이언트 전용) — 원본 RPC 를 직접 부른다.
        response = await self._client.batch_annotate_images(
            requests=[
                {
                    "image": vision.Image(content=image_bytes),
                    "features": [{"type_": vision.Feature.Type.TEXT_DETECTION}],
                }
            ]
        )
        result = response.responses[0]
        if result.error.message:
            raise RuntimeError(result.error.message)
        annotations = result.text_annotations
        return annotations[0].description if annotations else ""
