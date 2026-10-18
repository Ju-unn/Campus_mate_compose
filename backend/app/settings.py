from pydantic import Field, field_validator
from pydantic_settings import BaseSettings


class AdminWebSettings(BaseSettings):
    """관리자 웹 대시보드(설계 10-18 §6-6)가 쓰는 CORS 허용 주소. 아래 Settings 와 따로 둔 이유: CORS 미들웨어는 앱이 돌기
    전에만 붙일 수 있어 main.py 가 import 될 때 읽는데, 그때는 Settings 의 필수값이 없을 수 있다(시험 · e2e 가 app.main 을 import)."""

    # 쉼표 목록(예: https://admin.campus-mates.com). 비면 CORS 미들웨어를 붙이지 않는다 — 지금 배포와 똑같다.
    admin_allowed_origins: str = ""

    @field_validator("admin_allowed_origins")
    @classmethod
    def _no_wildcard(cls, value: str) -> str:
        # '*' 는 아무 사이트나 관리자 API 를 부르게 연다. 서버를 띄우지 않는다(main.py import 에서 멈춘다).
        if "*" in value:
            raise ValueError("ADMIN_ALLOWED_ORIGINS 에 '*' 는 쓸 수 없다 — 관리자 웹 주소만 적는다")
        return value

    @property
    def admin_origins(self) -> list[str]:
        # 끝의 '/' 는 뗀다 — 브라우저가 보내는 Origin 에는 붙지 않아 그대로 두면 조용히 안 맞는다.
        return [o.strip().rstrip("/") for o in self.admin_allowed_origins.split(",") if o.strip()]


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
    # 관리자 웹 주소(예: https://admin.campus-mates.com, 설계 10-18 §8-1). 있으면 인증샷 디스코드 알림에 그 건의 검수 링크를 싣는다.
    # 비면 지금처럼 "Supabase 대시보드에서 확인" 안내다. 끝의 '/' 는 붙이는 쪽(heart_tasks/router.py)이 뗀다.
    admin_base_url: str = ""
    # 관리자 관문(admin/caller.py)이 받는 2단계 인증 나이(시간). 토큰 amr 의 totp 시각이 이보다 오래면 403 mfa_required —
    # 토큰을 새로 고쳐도 aal2 는 그대로 남아서, 2단계를 마친 시각으로 관리자 세션 수명을 끊는다.
    admin_mfa_max_age_hours: int = 12

    @property
    def postgrest_url(self) -> str:
        return f"{self.supabase_url}/rest/v1"

    @property
    def auth_url(self) -> str:
        return f"{self.supabase_url}/auth/v1"

    @property
    def storage_url(self) -> str:
        return f"{self.supabase_url}/storage/v1"
