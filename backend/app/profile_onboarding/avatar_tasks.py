"""아바타 생성 작업 한 건을 Cloud Tasks 에 등록한다.

자격증명은 Cloud Run 서비스 계정(ADC)이고 토큰을 받는 방식은 `cards/push.py` 의 `FcmSender` 와 같다 —
새 파이썬 패키지를 더하지 않으려고 REST 를 직접 부른다(계획서 "새 의존성" 절).
"""
import asyncio
import base64
import json
from uuid import UUID

import google.auth
import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest

_SCOPE = "https://www.googleapis.com/auth/cloud-platform"

# 큐 리전은 Cloud Run 리전과 같이 움직이는 값이라 환경변수로 만들지 않는다 — 늘려 봐야 배포할 때
# 빠뜨릴 칸만 는다. **다만 큐를 다른 리전에 만들면 등록이 404 로 조용히 실패한다**(DEPLOY.md 참고).
_LOCATION = "asia-northeast3"

# 큐가 요청을 끊는 시각. 여기서 끊기면 asyncio 가 CancelledError(=BaseException)를 던져 워커 안에서는
# 못 잡는다 — 남은 pending 행은 10분 정리가 치운다(계획서 "pending 이 남는 경우").
_DISPATCH_DEADLINE = "240s"


class AvatarTaskQueue:
    def __init__(
        self,
        project_id: str,
        queue: str,
        worker_url: str,
        service_account_email: str,
        client: httpx.AsyncClient,
        credentials=None,
    ):
        self._project_id = project_id
        self._queue = queue
        self._worker_url = worker_url
        self._service_account_email = service_account_email
        self._client = client
        self._credentials = credentials

    async def _access_token(self) -> str:
        if self._credentials is None:
            self._credentials, _ = await asyncio.to_thread(google.auth.default, scopes=[_SCOPE])
        if not self._credentials.valid:
            await asyncio.to_thread(self._credentials.refresh, GoogleAuthRequest())
        return self._credentials.token

    async def enqueue(self, profile_id: UUID, attempt_id: UUID) -> None:
        """실패하면 예외를 던진다 — 부르는 쪽이 방금 만든 pending 행을 지운다(계획 B3⑥).

        작업 이름(`task.name`)은 일부러 주지 않는다. 이름으로 중복을 거르면 구글 문서가 경고하는
        처리량 저하가 붙고, 우리 멱등성은 이미 `pending` 부분 유니크 인덱스가 맡는다.
        """
        body = base64.b64encode(
            json.dumps({"profile_id": str(profile_id), "attempt_id": str(attempt_id)}).encode()
        ).decode()
        response = await self._client.post(
            f"https://cloudtasks.googleapis.com/v2/projects/{self._project_id}"
            f"/locations/{_LOCATION}/queues/{self._queue}/tasks",
            json={
                "task": {
                    "httpRequest": {
                        "url": self._worker_url,
                        "httpMethod": "POST",
                        "headers": {"Content-Type": "application/json"},
                        "body": body,
                        # 워커는 이 토큰의 audience 와 발급 계정을 둘 다 본다(core/batch_auth.py).
                        "oidcToken": {
                            "serviceAccountEmail": self._service_account_email,
                            "audience": self._worker_url,
                        },
                    },
                    "dispatchDeadline": _DISPATCH_DEADLINE,
                }
            },
            headers={"Authorization": f"Bearer {await self._access_token()}"},
        )
        response.raise_for_status()
