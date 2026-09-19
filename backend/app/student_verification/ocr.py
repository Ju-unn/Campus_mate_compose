from google.cloud import vision


class VisionOcr:
    """Google Cloud Vision 으로 학생증 이미지에서 텍스트를 추출한다(2026-09-19 결정).
    ADC(Cloud Run 서비스 계정)로 인증하므로 별도 API 키가 없다."""

    def __init__(self, client: vision.ImageAnnotatorAsyncClient):
        self._client = client

    async def extract_text(self, image_bytes: bytes) -> str:
        image = vision.Image(content=image_bytes)
        response = await self._client.text_detection(image=image)
        if response.error.message:
            raise RuntimeError(response.error.message)
        annotations = response.text_annotations
        return annotations[0].description if annotations else ""
