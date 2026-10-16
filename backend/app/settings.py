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
    # 빈 값을 막는다 — `PHONE_ENCRYPTION_KEY=` 로 배포하면 전화번호 · 실명 · 카카오톡 아이디가 빈 키로 암호화된다.
    phone_encryption_key: str = Field(min_length=1)
    # 조각 6: 세 배치(/batch/*)를 Cloud Scheduler 만 부르게 하는 ID 토큰의 audience(경로 없는 서비스 URL)와
    # 발급 계정(core/batch_auth.py). 하나라도 비면 배치가 아무도 통과시키지 않는다(열린 문이 되지 않게).
    batch_audience: str = ""
    batch_service_account: str = ""
    # 조각 2 후속(아바타 비동기, 2026-09-25 결정): 작업 큐 이름 · 워커 URL · 작업을 부를 서비스 계정.
    # 리전과 프로젝트는 여기 두지 않는다 — 프로젝트는 위 google_cloud_project 가 이미 들고 있고
    # 리전은 Cloud Run 과 같이 움직여서, 칸을 늘려 봐야 배포할 때 빠뜨릴 자리만 는다(avatar_tasks.py).
    # 하나라도 비면 아바타 POST 가 **행을 만들기 전에** 503 을 낸다(못 부를 걸 알면서 남기지 않는다).
    avatar_tasks_queue: str = ""
    avatar_worker_url: str = ""
    avatar_tasks_service_account: str = ""
    # 결함 A7: 학생증 검토 결과 트리거(pg_net)가 보내는 공유 비밀. Secret Manager 와 Supabase Vault 에 같은 값.
    # 비면 /hooks/verification-reviewed 가 아무도 통과시키지 않는다.
    verification_hook_secret: str = ""
    # 소셜 로그인 전환: 탈퇴 때 카카오 연결 끊기(account/social_unlink.py)에 쓰는 앱 어드민 키.
    # 비면 연결 끊기를 건너뛴다 — 서버 시작을 막지 않는다.
    kakao_admin_key: str = ""
    # 탈퇴 때 애플 토큰 철회(App Store 5.1.1(v), account/social_unlink.py). Sign in with Apple 키(.p8)의
    # 팀 ID · 키 ID · PEM 본문(Secret Manager `apple-sign-in-private-key`). 하나라도 비면 철회를 건너뛴다 — 서버 시작을 막지 않는다.
    apple_team_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""
    # 아이폰 하트 구매(billing/apple_router.py)가 App Store Server API 를 부를 때 쓰는 앱 내 구입 키(.p8)의
    # 키 ID · 발급자(Issuer) ID · PEM 본문(Secret Manager `apple-iap-private-key`). 위 Sign in with Apple 키와 다른 키다(재사용 불가).
    # 하나라도 비면 아이폰 결제 확인만 503(apple_not_configured)이고 서버 시작은 막지 않는다. 환불 알림은 이 키 없이 돈다.
    apple_iap_key_id: str = ""
    apple_iap_issuer_id: str = ""
    apple_iap_private_key: str = ""
    # 홈 리뷰 띠(home/router.py `GET /home/summary`)에 보일 실제 스토어 평점 · 평가 수. 사람이 Cloud Run 에 손으로 넣는 값이라
    # 글자로 받는다 — 숫자 타입이면 잘못 넣는 순간 Settings() 가 실패해 서버 전체가 멈춘다. 검사는 홈 요약이 한다(어긋나면 0).
    store_rating: str = "0"
    store_rating_count: str = "0"

    @property
    def postgrest_url(self) -> str:
        return f"{self.supabase_url}/rest/v1"

    @property
    def auth_url(self) -> str:
        return f"{self.supabase_url}/auth/v1"

    @property
    def storage_url(self) -> str:
        return f"{self.supabase_url}/storage/v1"
