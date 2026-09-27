from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str
    # 웹훅 서명 검증 전용이다 — 신원 해시에는 쓰지 않는다(아래 identity_hmac_key).
    auth_hook_signing_secret: str
    # 조각 6 준비(미결 41①): Secret Manager 키 이름 `identity-hmac-key`.
    # 재가입 차단 이메일 해시와 지인 차단 연락처 해시가 쓰는 키다. 서명 키와 수명이 다르다 —
    # 서명 키는 언제든 바꿔도 되지만 이 키를 바꾸면 저장된 해시가 전부 무효가 된다.
    # 한 값으로 묶어 두면 한쪽이 새는 순간 둘 다 버려야 한다.
    # 빈 값을 막는다 — `IDENTITY_HMAC_KEY=` 로 배포하면 모든 해시가 같은 빈 키로 계산돼
    # 재가입 차단이 조용히 풀린다. 실제 키 길이는 Secret Manager 에 만들 때 사람이 지킨다.
    identity_hmac_key: str = Field(min_length=1)
    discord_webhook_url: str
    discord_report_webhook_url: str = ""
    # ADC/google-cloud 라이브러리가 환경변수로 직접 읽는다 — 이 필드는 부팅 시 존재를 강제하는 용도다.
    google_cloud_project: str
    # 조각 2: Secret Manager 키 이름 `openai-api-key`(2026-09-19 준비 가이드 메모)
    openai_api_key: str
    # 조각 2: Secret Manager 키 이름 `phone-number-encryption-key` — pgcrypto pgp_sym_encrypt/decrypt 에 넘긴다.
    phone_encryption_key: str
    # 조각 4: Secret Manager 키 이름 `card-batch-secret` — /batch/daily-cards 를 Cloud Scheduler 만 부르게 한다.
    # 비어 있으면 엔드포인트가 아무도 통과시키지 않는다(설정을 빠뜨린 배포가 열린 문이 되지 않게).
    card_batch_secret: str = ""
    # 조각 2 후속(아바타 비동기, 2026-09-25 결정): 작업 큐 이름 · 워커 URL · 작업을 부를 서비스 계정.
    # 리전과 프로젝트는 여기 두지 않는다 — 프로젝트는 위 google_cloud_project 가 이미 들고 있고
    # 리전은 Cloud Run 과 같이 움직여서, 칸을 늘려 봐야 배포할 때 빠뜨릴 자리만 는다(avatar_tasks.py).
    # 하나라도 비면 아바타 POST 가 **행을 만들기 전에** 503 을 낸다(못 부를 걸 알면서 남기지 않는다).
    avatar_tasks_queue: str = ""
    avatar_worker_url: str = ""
    avatar_tasks_service_account: str = ""

    @property
    def postgrest_url(self) -> str:
        return f"{self.supabase_url}/rest/v1"

    @property
    def auth_url(self) -> str:
        return f"{self.supabase_url}/auth/v1"

    @property
    def storage_url(self) -> str:
        return f"{self.supabase_url}/storage/v1"
