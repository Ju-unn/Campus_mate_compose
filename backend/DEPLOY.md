# backend 배포 — Google Cloud Run (asia-northeast3, 서울)

**아래 명령은 GCP 프로젝트가 준비되고 사용자가 승인한 뒤에만 실행한다** (spec §13-37).

## 0. 사전 준비 완료 (2026-09-20)

값은 전부 Secret Manager 또는 KeePassXC 에 있고, 이 문서엔 이름만 적는다 — URL·키 값은 적지 않는다.

- **Cloud Vision API** — campus-mate GCP 프로젝트에 사용 설정 완료. 별도 인증 키 없이 Cloud Run 기본 서비스 계정으로 자동 인증(조각 1b)
- **디스코드 웹훅** — `학생증-재검토` 채널 웹훅 생성, Secret Manager `discord-review-webhook-url` 로 등록 완료(조각 1b 계획 초안의 가칭 `discord-webhook-url`이 아니라 이 이름을 쓴다)
- **OpenAI API 키** — Secret Manager `open-api-key` 로 등록 완료(조각 2 아바타 변환용, 준비 가이드의 가칭 `openai-api-key`가 아니라 이 이름을 쓴다)
- **전화번호 암호화 키** — Secret Manager `phone-number-encryption-key`(version 1) 로 등록 완료(조각 2 pgcrypto)
- **Firebase** — 기존 campus-mate GCP 프로젝트에 연동, Android 앱(`io.github.juunn.campusmate`) 등록, FCM v1 사용 설정 완료(푸시 알림용). `google-services.json` 은 사용자 로컬에만 두고 커밋하지 않는다(`.gitignore`).

## 1. 최초 1회

**시크릿 값을 파일에서 읽어 넣을 때는 반드시 `tr -d '\r\n'` 을 거친다(2026-09-21 사고).**
윈도우에서 만든 파일은 줄 끝이 `\r\n` 이라 `--data-file=` 로 그대로 넣으면 **`\r` 이 값의 일부로 저장된다.**
눈으로는 보이지 않고 길이만 1 바이트 길어져서, 배치 공유 비밀(`card-batch-secret`)이 이 사고로 오염돼 Cloud Scheduler 가
계속 401 을 받았다. `echo -n` 으로 직접 넣을 때도 `-n` 을 빠뜨리면 같은 일이 난다.

```bash
gcloud config set project <PROJECT_ID>
gcloud services enable run.googleapis.com secretmanager.googleapis.com vision.googleapis.com

# 파일에서 읽어 넣는 경우 — 줄바꿈을 반드시 떼어낸다
tr -d '\r\n' < secret.txt | gcloud secrets create <이름> --data-file=-

# 시크릿 등록 (값은 여기 문서에 남기지 않는다)
# auth-hook-signing-secret 은 최초 배포 시 자리표시자 값으로 등록한다 — Supabase가 Auth Hook을
# 등록할 때 발급하는 실제 whsec_... 값은 아직 없기 때문. Part C Task C3에서 Supabase가 발급한
# 값으로 새 버전을 추가하면 :latest 를 참조 중이라 재배포 없이(또는 서비스 재시작만으로) 반영된다.
echo -n "<service-role-key>" | gcloud secrets create supabase-service-role-key --data-file=-
echo -n "<placeholder-until-supabase-issues-whsec>" | gcloud secrets create auth-hook-signing-secret --data-file=-
echo -n "<discord webhook url>" | gcloud secrets create discord-review-webhook-url --data-file=-


# Cloud Run 기본 compute 서비스 계정이 위 시크릿을 읽을 수 있도록 권한을 부여한다
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member=serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor
```

Vision API는 Cloud Run 기본 컴퓨트 서비스 계정에 별도 IAM 역할이 필요 없다(API 활성화 + ADC 자격만으로 호출 가능).

푸시(FCM HTTP v1)는 Vision 과 달리 역할이 하나 필요하다. **FCM 서버 키(자격증명 시크릿)는 만들지 않는다** —
Cloud Run 이 자기 서비스 계정(ADC)으로 보낸다(2026-09-20 준비 가이드 확정).

```bash
# 조각 4: 같은 서비스 계정에 FCM 전송 권한만 더한다
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member=serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com \
  --role=roles/firebasecloudmessaging.admin
```

역할 이름은 `roles/firebasecloudmessaging.admin` 이다 — `roles/firebasemessaging.admin` 은 없는 역할이라
`add-iam-policy-binding` 이 그 자리에서 거부한다.

## 2. 배포

```bash
cd backend
gcloud run deploy campus-mate-backend \
  --source . \
  --region asia-northeast3 \
  --allow-unauthenticated \
  --set-env-vars SUPABASE_URL=<project-url>,GOOGLE_CLOUD_PROJECT=<PROJECT_ID>,AVATAR_TASKS_QUEUE=<큐 이름>,AVATAR_WORKER_URL=<cloud-run-url>/tasks/avatar-generate,AVATAR_TASKS_SERVICE_ACCOUNT=<큐가 쓸 서비스 계정 이메일>,BATCH_AUDIENCE=<cloud-run-url>,BATCH_SERVICE_ACCOUNT=campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --set-secrets SUPABASE_SERVICE_ROLE_KEY=supabase-service-role-key:latest,AUTH_HOOK_SIGNING_SECRET=auth-hook-signing-secret:latest,DISCORD_WEBHOOK_URL=discord-review-webhook-url:latest,IDENTITY_HMAC_KEY=identity-hmac-key:latest,OPENAI_API_KEY=open-api-key:latest,PHONE_ENCRYPTION_KEY=phone-number-encryption-key:latest,DISCORD_REPORT_WEBHOOK_URL=discord-report-webhook-url:latest,KAKAO_ADMIN_KEY=kakao-admin-key:latest,VERIFICATION_HOOK_SECRET=verification-hook-secret:latest
```

`BATCH_AUDIENCE` · `BATCH_SERVICE_ACCOUNT` 중 하나라도 빠뜨리면 세 배치(`/batch/*`)는 **아무 요청도 통과시키지 않는다**(전부 401).
열린 채로 남는 쪽보다 닫힌 채로 실패하는 쪽을 택했다 — 카드가 안 나가면 바로 눈에 띈다.
`CARD_BATCH_SECRET` 은 이 명령에도 서버 코드에도 없다(OIDC 전환, §4-3).

**`KAKAO_ADMIN_KEY`(소셜 로그인 전환)** — 카카오 앱의 어드민 키. 탈퇴할 때 카카오 연결 끊기(`app/account/social_unlink.py`)에 쓴다.
비어 있으면 그 단계만 건너뛴다(경고 없이, 서버 시작은 막지 않는다). Secret Manager 에 시크릿 `kakao-admin-key` 로 등록했다(2026-10-09).
위 `--set-secrets` 목록에 `KAKAO_ADMIN_KEY=kakao-admin-key:latest` 를 더해 쓴다. 값은 이 문서에 적지 않는다.

**`APPLE_PRIVATE_KEY`(애플 토큰 철회, App Store 5.1.1(v))** — 탈퇴할 때 애플 토큰 철회(`app/account/social_unlink.py`)에 쓴다. Sign in with Apple 키(`.p8`)의 PEM 본문을 Secret Manager 에 시크릿 `apple-sign-in-private-key` 로 등록하고(`gcloud secrets create apple-sign-in-private-key --data-file=AuthKey_<키 ID>.p8`, PEM 이라 줄바꿈이 남아도 · `tr -d '\r\n'` 로 지워도 읽힌다), 위 `--set-secrets` 목록에 `APPLE_PRIVATE_KEY=apple-sign-in-private-key:latest` 를 더한다. 같이 쓰는 `APPLE_TEAM_ID`(팀 ID) · `APPLE_KEY_ID`(키 ID)는 비밀이 아니라 `--set-env-vars` 에 `APPLE_TEAM_ID=<팀 ID>,APPLE_KEY_ID=<키 ID>` 로 더한다.
셋 중 하나라도 비면 그 단계만 건너뛴다(경고 없이, 서버 시작은 막지 않는다). 앱이 탈퇴 본문에 `apple_authorization_code` 를 실어 보낸 애플 사용자만 철회한다 — 코드를 애플 `/auth/token` 으로 refresh_token 과 바꾼 뒤 `/auth/revoke` 로 바로 철회하고, 토큰은 저장하지 않는다. client_id 는 번들 ID(`io.github.juunn.campusmate`)다. 값은 이 문서에 적지 않는다.

**설정 개수와 전체 `--set-*` 명령 주의.** 위 전체 명령은 최초 배포용이라 지금 서비스 설정과 같지 않다(그대로 다시 돌리지 않는다). 이 명령에는 `APPLE_TEAM_ID` · `APPLE_KEY_ID`(env)와 `APPLE_PRIVATE_KEY=apple-sign-in-private-key:latest`(시크릿), 아이폰 하트 구매용 `APPLE_IAP_KEY_ID` · `APPLE_IAP_ISSUER_ID`(env)와 `APPLE_IAP_PRIVATE_KEY=apple-iap-private-key:latest`(시크릿, §4-10), 홈 리뷰 띠용 `STORE_RATING` · `STORE_RATING_COUNT`(§4-13), 관리자 웹용 `ADMIN_ALLOWED_ORIGINS` · `ADMIN_BASE_URL` · `ADMIN_MFA_MAX_AGE_HOURS`(§4-14), 졸업생 스위치 `GRADUATE_VERIFICATION_ENABLED`(§4-14), `MIN_APP_VERSION`(아래)이 빠져 있다. `--set-env-vars` · `--set-secrets` 는 **목록 전체를 갈아끼우므로** 서비스에 들어 있는 이 값들이 지워진다(애플 값이 비면 탈퇴 때 애플 토큰 철회가 조용히 건너뛰어진다). 배포는 아래 "현행 배포 방식"으로 하고, 새 값은 `--update-env-vars` · `--update-secrets` 로 **더한다.**
코드로 센 설정은 `Settings` 27개(env 16 · 시크릿 11) + 별도 클래스 `AdminWebSettings` 의 `ADMIN_ALLOWED_ORIGINS` 1개 = 28개다(`ADMIN_MFA_MAX_AGE_HOURS`(기본 12, 관리자 2단계 인증 나이 상한) · `MIN_APP_VERSION`(기본 빈 글자)이 `Settings` 에 있다). 운영 서비스는 env 27개(그중 시크릿 11)다 — `ADMIN_MFA_MAX_AGE_HOURS`(운영에 넣지 않은 것으로 추정, §4-14) · `MIN_APP_VERSION`(아직 안 넣었다)이 없고, `settings.py` 밖의 `GRADUATE_VERIFICATION_ENABLED` 가 있어 27개다. `MIN_APP_VERSION` 을 넣으면 28개가 된다. 이 개수를 지키는 시험은 없다(`backend/tests/test_deploy_docs.py` 는 아래 `MIN_APP_VERSION` 문단의 "두 스토어" · "공개" 만 본다). 애플 키 6개는 운영 서비스에 모두 연결돼 있다(대장 전달 값). **2026-11-11 코드 기준(운영 미배포): `Settings` 37개(env 22 · 시크릿 15) + `AdminWebSettings` 1개 = 38개다** — 11-08 회의 묶음이 env 6개(`HOME_STATS_MIN_SIGNUPS` · `INQUIRY_NOTIFY_TO` · `INQUIRY_SMTP_USER` · `SMS_PROVIDER` · `SMS_DAILY_GLOBAL_LIMIT` · `PHONE_VERIFICATION_REQUIRED`)와 시크릿 4개(`INQUIRY_SMTP_PASSWORD` · `SOLAPI_API_KEY` · `SOLAPI_API_SECRET` · `SOLAPI_SENDER`)를 더했다(§4-25). 운영 서비스는 이 값을 넣기 전까지 위 27개 그대로다.

**현행 배포 방식(2026-10-13 ~ 14 배포 기준, 대장 전달 값)** — 설정을 바꾸지 않는 코드 배포는 env · 시크릿 목록을 넘기지 않는다. 그러면 새 리비전이 **직전 리비전의 env · 시크릿을 그대로 이어받는다**:

```bash
cd backend
gcloud run deploy campus-mate-backend --source . --project=<PROJECT_ID> --region=asia-northeast3 --allow-unauthenticated --quiet
```

새 env · 시크릿이 생길 때만 `--update-env-vars` · `--update-secrets`(목록에 **더하기**)를 쓴다 — `--set-*`(갈아끼우기)는 위 이유로 쓰지 않는다. 배포 뒤 리비전 이름 · 되돌림 하한은 §5.

**업로드는 `.gcloudignore`, 이미지는 `.dockerignore` — 둘 다 맞춘다.** `gcloud run deploy --source .` 는 제외 목록을 두 군데에서 본다. ① PC 에서 클라우드로 올리는 **업로드** 단계는 `backend/.gcloudignore`, ② 올라간 뒤 **이미지를 만드는**(Dockerfile `COPY`) 단계는 `backend/.dockerignore` 다. 서로 다른 파일이라 **한쪽만 고치면 다른 단계에는 반영되지 않는다 — 제외할 것을 바꿀 때는 두 파일을 같이 맞춘다.** `.gcloudignore` 는 `.gcloudignore` · `.git` · `.gitignore` · `.venv/` · `__pycache__/` · `*.pyc` · `.pytest_cache/` · `*.egg-info/` · `tests/` · `.env` · `.env.*`(가상환경 · 시험 · 비밀값 파일)를 뺀다. `Dockerfile` · `pyproject.toml` · `app/` 은 이미지에 필요하니 **어느 쪽 목록에도 넣지 않는다.** **배포 뒤 확인**: Cloud Build 로그(콘솔 또는 `gcloud builds log <빌드 ID>`)에 `inflating: /workspace/.venv` 가 한 줄도 없어야 한다 — 보이면 `.gcloudignore` 가 빠졌거나 어긋난 것이다(정상이면 업로드가 170 파일 · 1MB 안팎이다, §3). 이미 쌓인 업로드 zip · 이미지는 §4-24 의 자동 삭제 규칙(업로드 버킷 30일, 이미지 창고 최근 15개 보존)이 맡고, 되돌릴 수 있는 리비전의 하한도 거기서 정해진다.

**`MIN_APP_VERSION`(강제 업데이트 — 앱 1.0.1 이상 빌드부터 읽는다)** — 이 버전 **미만** 인 앱을 "업데이트해 주세요" 화면으로 막는다. `GET /app/version`(인증 없음, 응답 `{"min_version": "<버전>"}` 또는 `{"min_version": null}`, `Cache-Control: public, max-age=300`)이 이 값을 알려 주고 앱이 시작할 때와 앱으로 돌아올 때 비교한다. 1.0.0 은 이 경로를 읽지 않아 막히지 않고, 이 경로를 읽는 첫 공개 버전은 1.0.2 다(§4-20). 기본은 비어 있어 아무도 막지 않는다. 형식이 `숫자.숫자.숫자` 가 아니면(예: `1.0`, `1.0.1+19`) 서버는 뜨고 로그에 경고(`MIN_APP_VERSION 형식이 올바르지 않아 무시한다`)만 남긴 채 막지 않는다. **고친 빌드가 두 스토어(구글 플레이 · 앱 스토어)에서 모두 공개된 뒤에만 올린다** — 공개되기 전에 올리면 업데이트할 곳이 없는 사람이 앱을 쓸 수 없다. 올리는 법은 새 env 하나를 더하는 `gcloud run services update campus-mate-backend --project=<PROJECT_ID> --region=asia-northeast3 --update-env-vars MIN_APP_VERSION=<버전>`(새 리비전이 뜬다), 푸는 법은 `--remove-env-vars MIN_APP_VERSION`(앱은 다음 시작 또는 앱으로 돌아올 때 풀린다). 앱이 서버를 못 부르거나(장애 · 3초 시간 초과) 응답이 이상하면 앱은 막지 않는다 — 서버 장애로 앱이 잠기지 않는다. **예시 값 `1.0.1` 로는 아무도 막히지 않는다**(1.0.0 앱은 이 경로를 읽지 않고, 읽는 앱은 1.0.1 이상이다) — 처음으로 사람을 막는 값은 1.0.2 보다 높은 다음 버전 숫자다(§4-20).

**`IDENTITY_HMAC_KEY` · `OPENAI_API_KEY` · `PHONE_ENCRYPTION_KEY` 는 `settings.py` 가 필수(`min_length=1` 등)로 요구하므로 배포 명령에서 빠지면 그 자리에서 기동이 실패한다.** 위 명령에 셋 다 들어 있다(시크릿 이름 `identity-hmac-key` · `open-api-key` · `phone-number-encryption-key`). `DISCORD_REPORT_WEBHOOK_URL`(`discord-report-webhook-url`, 신고 전용 채널 — 비어 있으면 신고 알림만 건너뛰고 경고 로그)도 위 명령에 있다. `KAKAO_ADMIN_KEY` 와 `VERIFICATION_HOOK_SECRET`(`verification-hook-secret`, 학생증 검토 결과 훅의 공유 비밀 — 비어 있으면 `/hooks/verification-reviewed` 가 모든 요청을 막는다)도 위 명령에 있다. **`PHONE_ENCRYPTION_KEY` 는 전화번호 · 실명 · 카카오톡 아이디 암호화에 같이 쓴다**(같은 키, §4-4 · `docs/SUPABASE.md` §8) — 이 키를 바꾸면 전화번호 · 실명 · 카톡 암호문을 모두 다시 암호화해야 한다

**Auth OTP expiry — Supabase 대시보드 Authentication 설정의 OTP 유효시간을 300초(5분)로 맞춘다.** 기본값(3600초)과 앱의 인증 코드 화면 카운트다운(5분)이 어긋나 있었다(운영에서는 아직 3600초, 승인 대기 중).

`--allow-unauthenticated` 로 배포한다 — Supabase HTTP Auth Hook은 GCP IAM 아이덴티티 토큰을 발급할 수 없어서, IAM 인증을 걸면 훅 호출 자체가 막힌다. 대신 요청 인증은 Standard Webhooks HMAC 서명 검증 + timestamp ±5분 범위 검사(코드에 구현됨)가 담당한다.

## 3. 배포 확인

엔드포인트가 `--allow-unauthenticated`라 토큰 없이 바로 확인한다:

```bash
curl https://<서비스 URL>/health
```

`{"status":"ok"}` 가 나오면 성공.

**빌드 로그도 본다.** 배포 뒤 Cloud Build 로그에 `inflating: /workspace/.venv` 가 0줄이어야 한다(업로드 제외 목록 `backend/.gcloudignore` 가 맞는지 보는 확인, §2 "업로드는 `.gcloudignore`, 이미지는 `.dockerignore`"). 이 확인은 `/health` 와 달리 코드가 아니라 배포 방식이 어긋났는지를 알려 준다.

## 4. 카드 지급 배치 (조각 4, 2026-09-21)

하루 한 번 07:00 Asia/Seoul 에 `/batch/daily-cards` 를 부른다. **요일 사다리(주 2회 · 3회 · 매일) 판정은
코드가 하므로 job 은 하나면 된다** — 요일마다 job 을 만들지 않는다. 무료 한도 3 job 안이라 비용은 0 이다.

```bash
gcloud services enable cloudscheduler.googleapis.com

# 매일 07:00 Asia/Seoul. 요일 판정은 코드가 하므로 job 은 하나면 된다.
gcloud scheduler jobs create http campus-mate-daily-cards \
  --location=asia-northeast3 \
  --schedule="0 7 * * *" \
  --time-zone="Asia/Seoul" \
  --uri="<cloud-run-url>/batch/daily-cards" \
  --http-method=POST \
  --oidc-service-account-email=campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --oidc-token-audience=<cloud-run-url> \
  --attempt-deadline=600s
```

인증은 OIDC 다(§4-3) — 계정 · 권한 · `BATCH_AUDIENCE` 는 §4-3 의 것을 쓰고 `--headers` 는 붙이지 않는다. `<cloud-run-url>` 은 `https://` 를 포함한 서비스 주소다(경로 · 끝 `/` 없이).

- Cloud Run 이 `--allow-unauthenticated` 라 이 엔드포인트는 스스로를 지킨다(조각 1a auth hook 과 같은 이유).
- 토큰이 없거나 틀리면 401 이고, 그때는 아무 카드도 나가지 않는다.
- 실행 결과는 `{"issued": 3, "no_candidate": 1, "skipped_regions": ["busan"], "failed": 0}` 모양으로 돌아오고
  Cloud Logging 에 남는다. `skipped_regions` 는 오늘이 지급 요일이 아닌 지역그룹이고, `failed` 는 사람 단위로
  실패해 건너뛴 수다(0 이 아니면 로그의 "카드 지급 실패 owner=…" 를 본다 — 배치는 멈추지 않는다).
- 실행 시간이 600초를 넘기 시작하면 지역그룹별로 job 을 나눈다(백로그).

손으로 한 번 돌려 보려면:

```bash
gcloud scheduler jobs run campus-mate-daily-cards --location=asia-northeast3
```

**주의:** 이 배치는 조각 4 의 DB 마이그레이션(`region_group_settings` · `daily_cards` …)이 클라우드에
적용된 뒤에야 돈다. 적용 전에 job 을 만들면 매일 500 이 쌓인다 — 마이그레이션 적용 뒤에 만든다.

**카드 선정 · 유료 카드(지시문 22) 배포 순서:** DB 마이그레이션 4개(`20261010010000` ~ `20261010040000`) 적용 →
곧바로 서버 배포 → 앱 배포. 두 단계 사이를 짧게 둔다.

- 서버를 먼저 배포하면 깨진다. DB 에 `pickable` 칸이 없어 `KeyError` 로 `/cards/today` 와 지급 배치가 실패한다
  (`paid_card_offers` 표 · `rpc/purchase_paid_card` 도 마찬가지다).
- 반대로 DB 만 적용되고 옛 서버가 남아 있으면, 이제 후보에 이미 본 사람까지 들어 있어서 옛 서버가 쉬는 기간 안의
  사람이나 살아 있는 카드가 있는 사람에게도 카드를 줄 수 있다. 그렇게 쌓인 데이터는 되돌릴 수 없다.
- 그래서 지급 배치 시각(07:00 Asia/Seoul)을 피해서 배포한다. 두 단계의 간격이 07:00 에 걸치면 그동안
  Cloud Scheduler 의 카드 지급 job(`campus-mate-daily-cards`)을 잠시 중지했다가 서버 배포 뒤에 다시 켠다.

## 4-1. 신뢰 확인 게이트 배치 (조각 5, 2026-09-22)

매시 정각 Asia/Seoul 에 `/batch/chat-gate` 를 부른다. 두 가지를 한다 — ① 매칭 24시간을 막 넘긴
사람에게 신뢰 확인 리마인드 푸시 ② 48시간을 넘긴 매칭을 닫기(`chat_closed_at` 기록). **무료 한도
3 job 중 두 번째**라 비용은 여전히 0 이다.

```bash
# 매시 정각 Asia/Seoul. 리마인드 시각 판정은 코드가 하므로 job 은 하나면 된다.
gcloud scheduler jobs create http campus-mate-chat-gate \
  --location=asia-northeast3 \
  --schedule="0 * * * *" \
  --time-zone="Asia/Seoul" \
  --uri="<cloud-run-url>/batch/chat-gate" \
  --http-method=POST \
  --oidc-service-account-email=campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --oidc-token-audience=<cloud-run-url> \
  --attempt-deadline=600s
```

인증은 카드 배치와 같은 스케줄러 계정 · audience 의 OIDC 다(§4-3). 둘 다 우리 스케줄러만 부르는 엔드포인트라 나눌 이유가 없다.

- 실행 결과는 `{"reminded": 2, "closed": 1, "passed": 0}` 모양이고 Cloud Logging 에 남는다.
  `passed` 는 **양쪽이 수락했는데 통과 도장이 빠진 방을 배치가 대신 찍어 준 수**다. 0 이 정상이고,
  계속 올라오면 `/trust` 가 중간에 끊기고 있다는 뜻이다.
- **매시 정각을 건너뛰면 그 시간에 걸린 리마인드는 다시 오지 않는다.** 보낼 시각을 한 시간짜리 창으로
  판정하기 때문이다("보냈다" 표시 컬럼을 두지 않으려고 고른 방식). 마감(`chat_closed_at`)은 다음 시간에
  따라잡으므로 문제가 없다.
- 새벽(22~8시)에 걸린 리마인드는 서버가 **아침 8시로 미뤄** 보낸다. 조용한 시간에 버려지면 창이 한 번뿐이라
  영영 못 가기 때문이다.
  - **"걸린다" 판정**: 기본 시각(매칭 24시간 뒤)을 **정각으로 올린** 시각이 조용한 시간(22시 ~ 다음 날 08시 전)이거나 기본 시각의 '시'가 8시 전이면(21시대 · 07시대 포함) 그다음 아침 **08:00** 으로 민다(`reminder_at`, `backend/app/chat/gate.py`). 배치가 매시 정각에만 돌고 창이 `[시각, 시각 + 1시간)` 이라 실제로 보내지는 때는 기본 시각을 정각으로 올린 시각이기 때문이다(기본 시각이 21:30 이면 22:00 배치에 걸린다). 07시대(07:00:01 ~ 07:59:59)는 올림이 08:00 이라 괜찮아 보이지만 스케줄러가 정각보다 몇 초 늦게 부르면 07:00:02 배치가 창에 걸려 버려질 수 있어 올림과 상관없이 08:00 으로 민다. 정각(21:00:00 등)은 그 정각 배치가 바로 보내므로 그대로 둔다. 이 시각 계산은 사람마다 켜 둔 방해 금지 설정을 보지 않고 모두 같다. 밀어도 기본 시각에서 최대 11시간(21:00:01 → 다음 아침 08:00)이라 마감(매칭 48시간 뒤 = 기본 시각 + 24시간)보다 늘 이르다. 설계 §2.5 · 계획서 `2026-09-22-slice5-chat.md` 에 같은 규칙이 있다.
- **같은 매시 배치가 하는 일이 셋 더 있다**(새 job · env · 시크릿 없음, 응답에 칸만 늘었다).
  지금 응답은 `{"reminded", "closed", "passed", "deferred_sent", "notifications_purged", "photos_deleted", "pending_expired"}` 모양이다.
  - `deferred_sent` — 밤에 보류한 알림을 아침에 묶어 보낸 수. `notifications_purged` — 90일 지난 알림함 줄을 지운 수.
  - **학생증 사진 정리(PR #463)** — `app/student_verification/retention.py`.
    ① 제출하고 **30일이 지나도 검토 대기**인 시도를 반려로 닫고(사유 "검토 기한이 지나 사진을 삭제했어요. 학생증을 다시 올려 주세요",
    한 번에 100명) 사진을 지운다 → `pending_expired`. ② 검토가 끝났는데 `student-id-temp` 에 남은 사진을 지운다 → `photos_deleted`(①의 삭제 포함).
    시도를 먼저 닫고 프로필을 나중에 바꾸므로 그 순간 검토 결과 훅이 "기한 만료" 알림을 보낸다. 실패는 로그(시도 id 만)에 남기고
    다음 정각이 다시 고른다 — 앞의 리마인드 · 마감 결과는 잃지 않는다.
  - `photos_deleted` 가 매시 계속 0 이 아니면 대시보드 수동 확정 뒤 훅이 사진을 못 지우고 있다는 뜻이다(`docs/SUPABASE.md` §7).

**주의:** 이 job 도 조각 5 의 `messages` 마이그레이션이 클라우드에 적용된 뒤에 만든다.

## 4-2. 아바타 작업 큐 (조각 2 후속, 2026-09-26)

아바타를 만드는 데 1분 가까이 걸려서 요청 안에서 만들지 않는다. 04-3 의 "다음"은 **작업만 등록하고**
바로 다음 질문으로 넘어가고, Cloud Tasks 가 워커(`/tasks/avatar-generate`)를 따로 부른다.
스케줄러가 아니라 **큐**라 무료 한도 3 job 과는 상관이 없다.

**전제: 큐 리전 = Cloud Run 리전(`asia-northeast3`).** 코드가 리전을 모듈 상수로 박고 있어서
(`app/profile_onboarding/avatar_tasks.py`), 큐를 다른 리전에 만들면 작업 등록이 **조용히 404 로
실패**한다. 화면에는 "잠시 후 다시 시도해 주세요"만 뜬다.

```bash
gcloud services enable cloudtasks.googleapis.com

# 재시도는 끈다(--max-attempts=1). 실패 횟수는 우리 코드가 직접 세고(5회 → 기본 아바타 + 하트 10),
# 큐가 몰래 한 번 더 부르면 그 카운트와 겹친다.
# 동시 처리는 3~5 로 시작한다. 높이면 OpenAI 가 429 를 돌려주는데, 재시도가 없어서 그 429 가 그대로
# **사람의 무료 5회 중 한 번**으로 깎인다. 느린 것보다 나쁘다.
gcloud tasks queues create <큐 이름> \
  --location=asia-northeast3 \
  --max-attempts=1 \
  --max-concurrent-dispatches=5

# 큐가 워커를 부를 때 쓸 서비스 계정. 워커는 이 계정이 발급한 ID 토큰만 통과시킨다.
gcloud iam service-accounts create <계정 이름> --display-name="avatar task invoker"
gcloud run services add-iam-policy-binding campus-mate-backend \
  --region=asia-northeast3 \
  --member="serviceAccount:<계정 이메일>" \
  --role="roles/run.invoker"

# Cloud Run 서비스 계정이 큐에 작업을 넣고, 그 계정을 대신해 오이디씨 토큰이 붙은 작업을 만들 수 있어야 한다.
gcloud tasks queues add-iam-policy-binding <큐 이름> \
  --location=asia-northeast3 \
  --member="serviceAccount:<Cloud Run 서비스 계정>" \
  --role="roles/cloudtasks.enqueuer"
# roles/iam.serviceAccountTokenCreator 가 아니라 serviceAccountUser 가 필요하다 — 실기기에서 아바타 등록이
# 403 으로 막혀서 잡힌 오류였다. oidcToken 을 붙인 작업을 만드는 호출자는 그 계정에 대해
# iam.serviceAccounts.actAs 가 있어야 한다(Google Cloud "Create HTTP target tasks" 문서).
# 토큰 자체는 Cloud Tasks 서비스 에이전트가 만든다(roles/cloudtasks.serviceAgent, API 를 켜면 자동 부여).
gcloud iam service-accounts add-iam-policy-binding <계정 이메일> \
  --member="serviceAccount:<Cloud Run 서비스 계정>" \
  --role="roles/iam.serviceAccountUser"
```

- **이 역할이 빠지면**: `POST /avatar/generate` 가 502, 백엔드 로그에 "아바타 작업 등록 실패" + Cloud Tasks 403 이다. 앱은 502 · 503 을 "잠시 후 다시 시도해 주세요" 로 보인다(`ServerUnavailableFailure`). 그 밖의 5xx 는 "알 수 없는 오류" 다.
- 운영 서비스 계정에는 `serviceAccountUser` 가 있고, 옛 `serviceAccountTokenCreator` 도 아직 남아 있다. 둘 다 있어도 동작엔 지장 없고, 최소 권한 원칙상 옛 역할을 뺄지는 사용자 결정 대기다.

- 환경변수 3개(`AVATAR_TASKS_QUEUE` · `AVATAR_WORKER_URL` · `AVATAR_TASKS_SERVICE_ACCOUNT`)는 §2 의
  `--set-env-vars` 에 있다. **하나라도 비면** POST 는 행을 만들기 전에 503 을 내고 워커는 아무도
  통과시키지 않는다 — 설정을 빠뜨린 배포가 열린 문이 되지 않게 한 쪽이다.
- `AVATAR_WORKER_URL` 은 워커 주소이면서 **토큰의 audience** 다. 둘이 어긋나면 큐는 부르는데 워커가
  401 로 튕긴다.
- 작업이 240초를 넘기면 큐가 요청을 끊는다. 그때 남는 "만드는 중" 행은 **10분 뒤 다음 POST 가** 정리한다
  (코드에서 못 잡는다 — 끊김은 `CancelledError` 라 `except Exception` 을 통과한다).
- 급할 때 멈추려면 `gcloud tasks queues pause <큐 이름> --location=asia-northeast3`. **10분 안에 다시
  푼다.** 넘기면 그동안 기다리던 사람들의 실패 횟수를 사람이 보정해야 한다.

**주의:** 이 큐도 Part C 마이그레이션(`is_fallback` · `profile_avatars_one_pending`)이 클라우드에
적용된 뒤에 만든다. 적용 전에 만들면 작업마다 500 이 쌓인다.

**각주 — `OPENAI_API_KEY` 를 빠뜨리면 아무 오류도 안 보인다.** 비동기가 되면서 생성 실패가 워커 안에서
나기 때문에 POST 는 멀쩡히 202 를 주고, 사람은 "다시 만들기" 를 다섯 번 누른 뒤 기본 아바타와 하트 10 을
받는다 — 겉보기엔 정상 동작이다. 확인할 곳은 Cloud Run 로그의 `아바타 생성 실패`
(`app/profile_onboarding/avatars.py`) 한 줄뿐이다.

**필수 업로드 — 기본 아바타 원본 `avatars/defaults/fallback-avatar.png`** (결함 D-02).
아바타를 5번 연속 못 만든 사람에게 기본 아바타를 주는 보상(`copy_fallback_avatar`)은 이 파일을 **복사**하는
것으로 시작한다. 버킷에 없으면 복사가 멈춰서 행도 하트도 안 생기는데, 겉으로는 조용하다. 큐를 만들 때 같이 올린다.

```bash
# 그림은 사용자가 정한 PNG 한 장(성별 무관 공용). 운영 쓰기라 사용자 허락 뒤에만 올린다.
supabase storage cp <로컬 PNG> ss:///avatars/defaults/fallback-avatar.png   --project-ref <project-ref> --experimental --content-type image/png
```

- **빠뜨려도 서버는 뜬다.** 시작할 때 서버가 이 파일을 한 번 읽어 보고(`app/profile_onboarding/startup_check.py`),
  없으면 Cloud Run 로그에 **ERROR**(`기본 아바타 원본이 없다`)를 남기고 Discord 알림방에도 한 줄 보낸다.
  부팅은 막지 않는다 — 이 파일이 없어도 가입 말고는 멀쩡하다.
- 배포 직후 §3 확인과 함께 로그에서 그 ERROR 가 **없는지** 본다. 인스턴스가 여러 개 뜨거나 0 에서 다시 뜰 때(콜드스타트)마다 파일이 올라올 때까지 알림이 간다.
- 목록을 못 읽은 경우(Storage 장애 · 네트워크)는 "없다" 가 아니라서 WARNING 만 남기고 Discord 는 보내지 않는다.

## 4-3. 배치 인증 OIDC 전환 (조각 6, 2026-09-27)

§4 · §4-1 · §4-4 의 job 은 모두 구글이 서명한 ID 토큰(OIDC)으로 서버를 부른다. 서버는 공개키로 토큰을 검증한 뒤 발급 계정까지 본다(`app/core/batch_auth.py`). 복사해 둘 공유 열쇠가 없고, 옛 `X-Batch-Secret` 헤더 · `CARD_BATCH_SECRET` 은 서버가 읽지 않는다(카드 · 채팅 · 정리 배치 라우터가 아바타 워커처럼 `verify_oidc_token` 을 바로 부른다).

환경변수 2개가 필요하다. 비밀이 아니라서 `--set-secrets` 가 아니라 `--set-env-vars`(또는 `--update-env-vars`)로 넣는다.

- `BATCH_AUDIENCE` — Cloud Run 서비스 URL, **경로 없이**(끝에 `/` 도 없이). 모든 job 이 이 값 하나를 같이 쓴다.
- `BATCH_SERVICE_ACCOUNT` — 스케줄러 서비스 계정 이메일 `campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com`.
- **둘 중 하나라도 비어 있으면 OIDC 로는 아무도 못 들어온다** — 배치가 전부 401 이다.

`<cloud-run-url>` 은 이 명령이 찍는 값 그대로다(`https://` 포함, 경로 · 끝 `/` 없이):

```bash
gcloud run services describe campus-mate-backend --region=asia-northeast3 --format='value(status.url)'
# 서비스에 들어간 값이 위 출력과 글자까지 같아야 한다
# (Cloud Run URL 은 모양이 두 가지다 — …a.run.app 과 …<프로젝트 번호>.asia-northeast3.run.app).
gcloud run services describe campus-mate-backend --region=asia-northeast3 --format=yaml | grep -A1 BATCH_
```

**서비스 계정 만들고 권한 주기**

```bash
gcloud iam service-accounts create campus-mate-scheduler --display-name="campus mate scheduler"

# job 이 부를 Cloud Run 서비스에 호출 권한을 준다.
gcloud run services add-iam-policy-binding campus-mate-backend \
  --region=asia-northeast3 \
  --member="serviceAccount:campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/run.invoker"

# job 을 만들거나 고치는 사람(= gcloud 로그인 계정)은 이 계정에 대해
# iam.serviceAccounts.actAs 가 있어야 한다 — §4-2 의 403 과 같은 교훈이다.
# 프로젝트 소유자면 이미 있지만, 없으면 job 만들기 · 고치기가 PERMISSION_DENIED 로 멈춘다.
gcloud iam service-accounts add-iam-policy-binding campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --member="user:<gcloud 로그인 이메일>" \
  --role="roles/iam.serviceAccountUser"
```

확인: `gcloud run services get-iam-policy campus-mate-backend --region=asia-northeast3` 에 `roles/run.invoker` 와 `campus-mate-scheduler@…` 가 같이 보인다.

**job 의 인증을 OIDC 로 바꾸기 (기존 job 을 고칠 때)**

```bash
# --oidc-token-audience 는 **경로 없는** 서비스 URL 이다. 빠뜨리면 구글이 job 의 --uri 전체
# (…/batch/daily-cards)를 audience 로 넣어 서버의 BATCH_AUDIENCE 와 어긋난다 → 401.
# 두 job 이 같은 audience 를 써서 서버 설정이 하나로 끝난다.
gcloud scheduler jobs update http campus-mate-daily-cards \
  --location=asia-northeast3 \
  --oidc-service-account-email=campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --oidc-token-audience=<cloud-run-url>

gcloud scheduler jobs update http campus-mate-chat-gate \
  --location=asia-northeast3 \
  --oidc-service-account-email=campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --oidc-token-audience=<cloud-run-url>

# 헤더는 따로 뺀다. --clear-headers 는 job 에 붙인 헤더를 **전부** 지운다 —
# §4 · §4-1 의 만들기 명령이 붙인 헤더는 X-Batch-Secret 하나뿐이다.
gcloud scheduler jobs update http campus-mate-daily-cards --location=asia-northeast3 --clear-headers
gcloud scheduler jobs update http campus-mate-chat-gate --location=asia-northeast3 --clear-headers
```

처음에 적었던 `--remove-headers=X-Batch-Secret`(OIDC 플래그와 한 명령)은 `gcloud scheduler jobs update http --help` 에는 있지만 SDK 586 에서 `TypeError` 로 죽었다. 그래서 OIDC 를 먼저 따로 붙이고 헤더는 `--clear-headers` 로 뺀다. `--update-headers` 는 헤더를 **더하거나 고치는** 플래그라 여기 맞지 않는다.

확인: `gcloud scheduler jobs describe campus-mate-daily-cards --location=asia-northeast3 --format='yaml(httpTarget)'`
에 `oidcToken`(계정 · audience)이 있고 `X-Batch-Secret` 이 없다. `campus-mate-chat-gate` 도 같다.

**손으로 돌려 확인**

```bash
gcloud scheduler jobs run campus-mate-daily-cards --location=asia-northeast3
gcloud scheduler jobs run campus-mate-chat-gate --location=asia-northeast3

# 1~2분 뒤. 두 경로 모두 200 이어야 한다 — 헤더가 없으니 200 이면 토큰으로 들어온 것이다.
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="campus-mate-backend" AND httpRequest.requestUrl:"/batch/"' \
  --freshness=15m --limit=5 --format='value(timestamp,httpRequest.requestUrl,httpRequest.status)'
```

- 401 이면 대개 audience 가 어긋난 것이다. job 의 `--oidc-token-audience` 와 `BATCH_AUDIENCE` 가 **글자 하나까지**(경로 · 끝 `/`) 같은지 본다.
- 카드 배치는 하루 한 장이라 손으로 한 번 더 돌려도 안전하다(`issuing.py`, DB 유일 인덱스도 막는다 — §4-17).
- chat-gate 를 손으로 돌리면 그 시간 리마인드 대상에게 알림이 한 번 더 갈 수 있다(`app/chat/gate.py` 의 한 시간 창). 한 번만 돌린다.

**공유 열쇠 시크릿 `card-batch-secret`** — 서버는 `CARD_BATCH_SECRET` 을 읽지 않는다. 서비스에 참조가 남아 있으면 `gcloud run services update campus-mate-backend --region=asia-northeast3 --remove-secrets=CARD_BATCH_SECRET` 로 먼저 뺀다(남은 채로 시크릿 버전을 끄면 새 인스턴스가 시크릿을 못 읽어 뜨지 못한다). 서비스에서 뺀 것을 확인한 뒤 `gcloud secrets versions disable <버전 번호> --secret=card-batch-secret`, 계속 200 이면 `gcloud secrets delete card-batch-secret` 으로 지운다.

**새 job 은 처음부터 OIDC 로 만든다** — `--oidc-service-account-email` · `--oidc-token-audience=<cloud-run-url>` 로 만들고 `--headers` 는 붙이지 않는다. 계정 · 권한 · 서버 설정은 위 것을 그대로 쓴다.
주소는 `--uri=<cloud-run-url>/batch/<경로>` 다 — 여기 `<cloud-run-url>` 은 `https://` 를 포함하므로 또 붙이면 `https://https://` 가 된다.

## 4-4. 탈퇴 · 지인 차단 · 정리 배치 (조각 6 PR 3, 2026-09-27)

**적용 순서 — 이 순서대로, 앞 단계가 끝난 뒤에 다음 단계로 간다.**

1. 마이그레이션 클라우드 적용 — `20260927030000_set_phone_number_with_hmac` · `20260927030100_create_withdraw_account`.
2. `NOTIFY pgrst, 'reload schema';` (SQL 편집기) — 새 서버의 5인자 `set_phone_number` 호출이 옛 스키마 캐시에 걸리지 않게 한 번 새로 고친다.
3. 새 서버 배포(§2 명령 그대로, 새 env · 시크릿 없음).
4. 백필 한 번(아래) — 새 서버 배포 **뒤**에 돌린다. 그 전에는 옛 서버의 3인자 호출이 `phone_hmac` 을 null 로 덮고, null 행은 지인 차단 대조에서 빠진다.

**백필** — 예전에 저장된 번호에 지인 차단 해시를 채운다. 한 번 쓰고 버리는 스크립트라 컨테이너에는 없다
(`backend/scripts/`). 다시 돌려도 안전하다(빈 칸인 행만 고르고 빈 칸일 때만 쓴다).

```bash
cd backend
# settings.py 가 §2 의 env 와 시크릿을 전부 요구한다. 시크릿은 Secret Manager 에서 env 로 넣는다 — 값은 여기 적지 않는다.
#   예: export PHONE_ENCRYPTION_KEY="$(gcloud secrets versions access latest --secret=phone-number-encryption-key)"
.venv/Scripts/python.exe -m scripts.backfill_phone_hmac
# 출력은 건수뿐이다: filled=<채운 행> skipped=<휴대전화가 아니거나 복호화 결과가 없는 행>
```

**학교 메일 인증 기록 백필(소셜 로그인 전환)** — 학교 메일 OTP 로 가입한 기존 계정의 학교 메일 해시를
`school_email_claims` 에 채운다. 마이그레이션이 `profiles.school_email_verified_at` 은 채웠지만 이 표는 비어 있고,
HMAC 키가 서버에만 있어 SQL 로는 못 채운다. 비어 있으면 기존 사용자의 학교 메일로 새 소셜 계정이 인증받을 수 있다.

- **언제**: 소셜 로그인 마이그레이션 적용 **뒤**, Supabase 의 카카오 · 구글 로그인을 켜고 앱을 배포하기 **전**.
  서버 배포 전후는 상관없지만 소셜 로그인 공개 전에는 반드시 끝낸다.
- **어떻게**: 위 백필과 같은 자리(backend 폴더)에서 한 번 돌린다. `settings.py` 가 §2 의 env 와 시크릿을 전부 요구한다
  — 이 스크립트가 실제로 쓰는 것은 `SUPABASE_URL` · `SUPABASE_SERVICE_ROLE_KEY` · `IDENTITY_HMAC_KEY` 다.
  값은 Secret Manager 에서 env 로 넣고 여기 적지 않는다.

```bash
cd backend
.venv/Scripts/python.exe -m scripts.backfill_school_email_claims
# 출력은 건수뿐이다: filled=<채운 계정> skipped=<계정 이메일을 못 읽었거나 빈 계정>
#                    already=<이미 기록이 있는 계정> conflicts=<같은 학교 메일 해시가 다른 계정에 이미 있음>
```

- **확인**: 실행 뒤 SQL 편집기에서 `select count(*) from public.school_email_claims` 가 대상 수와 같은지 본다.
  대상 수는 `select count(*) from public.profiles where school_email_verified_at is not null and university_id is not null and status <> 'withdrawn'` 이다.
  `skipped` 나 `conflicts` 가 0 이 아니면 그 수만큼 모자란다 — skipped 는 다시 돌리면 다시 고르고, conflicts 는 같은 학교 메일을
  쓴 기존 계정이 둘 있다는 뜻이라 사람이 본다(출력에 id 를 싣지 않으니 SQL 로 찾는다).
- **다시 돌려도 안전하다**: 이미 기록이 있는 계정은 건너뛰고(already), 쓸 때도 같은 해시가 있으면 덮지 않는다.
  탈퇴한 계정은 대상이 아니다(재가입 제한은 `signup_blocks` 가 맡는다).

**실명 · 카카오톡 아이디 암호화 (일회용 백필은 끝났다).** 옛 평문 `profile_private.real_name` · `kakao_id` 는 암호문 열 `real_name_enc` · `kakao_id_enc` 로 옮겼다(전화번호와 같은 `pgp_sym_encrypt` 에 **같은 키** `PHONE_ENCRYPTION_KEY`, DB 함수 · 규칙은 `docs/SUPABASE.md` §8). 평문 열과 백필 함수는 마이그레이션 `20261012010000_drop_plaintext_real_name_and_kakao_id` 로 운영에서 지웠다. 백필 스크립트 `backend/scripts/backfill_encrypt_profile_private.py` 는 부를 DB 함수가 없어 **다시 돌리지 않는다**(죽은 코드라 지울 대상이다).

- **되돌릴 수 없다.** 롤백 마이그레이션이 없고, 사용자가 되살릴 수 있는 백업도 없다(Supabase 백업 · PITR 은 유료 — 출시 후 결정). 반대로 Supabase 쪽 내부 백업 · WAL 에는 보관 기간 동안 평문이 남아 있을 수 있다.
- **암호화 키 보관 주의**: 실명 · 카톡 아이디 · 전화번호를 읽는 길은 `phone-number-encryption-key`(Secret Manager) 하나뿐이다. 이 키를 잃거나 다른 값으로 바꾸면 세 값이 전부 못 읽는 암호문이 된다 — 키 버전을 지우거나 덮지 않고, 바꿀 때는 옛 키로 복호화 → 새 키로 다시 암호화를 먼저 한다.
- **서버 롤백 주의**: **평문 열에 쓰거나 읽는 서버로 되돌리면 안 된다** — 학생증 제출(실명 저장) · 카톡 아이디 저장 · 계정 조회가 42703(열 없음)으로 실패한다. 평문 쓰기 · 폴백 읽기를 뺀 서버는 리비전 `00063`(PR #474)이다 — **`00063` 아래로 되돌리지 않는다.**
- **키 로그 노출 점검**: `pg_stat_statements`(대시보드 Query Performance) · Postgres 로그에서 `pgp_sym_encrypt` · `pgp_sym_decrypt` 호출의 키 인자가 `$1` 같은 **자리표시자로만** 보이는지 본다. PostgREST 는 RPC 인자를 JSON 바디로 받아 바인딩하므로 보통 문제없지만, `log_statement` · `auto_explain` 같은 설정이 인자 값을 남기는지 같이 본다. 서버는 키를 JSON 바디로만 넘기고 URL 에는 넣지 않는다(`app/profile_onboarding/encryption.py`). 운영 `log_statement` 는 `ddl` 이라 일반 문장(RPC 호출)의 인자 값은 로그에 남지 않는다.
- **배포 순서 교훈**: ① 열을 지우기 전에 그 열을 쓰는 서버를 먼저 없앤다 — "복호화 우선 · 평문 폴백" 서버도 평문 열을 쓰므로 읽기 전환이 아니다. ② 백필 검사는 새 서버 배포 **직전**에 다시 돌리고, 새 서버 배포 **뒤**에는 돌리지 않는다(새 서버는 평문 열을 고치지 않아 사용자가 바꾼 값이 거짓 불일치로 보이고, 빈 값으로 지운 카톡 아이디를 남은 평문으로 되살린다). ③ 되돌릴 수 없는 마이그레이션은 백업이 없다는 사실을 알고 받아들인 뒤에 적용한다.

**정리 배치 job** — 매일 04:00 Asia/Seoul 에 `/batch/cleanup`. 처음부터 OIDC 다(§4-3 의 계정 · 권한 · `BATCH_AUDIENCE` 를 그대로 쓰고 `--headers` 는 붙이지 않는다). 무료 한도 3 job 중 세 번째다.

```bash
gcloud scheduler jobs create http campus-mate-cleanup \
  --location=asia-northeast3 \
  --schedule="0 4 * * *" \
  --time-zone="Asia/Seoul" \
  --uri="<cloud-run-url>/batch/cleanup" \
  --http-method=POST \
  --oidc-service-account-email=campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --oidc-token-audience=<cloud-run-url> \
  --attempt-deadline=600s
```

- 하는 일: ① 탈퇴 30일 지난 계정의 Storage 파일(버킷 3개) → auth 사용자 삭제(profiles 는 cascade, 한 번에 100명)
  ② 처리 끝나고 1년 지난 신고(열린 신고는 남는다) ③ 기한 지난 재가입 제한(무기한은 남는다) ④ 옛 키 버전 지인 차단 행 세기.
  - ① 의 버킷은 **4개**다 — `avatars` · `profile-photos` · `student-id-temp` · `heart-task-proofs`(`app/account/batch_router.py` `STORAGE_BUCKETS`). **⑤ 검수 끝나고 60일 지난 무료 하트 인증샷**을 하루 100장씩 지운다(파일 먼저, 경로 비우기는 나중 — `app/heart_tasks/cleanup.py`). `heart-task-proofs` 버킷이 운영에 없으면 ① 이 그 버킷에서 막혀 탈퇴 계정이 전부 `skipped` 가 된다 — 무료 하트 마이그레이션(§4-5)이 먼저다.
  - ② 는 `resolved_at` 기준이다(열린 신고는 남는다).
  - **⑥ 글 속 취향 나누기가 실패해 단어 칸이 null 인 사람의 4칸을 다시 만든다**(하루 최대 20명 · 150초 예산, `app/matching/vectors.py` `refill_taste`). ⑤ 뒤에 돌고 07:00 카드 배치보다 먼저 메운다. 자세한 내용은 §4-19.
- 결과는 `{"deleted_accounts", "skipped_accounts", "deleted_reports", "deleted_signup_blocks", "stale_key_rows", "deleted_heart_proofs", "refilled_taste"}` 모양이다(`deleted_heart_proofs` = ⑤, `refilled_taste` = ⑥ 에서 다시 만들려고 **시도한** 사람 수 — 실패한 사람도 센다). **2026-11-11 코드(운영 미배포)부터 응답에 `deleted_inquiries`(답변 완료 1년 지난 문의 — 답을 안 한 문의는 남는다)와 `deleted_phone_verifications`(보낸 지 30일 지난 문자 인증 줄) 두 키가 더해진다** — 두 단계는 DB 표가 아직 없어도 다른 정리가 멈추지 않게 따로 감싸 실패하면 0 으로 두고 경고만 남긴다(§4-25).
  `skipped_accounts` 는 파일 삭제가 실패해 **내일 다시** 할 사람이다. 며칠째 같은 수면 로그의 `탈퇴 계정 정리 건너뜀` 을 본다.
  `stale_key_rows` 가 0 이 아니면 `identity-hmac-key` 를 바꾼 뒤 옛 행이 남은 것이다(`app/signup_policy.py` 의 `IDENTITY_KEY_VERSION`).
- 확인: `gcloud scheduler jobs run campus-mate-cleanup --location=asia-northeast3` 뒤 §4-3 의 `logging read` 로 `/batch/cleanup` 200 을 본다. 다시 돌려도 안전하다(두 번째는 전부 0).

## 4-5. 무료로 하트 모으기 — 검수 운영 절차 (2026-09-28, 계획서 `2026-09-28-heart-tasks.md`)

새 env · 시크릿 · job 은 없다. 제출 알림은 학생증 재검토와 같은 디스코드 채널(`DISCORD_WEBHOOK_URL`)로 가고, 60일 정리는 §4-4 정리 배치 ⑤ 가 한다.

**적용 순서(끝남)**: 마이그레이션 번호 순서 그대로 한 번에 — `20260928010000_create_referrals` → `20260928020000_fix_grant_hearts_spend` → `20260928030000_create_heart_task_submissions` → `20260928030100_create_heart_task_functions` → `20260928040000_create_friend_reviews` → `NOTIFY pgrst, 'reload schema';` → 서버 배포. **서버를 먼저 배포하면** 목록 · 제출이 500 이고, 정리 배치가 없는 버킷에서 막혀 탈퇴 계정이 전부 skipped 된다. 코호트(`20260928050000`)도 서버(`/home/summary` 의 `cohort`)보다 먼저다.

**검수(운영자)**

1. 디스코드 "무료 하트 인증 1건 (제출: `<id>`, 계정: `<profile_id>`, 항목: `everytime_post`)" 을 본다. 사진 · 경로 · 이름은 싣지 않는다.
2. Supabase 대시보드 → Table editor → `heart_task_submissions` 에서 `id` 로 줄을 찾고, `storage_path` 로 Storage → `heart-task-proofs` 의 파일을 연다. **칸 이름은 `storage_paths`(경로 1~3개 배열)로 바뀌었다 — 대시보드로 열 때는 배열의 경로를 하나씩 연다. 운영 검수의 기본 길은 이제 관리자 웹의 인증샷 검수(사진 여러 장을 넘겨 본다)다.**
3. **승인**: 그 줄의 `status` 를 `approved` 로 저장한다 — 하트는 DB 트리거가 한 번만 준다(`reward_hearts` 만큼, 사유 `free_task`).
   **반려**: **"Edit row" 패널에서 `status` = `rejected` 와 `reject_reason`(`date_missing` · `not_verified` · `reused`) 을 한 번에 저장**한다 — 한 칸씩 저장하면 check 23514 로 막힌다.
   Edit row 가 바꾸지 않은 칸(`created_at` 등)까지 다시 보내 `CM409` 로 막히면 SQL Editor 에서 한 줄로 한다:

```sql
update public.heart_task_submissions set status = 'rejected', reject_reason = '<사유>' where id = '<id>';
-- 승인은 set status = 'approved'
```

4. **되돌리기는 없다.** 승인 · 반려는 끝 상태다(승인 → 반려, 반려 → 승인 모두 막힘). 반려를 잘못했으면 사용자가 다시 내면 된다. 승인을 잘못했으면 원장을 운영 보정으로 뺀다 — `grant_hearts` 는 2026-09-28(`20260928020000`)부터 음수(쓰기)도 받는다:

```sql
select public.grant_hearts('<profile_id>', -<지급한 하트>, 'admin_adjust', '<제출 id>');
```

   잔액이 0 밑으로 내려가면 check(`heart_balance >= 0`)로 막힌다 — 그 사이 하트를 써 버렸으면 남은 만큼만 뺀다.

**확인할 것**: 운영 첫 검수 때 Edit row 로 반려 저장이 되는지 한 번 본다(대시보드가 `created_at` 까지 다시 보내면 위 SQL 한 줄로). 배포 뒤 첫 04:00 정리 배치 응답에서 `skipped_accounts` 0 과 `deleted_heart_proofs` 칸을 본다.

**하트 값(현재)**: 에브리타임 **40** · 월 1회, 단톡방 25 · 월 3회(인증 캡션 "3명 이상"), 커뮤니티 투표 **5** · 하루 첫 투표 1번만 · 한 주 최대 **15**, 친구 코드 양쪽 50(PR #570, §4-13). 승인 절차(위 3번)는 그대로 — 트리거는 제출 행에 적힌 `reward_hearts` 를 주므로 값이 바뀌기 전에 낸 제출은 그때 적힌 금액으로 승인된다.
승인은 위 3번처럼 `heart_task_submissions.status` 를 `approved` 로 저장하면 트리거가 `grant_hearts` 를 한 번 부른다. **운영에서 이 지급 트리거(`free_task`)는
아직 한 번도 돌아 본 적이 없다** — 첫 실제 제출을 승인할 때 원장(`heart_transactions` 의 `free_task` 한 줄)과 잔액이 늘었는지 꼭 본다.
결과 푸시는 없다(사용자는 18a 상태와 잔액으로 안다).

## 4-6. 보안 점검 반영 (2026-10-12)

점검 원문(읽기 전용 점검, 2026-10-12)은 사용자 폴더 `CampusMate_문서/출시준비/보안점검_10-12.md` 에 있다. 새 env · 시크릿 · job 은 없다.
아래는 보안 점검에서 나온 운영 규칙이다.

- **API 문서 주소를 닫았다**: `/docs` · `/redoc` · `/openapi.json` 은 404 다(`app/main.py` `docs_url=None, redoc_url=None, openapi_url=None`).
  경로 목록이 필요하면 코드에서 `app.openapi()` 를 부른다 — E2E 하네스(E-HEART-49 · 51)도 운영 주소가 아니라 이 방식으로 읽는다.
- **빈 `PHONE_ENCRYPTION_KEY` 로는 서버가 뜨지 않는다**(`settings.py` `min_length=1`). 빈 키로 배포되면 전화번호 · 실명 · 카톡 아이디가 빈 키로 암호화되기 때문이다.
- **로그 · 알림 규칙** — 실명 · OCR 글자 · **사진 경로** · **디스코드 웹훅 주소**를 로그와 알림에 남기지 않는다. 디스코드 알림에는 id 만 싣는다.
  웹훅 실패 로그는 `raise_for_status` 대신 상태 코드만 찍는다(예외 문구에 웹훅 주소가 통째로 들어간다). 라우터가 잡지 않은 저장소 호출 실패(`httpx.HTTPStatusError`)는
  전역 처리기가 메서드 · 상태 코드 · 예외 이름만 남기고 500 을 준다(예외 문구에 Supabase 호스트 · 사진 경로가 든다, `app/main.py` `upstream_call_failed`).
  암호문 복호화 실패는 `profile_id` · 상태 코드만 남긴다(`core/postgrest.py` `_read_private`).
- **자유 글 서버 상한 1000자** — 자기소개 · 이상형 글(`profile_onboarding/schemas.py` `FREE_TEXT_MAX_LENGTH`).
  온보딩 `/bio` · `/ideal-note` 와 `PATCH /me/profile` 의 자기소개가 같은 `FreeText` 타입을 쓴다 — `\r\n` · `\r` 을 `\n` 으로 줄인 뒤 1000자를 세고, 줄 바꿈이 **40줄**(`FREE_TEXT_MAX_LINES = 1000 // 25`)을 넘으면 검증 오류로 거절한다(옛 앱 · 직접 호출이 줄 바꿈만 넣어 카드를 늘이는 것을 막는다). 앱은 300자 · 6~8줄로 조용히 막는다(DESIGN.md §8.5) — 서버 1000 은 옛 긴 글을 고쳐 저장할 수 있게 그대로 둔다. 서버를 배포하기 전에도 앱은 안전하다.
- **학생증 업로드 뒤 시도 행을 쓰기 전에 실패하면 방금 올린 사진을 지운다**(PR #472) — 고아 사진이 버킷에 남지 않게.
- **유료 카드 결제 전 응답에 원본 아바타 주소 · 상대 id 를 싣지 않는다**(PR #473, 리비전 `00062`) — 서버가 8×10 JPEG 미리보기를 만들어 준다(설계 문서 §6.8).
  Pillow(`pillow>=12.3`)가 서버 의존성에 들어갔다(이미지는 그대로 `--source .` 빌드).
- **앱**: 안드로이드 `allowBackup=false`(앱 데이터가 기기 백업으로 빠져나가지 않게, `AndroidManifest.xml`).
- **GitHub 저장소**: 비밀 스캔 · 푸시 차단(push protection) · Dependabot 을 켰다.
- **아직 안 고친 것(출시 전)**: ① 가입 훅이 "재가입이 제한된 메일" 이라고 알려 주는 메시지 — E2E 하네스와 함께 정리 예정
  ② 학교 메일 로그인 방식(`amr`) 검사 — Supabase 가 실제로 주는 값을 먼저 확인해야 한다 ③ 운영 "테스트대학" 의 `gmail.com` · `naver.com` 도메인 — 출시 직전 삭제(사용자 승인 필요, 지우면 테스트 로그인이 막힌다).

## 4-7. 보낸 신청 · 친구 코드 지인 리뷰 서버 (2026-10-13)

두 기능 모두 **DB 마이그레이션 · 새 env · 새 시크릿 · 새 Scheduler job 이 없다**(코드만). 보낸 신청 `GET /cards/sent` = PR #483, 친구 코드 지인 리뷰 = PR #486. 규칙은 설계 문서 §2.2 · §2.8, 화면은 DESIGN.md §8.6 · §9 20f.

### `GET /cards/sent` — 대화 탭 "보낸 신청"

로그인 + 학생증 통과 가입자(`get_verified_caller`)만. 응답 `{"sent": [...]}`, 최신 신청 먼저, **상한 50건**(페이지 없음). 한 건의 필드:

| 필드 | 값 |
| --- | --- |
| `card_id` | 신청한 카드 id |
| `status` | `waiting` · `matched` · `rejected` · `expired` 4종. 판정 순서는 매칭 > 상대 응답 > 기한 |
| `days_left` | `waiting` 일 때만 정수. 남은 시간의 **올림**이라 최소 1 — 1 이면 24시간 이하라 앱이 "오늘 마감" 으로 그린다(서버는 "1일 남음" 을 따로 가르지 않는다). 나머지 상태는 null |
| `match_id` | 대화 탭 방 id(`/chat/matches/{match_id}`). 매칭이 아니거나 매칭 행이 없는 `matched` 면 null(앱이 누를 수 없게 둔다) |
| `sent_at` · `expires_at` · `resolved_at` | 보낸 시각 · 보낸 지 7일(응답 기한) · 끝난 시각(`waiting` 이면 null) |
| `profile` | 카드 앞면 요약. **상대 `profile_id` 는 싣지 않는다** |

- **숨김 규칙** — 아래는 구분 없이 똑같이 목록에서 빠진다: 상대가 차단(어느 방향이든) · 정지 · 탈퇴 · 가림, 또는 매칭 뒤 어느 쪽이든 방을 나갔음. 나가기만 남고 차단만 사라지면 차단 사실이 새기 때문이다
- 끝난 뒤(거절 · 만료 · 성사) 7일이 지나면 빠진다(`SENT_RETENTION_DAYS = 7`, `app/cards/router.py`). 맹점: 보낸 지 7일이 넘어 상대 카드로 뒤늦게 매칭되면 매칭 뒤 7일이 아니라 보낸 지 14일에 빠진다
- 푸시와 알림함은 없고 취소 API 도 없다. 결정 · 프로필 · 매칭 · 차단을 각 한 번씩 읽는다
- **남은 확인**: `fetch_sent_acceptances` 가 인덱스 경로를 타는지 `EXPLAIN` 으로 본 적이 없다(코드 주석)

### `POST /friend-reviews/code-lookup` — 친구 코드 확인

요청 `{"code": "<친구 코드>"}`(앞뒤 공백 · 소문자는 서버가 정리). 친구 코드 = 추천 코드(`profiles.referral_code`).

| 응답 | 뜻 |
| --- | --- |
| 200 `{nickname, university, already_reviewed}` | 쓸 수 있는 사람. 프로필 id · 아바타는 싣지 않는다. `already_reviewed` 가 true 면 앱이 쓰기 대신 안내한다 |
| 404 `코드를 찾을 수 없어요` | 없는 코드 · 본인 · 비활성(정지 · 탈퇴) · 차단 · 같은 전화번호 해시 **전부 이 하나**. 이유는 서버 로그에만 남는다(`reason=` 과 호출자 id — 코드 · 닉네임 원문은 없다). 조회 셋을 한 번에 보내 응답 시간으로도 가르지 못한다 |
| 429 `잠시 후 다시 시도해 주세요.` | 코드 확인 **실패가 시간당 10번**을 넘음 |
| 422 | 코드가 비었거나 20자를 넘음 |

### `POST /friend-reviews` — `friend_code` 추가

본문은 `reviewee_id`(UUID) **또는** `friend_code` **하나만**(0개 · 2개는 422), `tags` 1~3개(12종 고정), `comment` 선택 100자. 성공 201 `{id}`.

- 코드 경로는 코드로 받는 사람을 다시 찾아 확인과 같은 검사를 한다(앱이 본 확인 결과를 믿지 않는다). 추천 연결(`referrals`)은 보지 않고 하트 보상도 없다. 기존 `reviewee_id` 경로 동작은 그대로다
- 409 `이미 리뷰를 남겼어요` · 404 · 429 는 위와 같은 문구다. 429 는 확인 실패 상한 **또는** 코드 경로 쓰기 **24시간 5건** — 5건은 경로와 무관하게 내가 24시간 안에 쓴 리뷰 전체를 센다(추천 경로로 쓴 것도 센다). 422 는 대상 0개 · 2개, 코드 형식, 태그 규칙
- 저장 뒤 받는 사람에게 "새 지인 리뷰" 푸시를 보낸다. 쓴 사람 닉네임이 비어 있으면 건너뛴다("None 님이" 방지). 푸시 실패는 저장을 되돌리지 않는다

### 알려진 한계 · 롤백

- **확인 실패 창 · 작성 상한 창은 서버 인스턴스 메모리다.** Cloud Run 이 재시작하거나 인스턴스가 늘면 느슨해진다(쓰기 상한은 DB 작성 수가 보완, 확인 실패 상한은 보완 없음). 출시 전 DB 작성 기록으로 올린다(설계 문서 §13 출시 전 결정 44). 기존 `/referral/redeem` 에는 실패 횟수 제한이 없다(별도 PR)
- 두 PR 은 DB 를 건드리지 않아 리비전만 되돌리면 되지만, 되돌림 하한(§5)이 이 기능보다 새 리비전이라 이 기능이 없는 리비전으로 내릴 일은 없다.

## 4-8. 채팅 읽음 '1' · 실시간 이벤트 · 푸시 로그 (2026-10-13 ~ 14)

설계안 원문은 사용자 폴더 `CampusMate_문서/기획·설계/채팅_실시간_전환_설계안_10-13.md`(안 A — 서버가 쏘고 앱은 사용자 채널 하나를 듣는다). **순서는 서버 → 운영 DB 정책 → 앱** 이었다(서버만 먼저 나가도 듣는 앱이 없어 무해하고, 정책 전에 나간 앱은 입장이 거부돼 폴링으로만 돈다). 새 env · 시크릿 · job 은 없다.

### 채팅 API — `partner_last_read_at` (PR #501, 리비전 `00069`)

`GET /chat/matches/{match_id}`(방 머리말)와 `GET /chat/matches/{match_id}/messages`(메시지 목록) 응답에 **`partner_last_read_at`**(상대의 `match_participants.last_read_at`, ISO 시각)을 싣는다. 상대가 한 번도 안 읽었으면 `null`, `limit` 과 무관하게 늘 실린다 — 앱은 `limit=1` 로 가볍게 불러 읽음 변화를 본다. 나간 방은 404, 상대가 나간 방은 그대로 읽히고 값도 실린다. 옛 앱은 모르는 키를 무시한다. 읽음 찍기는 `PATCH /chat/matches/{id}/read`(앱이 방에 들어올 때 · 나갈 때 · 보는 동안 받은 줄 3초 묶음, `docs/ERD.md` §4). 푸시 30초 규칙(`IN_ROOM_WINDOW`)은 그대로다.

### 실시간 이벤트 계약 (서버 PR #508 `00070` · DB PR #512 · 앱 PR #510)

- **채널**: 사람마다 `user:<profile_id>` 하나, **반드시 private**. 입장 권한은 `realtime.messages` 받기 정책 `user_channel_read_own`(본인 토픽 broadcast 만, `docs/ERD.md` §2) — **운영 적용 완료**(2026-10-14, 원격 `20261013154505`). 보내기(insert) 정책은 없다
- **쏘는 쪽**: FastAPI 가 `service_role` 키로 Supabase Realtime Broadcast REST(`POST <SUPABASE_URL>/realtime/v1/api/broadcast`, `messages` 배열에 받는 사람 몫을 묶어 **한 번**)를 부른다(`app/chat/realtime.py` `Broadcaster`). 받는 사람은 쓰기 직후 `match_participants` 의 `left_at is null` 을 다시 읽어 정한다 — 나간 · 차단한 사람은 채널이 열려 있어도 받지 않는다
- **실패는 로그만 남기고 삼킨다**(쓰기는 이미 끝났다 — 요청은 성공). 로그 `실시간 쏘기 실패 event=<이벤트> status=<코드>` 또는 예외 이름만(예외 문구에 프로젝트 주소가 들어 있어 쓰지 않는다)
- **요청 안에서 `await`, 제한 1.5초**(`TIMEOUT_SECONDS`) — Cloud Run 은 응답 뒤 CPU 를 줄여 응답 뒤 작업이 밀리거나 사라지기 때문이다. **마감 배치(chat-gate)는 첫 실패 뒤 나머지 방 쏘기를 건너뛴다**(`give_up_after_failure`, Realtime 장애 때 방마다 1.5초씩 기다리지 않게). 요청 경로는 매번 시도한다
- **이벤트 3종**:

| 이벤트 | 받는 사람 | payload | 쏘는 곳 |
| --- | --- | --- | --- |
| `message` | 방에 남은 두 사람 — **보낸 사람 본인 포함**(다른 기기 목록) | `{match_id, message: {id, sender_id, kind, body, created_at}}` — `kind` 는 `text` · `left` · `trust_accept` | `ChatRepository.insert_message`(보내기 · 나감 줄 · 수락 줄 · 차단이 모두 지난다) |
| `read` | **상대에게만** | `{match_id, reader_id, last_read_at}` | `touch_read`(읽음 찍기) |
| `room_changed` | 두 사람 | `{match_id, reason}` — `reason` 은 `matched`(새 매칭, `cards/router.py` 매칭 생성 직후) · `closed`(마감 배치가 방을 닫음) | 매칭 생성 · 방 닫기 |

- **앱 쪽 규칙(PR #510)**: 로그인 · 관문 통과 · 앱이 보이는 동안만 구독하고, 뒤로 가면 멈추고 로그아웃하면 채널을 지운다. 인증 갱신은 supabase_flutter 가 자동으로 `setAuth` 한다. 거부되면 2초에서 5분까지 지수 백오프로 다시 건다. **폴링은 채널이 실제로 `SUBSCRIBED` 일 때만 30초(안전망)로 늦추고, 아니면(거부 · 끊김 · 정책 없음) 대화 탭 목록 3초 · 방 안 읽음 확인 2초**다. 값의 기준은 늘 서버 API 다 — 이벤트는 빨리 보여 주는 용도라 유실돼도 폴링 · 복귀 새로고침이 메운다. 붙을 때 목록 한 번 읽기와 방 읽음 확인으로 놓친 이벤트를 메운다
- **Realtime 설정 "Allow public access" 는 끄지 않는다** — 방 채널 `messages:<match_id>`(postgres_changes)가 public 채널이라서다(PR #512)
- **남은 확인**: 동시 연결 한도(앱이 앞에 있는 모든 사용자가 소켓 1개) — 요금제 한도와 대조는 출시 전(설계안 §7). 하네스 대기값(정책 뒤 목록 폴링 30초)은 후속
- **되돌리기**: 앱이 이벤트를 못 받아도 폴링으로 돈다. 정책 되돌리기는 `drop policy if exists "user_channel_read_own" on realtime.messages;`(새 마이그레이션 + 별도 승인)

### 푸시 로그 · APNs 키 (PR #500, 리비전 `00069` / 2026-10-13 아이폰 푸시 복구)

- 성공은 INFO 한 줄 **`FCM 전송 성공 kind=<종류> platform=<android|ios> token=<앞 6자>…(<길이>)`**, 실패는 WARNING **`FCM 전송 실패 <상태 코드> kind=… platform=… token=… | <FCM 오류 status · code · message · errorCode>`**(JSON 이 아니면 앞 200자, 전체 300자 상한). 토큰은 앞 6자와 길이만 남기고 FCM 이 토큰을 되돌려 줘도 한 번 더 가린다. 제목 · 본문 · 이름은 남기지 않는다. `app.cards.push` 로거에만 INFO 수준과 stderr 핸들러를 단다(운영 uvicorn 은 루트 핸들러가 없어 한 줄씩 나온다). Cloud Run 로그에서 `FCM 전송 성공` · `FCM 전송 실패` 로 찾는다
- **APNs 인증 키**: 아이폰(TestFlight · 출시 빌드)은 애플 운영 APNs 서버를 쓰므로 **Sandbox & Production 범위** 키를 Firebase 클라우드 메시징에 올려야 한다. 샌드박스 전용 키(옛 키 `JT647G2N3A`)는 운영에서 FCM 401 `Invalid APNs credential` 이 난다. 지금 쓰는 키는 `R52HCC98ZY` 다(실기기 도착 · 로그 `FCM 전송 성공 … platform=ios` 로 확인). 키 ID 는 비밀이 아니지만 **키 파일(.p8) 내용은 이 문서 · 채팅 · 로그 어디에도 적지 않는다.** 옛 키를 애플에서 지울지는 사용자 결정 전이다(안 지움). 서버 설정은 필요 없다(FCM 이 APNs 로 보낸다)
- **같은 종류 알림 한 장으로 합치기(서버 PR #546)**: `kind` 가 `_COLLAPSED_KINDS`(지금은 **`verification_result` 하나**, `app/cards/push.py`)면 FCM v1 메시지에 안드로이드 **`android.notification.tag = <kind>`** 와 iOS **`apns.headers.apns-collapse-id = <kind>`** 를 붙인다 — 새 학생 인증 결과 알림이 앞 알림을 덮어 알림 줄에 한 장만 남는다(배경: 발송은 1번인데 앱이 읽은 뒤 지우지 않아 "학생 인증이 끝났어요" 가 계속 보였다). 다른 kind 의 payload 는 그대로다. **앱 짝(같은 PR, vc6 부터)**: 학생 인증 관문을 지나는 순간(3c 또는 홈) 한 번만 이 tag 로 결과 알림을 지운다(`frontend/lib/core/push/foreground_push.dart` `gateChanged` — 앱이 띄운 알림은 id, FCM SDK 가 띄운 알림은 tag). **kind 이름을 바꾸면 앱도 같이 바꾼다.** 한계: iOS 는 합치기만 하고 지우지는 못한다(로컬 알림 창구가 안드로이드 설정만 준비됨). 배포 순서는 서버 → 앱(vc6). 실기기 확인(통과 푸시를 받은 뒤 3c 로 들어가면 알림이 사라지는지 — 앱 앞 · 뒤 · 꺼짐)은 이 문서 정리 시점에 받지 못했다
- **푸시 로그 3종과 동작(서버 PR #647, 상세 · 배포 점검은 §4-22)**: 위 `FCM 전송 성공` · `FCM 전송 실패` 두 줄 말고 아래 셋이 있다. Cloud Run 로그에서 이름으로 찾는다. ① WARNING **`FCM 전송 예외 kind=… platform=… token=<앞 6자>…(<길이>) | <예외 종류>`** — 푸시 서버에 닿지 못한 오류(연결 · 시간 초과 · 끊김, `httpx.HTTPError`)와 구글 인증 토큰을 못 받은 오류(`GoogleAuthError`)를 `notify` 가 잡은 것. ② ERROR **`FCM 인증 실패 kind=… platform=… | <예외 종류>`** — 그중 서비스 계정(ADC) 설정이 깨진 `DefaultCredentialsError` · `RefreshError`. 일시 장애가 아니라 모든 푸시가 안 가는 사고라 ERROR 로 따로 남기고, 기기와 무관하니 토큰은 적지 않는다. ③ INFO **`FCM 죽은 토큰 정리 kind=… platform=… token=…`** — FCM 이 그 토큰은 더는 안 된다고 답해(404, 또는 400 이 토큰 칸을 집어 거절) 서버 토큰을 지울 때 남긴다(토큰이 왜 사라졌는지 나중에 찾으려는 것). 예외 문구에는 주소가 들어 있을 수 있어 ①②는 **예외 종류 이름만** 적는다. 동작: ①②가 나면 그 알림의 **남은 기기를 건너뛰고 이번 푸시만 접는다 — 재전송은 하지 않는다**(다음 알림이 곧 오고, 지금 다시 시도하면 응답만 느려진다). 그래서 채팅 보내기 · 카드 결정 · 수락 · 신뢰 확인이 푸시 때문에 500 이 되지 않는다(채팅은 500 이면 앱이 다시 보내 메시지가 두 줄이 된다). FCM 이 오류로 답한 경우(`FCM 전송 실패` · 죽은 토큰)는 그 기기만의 일이라 다음 기기로 간다. 그 밖의 예외(코드 버그)는 삼키지 않고 그대로 올라온다.

## 4-9. 인앱결제 — 구글 플레이 하트 구매 서버 (2026-10-13, 서버 PR #499 · DB PR #498)

**배포 순서는 DB 적용 → 서버 PR merge → 서버 배포 → 앱**이었다(서버가 먼저 나가면 없는 DB 함수를 부른다). 새 env · 시크릿은 없다 — 구글 플레이 개발자 API(`androidpublisher`)는 **Cloud Run 서비스 계정(ADC)** 으로 부른다(FCM 과 같은 방식, 새 패키지 없음). 그래서 **플레이 콘솔 "사용자 및 권한" 에 이 서비스 계정을 초대**해야 구매 조회 · 소비가 된다(앱 PR #506 기준 미확인 — 플레이 콘솔 상품 5개 등록 · 라이선스 테스터와 함께 샌드박스 시험 전 준비). 표 · 함수는 `docs/ERD.md` §6, 화면은 DESIGN.md §8.10. 경로 이름에 `refund` · `purchase` · `buy` 를 쓰지 않는다(E2E 하네스 E-HEART-49 · 51 이 그런 이름의 경로를 유료 카드 하나만 허용한다).

| 경로 | 뜻 |
| --- | --- |
| `GET /billing/status` | 학생증 통과 가입자. `{account_token, first_purchase_bonus}` — `account_token` 은 결제 창의 `applicationUserName`(구글 `obfuscatedExternalAccountId`)에 싣는 계정 표시(sha256 방식), `first_purchase_bonus` 는 100하트 이상 상품을 산 적이 없으면(환불된 것도 센다, 50하트만 산 사람은 자격이 남는다) `{hearts: 50, min_product_hearts: 100}`, 산 적이 있으면 null(화면 배지용 — 실제 판정은 지급 때 DB 함수가 다시 한다) |
| `POST /billing/google/verify` | 본문 `{product_id, purchase_token}`(`heart_50` ~ `heart_800`, 토큰은 영문 · 숫자 · `. _ -` 만 1000자 이하). **200** `{result: granted \| already_granted, hearts, bonus_hearts, heart_balance}` · **202** `{result: pending}`(결제 대기 — 행을 만들지 않는다) · **409** `purchase_other_account`(다른 계정 표시 — 소비하지 않는다, 3일 안에 안 오면 구글이 환불) · **409** `purchase_token_used`(다른 사람이 이미 받은 영수증) · **422** `purchase_invalid`(결제됨이 아님 · 수량 1 아님 · 상품 불일치) · **503** `billing_unavailable`(구글 조회 실패 — 앱은 지연으로 보고 나중에 다시 보낸다). 지급 뒤 아직 소비 전이면 **서버가 소비(consume)** 한다(실패해도 다음 재전송 때 다시) — 앱은 소비하지 않는다 |
| `POST /batch/billing-voided` | 배치 전용(카드 · 채팅 · 정리 배치와 같은 OIDC 문). 구글 Voided Purchases 를 **최근 7일** 조회해 `refund_store_purchase` 로 회수하고(멱등이라 겹쳐도 된다), 5년 지난 구매 행을 지운다. 응답 `{voided, …건수, purged}`. 구글이 답하지 못하면 503 이고 아무것도 바꾸지 않는다. 회수가 모자라면(이미 쓴 하트) 경고 로그만 — 번호와 숫자만 남긴다 |

- **로그**: 구매 토큰 · 주문 번호는 남기지 않는다(`profile_id` · 상품 · 결과 · 상태 코드만). httpx INFO 가 주소(토큰 포함)를 찍지 않게 못박았다(`app/billing/play.py`)
- **알려진 한계**: verify 요청 빈도 제한 없음(출시 전 백로그) · 구글 쪽 동작은 샌드박스 시험으로 확인 전 · 계정 표시 토큰은 sha256 방식 유지
- **`/batch/billing-voided` 를 부르는 Cloud Scheduler job 이 있다**(매시 30분 — §4-15 "서버 스케줄"). 새로 만들 일이 생기면 §4-3 의 OIDC job 만들기 명령을 경로만 바꿔 쓴다

## 4-10. 인앱결제 — 아이폰(애플) 하트 구매 서버 (2026-10-14, 서버 PR #519 · 후속 PR #521, 앱 PR #520)

계획서는 사용자 폴더 `CampusMate_문서/출시준비/애플_인앱결제_구현계획_초안.md`(끝의 "구현 편차 기록"). 사용자 결정(10-14): 첫 출시에 포함 · `cryptography` 추가 승인 · 환불 알림은 서명 체인 직접 검증 · 가격은 안드로이드와 같게(화면은 스토어 가격 우선).
**DB 마이그레이션은 없다** — §4-9 의 `purchases` 표와 두 함수를 `store = 'app_store'` 로 부른다(`docs/ERD.md` §6). **새 env 2개 · 새 시크릿 1개 · 새 서버 의존성 1개**(`cryptography>=50`, `pyproject.toml`). Scheduler job 은 없다 — 환불은 애플이 알림으로 보내 준다(구글은 우리가 매시 조회, §4-9).
코드는 `app/billing/apple.py`(애플 API 조회 · 서명 검증) · `app/billing/apple_router.py`(두 경로). 경로 이름 규칙은 §4-9 와 같다(`refund` · `purchase` · `buy` 를 쓰지 않는다). 하네스 `e2e/area3_safe.py` `VERIFIED_ROUTES` 에 `POST /billing/apple/verify` 한 줄이 더해졌다(알림은 로그인 관문이 없어 목록 대상이 아니다).

**배포 순서는 서버 → TestFlight(앱)** 다. 서버만 먼저 나가는 것은 무해하다(안드로이드 길은 그대로). 앱이 먼저 나가면 `/billing/status` 에 `apple_account_token` 이 없어 **iOS 는 결제 불가 배너만 보인다**(구글용 계정 표시로 대신 사지 않는다). 운영 서비스에는 앱 내 구입 키 env 2개 · 시크릿 1개가 연결돼 있다(§2). TestFlight 샌드박스 시험 결과는 받지 못했다.

### 키 · 설정

- **앱 내 구입 키(In-App Purchase key, `.p8`)** 를 쓴다. App Store Connect 에서 발급한다. **Sign in with Apple 키(`apple-sign-in-private-key`, §2)나 APNs 키(§4-8)와 다른 키다 — 재사용할 수 없다.**
- 키 ID · 발급자(Issuer) ID 는 비밀이 아니라 env, `.p8` 본문은 Secret Manager 시크릿 **`apple-iap-private-key`**. 기존 env · 시크릿은 그대로 두고 **더하기**(`--update-*`)로 넣는다 — `--set-*` 는 목록 전체를 갈아끼워 다른 값을 지운다(§2).

```bash
# .p8 PEM 본문을 그대로 넣는다(PEM 이라 줄바꿈이 남아도 읽힌다). 키 파일 내용은 이 문서 · 채팅 · 로그에 적지 않는다.
gcloud secrets create apple-iap-private-key --data-file=<내려받은 .p8 파일>

# 읽기 권한은 §1 에서 서비스 계정에 프로젝트 단위로 준 roles/secretmanager.secretAccessor 로 된다.
cd backend
gcloud run deploy campus-mate-backend --source . --project=<PROJECT_ID> --region=asia-northeast3 --allow-unauthenticated --quiet \
  --update-env-vars APPLE_IAP_KEY_ID=<키 ID>,APPLE_IAP_ISSUER_ID=<발급자 ID> \
  --update-secrets APPLE_IAP_PRIVATE_KEY=apple-iap-private-key:latest
```

- **키 없이도 서버는 정상으로 뜬다**(`settings.py` 빈 기본값). 셋 중 하나라도 비면 `POST /billing/apple/verify` 만 **503 `apple_not_configured`**(애플에 묻기 전) 이고 로그 `애플 인앱 구입 키 미설정 profile=… product=…` 가 남는다. **환불 알림은 키 없이 돈다**(애플에 다시 묻지 않고 서명만 본다)
- 키 본문을 못 읽거나 애플이 401 · 403(키 ID · 발급자 ID 가 틀림)을 주면 503 `billing_unavailable` · 로그 `애플 거래 조회 실패 … status=key` 또는 `status=401` · `status=403`
- **운영 401 이면 샌드박스에 한 번 더 묻는다**(서버 PR #532). 개발자 멤버십이 비활성인 동안 **같은 키로 운영 주소만 401 을 주고 샌드박스는 404 로 인증을 넘는 것**이 실측됐다(2026-10-14). 그래서 운영이 401 이면 샌드박스에 한 번 더 묻고(WARNING 로그 `애플 거래 조회 production:401 — 샌드박스에 한 번 더 묻는다`), 샌드박스에 거래가 있으면 `is_test = true` 로 지급한다. **운영 401 뒤 샌드박스에도 없으면(404) 운영 거래인지 알 수 없어 422 가 아니라 503**(앱이 다시 보낸다). 운영 403 · 429 · 5xx · 시간 초과는 샌드박스로 넘기지 않는다(일시 장애를 샌드박스 거래로 오인하지 않게). 서명 체인 · 계정 대조 · 환불 검사는 그대로다
  - **로그 형식**: `애플 거래 조회 실패 profile=<profile_id> product=<상품> status=<물은 환경:상태 코드 …>` — 예 `status=production:401 sandbox:404` · `status=production:401 sandbox:401` · `status=production:404 sandbox:503` · `status=production:403`(샌드박스로 안 넘어감) · `status=production:transport`(연결 실패) · `status=production:404 sandbox:transport` · 키를 못 읽으면 `status=key`. 토큰 · 거래 번호 · JWS 는 담지 않는다(`tests/billing/test_apple_router.py`)
  - **멤버십이 돌아온 뒤에도 WARNING `production:401` 이 보이면 실제 구매가 503 이 된다** — 키 ID · 발급자 ID · 멤버십 상태를 먼저 본다
- **기동 로그로 `cryptography` 확인** — 서버는 시작할 때 INFO 한 줄 **`cryptography=<버전>`** 을 찍는다(`app/main.py` lifespan). 이 부품이 운영 이미지에 없으면 `import` 에서 서버가 아예 뜨지 않는다(탈퇴 때 애플 토큰 철회도 같은 부품을 쓴다). 배포 뒤 한 번 본다:

```bash
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="campus-mate-backend" AND textPayload:"cryptography="' \
  --freshness=30m --limit=5 --format='value(timestamp,textPayload)'
```

### 경로

| 경로 | 뜻 |
| --- | --- |
| `GET /billing/status` | §4-9 의 두 키에 **`apple_account_token`** 을 더했다. profile_id 에서 고정 namespace 로 만든 **UUIDv5**(같은 사람이면 늘 같은 값, profile_id 를 그대로 애플에 보내지 않는다). iOS 결제 창의 `applicationUserName` → StoreKit `appAccountToken` 에 싣는다(애플은 UUID 만 받는다). **namespace 를 바꾸면 이미 산 거래가 전부 "다른 계정" 이 된다**(`apple.py` `_ACCOUNT_NAMESPACE`) |
| `POST /billing/apple/verify` | 학생증 통과 가입자. 본문 **`{product_id, transaction_id}`**(상품은 §4-9 의 5종, 거래 번호는 숫자 1 ~ 64자 — 그 밖은 애플에 묻기 전에 422). 앱이 준 값을 믿지 않고 서버가 App Store Server API `GET /inApps/v1/transactions/{거래 번호}` 를 **운영 주소 → (404 면) 샌드박스 주소** 순서로 묻는다(TestFlight · 심사 거래는 샌드박스 — 운영 401 도 샌드박스로 넘어간다, 위 "키 · 설정" 의 PR #532 줄). 받은 `signedTransactionInfo` 는 **코드에 내장한 Apple Root CA G3 까지 인증서 체인을 검증**한 뒤에만 믿는다. 확인 칸: `environment`(Production / Sandbox → `is_test`) · 거래 번호 · 번들 ID(`io.github.juunn.campusmate`) · 상품 · 소모품 · 직접 구매 · 수량 1. 지급은 `grant_store_purchase`(`store = app_store`), 200 응답 모양은 구글과 같다. **대기(202)는 없다**(애플 거래 조회에는 대기 상태가 없다). **애플은 소비(consume) 호출이 없다** — 서버가 지급하면 앱이 거래를 끝낸다(아래 표) |
| `POST /billing/apple/notifications` | **로그인 없는 공개 주소**(애플이 부른다). 본문 `{signedPayload}`(App Store Server Notifications **V2**). **서명 체인 검증만이 믿는 근거다.** 서명이 틀림 · 다른 앱(번들) · 알림과 거래의 `environment` 가 다름 → **400**(아무것도 바꾸지 않는다). 본문이 없으면 422. **`REFUND` · `REVOKE`** → `refund_store_purchase('app_store', …)` 로 회수하고 200 `{result: refunded \| already_refunded \| unknown}`(이미 회수했거나 우리가 지급한 적 없는 거래도 200 — 멱등). **`TEST` 와 그 밖 알림**은 로그만 남기고 200 `{result: ignored}`(소비 정보 요청 `CONSUMPTION_REQUEST` 도 답하지 않는다). **`REFUND_REVERSED`(환불 번복)는 하트를 되돌리지 않는다** — WARNING 로그만, 운영자가 App Store Connect 에서 확인한다(사용자 결정 A-6 미결). DB 실패는 500 이라 애플이 다시 보낸다 |

**App Store Connect 알림 주소** — 앱의 App Store Server Notifications 설정에 **운영(Production) 주소와 샌드박스(Sandbox) 주소를 둘 다** `https://<서비스 URL>/billing/apple/notifications` 로, 버전은 **Version 2** 로 넣는다. 서버는 주소 하나로 둘 다 받는다(샌드박스 거래는 `is_test = true` 행이다). 둘 중 하나를 비우면 그쪽 환불은 하트가 회수되지 않는다. 애플의 시험 알림(`TEST`)이 오면 로그 `애플 알림 type=TEST … — 할 일 없음` 과 200 이 남는다. 프로덕션 · 샌드박스 두 주소 모두 `/billing/apple/notifications` Version 2 로 등록돼 있다(대장 전달 값). 설정 화면의 정확한 위치는 애플 쪽 UI 라 이 문서 담당이 직접 보지 않았다.

### 에러 code 와 앱 동작 (앱 PR #520 · #521)

문구는 서버 `detail` 이 아니라 앱 글자(pen)를 쓴다 — 화면은 DESIGN.md §8.10. **"끝낸다"(finish)** 는 앱이 StoreKit 거래를 끝내는 것이다. 끝내지 않은 거래는 다음 앱 시작 때 StoreKit 이 한 번 다시 주고, 끝내지 않은 채 두면 같은 Apple ID 가 같은 상품을 다시 사지 못한다. 애플에는 구글의 "3일 안에 확인 안 하면 자동 환불" 이 없다.

| 상태 · code | 뜻 | 앱 |
| --- | --- | --- |
| 200 `granted` · `already_granted` | 하트가 들어갔다 · 이미 들어가 있다 | 성공 토스트, **끝낸다** |
| 422 `purchase_invalid` | 애플이 모르는 거래, 또는 이 요청의 구매가 아님(번들 · 상품 · 종류 · 수량 · 환경) | 빨간 배너 "결제를 확인하지 못했어요". 끝내지 않는다 — 서버를 고친 뒤 다음 앱 시작 때 다시 확인된다. 이 로그인 동안은 다시 보내지 않는다 |
| 422 `purchase_revoked` | **애플이 환불한 거래**(`revocationDate`) — 계정 대조보다 먼저 본다(PR #521) | 토스트(info) **"환불된 결제예요"**, **하트 없이 끝낸다** |
| 409 `purchase_other_account` | 거래의 `appAccountToken` 이 이 계정 것이 아님 | 배너 "다른 계정으로 결제한 하트예요". 끝내지 않는다 — 결제한 계정으로 로그인하면 들어온다 |
| 409 `purchase_token_used` | 다른 계정이 이미 받은 거래(같은 계정이 다시 보내면 200 `already_granted`) | 토스트 "이미 처리된 결제예요", **끝낸다** |
| 503 `billing_unavailable` | 애플 조회 실패(5xx · 429 · 시간 초과 · 401/403 · 키를 못 읽음), 또는 **애플 답의 서명 검증 실패**(우리 쪽 문제일 가능성이 커서 422 가 아니다) | 배너 "하트 지급이 늦어지고 있어요". 끝내지 않고 앱 시작 · 앱 복귀 · 상점 진입 때 다시 보낸다 |
| 503 `apple_not_configured` | 서버에 앱 내 구입 키가 없음(애플에 묻기 전) | 앱은 모르는 code 라 `billing_unavailable` 과 같게(지급 지연) |
| 500 | DB 함수가 계약 밖 결과를 줌 · 그 밖 서버 오류 | 지급 지연과 같게, 끝내지 않는다 |

### 로그 · 비밀

- **거래 번호 · JWS · 키 · 우리가 만든 토큰(JWT)은 로그에 남기지 않는다.** 확인 경로 로그는 `profile_id` · 상품 · 결과 · 상태 코드만, 알림 로그는 알림 종류 · 거래 번호 **앞 6자**(`tx=`) · 환경 · 결과만이다(`profile_id` 도 없다). 거래 번호는 비밀은 아니어서 문의 · 환불 번복 처리 때 찾도록 `purchases.store_order_id` 에 평문으로 둔다
- Cloud Run 로그에서 찾는 말: `애플 인앱 구입 키 미설정` · `애플 거래 조회 실패` · `애플 거래 서명 검증 실패`(ERROR) · `확인되지 않는 애플 거래` · `환불된 애플 거래` · `다른 계정의 애플 거래` · `다른 계정이 이미 받은 애플 거래` · `애플 알림 type=` · `애플 알림 거절 reason=` · `애플 환불 회수 부족`(이미 쓴 하트, 숫자만) · `애플 알림 REFUND_REVERSED`
- **`.p8` 키 내용 · App Store Connect 비밀번호 · 샌드박스 테스터 비밀번호는 이 문서 · 채팅 · 로그 · PR 어디에도 적지 않는다.** 시크릿으로만 넣고, 명령에는 자리표시자를 쓴다

### 알려진 한계 · 롤백

- 환불 번복(`REFUND_REVERSED`)은 자동으로 되돌리지 않는다(위). 자주 생기면 DB 함수(`restore_store_purchase`)를 더한다 — 새 마이그레이션 + 별도 승인
- 믿는 루트는 내장한 Apple Root CA G3 하나다(2039-04-30 만료). 애플이 루트를 바꾸면 확인은 503(앱은 거래를 끝내지 않고 기다린다) · 알림은 400(애플이 다시 보낸다)이 되므로 `apple.py` 의 루트를 바꿔 배포한다
- 확인 요청 빈도 제한이 없다(구글 §4-9 과 같다, 출시 전 백로그). 실기기(TestFlight 샌드박스) 시험 결과는 이 문서 담당이 받지 못했다
- **DB 변경이 없어 리비전만 되돌리면 된다.** 애플 경로가 없는 리비전으로 내리면 iOS 앱은 `apple_account_token` 이 없어 결제 불가 배너가 되고, 이미 결제한 거래는 끝내지 않은 채 남아 서버를 다시 올린 뒤 앱 시작 때 들어온다(추정). 이 기능이 든 앱 빌드가 나간 뒤에는 그 리비전 아래로 되돌리지 않는다

## 4-11. 홈 레일 흐린 아바타 `GET /home/people` (2026-10-15, 서버 PR #549 · 앱 PR #550)

사용자 결정(10-15): 홈 레일(mosaic-rail)에 **모든 학교의 활성 가입자를 성별 섞어 흐린 아바타로** 보여 준다. 블러는 "중간", 후보가 모자라면 서버가 빈 목록을 주고 앱이 기본 그림 칸으로 대신한다. 본인 옵트아웃은 없고 개인정보 처리방침 한 줄과 05-12c 안내 한 줄로 알린다(안내 줄은 가입 맨 끝 5b 리빌 설명 아래에 있다, DESIGN §9 5b). **DB 마이그레이션 · 새 env · 새 시크릿 · 새 job 은 없다**(코드만). 화면은 `frontend/docs/DESIGN.md` §8.9 `mosaic-rail`.

| 항목 | 값 (`app/home/router.py`) |
| --- | --- |
| 인증 | 로그인 + 학생증 통과 가입자(`get_verified_caller`). 토큰이 없으면 401 |
| 응답 | `{"people": ["<base64 JPEG>", …]}` — **112×140**(`HOME_PEOPLE_SIZE`, 레일 칸 크기) JPEG 최대 **12장**(`HOME_PEOPLE_COUNT`). **id · 저장소 경로 · 공개 주소 · 닉네임 · 학교 · 성별은 싣지 않는다**(공개 저장소 주소에 profile_id 가 든다) |
| 블러 | 가우스 반경 **8**(`HOME_PEOPLE_BLUR_RADIUS`) — 머리색 · 옷 색 · 몸 형태는 남고 눈 · 코 · 입 · 안경 · 얼굴 윤곽은 뭉개진다. 10-15 그림 예시로 3 · 5 · 6 · 8 · 10 을 견줘 골랐다(6 이하는 생김이 어렴풋이 남고 10 은 머리와 얼굴 경계까지 사라짐). **이 한 곳만 고쳐 서버 배포로 바꾼다**(env 아님) |
| 후보 | `profiles` 에서 `status = active` · 자동 가림 아님(`auto_hidden_at is null`) · 매칭 일시중지 아님 · 나 아님을 **최근 활동 순 60명**(`HOME_PEOPLE_POOL`, 모든 학교 · 성별)으로 읽는다(`HomeRepository.fetch_recent_people`) |
| 빼는 사람 | 본인 · **일반 차단 양방향** · **지인 차단 양방향**(카드와 같은 규칙 — 지인을 막아 둔 사람 얼굴이 그 지인 홈에 뜨면 안 된다) · 매칭 일시중지 · 자동 가림 · 지금 아바타가 기본 그림(`is_fallback`)인 사람(옛 아바타가 있어도 안 쓰는 얼굴은 꺼내지 않는다 — "지금 아바타" = `ready` 중 최신, 채팅 `latest_avatar_path` 와 같은 규칙). 차단 조회는 **후보 60명 id 로만** 묻는다(`fetch_blocked_among` · `fetch_contact_block_partner_ids`) — 내 차단 전부를 읽으면 db-max-rows(1000)에서 조용히 잘린다 |
| 최소 인원 | 위 규칙을 지난 후보가 **10명 미만**(`HOME_PEOPLE_MIN`)이면 `{"people": []}` — 사람이 적으면 흐린 얼굴도 누구인지 짐작된다. 후보 수로 세므로 후보가 10명을 넘어도 사진 몇 장을 못 만들면 10장보다 적게 나갈 수 있다 |
| 고르기 · 만들기 | 후보 가운데 12명을 무작위로 뽑고(`get_rng`, 시험은 시드 고정), 비공개 `avatars` 원본을 **서버가 받아** 흐린 미리보기로 만든다(`cards/paid_preview.py` `cached_preview` — 유료 카드 미리보기와 같은 코드, 캐시 키 = 경로 · 크기 · 강도. 유료 카드 기본값 8×10 · 반경 1 은 바이트까지 그대로). 동시에 받고, 못 받거나 못 읽은 사람만 건너뛴다 |

- **로그**: 못 만든 장수만 WARNING `홈 레일 흐린 사진 <n>/<m> 장을 못 만들어 건너뛰었다` — 예외 문구에는 저장소 주소(경로 = profile_id)가 들어 있어 남기지 않는다
- **`/home/summary` 와 따로 둔 이유**: 캐시가 빈 인스턴스가 원본을 받아 흐리는 동안 요약이 늦어지지 않고, 여기가 실패해도 다른 블록은 그려진다. 앱은 요약이 도착했고 학교 대기(코호트)가 아닐 때만 부르고, 실패 · 빈 목록이면 5분 뒤 홈에 다시 들어올 때 다시 묻는다
- **순서 · 롤백**: 서버 먼저, 앱 나중이었다(앱이 먼저 나가면 레일이 기본 그림 칸으로 나올 뿐 깨지지 않는다). DB 변경이 없어 리비전만 되돌리면 되고, 되돌리면 앱 레일이 기본 칸이 된다(추정)
- **확인할 것**: 노션 방침의 "홈 흐린 아바타 노출" 한 줄 게시 여부는 이 문서 담당이 받지 못했다. 실기기에서 레일 그림이 서버 바이트로 나오는지는 E2E E-HOME-12 가 본다(앱이 `memory` 출처를 말하면 pass, 네트워크 주소면 fail)
- **알려진 한계(코드 주석)**: `last_active_at` 인덱스가 없어 `profiles` 를 훑어 정렬한다 — 가입자가 수만 명이 되면 `(last_active_at desc) where status='active' and auto_hidden_at is null and not matching_paused` 부분 인덱스(새 마이그레이션 + 승인). 후보 id 를 주소에 싣는 차단 조회는 POOL 이 100 이상이 되면 두 번 나누거나 RPC 로

## 4-12. 온보딩 서버 묶음 — 가입 전화번호 규칙 · 성별 · 유료 카드 MBTI 이유 · 소개글 프롬프트 (2026-10-15, 서버 PR #544 · 앱 PR #543)

사용자 폰 시험에서 지적된 가입 · 소개글 문제를 서버에서 고쳤다. **DB 마이그레이션 · 새 env · 새 시크릿 · 새 job 은 없다.** 앱 짝은 PR #543 이고, 옛 앱도 서버 422 를 일반 4xx 오류로 보여 줘서 **서버를 먼저 배포해도 안전했다**.

- **가입 전화번호 규칙(`POST /profile-onboarding/basic-info`)** — `app/profile_onboarding/phone_number.py` `to_signup_e164`. 숫자만 남겨 `+82` 를 국내 모양으로 되돌린 뒤(`to_e164`) **010 + 8자리만** 받는다(옛 011 · 016~019 는 막는다 — 앱이 이미 11자리만 받았다). 뒤 8자리가 ① 전부 같은 숫자(A, 10개) ② 한 줄로 이어지는 순서(B — `0123456789` · `9876543210` 안에 통째로 든 8자리, 오름 3 · 내림 3 = **6개**) ③ 알려진 가짜 6개(C — `12341234` · `12341111` · `11112222` · `12121212` · `00001234` · `12340000`)면 거른다
  - 막힌 번호는 **아무것도 쓰지 않고** **422** `{"detail": "올바른 휴대폰 번호를 입력해 주세요", "code": "phone_number_invalid"}`(`core/errors.py` `PHONE_NUMBER_INVALID` · `CODE_PHONE_NUMBER_INVALID`).
  - **연락처 차단 · 지인 대조는 `to_e164` 를 그대로 쓴다** — 친구 번호가 가짜 모양이어도 지문은 등록해야 한다. 이미 가입한 사람의 번호는 건드리지 않는다
  - 규칙 근거는 사용자 폴더 `CampusMate_문서/출시준비/전화번호_인증_방법_가격.md` §3-1 · §3-2 A·B·C · §3-4(패턴 하나가 막는 번호 1,000개 이내만). **앱 `SignupPhoneNumber`(`frontend/lib/profile/basic/model/data/signup_phone_number.dart`)와 같은 목록이어야 한다** — 한쪽만 고치지 않는다. 문자(SMS) 본인 인증은 사용자 결정 대기
- **성별(`BasicInfoRequest.gender`)** — `Literal["male", "female"]`(DB enum `gender` 와 같다). 그 밖의 문자열은 FastAPI 검증 오류 422 다
- **유료 카드 이유 "MBTI가 잘 맞아요"** — 내 선호 MBTI 에 **한쪽만 고른 축이 하나도 없으면**(`{}` · 8개 전부 · 축마다 양쪽 같음 = 전부 상관없음) 계수가 1.0 이어도 이 이유를 붙이지 않는다(`matching/scoring.py` `mbti_prefers_a_side`, `cards/paid_offer.py` `_strengths`). 점수 계산은 그대로다
- **자기소개 초안(`POST /profile-onboarding/bio-draft`)** — `app/profile_onboarding/bio_draft.py`. 프롬프트 원본은 사용자 폴더 `CampusMate_문서/출시준비/GPT_소개글_프롬프트.md` §5(대장 10-15 지시로 §7 전부 A 채택, 2~3문장)
  - 시스템 프롬프트: **한국어만**(MBTI 네 글자 · 관심사 이름의 원래 영문만 예외) · 1인칭 해요체 · MBTI 가 있으면 한 번 넣기(없으면 말하지 않기) · 성향 · 관심사 · 특징 중 3~4가지 · 2~3문장 안팎을 2~3문단으로(줄바꿈 한 번) · 120~220자 · 실명 · 학교 · 연락처 · **종교 · 흡연** · 외모 · 재산 금지
  - 사용자 프롬프트: `MBTI: <값 또는 "없음">` 을 **맨 앞 줄**로, 이어 성향 · 관심사 · 나의 특징. **종교 · 흡연은 재료에서 뺐다**(민감정보 — 이제 종교는 OpenAI 로 가지 않는다). 이상형 답변 · 닉네임 · 학교 · 학과 · 키 · 나이 · 전화번호는 넣지 않는다
  - 호출: `gpt-4o-mini` · `temperature=0.7` · `max_tokens=300`. 빈 줄은 줄바꿈 한 번으로 줄이고 앞뒤 공백을 자른다
  - **최대 2번 부른다**(`_ATTEMPTS = 2`): 허용된 영문 밖의 영어가 남거나 답이 비면 한 번 더 만든다. 두 번째에도 영어가 남으면 **마지막 결과를 쓴다**. 빈 답이면 앞의 초안을 지우지 않는다. **두 번 다 비면 502 이고 저장하지 않는다**(앱은 "직접 써 주세요" — 생성 실패와 같다, 빈 값을 저장하면 다음에 열어도 다시 만들지 않기 때문)
  - 초안은 사람마다 한 번 만들어 저장하므로 **이미 초안을 받은 사람은 그대로다** — 고친 뒤 새로 초안을 받는 사람부터 적용. 실제 OpenAI 호출 결과(한국어만 · 줄바꿈)는 PR 시점에 확인하지 못했다(배포 뒤 한 번 만들어 보기)
- **롤백**: DB 변경이 없어 리비전만 되돌리면 된다. 다만 `00078` 아래로 가면 가입 번호 규칙이 서버에서 풀리고(앱 vc6 의 즉시 안내만 남는다) 422 대신 옛 400 이 돌아온다(추정)

## 4-13. 홈 리뷰 띠 env · 받은 신청 프로필 · 무료 하트 값 · 아바타 확인 맨 끝 · 내 프로필 두 칸 (서버 PR #565 ~ #577)

이 절에 든 서버 PR:

| PR | 무엇 | 파일 |
| --- | --- | --- |
| #565 | 홈 리뷰 띠 스토어 평점 env 두 개 · `/home/summary` 두 칸 | `app/settings.py` · `app/home/router.py` |
| #568 | `GET /cards/acceptances/{card_id}` 받은 신청 한 건의 상대 프로필 | `app/cards/router.py` |
| #570 | 무료 하트 서버 상수(에브리타임 40 · 투표 표시 5) + DB 마이그레이션 2개 | `app/heart_tasks/router.py` · `app/community/router.py`(독스트링) · `supabase/migrations/20261016144525` · `20261016144530` |
| #574 | 아바타 확인 단계를 가입 맨 끝(자기소개 뒤)으로 · 다음 단계 조회가 가입 확정 | `app/profile_onboarding/onboarding_progress.py` · `repository.py` · `router.py` |
| #577 | `GET /me/profile` 에 `ideal_note` · `survey_answers` | `app/me/repository.py` · `app/me/router.py` |

**새 시크릿 · 새 Scheduler job · 테이블 · 열 변경은 없다.** DB 쪽은 #570 의 함수 재정의 하나 · FAQ 문구 갱신 하나뿐이다(아래).

### `GET /cards/acceptances/{card_id}` — 받은 신청 · 프로필 보기 (PR #568)

- **받는 사람 전용 · 읽기 전용**(아무것도 쓰지 않는다). 대화 탭 받은 신청 행의 "프로필 보기"(앱 13-4, `frontend/docs/DESIGN.md` §8.6 `acceptance-detail`)가 부른다. 인증은 다른 카드 경로와 같다(로그인 + 학생증 통과, 토큰 없으면 401)
- **판정 순서는 수락 응답(`respond_to_acceptance`)과 같고 코드도 같다**: 카드가 없음 · 내가 받는 사람(`target_id`)이 아님 · 그 카드의 결정이 수락이 아님 → **404** · 보낸 사람 프로필 행이 없음(지운 계정) · 카드에서 숨는 사람(차단 · 정지 등 `_hidden_from_cards`) → **404** · 이미 답함(`acceptance_responses` 있음) → **409** · 수락한 지 7일(`ACCEPTANCE_TTL_DAYS`)이 지남 → **410** · 이미 매칭된 상대 → **404**(받은 신청 목록에 없는 줄은 열리지도 않는다). 오류 문구는 기존 `ACCEPTANCE_NOT_FOUND` · `ACCEPTANCE_ALREADY_ANSWERED` · `ACCEPTANCE_EXPIRED`
- **응답**: `{"card_id": …, …}` + 10b 카드 상세와 **같은 몸통**(`profile_detail` — 아바타 공개 주소 · 성향 · 태그 · 소개글 등). **실사진 · 카카오톡 아이디 · 실명 · 전화번호는 싣지 않는다**(신뢰 확인 뒤 14c 몫). 시험 `backend/tests/cards/test_acceptance_detail.py`
- 옛 앱(빌드 15 · TestFlight 16 · AAB vc8)은 이 경로를 부르지 않는다 — 받은 신청 행의 거절 · 수락 버튼이 기존 `POST` 그대로라 영향이 없다

### 홈 리뷰 띠 환경변수 `STORE_RATING` · `STORE_RATING_COUNT` (PR #565)

- `settings.py` 의 `store_rating` · `store_rating_count` — **글자(str)로 받고 기본값 `"0"`**. 사람이 Cloud Run 에 손으로 넣는 값이라, 숫자 타입이면 잘못 넣는 순간 `Settings()` 가 실패해 서버 전체가 뜨지 않는다. 그래서 글자로 받고 검사는 홈 요약이 한다
- `GET /home/summary` 응답에 `store_rating`(0 또는 1 ~ 5 소수) · `store_rating_count`(0 이상 정수) 두 칸이 더해진다(`app/home/router.py` `_store_rating`). **검증: 숫자로 못 읽음 · 평가 수 음수 · 별점이 0 ~ 5 밖(NaN 포함) · 평가가 있는데 별점 1 미만이면 둘 다 0 으로 내린다** → 앱은 평가 수 0 이면 띠를 숨긴다(가짜 숫자를 보이지 않는다). 시험 `backend/tests/home/test_home_summary.py` · `backend/tests/test_settings.py`
- **운영 값**: `STORE_RATING_COUNT=0` — 평가 수가 0 이면 앱이 띠를 숨긴다(스토어에 실제 별점이 생기기 전에 가짜 숫자를 보이지 않으려는 것, §4-15). 스토어에 실제 별점이 생기면 `STORE_RATING` · `STORE_RATING_COUNT` 를 같이 고친다(코드 배포 없이 env 갱신만, 새 리비전이 생긴다).

```bash
# 값을 바꿀 때도 같은 명령이다 — 목록에 더하기만 한다. 값은 사용자 승인 뒤에.
gcloud run services update campus-mate-backend --project=<PROJECT_ID> --region=asia-northeast3 \
  --update-env-vars STORE_RATING=<별점>,STORE_RATING_COUNT=<평가 수>
```

- 둘 다 비어도 서버는 뜬다(띠만 숨는다).

### 무료 하트 값 (PR #570, 사용자 확정 10-16 "무료하트조정 확정")

| 항목 | 값 | 어디 |
| --- | --- | --- |
| 에브리타임 홍보 | **40하트** · 월 1회 | 서버 `REWARD_HEARTS["everytime_post"]` — 제출할 때 금액을 행에 적고, 승인 트리거가 그 금액을 준다(이미 낸 제출은 적힌 금액으로 승인) |
| 단톡방 공유 | **25하트**(그대로) · 월 3회 | 서버 `REWARD_HEARTS["kakao_share"]`. 앱 18b 캡션은 "3명 이상이 있는 단톡방에 …" |
| 커뮤니티 투표 | **하루 첫 투표 5하트** · **주 최대 15**(한국 시간 월요일 0시 기준) | 지급은 DB `cast_poll_vote` · `poll_vote_reward_due`(마이그레이션 `20261016144525`). 서버 `POLL_VOTE_REWARD` 5 는 18a 표시용이다 |
| 친구 코드(추천) | **양쪽 50하트**(그대로) → **2026-11-10 개정: 새 사람 50 · 코드 주인 25**(DB `20261110120000`, 운영 미적용, §4-25) | DB `redeem_referral` |

- **DB 마이그레이션 2개**: `20261016144525_poll_vote_reward_5_cap_15`(두 함수 안 숫자만 바꾸는 `create or replace` — 이름 · 인자 · 반환형 · 권한 그대로) · `20261016144530_faq_free_heart_amounts`(FAQ "하트를 무료로 얻는 방법이 있나요?" 답의 숫자와 "학교 단톡방" → "단톡방", `update … replace` 라 두 번 돌려도 같다)
- **운영 적용**: 두 파일 모두 운영에 적용됐다(2026-10-16, 사용자 승인 문장 뒤 `apply_migration`). 투표 함수 파일 머리말의 "초안 — 아직 어디에도 적용하지 않았다" 와 FAQ 파일 머리말의 적용 날짜는 쓸 때의 문장이다 — SQL 파일은 고치지 않는다(`docs/SUPABASE.md` §1). FAQ 는 운영 실제 문구 "하루 첫 투표에 10하트" 까지 바꾸게 고친 SQL 그대로다(PR #573).
- **순서**: DB(투표 함수) → 서버 → 확인. 투표 함수(DB)와 서버 상수(18a 표시)는 같이 간다 — 어느 쪽이 먼저든 짧게 겹치는 동안 글자만 어긋난다(돈 · 데이터는 깨지지 않는다).
- **전환 주**: 적용한 날이 든 주에 옛 10하트를 한 번 받았으면 5하트를 한 번 더 받아 15 에서 멈추고, 두 번 이상 받았으면 그 주는 더 받지 못한다(이미 받은 하트는 회수하지 않는다, 마이그레이션 머리말)

### 아바타 확인을 가입 맨 끝으로 · 다음 단계 조회의 가입 확정 (PR #574)

- **단계 순서**(`onboarding_progress.py` `_STEPS`): basic_info → kakao_id → photos → appearance_type → interests → my_traits → survey → ideal_conditions → ideal_traits → ideal_note → bio → **avatar** → complete. **설문을 마치면 아바타가 아직이어도 06-1 로 간다.** 조건식(`avatar_ready` = ready 행이 하나라도 있음, 5회 실패 보상의 기본 아바타 포함)은 그대로이고 작업 등록은 여전히 04-3 이다
- **가입 확정(`profiles.status` `pending` → `active`)이 두 곳**: ① `POST /profile-onboarding/bio` 저장 때 다음 단계가 complete 면(= 아바타가 이미 ready) 그 자리에서 ② **새로** `GET /profile-onboarding/next-step` 이 complete 를 계산했고 스냅샷 `_status` 가 `pending` 이면 `activate_profile` 을 부른 뒤 응답한다 — 06-3 저장 때 아바타가 아직이던 사람은 아바타가 끝난 뒤 앱이 단계를 다시 물을 때(리빌 "확인했어요", 앱 다시 켜기, 토큰 갱신) 가입이 끝난다
- **`activate_profile` 은 조건부 PATCH**(`status=eq.pending` 인 행만 → `active`) — 정지 · 탈퇴를 되살리지 않고, 06-3 저장과 단계 조회가 겹쳐도 한 번만 바뀐다. 이미 active 인 사람의 조회는 쓰기 0번이다(토큰 갱신마다 도는 조회라 사람마다 평생 한 번만 쓴다)
- 시험 `backend/tests/profile_onboarding/test_onboarding_progress.py` · `test_onboarding_router.py`(pending 활성화 · active · suspended · withdrawn 은 안 씀 · 아바타 미완성이면 안 씀 · 옛 앱 순서)

### `GET /me/profile` 두 칸 — `ideal_note` · `survey_answers` (PR #577)

- `ideal_note`: 문자열 또는 `null`(06-2a 이상형 글). `survey_answers`: `{"1": 0.5, …, "9": -1.0}` — 축 번호(1 ~ 9, `POST survey` 의 `answers` 와 같은 키) → 값(−1 ~ 1, numeric 이 정수 모양으로 와도 float 로 내린다). **설문 전이면 `{}`**
- 같은 읽기 요청의 `select` 에 `ideal_note` 와 `survey_answers(axis,value)` embed 를 넣었다 — 요청 수 1회 그대로, 내 행 아래 embed 라 남의 답은 닿지 않는다(FK `profile_id` → `profiles.id`). DB · 스키마 변경 없음. 시험 `backend/tests/me/test_me_profile.py`
- 쓰는 곳: 새 앱의 온보딩 뒤로가기(설문 · 06-2a 로 돌아갔을 때 저장한 값 채우기, 앱 PR #579). 옛 앱은 모르는 키를 무시한다. **새 앱 + 옛 서버**면 두 칸이 없어 앱이 빈 값으로 읽는다 — 돌아간 설문에서 9축을 미리 고르지 않아 직접 다시 골라야 보낼 수 있다(저장한 답을 0 으로 덮어쓰지 못하게 앱이 막는다)

### 배포 순서 · 롤백 주의

1. **DB**(사용자 승인 뒤 `apply_migration`): `20261016144525` · `20261016144530`.
2. **서버**: §2 "현행 배포 방식"으로 배포한다. 새 env(`STORE_RATING` · `STORE_RATING_COUNT`)는 `--update-env-vars` 로 더한다.
3. **앱**: 새 앱 빌드는 서버 배포 뒤에 낸다 — 새 앱은 받은 신청 행에 "프로필 보기" 하나뿐이라 옛 서버(경로 없음 → 404)에서는 **받은 신청에 답할 수 없다.** 아바타 확인 화면 · 리빌 · 설문 채우기도 새 서버를 전제로 한다(위).

**롤백**: 테이블 · 열 변경이 없어 서버는 리비전만 되돌리면 된다(하한은 §5). 단 **새 앱이 나간 뒤에는 이 묶음이 든 리비전 아래로 되돌리지 않는다** — 새 앱의 받은 신청 답하기가 404 로 막힌다. 되돌린 사이 06-3 을 냈는데 아바타가 아직이던 사람은 서버를 다시 올린 뒤 단계 조회 때 가입이 끝난다(추정). 투표 함수는 되돌리지 않는다(되돌리려면 옛 값 10 · 30 으로 새 마이그레이션 + 승인).

### 배포 후 점검 목록 (다음 배포에도 같은 목록을 쓴다)

- `curl https://<서비스 URL>/health` → `{"status":"ok"}`(§3)
- 무인증 401: `curl -s -o /dev/null -w '%{http_code}' https://<서비스 URL>/profile-onboarding/next-step` → `401`
- env: `gcloud run services describe campus-mate-backend --region=asia-northeast3 --format='value(spec.template.spec.containers[0].env)'` 로 이름만 본다(값을 보고서 · 채팅에 적지 않는다)
- 로그: 배포 뒤 30분 동안 Cloud Run 로그에 5xx · `upstream_call_failed` · Traceback 이 새로 늘지 않는지. 실명 · 사진 경로 · 웹훅 주소가 찍히지 않는지(§4-6)
- 기능 한 번씩(보호 계정): 받은 신청 프로필 보기 200 · 이미 답한 건 409 / `GET /home/summary` 의 `store_rating` · `store_rating_count` / 18a 줄 "40 · 월 1회" · "5 · 주 최대 15" / 설문만 낸 계정의 next-step 이 `ideal_conditions` · 다 낸 pending 계정이 next-step 한 번에 `active` / `GET /me/profile` 에 `ideal_note` · `survey_answers`
- 리비전 이름을 §5 에 적는다

## 4-14. 인증샷 여러 장 · 졸업생 인증(코드 기본 꺼짐, 운영은 켬) · 저녁 알림 기본값 · 관리자 웹 env (서버 PR #613 ~ #619)

운영에서는 졸업생 스위치가 켜져 있다. 새 시크릿 · 새 Scheduler job · 새 Cloud Tasks 큐는 없다(env 는 관리자 웹 2개 + 스위치 1개가 늘었다, §2). **되돌림 하한: `00087` 이전으로 되돌리지 않는다**(`00086` 은 인증샷 제출이 깨진다).

묶음에 든 서버 · DB 변경(앱만 바뀐 PR #591 카카오 초대 코드 공유 · #611 사진 안내문 · #612 연락처 제한 안내문은 서버가 없다):

| PR | 무엇 | 서버 파일 | DB 마이그레이션 |
| --- | --- | --- | --- |
| #613 | 인증샷 1~3장 + 단톡방 검수 중에도 월 3회까지 이어 제출 + 관리자 사진 여러 장 | `app/heart_tasks/*` · `app/admin/heart_task_review.py` · `app/admin/repository.py` | `20261019100000_heart_task_multi_photos` |
| #614 | 저녁 알림 제한(방해 금지) 기본값 꺼짐 | `app/cards/*`(알림 설정 `NOTIFICATION_DEFAULTS` · `push.notify`) | `20261019210000_notification_quiet_hours_default_off` |
| #615 | 졸업생 인증(신청 · 관리자 검수 · 정리 · 탈퇴 연동) | `app/graduate_verification/*` · `app/admin/graduate_*.py` · `app/account/*` · `app/chat/batch_router.py` · `app/student_verification/router.py` | `20261019200000_graduate_verification_tables` · `20261019200100_graduate_verification_functions` |

운영 DB 에는 위 마이그레이션 4개가 적용돼 있다. 원격 기록 버전은 파일 이름이 아니라 **적용 시각**이다(`docs/SUPABASE.md` §4 관례).

### 인증샷 여러 장 · 이어서 제출 (PR #613, 계획서 `2026-10-19-heart-task-multiphoto.md`)

- `heart_task_submissions.storage_path`(한 장) → **`storage_paths text[]`**(1~3개, check)로 바뀌었다. 옛 칸은 지웠고 옛 줄은 사진 1장짜리로 채웠다. "항목당 검수 중 한 줄" 부분 유일 인덱스도 지웠다. `submit_heart_task` 는 인자가 `p_path text` → `p_paths text[]` 로 바뀌어 **옛 함수를 지우고 새로 만들었고**, 사람 · 항목마다 advisory lock 아래에서 월 한도를 센다(동시 제출이 한도를 넘지 못한다).
- `POST /heart-tasks/{task}/submissions` 는 multipart 파트 `photos`(1~3장) 또는 옛 `photo`(1장)를 받는다. 오류: 400 사진 형식 · 크기, 422 0장 · 4장 이상, 409 한도에 찼고 검수 중(`HEART_TASK_IN_REVIEW`), 429 한도에 찼고 검수 중 없음(`HEART_TASK_MONTHLY_LIMIT`). 파일 이름은 `{profile_id}/{submission_id}-{n}.{jpg|png}`.
- `GET /heart-tasks` 줄은 **옛 여섯 칸을 그대로 두고** `can_submit` · `max_photos` · `pending[]`(`id` · `created_at` · `photo_urls` 600초 서명) 세 칸을 더했다. 옛 앱은 모르는 칸을 무시한다. 관리자 `GET/POST /admin/heart-tasks/{id}` 에는 `photo_urls`(5분 서명, 장수 유지) 가 더해지고 옛 `photo_url`(= 첫 장)은 남는다. 60일 정리와 탈퇴 정리는 장 수만큼 파일을 지운다.
- **배포 틈 · 되돌림 하한(대장 확정 D5)**: 옛 칸을 없앴으므로 마이그레이션 적용 **직후 곧바로 서버를 배포**해야 했다(그 사이 제출 · 관리자 사진 보기 오류). **서버만 `00086-7zf` 이전으로 되돌리면 인증샷 제출 · 관리자 사진 보기가 깨진다**(옛 서버는 `storage_path` 와 `p_path` 를 쓴다). 되돌림이 필요하면 **고친 서버의 새 리비전**으로 한다 — 이 묶음 이후 서버 안전 하한은 **`00087`** 이다.

### 저녁 알림 제한 기본값 (PR #614)

- `notification_settings.quiet_hours`(22~08시 방해 금지) 기본값을 **앱 · 서버 `NOTIFICATION_DEFAULTS` · DB 컬럼 모두 `false`** 로 바꿨다. 새 가입자부터 꺼진 채 시작한다.
- **기존 사용자 값은 지킨다**: 서버가 "설정 행이 없으면 켜짐"으로 읽고 있어서, 마이그레이션이 **행이 없는 기존 사용자에게 `quiet_hours = true` 행을 먼저 채우고** 그다음 컬럼 기본값을 `false` 로 바꾼다. 이미 행이 있는 사용자는 건드리지 않는다.
- **순서: 마이그레이션 → 서버 → 앱.** 서버가 마이그레이션보다 먼저 나가면 행 없는 기존 사용자의 제한이 꺼진다.

### 졸업생 인증 서버 (PR #615, 계획서 `2026-10-19-graduate-verification.md`, 결정 기록 `docs/decisions/2026-10-19-graduate-verification-decision.md`)

**스위치: `GRADUATE_VERIFICATION_ENABLED` — 코드 기본값은 `false`(꺼짐)이고, 운영은 `true` 로 켜 두었다.** 켜진 서버는 `GET /me/verification-status` 의 `graduate_enabled` 가 `true` 이고 새 앱은 동의 다음에 인증 방법 고르기를 한 번 지난다(옛 앱 vc11 · vc12 는 모르는 칸을 무시하고 지금처럼 학교 메일이 바로 나온다). **꺼진 서버(코드 기본값 · 끄기 명령 후)에서는** 새 앱도 학교 메일 관문만 만나고, `PUT /me/verification-method` 의 졸업증명서 값과 `POST /graduate-verification` 은 403 `graduate_disabled` 다. 관리자 웹의 "졸업생" 화면은 신청이 들어오면 바로 쓴다.

**켜기 조건** — 켜는 것은 별도 사용자 승인이 필요하다. 아래 세 가지는 **공개 출시(스토어 제출) 전까지** 끝내야 한다. 1번 처리방침(노션)과 이용약관은 반영을 마쳤다. 2번 스토어 개인정보 양식과 3번 법률 확인 · 실제 졸업증명서 샘플 판독 검증이 끝났다는 전달은 받지 못했다.

1. **처리방침 변경 반영**: 수집 항목(졸업증명서 사진 · 이전 학교 이메일 · 문서확인번호), 목적, 보유 기간(사진 = 결정 즉시 · 최대 14일, 평문 = 결정 즉시, 해시 = 계정 존속 + 재가입 제한 기간), 처리 위탁 · 국외 이전(Google Cloud Vision), 관리자 열람 기록, 동의 방식.
2. **스토어 개인정보 양식 변경**(구글 데이터 보안 · 애플 앱 개인정보). 칸 이름은 스토어 현재 화면을 보고 확정한다. 새 앱 빌드를 **제출하기 전에** 반영한다.
3. **법률 확인 + 실제 졸업증명서 샘플 판독 검증**(계획서 0-5 · 11장).

```bash
# 켜기 — 사용자 승인 문장 뒤에만. 목록에 더하기만 한다(--set-env-vars 금지, §2). 새 리비전이 생긴다.
gcloud run services update campus-mate-backend --project=<PROJECT_ID> --region=asia-northeast3 \
  --update-env-vars GRADUATE_VERIFICATION_ENABLED=true
# 끄기(되돌리기): 같은 명령에 =false, 또는 --remove-env-vars GRADUATE_VERIFICATION_ENABLED. 코드 배포 없이 끝나고 새 앱도 옛 관문으로 돌아간다.
```

- **켠 뒤 점검**(신청 · 승인 · 삭제 확인의 운영 결과는 받지 못했다): `GET /me/verification-status`(시험 계정 토큰)의 `graduate_enabled` 가 `true` → 시험 계정으로 신청 → 관리자 웹 "졸업생" 목록에 뜸 → 승인 또는 반려 → **버킷 `graduate-cert-temp` 가 비어 있음**(결정 즉시 삭제 확인) → 신청 행의 평문 3칸(`ocr_document_number` · `ocr_school_text` · `previous_school_email`)이 null. 켠 뒤 서버 안전 하한은 `00087` 이다(그 아래는 `PUT /me/verification-method` 가 404).
- **새 시크릿 없음**: 스위치(env 1개, 시크릿 아님)는 `GraduateSettings`(별도 클래스, 코드 기본 `false`)가 요청마다 읽는다. 번호 · 학번 해시는 기존 **`IDENTITY_HMAC_KEY`** 를 같은 키로 쓰되 입력 앞에 `graduate-document|` · `graduate-student|` 접두사를 붙여 학교 메일 해시와 겹치지 않는다(키를 바꾸면 졸업생 해시도 모두 무효가 된다 — `key_version` 칸). 글자 인식은 기존 Vision 클라이언트 팩토리(`get_vision_client_factory`)를 그대로 쓴다 — 새 API 사용 설정 없음. 신청 알림은 학생증 때와 같은 디스코드 채널(`DISCORD_WEBHOOK_URL`)로 가며 **신청 id 와 profile_id 만** 싣는다.
- **버킷 `graduate-cert-temp`**: 마이그레이션이 만든 비공개 버킷(10MB, `image/jpeg` · `image/png`, 클라이언트 정책 없음). 경로 `{profile_id}/{request_id}.jpg|png`. 옛 `student-id-temp` 와 섞지 않았다(그 안의 옛 학생증 삭제는 사용자 승인 대기, 출시후_할일 1-1).
- **정리 배치**: 새 job 이 아니라 **기존 매시 `/batch/chat-gate`** 가 한다(§4-1). ① 14일 지난 대기 신청 → `cancelled(expired)` + 평문 비움 + 사진 삭제 ② 학교 메일로 따로 인증을 마친 사람의 대기 신청 닫기(`verified_otherwise`) ③ 결정이 났는데 `photo_path` 가 남은 줄의 사진 삭제. 응답에 키 `graduate_photos_deleted` · `graduate_pending_expired` · `graduate_verified_cancelled` 가 더해졌다(옛 학생증 키는 그대로). 졸업생 정리가 터져도 응답은 200 이고 앞 결과는 유지된다. 미인증 14일 계정 정리(`/batch/cleanup`)는 **대기 신청이 있거나 14일 안에 결정된 졸업생을 지우지 않는다**(DB 함수 `list_unverified_accounts` 교체 + 지우기 직전 재확인).
- **탈퇴**: 대기 신청을 `cancelled(account_withdrawn)` 으로 닫고 사진 폴더를 비운다(`withdraw` 단계 `graduate_request` · `graduate_files`). 재가입 제한 해시는 학교 메일 claims 가 먼저, 없으면 졸업생 학번 해시, 둘 다 없으면 없음(null)이다. 읽기가 실패하면 둘 다 503 으로 멈춘다(null 로 탈퇴시켜 제한을 잃지 않는다).
- **경로**: 신청자(로그인 + 정지 · 동의 확인) `PUT /me/verification-method` · `POST /graduate-verification`(multipart `photo` · `agreed` · 선택 `previous_school_email`, 201 `{"state":"pending","attempts_left":n}`) · `GET /me/verification-status` 새 칸 `graduate_enabled` · `verification_method` · `graduate`. 관리자(`get_admin_caller` — 로그인 → 2단계 aal2 → 명단) `GET /admin/graduate-requests` · `GET /admin/graduate-requests/{id}` · `POST .../approve` · `POST .../reject`. 오류 응답은 `{"detail": 문구, "code": 코드}`(인앱결제와 같은 모양). 반려 사유 코드 4개 `unreadable` · `not_certificate` · `unverifiable` · `school_unsupported`. 신청은 사람당 **3회**(만료로 닫힌 것은 세지 않는다), 대기는 **14일**을 넘기지 못한다.
- **푸시**: 종류 `verification_result` 를 재사용(알림 종류 check 변경 없음), `data` = `route: graduate_verification` · `state` · `reason`. 앱은 화면을 옮기지 않고 인증 관문만 다시 묻는다.
- **로그**: 사진 경로 · 문서확인번호 · 학번 · 이메일 · OCR 글자를 로그와 디스코드에 쓰지 않는다 — 신청 id 와 profile_id 만. 배포 뒤 30분 동안 로그에서 이를 확인한다(§4-6).

### 약관 동의 판 · 원본대조번호 (PR #619 · #617)

- **`CONSENT_VERSION`**(`backend/app/consents/policy.py`)을 올리면 이미 가입한 계정은 모두 02-c-4 재동의 화면을 한 번 거친다(신규 가입자는 새 판으로 기록, DB 제약은 날짜 형식 text 라 새 값을 막지 않는다). E2E 하네스 상수도 같은 값으로 맞추고, 서버 상수와 같은지 보는 시험이 있다. 현재 판은 `2026-10-20` 이다(§4-15).
- **PR #617 졸업증명서 번호 라벨에 "원본대조번호" 추가**(`graduate_verification/document_reader.py`): 서울대학교 양식은 문서확인번호 라벨이 "원본대조번호"라 OCR 이 번호를 못 읽었다. 라벨 목록 = 원본대조번호 · 문서확인번호 · 문서번호 · 확인번호 · 발급번호(라벨 글자 사이 공백 허용), `제 ○○ 호` · 학위등록번호는 문서확인번호가 아니라 읽지 않는다. 합성 글자로 시험했고 **실제 졸업증명서 샘플 판독 검증은 여전히 안 됐다**(결정 기록 §6 위험 1). 스위치가 켜져 있어 지금 쓰인다.

### 관리자 웹 환경변수 `ADMIN_ALLOWED_ORIGINS` · `ADMIN_BASE_URL`

- **`ADMIN_ALLOWED_ORIGINS`**: 쉼표 목록(관리자 웹 주소). **비어 있으면 CORS 를 붙이지 않는다**(관리자 웹 배포 전과 같다). `*` 를 넣으면 서버가 **기동하지 않는다**(`AdminWebSettings` 검사). 끝의 `/` 는 서버가 뗀다. `Settings` 가 아니라 별도 클래스가 `main.py` import 때 읽는다.
- **`ADMIN_BASE_URL`**: 관리자 웹 주소. 있으면 디스코드 인증샷 · 신고 알림에 그 건의 검수 링크를 싣는다(없으면 "Supabase 대시보드에서 확인").
- `ADMIN_MFA_MAX_AGE_HOURS`(기본 12, 관리자 2단계 인증 나이 상한)는 운영 서비스에 넣지 않은 것으로 **추정**한다 — 이 문서 담당이 서비스를 조회하지 않았다.
- 값은 이 문서에 적지 않는다. 관리자 웹은 Vercel 에서 main 반영 때 자동 배포된다. 인증샷 여러 장 보기는 `photo_urls` 가 없는 옛 서버 응답도 읽어서 서버보다 먼저 나가도 죽지 않는다(사진은 첫 장만).
- **`admin_actions` 는 SQL 창에서 손대지 않는다**: 관리자 쓰기 경로의 작업 기록이고(보관 2년) 서버가 같은 요청 안에서 쓴다. `admin_users`(관리자 명단)는 서버가 읽기만 한다 — 등록은 사용자 승인 뒤 대장이 SQL 한 줄로 한다.

### 배포 순서 · 롤백 주의

1. **DB**(사용자 승인 뒤 `apply_migration`, 파일 번호 순서) → `20261019100000` 을 적용한 직후 **곧바로 서버**(인증샷 틈) → 관리자 웹(Vercel 자동) → **앱**(AAB · TestFlight). 앱은 서버 뒤에 나간다.
2. 서버 배포는 §2 "현행 배포 방식"(env · 시크릿 이어받기). 04:00 KST 정리 시각 전후는 피한다.
3. **롤백 하한**: 어떤 경우에도 `00063` 아래로 가지 않는다(§4-4). 이 묶음 이후에는 **`00087` 이전(`00086`)으로 되돌리지 않는다** — `storage_paths` 마이그레이션 때문에 인증샷 제출 · 관리자 사진 보기가 깨진다. 되돌림은 "고친 서버의 새 리비전"으로 한다. 스위치를 켠 운영에서는 `00087` 이전이 `PUT /me/verification-method` 404 로 새 앱의 방법 고르기도 막는다. 졸업생 기능만 끄려면 리비전을 되돌리지 말고 스위치 env 를 `false` 로 바꾸는 새 리비전을 만든다. 마이그레이션은 되돌리지 않는다.
4. **iOS 암호화 신고**: `ITSAppUsesNonExemptEncryption = false` 가 설정돼 있다(앱 안 암호화는 로그인 nonce 해시뿐이고 나머지 통신은 OS 의 HTTPS 다).

### 배포 후 점검 목록 (다음 배포에도 같은 목록을 쓴다)

- `/health` 200 · 무인증 호출 401 · ERROR 로그 0
- `GET /me/verification-status`(시험 계정) 의 `graduate_enabled` 가 `true` 이고 옛 칸이 그대로
- 매시 `/batch/chat-gate` 응답에 `graduate_*` 세 키
- 인증샷 제출 한 번(시험 계정) + 관리자 상세에서 사진 여러 장 보기, `NOTIFY pgrst, 'reload schema'` 가 필요했는지
- 사진 경로 · 번호 · 이메일이 로그에 없는지(§4-6)

## 4-15. 약관 동의 판 2026-10-20 · 리뷰 띠 숨김 · 코호트 오픈 시각 · 환불 확인 배치 · 서버 스케줄

졸업생 스위치 `GRADUATE_VERIFICATION_ENABLED` 는 켜진 채이고 되돌림 하한은 **`00087` 이전 금지**(§4-14)다. 새 시크릿 · 새 Cloud Tasks 큐는 없다.

| 항목 | 값 |
| --- | --- |
| 약관 동의 판 | `CONSENT_VERSION = "2026-10-20"`(`backend/app/consents/policy.py`, PR #626 — Firebase 수집 안내를 반영한 약관 · 방침 시행일 2026-10-20). 이미 가입한 계정은 모두 02-c-4 재동의를 한 번 거친다(10-19 판 #619 와 같은 방식). E2E 하네스 상수도 같은 값(서버 상수와 같은지 보는 시험이 있다). |
| 홈 리뷰 띠 | 환경변수 **`STORE_RATING_COUNT=0`** — 평가 수가 0 이면 앱이 띠를 숨긴다(§4-13 검증 규칙). 스토어에 실제 별점이 생기기 전에 가짜 숫자(5.0 · 1명)를 보이지 않기 위해서다. 실제 별점이 생기면 `STORE_RATING` · `STORE_RATING_COUNT` 를 같이 고친다(§4-13 명령 그대로, 새 리비전이 생긴다). |
| 코호트 오픈 시각 | 서버 코드 변경이 아니라 **DB 데이터**다: 서울 학교 64곳의 `universities.card_opens_at = 2026-11-02(월) 07:00 KST`(마이그레이션 `20261020110000`, `docs/ERD.md` §3). 홈이 이 값을 읽어 오픈 대기(카운트다운)를 보인다. 시험 학교(`region_group = 'e2e'`) 1곳만 열려 있다(심사 계정용). **운영 값은 지금 null 이다(열려 있음) — §4-17 "카드 오픈 날짜".** |
| 최대 인스턴스 | **20** (Cloud Run `--max-instances`) |
| 로그 보관 | **30일** |
| 졸업생 인증 | 스위치 켜짐 유지 |

**서버 스케줄(Cloud Scheduler) 4개** — 전부 OIDC(§4-3):

| 일 | 경로 | 시각(Asia/Seoul) |
| --- | --- | --- |
| 카드 지급 | `/batch/daily-cards` | 매일 07:00 |
| 정리(탈퇴 · 미인증 계정 · 60일 지난 하트 인증샷 · 취향 단어 빈 칸 다시 채우기) | `/batch/cleanup` | 매일 04:00 |
| 채팅 확인(신뢰 확인 게이트 · 알림 · 졸업생 정리) | `/batch/chat-gate` | 매시 정각 |
| 환불 확인(구글 Voided Purchases) | `/batch/billing-voided` | 매시 30분 |

**환불 정책 A (남은 하트만 회수)** — `refund_store_purchase` 는 `min(잔액, 구매분 + 보너스)` 만 거두고, 모자란 수는 `purchases.clawed_back_hearts` 와 `shortfall` 로 남긴다(`docs/ERD.md` §6). 관리자 웹 결제 화면에 **"환불이 잦은 계정"** 표가 더해졌다 — 서버 `GET /admin/billing/frequent-returns`(경로에 `refund` 를 쓰지 않는다, e2e 금지어), DB 함수 `admin_billing_returned_accounts`(`20261019220000`). 서버 코드는 PR #622 로 main 에 들어왔고 `00091-rnc`(PR #626 이후 리비전)에 포함된다(main 순서에서 본 추정 — 리비전별 목록은 전달받지 못했다). 정책 B(다른 보상 방식)는 출시 후로 미뤘다.

**스토어 사실**: 국가는 대한민국만, 출시는 수동(관리형)이다. 연령 등급은 앱스토어 한국 19+, 구글 18+(타겟층). 아이폰 전용(iPad 는 호환 모드), 안드로이드는 세로 고정이 없고 접이식 기기는 시험하지 않았다. 빌드 · 제출 경위는 `docs/history/deploy-log-2026.md` 와 `docs/decisions/` 에 있다.

**사고 기록 — vc13 ~ vc17 카카오 키 빈 값(2026-10-20)**: `android/app/build.gradle.kts` 는 카카오 복귀 스킴 키를 환경변수 `KAKAO_NATIVE_APP_KEY` → `android/local.properties` → 빈 문자열 순으로 읽어 `manifestPlaceholders["kakaoKey"]` 에 넣는다. 이 값은 `--dart-define` 과 **별개**라서, `--dart-define` 만 맞추고 환경변수를 빼먹으면 빌드는 되는데 매니페스트의 `kakao<키>` 스킴이 빈 값이 되어 카카오 로그인이 앱으로 돌아오지 못한다. **재발 방지 규칙**: 안드로이드 릴리스 빌드 전에 같은 셸에서 `export KAKAO_NATIVE_APP_KEY=...` 를 하고, 빌드 뒤 AAB 매니페스트에서 `kakao<키>` 스킴을 확인한다(`frontend/run.md` "AAB 빌드"). 결정 배경은 `docs/decisions/2026-10-20-launch-day-decisions.md`.

**되돌림 주의(약관 판)**: `policy.py` 는 현재 판의 동의 행만 센다. `00091-rnc` 아래의 약관 판(`2026-10-19`)으로 되돌리면 2026-10-20 판만 동의한 신규 가입자는 02-c-4 를 다시 만난다(코드 근거, 시험하지 않았다).

## 4-16. 관리자 매칭 현황 "대화 신청" 목록 · 구글 심사용 시험 데이터 · 심사원 로그인 계정 (서버 PR #631)

새 env · 시크릿 · job 은 없다. 운영 DB 함수 `admin_matching_requests` 가 적용돼 있고(원격 버전 `20261027053822`), 관리자 웹은 `admin-web.yml` 로 자동 배포된다.

| 항목 | 값 |
| --- | --- |
| 서버 경로 | `GET /admin/matching/requests?status=&limit=&before=` (`backend/app/admin/matching.py`). `status` ∈ `waiting` · `accepted` · `rejected` · `expired`(틀리면 422), `limit` 1 ~ 100(기본 50), `before` = 앞 쪽의 `next_before`(`{requested_at}\|{card_id}` 꼴). 최근 순. 다른 관리자 경로와 같이 로그인 → 2단계(aal2) → 명단 관문(`get_admin_caller`) 아래이고, 읽기만 하므로 작업 기록(`admin_actions`)에 남기지 않는다(설계 §8-4c) |
| DB 함수 | `admin_matching_requests(p_status, p_before_at, p_before_id, p_limit)` — 마이그레이션 `20261027100000`. 새 표 없음, `security invoker` · `search_path ''` · `service_role` 만 실행(`docs/ERD.md` §7). 신청 = 카드를 받은 사람이 **수락**한 것(`card_decisions.decision = 'accept'`) |
| 반환 칸 10개 | 카드 id · 신청 시각 · 상태 · 응답 시각 · 신청한 사람(id · 닉네임 · 학교) · 받은 사람(id · 닉네임 · 학교). **사진 · 카톡 아이디 · 대화 · 전화는 없다.** 이 목록은 관리자 계정을 따로 거르지 않는다(SQL 에 그 조건이 없다) |
| 상태 판정 | 앱의 "보낸 신청"(`backend/app/cards/router.py` 의 `_sent_state`, 만료 `ACCEPTANCE_TTL_DAYS = 7`)과 같은 순서: 두 사람의 `matches` 줄이 있거나 응답이 수락이면 `accepted` → 응답이 거절이면 `rejected` → 응답이 없고 신청 후 7일이 지났으면 `expired` → 그 밖은 `waiting`. 신청하는 순간 즉시 매칭이 되는 길은 없다(매칭은 받은 사람이 답할 때만 생긴다) |
| 화면 | 관리자 웹 A9 매칭 현황 맨 아래 "누가 누구에게 대화를 신청했나"(읽기 전용, 상태 칩 5개 · 표 · 더 보기). `frontend/docs/DESIGN.md` §15 |
| 시험 | pgTAP `supabase/tests/admin_matching_requests_test.sql`, pytest `backend/tests/admin/test_admin_matching.py`, admin_web `test/matching/` |
| 알려진 한계 | `shortcut:` — 수락 전체를 훑고 정렬한다. 수락이 수십만 건을 넘으면 카드 결정 `(decided_at desc, card_id desc)` 인덱스를 더한다(SQL 주석). 지금 규모에서는 의미 없다 |

**배포 순서 · 롤백 주의 (코드 근거 — 시험하지 않았다)**
- 순서는 평소대로 **머지 → DB → 서버**다. DB 를 먼저 올려도 옛 서버는 이 함수를 부르지 않는다. 서버를 먼저 내보내면 이 경로만 함수를 못 찾아 오류가 난다(추정).
- **롤백 하한 판단**: `00092` 에서 `00091` 로 내리면 `GET /admin/matching/requests` 가 404 가 되고, 관리자 웹 A9 맨 아래 목록만 "신청 목록을 불러오지 못했어요" 를 보인다(그 목록은 위쪽 숫자 · 매칭 쌍 표와 따로 받는다). **사용자 앱에는 영향이 없다** — 추가된 것은 읽기 함수 하나뿐이고 표 · 열 변경이 없다. DB 함수는 서버가 내려가도 남아 있어 무해하다. 그래서 하한은 그대로 **`00063` 아래 금지 + `00087` 이전 금지**(§4-14)다.

**구글 심사용 시험 데이터 — 운영 DB 에 들어 있다, 공개 전 · 심사 통과 뒤 제거**
- 구글 Play 심사 대응으로 운영 DB 에 시험 데이터를 넣었다: 시험 학교(`region_group = 'e2e'`) 소속 가상 계정 **20개** + 심사 계정 앞으로 오늘 카드 **1장**(**만료 2026-10-28 07:00 KST**, 아직 결정 없음) + 채팅방 **3개**(메시지 합 16). 알림 · 푸시 행은 0, 네 표의 트리거 · 웹훅은 0건이었다. 사용자 승인 원문(메모 기록): 「실사용자 없어 승인해줄게」(10-26, 이 한 건 한정).
- **제거**: 구글 심사 통과를 확인한 뒤 **사용자에게 먼저 묻고** 지운다. 되돌림 스크립트와 manifest 는 저장소가 아니라 바탕화면 `E2E_결과\심사용_시험계정_10-27\` 에 있다(`rollback.py` — 먼저 dry-run, 승인 환경변수를 줘야 `--apply`, manifest 에 든 id 만 지운다).
- **그 전에는 하네스 전체 cleanup 을 돌리지 않는다**(시험 계정까지 지운다). 카드는 10-28 07:00 에 만료되므로 심사가 그보다 늦어지면 연장할지 사용자에게 묻는다(운영 쓰기 → 승인 문장 필요).
- 관리자 대화 신청 목록에 보이는 "수락" 2건은 이 시험 데이터일 가능성이 크다(대장 전달 추정, 확인하지 못했다).
- **운영 Auth 쓰기 — 심사원 로그인 계정(사용자 승인).** 안드로이드 전용 숨은 심사원 로그인(앱 1.0.2, `frontend/CLAUDE.md`)이 쓸 수 있게 **기존 심사용 계정(id 앞 8자 `acdbb0fc`)에 운영 Auth 관리자 API 로 비밀번호를 붙이고, 로그인 이메일을 심사 안내문에 맞춰 바꿨다.** 서버 · DB 코드는 바뀌지 않았다. 이 계정은 활성 · 학교 메일 인증 통과 · 구글 연결(identity)이 있고, 서버는 `GET /auth/user` 의 id 만 읽고, 가입 전 훅은 새 사용자에게만 돌고, 정리 배치는 연결이 이메일 하나뿐인 계정만 지운다 — 구글 연결이 남아 있어 이 계정은 지워지지 않는다. 구글 로그인도 같은 계정으로 계속된다. 비밀번호를 바꿀 때마다 저장소 밖 파일과 계정을 함께 맞춘다. **비밀번호 · 이메일 값은 이 저장소에 적지 않는다.** **구글 심사 통과 뒤에는 비밀번호를 무작위로 바꿔 입구를 막는다**(운영 쓰기라 사용자 승인 문장이 먼저이고, 위 시험 데이터 제거와 같은 때 사용자에게 묻는다). 심사원이 이 계정을 탈퇴하면 되돌릴 수 없어 심사 안내문에 금지로 적었다.

**후속 (사소, 아직 하지 않은 것)**: 수락 + 매칭인 줄의 응답 시각을 매칭 시각으로 맞출지(지금은 응답이 수락이면 응답 시각, 상대 카드로 먼저 매칭된 줄이면 매칭 시각), 화면 배지 색 · 간격의 pen 대조.

## 4-17. 학번 숫자 규칙 · 가입 직후 첫 카드 · 무료 카드 하루 한 장 · 매칭 점수 개편 (서버 PR #633 ~ #635)

새 env · 시크릿 · job 은 없다. 운영 DB 에 유일 인덱스 `daily_cards_one_free_per_day` 가 적용돼 있다(아래 "운영 DB" 행).

| 항목 | 값 |
| --- | --- |
| 학번 규칙 | `POST /school-info` 가 `student_number` 가 `[0-9]{1,3}`(숫자 1~3자리)이 아니면 **422 + 문자열 `detail` "숫자를 입력해 주세요"** 를 돌려준다(`backend/app/core/errors.py` `STUDENT_NUMBER_INVALID`, `student_verification/schemas.py` `has_valid_student_number`, 라우터 `save_school_info`). 거절하는 것: 글자 · **전각 숫자**(`\d` 가 아니라 `[0-9]` 로 썼다) · 앞뒤 공백 · 4자리 이상. 순서는 정지 계정 거절 → 학교 메일 관문 → 이 검사 → 저장이다. 목록 모양 `detail`(pydantic `pattern`)로 걸지 않고 라우터에서 문자열로 거절하는 이유: 목록이면 앱이 "알 수 없는 오류" 를 띄운다. 문구는 **"숫자를 입력해 주세요" 한 문구**다(글자 · 4자리 이상도 같다). **기존 저장값은 그대로**(고치는 마이그레이션 없음). 앱은 문자열 `detail` 을 학번 칸 아래 오류 줄에 그대로 띄운다 |
| 첫 카드 | `GET /cards/today` 가 응답을 만들기 전에 `issue_first_card`(`backend/app/cards/issuing.py`)를 부른다. **무료 카드(`source = 'daily'`)를 한 번도 못 받은 사람**(`CardRepository.has_had_daily_card` — 만료 · 결정 상관없이)에게 그 자리에서 한 장: 몫은 배치와 같고(`_issue_to_owner` — 유료 제안 확보 → 무료 상위 20~90% 구간에서 지급), 만료 = 다음 지급 시각(`ladder.next_issue_at`), **알림 없음**(화면을 이미 보고 있다). 자격은 `card_issue_owners()` 와 같다: `status = 'active'` · 매칭 쉼 아님 · 자동 가림 아님 · 학교 카드 오픈(`card_opens_at` 이 null 이거나 지남) · 벡터 있음 — **14일 접속 조건만 지금 열었으니 뺐다.** 지역 설정이 없으면 건너뛴다. **실패해도 오늘 탭은 200**(예외를 삼키고 `첫 카드 지급 실패 owner=<profile_id>` 로그만). 이유(사용자 결정 10-29): 목요일 가입자가 월요일 지급까지 100시간 넘게 빈 화면을 보다 떠난다(코드 주석) |
| 배치 | `issue_daily_cards` 가 **사람마다 지급 직전** `has_had_daily_card(since = 오늘 자정(KST))` 를 다시 본다 — 대상 목록을 배치 시작 때 한 번 읽어서, 그 뒤 앱이 첫 카드를 줬을 수 있다(카드 오픈일 07:00 에 겹친다). `insert_card` 의 **23505** 는 `DailyCardConflict` 로 읽어 **조용히 건너뛴다(`failed` 로 세지 않는다)**. 23505 만 본다 — FK 위반(23503, 상대가 그사이 지워짐)도 PostgREST 가 409 로 주지만 "이미 받았다" 가 아니므로 오류로 남는다 |
| 운영 DB | 마이그레이션 `20261029090000_daily_cards_one_free_per_day.sql` — `create unique index daily_cards_one_free_per_day on public.daily_cards (owner_id, ((issued_at at time zone 'Asia/Seoul')::date)) where source = 'daily'`. **무료 카드는 한 사람에게 서울 날짜당 한 장**, 산 카드(`purchased`)는 규칙 밖. 표 · 열 변경 없음(인덱스 하나). **만료 시각(`expires_at`)을 키로 쓰지 않은 이유**: 주 중에 사다리가 오르면(주 1회 → 주 2회) 월요일 카드와 목요일 카드의 만료가 같은 다음 월요일이 되어, 월요일 카드를 이미 정한 사람의 목요일 정상 카드가 막힌다(검토 권고). 2026-10-29 운영 적용 — 적용 전 같은 사람 · 같은 서울 날짜 무료 카드 2장 이상 **0건**을 읽어 확인했고(파일 머리말에도 있다), 적용 뒤 **unique · valid** 를 확인했다. `docs/ERD.md` §4 · `docs/ERD_DECISIONS.md` §11-34 |
| 시험 | pgTAP `supabase/tests/daily_card_one_per_cycle_test.sql`(파일 이름의 `one_per_cycle` 은 주기 기준이던 첫 안의 이름이 남은 것으로 보인다 — 추정). pytest: `backend/tests/cards/test_issuing.py` · `test_card_repository.py` · `test_paid_card_router.py`, `backend/tests/student_verification/test_router.py`. 하네스 `e2e/` 는 학번을 숫자('21' · '22')로 바꾸고, 배치 알림 시나리오는 옛 카드 1장(`_old_card`)으로 첫 카드를 막고 지급 시각을 후보마다 하루씩 벌린다 |

**알려진 한계**
- **후보가 1명뿐이면 무료 카드가 0장이던 한계**는 서버 PR #646 으로 풀렸다 — 유료 제안을 접고 그 사람을 무료로 준다(§4-21, 사용자 결정 2026-11-03, 설계 §13-45). 남는 한계 2가지는 §4-21.
- **앱 화면 11**: 카드 0 + 후보 있음이면 "다음 카드를 준비하고 있어요" 를 띄운다(`frontend/docs/DESIGN.md` §9 11).
- 앱 업데이트 몫은 `frontend/docs/DESIGN.md` §13-154 · §13-155 에 모았다.

**배포 순서 · 롤백 주의 (코드 근거 — 시험하지 않았다)**
- 순서는 평소대로 **머지 → DB(인덱스) → 서버**가 맞다. 서버가 먼저 나가도 동작은 같고 동시 요청을 막는 마지막 방어만 비어 있다. DB 가 먼저여도 옛 서버(`00093`)의 배치는 이미 "오늘 받은 사람은 건너뜀" 이라 충돌이 거의 없다(겹치면 옛 서버는 그 한 줄을 `failed` 로 센다, 추정).
- **롤백**: `00094` 에서 `00093` 으로 내리면 첫 카드와 학번 숫자 규칙이 빠진다(가입 직후 빈 화면이 돌아오고 학번에 글자가 들어간다). 인덱스는 남아도 옛 서버에 무해하다. `00095` 에서 `00094` 로 내리면 학번 오류 문구만 옛 문구("학번은 숫자 3자리까지 입력해 주세요")가 된다. 하한은 그대로 **`00063` 아래 금지 + `00087` 이전 금지**(§4-14).
- 인덱스를 내려야 하면 `drop index public.daily_cards_one_free_per_day`(데이터는 안 건드린다)를 새 마이그레이션 파일로 만들고, 운영 쓰기라 사용자 원문 승인 뒤에만 적용한다. 서버 `00094` 이상이 도는 동안 지우면 동시 요청 방어만 빠진다.

**카드 오픈 날짜 — 운영 DB 데이터, 지금 서울 학교 카드는 열려 있다 (2026-10-28 오후, 대장 전달 값)**
- 사용자 원문 승인 「현재 심사 2개다 실패여서 11월2일 이거 그냥 풀어줘 통과하면 정확한 날짜 정해서 다시 막아야할거같아」 에 따라 운영 DB 에서 서울 학교 64곳의 `universities.card_opens_at` 을 **2026-11-02(월) 07:00 KST → null** 로 바꿨다(`execute_sql` 데이터 갱신 한 번, **마이그레이션 파일 없음**). null 은 "이미 열린 학교" 다(설계 §2.9, `match_candidates` · `card_issue_owners` 의 열린 학교 조건).
- **저장소 `20261020110000_close_seoul_schools_until_cohort_open` 은 그대로**라서, 새 DB 를 이 마이그레이션들로 처음부터 만들면 서울 학교가 11-02 로 닫힌 채 만들어진다. 운영과 저장소가 이 값에서 다르다.
- 그 결과: 서울 학교 사용자는 지금 후보가 되고 카드 · 첫 카드(위 "첫 카드" 행의 자격 중 "학교 카드 오픈")를 받는다. 홈의 오픈 대기 화면도 이 값을 읽으므로 보이지 않을 것이다(코드 근거 추정, 시험하지 않았다).
- **남은 일**: 스토어 심사 통과 뒤 사용자가 정확한 날짜를 정하면 그 값으로 다시 막는다(운영 쓰기 — 사용자 원문 승인 뒤에만). 그때 마이그레이션 파일로 남길지도 정한다. 시험 학교(`region_group = 'e2e'`) 1곳은 열려 있다. 1.0.0 이 아직 공개 전이라 지금도 열려 있는 것으로 읽는다.

**매칭 점수 개편 (서버 PR #633)**: 운영 DB 에 마이그레이션 2개가 적용돼 있다 — `20261028090000_profile_vectors_text_facets`(`profile_vectors` 에 글 정리 칸 2개 `self_facets` · `want_facets`) · `20261028100000_match_candidates_face_fields`(함수 `match_candidates` 가 후보의 얼굴상 · 인상 4칸 + 글 정리 2칸을 더 돌려주고 성향 최대 거리 상수를 5.657 → 4.472 로 바꾼다, 반환 타입 그대로). **무료 카드는 점수 상위 20~90% 구간에서 뽑는다**(상위 20% 는 유료 전용, 하위 10% 제외, 그 구간에 뽑을 사람이 없을 때만 상위 90% 전체로 넓힘 — `backend/app/matching/band.py` · `cards/issuing.py`, 설계 §6.8). 점수 공식의 나머지 값(가중치 · 계수)은 설계 문서에 옮기지 못했다.

## 4-18. 매칭 글 속 취향 부딪힘 (서버 PR #638)

새 env · 시크릿 · job 은 없다. 앱은 바뀌지 않았다(서버 · DB 만). 운영 DB 에 마이그레이션 `20261030010000_taste_clash` 가 적용돼 있다. 배경: 설계 §6.7 "2026-10-30 운영 반영" · §13 미결46.

| 항목 | 값 |
| --- | --- |
| 서버 — 나누기 | `backend/app/matching/taste.py`(새 파일): 자기소개(`bio`) · "이런 사람이 좋아요"(`ideal_note`) 글을 `gpt-4o-mini`(온도 0, JSON)가 좋아함(`like`) · 싫어함(`dislike`) 목록으로 나눈다(v5 지시문; 성향 `style` 계열도 같이 나누지만 **저장하지 않는다**). 목록은 각 6개까지, 한 글 안에서 좋아함 · 싫어함 둘 다에 나온 단어는 둘 다 뺀다, 흡연 · 담배 · 연상 · 연하가 든 단어와 '나이' · '키' 류는 뺀다(앱 칸이 맡는다 — 흡연 × 0.5 · 선호 나이 · 키 범위). 호출이 실패하거나 답을 못 읽으면 **한 번만** 다시 부르고 그래도 안 되면 null(그 글은 검사 안 함). 로그에는 글 내용 없이 예외 종류만 남긴다 |
| 서버 — 사전 | `resolve_word_ids`: 사전 `taste_words` 에 없는 단어만 임베딩(글과 같은 모델 · 512차원)해 넣고 번호를 다시 읽는다. 두 요청이 같은 새 단어를 동시에 넣어도 unique + 중복 무시로 하나만 남고, 정렬해서 넣어 교착을 피한다 |
| 서버 — 저장 | `vectors.refresh_vectors` 가 임베딩 · 글 정리와 **같은 gather** 에서 나누기를 하고 4칸(`self_like_words` · `self_dislike_words` · `want_like_words` · `want_dislike_words`)을 함께 저장한다(사용자 저장 요청이 기다리는 시간을 늘리지 않으려는 것). 빈 글은 OpenAI 를 부르지 않고 빈 배열. **나누기 · 사전이 실패해도 임베딩 · 설문 · 글 정리 저장은 그대로이고 4칸만 null** |
| 서버 — 카드 선정 | `MatchingRepository.fetch_candidates` 가 `match_candidates` 결과에 이어 RPC `taste_clash_candidates` 를 불러 후보마다 `taste_clash` 표시를 붙인다. RPC 가 실패하면 로그(profile_id 와 예외 종류만)만 남기고 **전원 False**(카드 지급이 멈추지 않는다). `scoring.TASTE_CLASH_PENALTY = 0.6` 이 총점에 곱한다(흡연 · 종교와 같은 곱하기). **같은 취향 가점은 없다.** 유료 상위 20% · 무료 20~90% 구간은 그대로 |
| 운영 DB | 마이그레이션 `20261030010000_taste_clash.sql`: 표 `taste_words`(서버 전용 RLS 켬 · 정책 없음, `service_role` 은 `select` · `insert` 만, 임베딩 512 · `storage plain`) · `profile_vectors` 에 `bigint[]` 칸 4개(null = 나누기 전 · 실패) · 함수 `taste_clash_candidates(uuid) → jsonb`(6쌍 · 비슷함 0.6 초과, `service_role` 만 실행). `docs/ERD.md` §2 · §3 · §4, `docs/ERD_DECISIONS.md` §11-35. |
| 시험 | `backend/tests/matching/test_taste.py` · `test_taste_repository.py` · `test_scoring.py` · `test_vectors.py`, `supabase/tests/taste_clash_test.sql` |

**알려진 한계 · 남은 일 (설계 §13 미결46 에 같은 목록)**
- **나누기 · 사전이 일시 실패하면 글이 안 바뀐 저장에서도 4칸이 null 로 덮인다**(`refresh_vectors` 는 저장마다 4칸을 함께 쓴다). null 은 그 사람을 부딪힘 검사에서 빼므로 10-28 공식과 같아지고, 다음 글 저장이나 새벽 4시 정리 배치 ⑥(§4-19)이 다시 채운다.
- 아침 카드 배치가 사용자 1,000명 이상에서 5분 제한(Cloud Run · 스케줄러 300초) 안에 끝나는지 재지 않았다(시험 199명 46초).
- 단어가 다른 반대(반려동물 반대 45% 구별 등)는 놓친다. 앱의 "칸에도 넣을까요?" 안내는 앱 몫이다(`frontend/docs/DESIGN.md` §13-155). 흡연 칸 '상관없어요' 는 구현돼 있다(§4-23). 커플 성사 확률은 출시 후 서로 수락 비율로 다시 잰다.

**배포 순서 · 롤백 주의 (코드 근거 — 시험하지 않았다)**
- 순서는 평소대로 **머지 → DB → 서버**가 맞다. 새 서버는 벡터를 저장할 때 4칸을 함께 쓰므로 DB 에 칸이 없으면 벡터 저장이 전부 실패한다(마이그레이션 머리말). DB 가 먼저여도 옛 서버(`00095`)는 새 칸을 쓰지 않아 무해하다.
- **롤백**: `00096` 에서 `00095` 로 서버만 내리면 SQL 이 필요 없다(글 속 취향 부딪힘 감점이 빠질 뿐이고 4칸 · 사전 · 함수는 남은 채 쓰이지 않는다, 마이그레이션 머리말). DB 까지 내릴 때는 **서버를 먼저** 내린 뒤 함수 → 4칸 → 표 순으로 지운다(머리말에 SQL 이 있다) — 운영 쓰기라 사용자 원문 승인 뒤에만. 하한은 그대로 **`00063` 아래 금지 + `00087` 이전 금지**(§4-14).

## 4-19. 새벽 4시 정리 배치 ⑥ 취향 단어 다시 채우기 (서버 PR #640)

DB 변경 없음, 새 env 없음, 앱 변경 없음(서버만). 배경: §4-18 "알려진 한계" 의 첫 항목 · 설계 §13 미결46 ⑥(나누기 실패 때 4칸이 null 로 덮임).

| 항목 | 값 |
| --- | --- |
| 하는 일 | 매일 04:00 정리 배치(`POST /batch/cleanup`, §4-4)에 **⑥ 단계**가 더해졌다. 글 속 취향 나누기(GPT) · 단어 사전이 실패해 `profile_vectors` 의 취향 4칸(`self_like_words` 등)이 null 인 사람을 다시 나눠 4칸을 채운다. null 이면 그 사람은 부딪힘 검사에서 빠지므로(§4-18) 글을 다시 저장하지 않는 사람은 계속 빠져 있었다 |
| 대상 조회 | `MatchingRepository.fetch_taste_unsplit`(`backend/app/matching/repository.py`): `profile_vectors` 에서 `or=(self_like_words.is.null,want_like_words.is.null)` 인 `profile_id` 를 **`updated_at` 오래된 순**으로 읽는다. 빈 글은 `[]` 라 걸리지 않는다. 오래된 순인 이유: 다시 만들면 `updated_at` 이 오늘이 되어, 계속 실패하는 사람이 앞자리를 막지 않고 줄 뒤로 간다 |
| 한도 | `REFILL_LIMIT = 20`명, `REFILL_BUDGET_SECONDS = 150`초(`backend/app/matching/vectors.py`). 예산이 지나면 남은 사람은 내일로 미룬다(정리 요청이 시간 제한에 끊기지 않게 — §4-4 의 job 은 `--attempt-deadline=600s`) |
| 다시 채우기 | `refill_taste` → 한 사람씩 `_refill_one`: 글(`bio` · `ideal_note`)을 읽어 나누기 · 사전 번호 정하기를 다시 하고 **4칸만** 저장한다. 임베딩 · 글 정리(`self_facets` · `want_facets`)는 건드리지 않는다 — 그날 OpenAI 가 흔들려도 멀쩡한 글 정리를 덮지 않게. 또 실패하면 4칸 null 과 `updated_at` 이 저장돼 줄 뒤로 간다 |
| 실패 처리 | 한 사람의 실패는 로그(`profile_id` · 예외 종류만, 글 내용 없음: `취향 단어 다시 채우기 실패`)만 남기고 다음 사람으로 간다. ⑥ 전체가 예외로 실패해도 정리 ① ~ ⑤ 결과는 그대로이고 `refilled_taste: 0` + 경고 로그(`backend/app/account/batch_router.py`) |
| 응답 | `/batch/cleanup` 응답에 `refilled_taste` 칸이 더해진다 = **시도한 사람 수**(다시 실패한 사람도 센다 — 성공 수가 아니다). 그래서 이 숫자만으로는 성공과 실패를 가를 수 없다 — 실패는 로그로 본다 |
| 시험 | `backend/tests/matching/test_vectors.py` · `backend/tests/account/test_cleanup_batch.py` · `backend/tests/account/account_world.py` |

**알려진 한계 · 남은 일 (설계 §13 미결46 에 같은 목록)**
- **덮이는 일 자체는 그대로다.** `refresh_vectors` 는 저장마다 4칸을 함께 쓰므로 그 순간 나누기가 실패하면 4칸이 null 이 된다. ⑥ 은 이를 막지 않고 **다음 새벽 04:00 에 메운다**(최대 하루 동안 그 사람은 부딪힘 검사에서 빠진다).
- 글 읽기처럼 **저장 자체가 안 되는** 사람은 `updated_at` 이 오르지 않아 줄 앞자리에 남는다(드묾 — 검토 지적). 하루 20명 한도 안에서 매일 다시 시도되는 사람이 된다.
- 글을 읽은 뒤 저장하기까지 몇 초 사이에 사용자가 글을 고치면 옛 글의 단어가 덮일 수 있다(다음 저장 때 고쳐진다 — 검토 지적).
- 응답의 `refilled_taste` 값으로 실제 채움을 확인한 적은 없다(운영에는 빈 칸인 사람이 거의 없어 0 이 정상일 수 있다). 실패는 로그 `취향 단어 다시 채우기 실패` 로 본다.

**배포 순서 · 롤백 주의 (코드 근거 — 시험하지 않았다)**
- DB 변경이 없어 순서는 merge → 서버 배포 하나뿐이다.
- **롤백**: `00097` 에서 `00096` 으로 내리면 SQL 이 필요 없다 — ⑥ 다시 채우기만 빠지고(이미 채운 4칸은 그대로), 정리 ① ~ ⑤ 와 글 속 취향 부딪힘 감점은 그대로다. 하한은 그대로 **`00063` 아래 금지 + `00087` 이전 금지**(§4-14).

**배포 후 점검 목록 (다음 배포에도 같은 목록을 쓴다)**
- `/health` 200 · 무인증 `POST /batch/cleanup` 401 · 새 리비전 ERROR 로그 0
- 04:00 `/batch/cleanup` 200 · `취향 단어 다시 채우기 실패` 로그 0건

## 4-20. 강제 업데이트 `GET /app/version` (서버 PR #642 안의 커밋 `24472397`)

DB 변경 없음, 새 시크릿 · 새 Cloud Tasks 큐 · 새 Scheduler job 없음, env 는 `MIN_APP_VERSION` 하나가 **선택**이다(운영에는 아직 넣지 않았다 — 안 넣으면 아무도 안 막는다). 앱 쪽 짝은 `frontend/lib/core/app_update/`(화면 `frontend/docs/DESIGN.md` §9 01-2, 규칙 설계 문서 §4.7). 새 의존성 `package_info_plus` 의 승인 원문은 `frontend/CLAUDE.md` §2.1 의존성 표(원문은 `docs/decisions/2026-11-04-v102-decisions.md` §6).

| 항목 | 값 |
| --- | --- |
| 경로 | `GET /app/version`(`backend/app/app_version/router.py`, `main.py` 가 라우터 맨 앞에 붙인다). **인증 없음** — 로그인 전 시작 화면에서도 앱이 묻고, 값이 버전 숫자뿐이라 숨길 것이 없다 |
| 응답 | 200 `{"min_version": "1.0.1"}` 또는 `{"min_version": null}`, 헤더 `Cache-Control: public, max-age=300`. 값을 바꾸는 것은 새 리비전(배포)이라 5분 늦게 보여도 된다 |
| 설정 | env `MIN_APP_VERSION`(`settings.py` `min_app_version`, 기본 빈 글자). 비면 null = 아무도 안 막는다. 글자로 받는다 — 형식이 틀려도 `Settings()` 가 죽어 서버 전체가 멈추지 않게. 앞뒤 공백은 자르고, `숫자.숫자.숫자`(`[0-9]` 만, 전체 일치)가 아니면(예: `1.0`, `1.0.1+19`) null 로 두고 경고 로그 "MIN_APP_VERSION 형식이 올바르지 않아 무시한다" 만 남긴다 |
| 앱 동작 | 앱이 시작할 때와 백그라운드에서 돌아올 때(`main.dart` 의 `_onResume` 이 `updateRequirementProvider` 를 다시 읽는다) 설치된 버전(`package_info_plus` — 안드로이드 versionName · iOS CFBundleShortVersionString)과 견준다. 낮으면 앱 맨 위 `UpdateGate` 가 라우터 대신 01-2 "업데이트 필요" 를 그리고 스토어 상세(구글 플레이 · 앱 스토어)를 연다. 웹 · 데스크톱은 올릴 스토어가 없어 서버에 묻지도 않는다 |
| 막지 않는 경우 | 서버를 못 부름(장애) · **3초** 안에 답이 없음 · 200 이 아님 · 응답 모양이 이상함 · 설치 버전을 못 읽음은 전부 "막지 않음"이다(`AppVersionRepository.fetchMinimum` 이 어떤 실패든 null) — 서버 장애가 앱 잠금이 되지 않게 |
| 시험 | 서버 pytest `backend/tests/app_version/test_app_version_router.py`(함수 6개: 기본값은 아무도 안 막음 · 빈 값 · 값 그대로 · 앞뒤 공백 · 틀린 모양은 안 막고 경고 · 캐시 헤더), 앱 `frontend/test/core/app_update/` 4파일, 문서 시험 `backend/tests/test_deploy_docs.py` 의 `MIN_APP_VERSION` 문단 검사. |

**올리는 순서와 규칙**
- 순서: 고친 빌드를 두 스토어에 제출 → 두 스토어에서 **공개된 것을 확인** → 그다음에만 `MIN_APP_VERSION`(§2). 이 경로를 읽는 첫 공개 버전은 1.0.2 이므로 처음 사람을 막는 값은 **1.0.2 보다 높은 다음 버전 숫자**다. AAB 는 올리기 전에 매니페스트 `versionName` 을 확인한다(`frontend/run.md` — `--build-name` 을 빼면 1.0.0 으로 기록돼 나중에 갇힌다).
- **예시 값 `1.0.1` 로는 아무도 막히지 않는다.** 1.0.0 앱은 이 경로를 읽지 않고, 읽는 앱은 1.0.1 이상이다. 처음으로 사람을 막는 값은 1.0.2 보다 높은 다음 버전 숫자(예: 1.0.3 이 두 스토어에 공개된 뒤 `1.0.3`)다.

**배포 순서 · 롤백 주의 (코드 근거 — 시험하지 않았다)**
- DB 변경이 없어 순서는 merge → 서버 배포 하나뿐이다. 서버가 앱보다 먼저 나가도 1.0.0 앱은 이 경로를 부르지 않아 무해하다.
- **롤백**: 서버를 `00097` 로 내리면 이 경로가 사라져 404 가 되지만, 앱은 200 이 아닌 답을 "알아내지 못함 = 막지 않음"으로 읽어 막지 않는다(`AppVersionRepository.fetchMinimum`) — 롤백은 안전하다. 이미 올린 `MIN_APP_VERSION` 만 풀 때는 코드 롤백이 필요 없다(§2 `--remove-env-vars`). 하한은 그대로 **`00063` 아래 금지 + `00087` 이전 금지**(§4-14).

**배포 후 점검 목록 (다음 배포에도 같은 목록을 쓴다)**
- `/health` 200 · 무인증 `GET /app/version` 200 `{"min_version":null}` + 헤더 `Cache-Control: public, max-age=300`(`MIN_APP_VERSION` 을 비운 채)
- 무인증 `POST /batch/cleanup` 401 · 새 리비전 ERROR 로그 0 · env 개수(§2)
- AAB 매니페스트 `versionName` · 카카오 스킴 `kakao<키>` 채워짐 · 업로드 키 서명(`frontend/run.md`)
- 두 스토어에 고친 빌드가 공개된 것을 확인한 뒤에만 `MIN_APP_VERSION` 결정

## 4-21. 무료 카드 — 후보가 1명뿐이면 유료 제안을 접고 무료로 (서버 PR #646)

DB 변경 없음, 새 env · 시크릿 · job 없음, 앱 변경 없음. 사용자 결정(2026-11-03, 원문 대장 전달): 「후보가 1명이면 유료를 건너뛰고 무료로 주기 2번으로 가는게 맞는거 같아」 — 설계 §13 미결45 ②. 서버 PR #646(브랜치 `fix/free-card-when-solo`, 구현 `7c49edda` · 시험 `efa01e1e` · 하네스 주석 `d2bd73a1`).

| 항목 | 값 |
| --- | --- |
| 규칙 | 뽑을 수 있는 후보가 1명뿐이라 무료가 0장이 되면, 첫 카드와 지급 배치(`_issue_to_owner`)가 그 주기의 유료 제안을 `replaced` 로 접고 그 사람을 무료 카드로 준다. 무료로 줄 사람이 따로 있으면(후보 2명 이상) 유료 1 · 무료 1. 이번 주기에 이미 산 사람 · 지난 주기 제안의 `expired` 는 그대로. 받은 사람은 `pickable=false` 라 `GET /cards/today` 가 같은 사람으로 제안을 다시 만들지 않는다(`paid_card: null`) |
| 바뀌는 곳 | 서버만 — 설계 §2.1 ③ · §6.8 · §13 미결45. 표 · 열 · 함수 변경 없음 |

**알려진 한계 (설계 §6.8 과 같은 두 줄)**
- ① 지급일이 아닌 날 오늘 탭에서 카드 0장 + 후보 1명이면 그 1명이 유료 제안으로 보이고, 다음 지급일 배치에서 접혀 무료로 나간다(대장 결정 2026-11-03).
- ② 구매와 접기가 같은 순간(배치 07:00, 수백 ms)에 겹치면 같은 상대를 유료 · 무료로 둘 다 받을 수 있다(코드 shortcut 주석). 장래 통계에서 `replaced` 는 "사지 않음" 으로 읽는다.

**배포 순서 · 롤백 주의 (대장 전달 + 코드 근거 — 시험하지 않았다)**
- DB 변경이 없어 순서는 merge → 서버 배포 하나뿐이다.
- **롤백**: 이 규칙이 든 리비전(`00099-7gp`)에서 `00098-67v` 로 내리면 후보 1명이면 무료 카드가 0장이 되는 동작(유료 우선, §4-17)으로 돌아간다. SQL 이 필요 없다. 하한은 `00063` 아래 금지 + `00087` 이전 금지(§4-14).

**배포 후 점검 목록 (다음 배포에도 같은 목록을 쓴다)**
- `/health` 200 · 무인증 `GET /cards/today` 401 · 무인증 `POST /batch/cleanup` 401 · ERROR 로그 0
- 후보가 1명뿐인 사람의 첫 카드 · 지급 배치에서 유료 제안이 `replaced` 로 접히고 무료 카드가 나갔는지(운영에서 본 결과는 받지 못했다)

## 4-22. 푸시 고치기 4건 · 서버 배포 업로드 제외 목록 (서버 PR #647)

DB 변경 없음, 새 시크릿 · job 없음, 앱 변경 없음. `settings.py` 는 바뀌지 않아 새 env 도 없다. 서버 PR #647(브랜치 `fix/push-reliability`)의 커밋 4개: `fd1c2f09` · `f5b5960d` · `efc88bac` · `919949c1`. 배경: 사용자가 푸시 알림을 어떤 경우에 보내는지 분석해 달라고 물었고(운영 7일 기록은 전송 19 · 실패 0 · 중복 0), 그 분석에서 나온 고치기 4건이다.

| 항목 | 값 |
| --- | --- |
| M1 푸시 서버 오류 삼키기 | `notify`(`backend/app/cards/push.py`)가 푸시 서버에 닿지 못한 오류(연결 · 시간 초과 · 끊김, `httpx.HTTPError`)와 구글 인증 토큰 오류(`GoogleAuthError`)만 잡아 **이번 푸시만 접는다** — 그 알림의 남은 기기는 건너뛰고 재전송하지 않는다. 채팅 보내기 · 카드 결정 · 수락 · 신뢰 확인이 이 오류로 500 이 되지 않는다(채팅은 500 이면 앱이 다시 보내 메시지가 두 줄이 된다). 그 밖의 예외(코드 버그)는 삼키지 않는다. 로그: WARNING `FCM 전송 예외 kind=… platform=… token=<앞 6자>…(<길이>) \| <예외 종류>`, 인증(`DefaultCredentialsError` · `RefreshError`)은 ERROR `FCM 인증 실패 kind=… platform=… \| <예외 종류>`(§4-8) |
| L2 아침 묶음 한 번만 | `send_pending`(`backend/app/cards/push.py`)이 사람 × kind × 가는 화면 묶음마다 `CardRepository.claim_pending_pushes`(DELETE `id=in.(…)` + `select` + `Prefer: return=representation`)로 **지우면서 가져온 줄만** 보낸다 — 아침 배치가 겹쳐도(스케줄러 재시도 · 수동 실행) 한 줄은 한 쪽만 가져가 같은 알림이 두 번 가지 않는다. 묶음 개수도 실제로 가져간 줄 기준이다. 보내다 실패하면 그 줄은 사라진다(남기면 매시 같은 실패를 되풀이하거나 점심에 "밤사이" 알림이 간다). |
| L8 신뢰 확인 리마인드 시각 | `reminder_at`(`backend/app/chat/gate.py`): 기본 시각(매칭 + 24시간)을 정각으로 올린 시각이 22~08시면 다음 아침 08:00 으로 민다(21시대 · 07시대 포함, 방해 금지 설정과 무관). 규칙은 §4-1 에 있다, 설계 §2.5 |
| L7 죽은 토큰 정리 로그 | 죽은 토큰을 지울 때 INFO `FCM 죽은 토큰 정리 kind=… platform=… token=…`(§4-8) |
| 배포 업로드 제외 | `backend/.gcloudignore` 새로 — `--source` 업로드는 이 파일, 이미지 빌드는 `.dockerignore`(§2). 업로드 649 → 169 파일, zip 약 52MB → **0.76MB**, 빌드 로그 `inflating: /workspace/.venv` 0줄 |
| 바뀌는 곳 | 서버만 — `backend/app/cards/push.py` · `backend/app/cards/repository.py` · `backend/app/chat/gate.py` · `backend/.gcloudignore`, 시험, e2e 하네스(`e2e/area4_push_gate.py` — 서버 `reminder_at` 사본과 시험을 새 규칙에 맞췄다). 표 · 열 · 함수 변경 없음 |
| 시험 | `backend/tests/cards/test_push.py`(연결 · 인증 오류 · 기기 건너뛰기 · 코드 버그 미삼킴 · 죽은 토큰 로그 · 두 배치를 동시에 돌려도 한 번씩만) · `test_push_inbox.py` · `backend/tests/chat/test_gate.py`(21:30 · 21:00 · 07시대 + 하루치 분 단위 격자) · `test_chat_router.py`(푸시 서버 연결 오류에도 메시지가 한 번만 저장) |

**알려진 한계 · 남은 일**
- 앱 L1(로그아웃할 때 앱이 자기 등록 토큰을 모르면 서버에 그 토큰이 남음)은 앱 PR #650 으로 고쳤다 — 등록 토큰을 모르면 기기에서 읽어(`getToken`) 서버에서 지우고, 못 찾거나 못 지우면 기기 토큰을 버린다(찾기 + 삭제가 5초 예산 하나를 나눠 쓴다). 서버 · DB 변경은 없다. 남은 확인: iOS 실기기에서 알림 권한을 거부한 뒤 `getToken` 이 어떻게 동작하는지는 시험하지 못했다.
- 연결 오류가 나도 그 푸시는 다시 보내지 않는다(재전송 없음 — 다음 알림이 곧 오고, 지금 다시 시도하면 응답만 느려진다). 아침 묶음이 보내다 실패하면 그 줄은 사라진다.

**배포 순서 · 롤백 주의 (대장 전달 + 코드 근거 — 시험하지 않았다)**
- DB 변경이 없어 순서는 merge → 서버 배포 하나뿐이다.
- **롤백**: `00100-jh4` → `00099-7gp` 로 한 칸 내리면 **푸시 고치기 4건만** 빠진다(푸시 서버 오류가 다시 500 이 될 수 있고, 아침 묶음이 겹치면 두 번 갈 수 있고, 리마인드 시각이 옛 판정으로 돌아간다). 후보 1명 무료(§4-21)는 남는다. `00099-7gp` → `00098-67v` 는 후보 1명 무료만 빠진다. `.gcloudignore` 는 배포할 때만 쓰는 파일이라 리비전을 내려도 영향이 없다. 하한은 그대로 **`00063` 아래 금지 + `00087` 이전 금지**(§4-14).

**배포 후 점검 목록 (다음 배포에도 같은 목록을 쓴다)**
- `/health` 200 · 무인증 `GET /app/version` 의 `min_version` · 무인증 호출 401
- 새 리비전 ERROR 로그 0 · `FCM 전송 예외` 0 · `FCM 인증 실패` 0 (0 인 것은 푸시 서버 장애가 없었다는 뜻이지 새 처리 경로를 거쳤다는 뜻이 아니다)
- 빌드 로그 `inflating: /workspace/.venv` 0줄 (§2)
- 아침 묶음이 겹쳐도 한 번만 가는지 · 21시대 리마인드가 다음 아침 08:00 에 가는지 — 운영에서 본 결과는 받지 못했다(pytest 로만 확인했다)

## 4-23. 흡연 "상관없어요" 칸 — DB 칸 · 감점 규칙 · 저장 / 읽기 API (서버 PR #653)

**새 env · 시크릿 · job 없음**(`settings.py` 변경 없음). 서버 PR #653(브랜치 `feat/accepts-smoker`, 커밋 5개: `36078eda` · `a7827aa8` · `552afd10` · `4e4890c6` · `8217c335`). 서버는 앱(1.0.2)보다 항상 먼저 나가 있어야 한다 — 저장은 키가 없으면 DB 값을 건드리지 않고, 응답에 늘어난 키는 옛 앱이 무시하고, 기존 회원은 전원 null 이라 결과가 같다(옛 앱에 피해 없음 — 대장이 코드로 확인). 앱 짝 PR #654(06-1 화면).

| 항목 | 값 |
| --- | --- |
| DB | 마이그레이션 `supabase/migrations/20261104090000_profiles_accepts_smoker.sql` — `profiles.accepts_smoker boolean`(null 허용 · **기본값 없음 · 백필 없음**, 칸 설명 comment). 읽기 권한은 표 권한 그대로(authenticated 는 RLS 로 본인 행만, anon 은 못 읽음, 쓰기는 `service_role` 만). pgTAP `supabase/tests/accepts_smoker_test.sql` 6개(칸 있음 · boolean · null 허용 · 기본값 없음 · authenticated 읽기 · anon 못 읽음). 표 · 결정은 `docs/ERD.md` §3 · `docs/ERD_DECISIONS.md` §11-36 |
| 감점 규칙 | `backend/app/matching/scoring.py` `smoking_clash(owner, candidate)` — **받는 사람(owner)이 흡연자를 싫어하고**(`accepts_smoker` 가 거짓이거나, null 이고 `is_smoker` 가 거짓) **후보가 흡연자**(`is_smoker` 참)면 true → 총점 × `SMOKING_PENALTY`(0.5). `accepts_smoker` 가 참(상관없어요)이면 후보가 흡연자여도 감점 없음. 후보 쪽 칸은 보지 않는다. 유료 카드 이유 문구 "흡연 · 종교 조건이 맞아요"(`backend/app/cards/paid_offer.py`)도 **같은 함수**를 써서 점수와 이유가 어긋나지 않는다. null 은 옛 규칙("내가 비흡연자일 때만")과 같아 옛 앱 1.0.0 · 1.0.1 과 기존 회원의 결과는 바뀌지 않는다 |
| `match_candidates` | **바꾸지 않았다.** 감점은 받는 사람 쪽 값만 보므로 서버가 owner 행에서 읽는다(`backend/app/matching/repository.py` 의 owner 조회 칸 목록에 `accepts_smoker` 추가) |
| 저장 API | `POST /profile-onboarding/ideal-conditions` 본문(`IdealConditionsRequest`)에 `accepts_smoker`(JSON bool 또는 null, `"yes"` · `1` 같은 값은 422). **보낸 키만 저장한다** — 키가 없으면 PATCH 에 칸이 실리지 않아 DB 값이 그대로다(옛 앱이 이상형 조건을 다시 저장해도 새 앱이 고른 값이 안 지워진다). 보낸 `null` 은 null 로 되돌린다 |
| 읽기 API | `GET /me/profile` 응답에 `accepts_smoker` 키(true 상관없어요 · false 싫어요 · null 내 흡연 여부를 따른다). 옛 앱은 모르는 키를 무시한다 |
| 앱 짝(앱 PR #654, 앱 1.0.2) | 06-1 맨 아래 "흡연하는 사람 [싫어요] [상관없어요]"(`frontend/docs/DESIGN.md` §9 7). 처음 값 = 서버 값 > 내 흡연 여부(안 한다 = 싫어요, 한다 = 상관없어요) > 둘 다 모르면 두 칸 다 안 고른 채, 안 골랐으면 저장 요청에 `accepts_smoker` 키를 싣지 않는다 |
| 시험 | 점수 `backend/tests/matching/` · `cards/`, 저장 `backend/tests/profile_onboarding/`, 읽기 `backend/tests/me/`, pgTAP `supabase/tests/accepts_smoker_test.sql`, e2e 단위 `e2e.test_area5_read` · `e2e.test_area5_act` |

**알려진 한계 · 남은 일**
- e2e **실행형 시나리오(에뮬레이터)는 돌리지 않았다** — 단위 시험만 돌렸다.
- `e2e/test_area2_time_batch.py` 의 점수 기준 모델(`score`, 249줄 근처)은 **옛 흡연 규칙 그대로**(받는 사람이 비흡연자 + 후보 흡연자)다. e2e 계정은 `accepts_smoker` 가 null 이라 같은 결과가 나온다 — 칸을 쓰는 e2e 시나리오가 생기면 그때 모델을 맞춘다.
- 앱 쪽 한계(앱 PR #654): 06-1 에서 뒤로 가 설문의 흡연 답을 바꾸고 돌아오면 06-1 칸은 처음 값 그대로 남는다(화면에 보이고 고칠 수 있다). 설명 문구가 실제 폰에서 몇 줄로 접히는지는 확인하지 못했다.
- `ERD.pen` 의 `profiles` 상자는 아직 이 칸을 반영하지 않았다.

**배포 순서 · 롤백 주의 (대장 전달 + 코드 근거 — 롤백은 시험하지 않았다)**
- **순서: DB 칸 → 서버 배포 → 앱(1.0.2).** 새 서버가 `profiles` 조회(`fetch_owner` · `GET /me/profile`)에 `accepts_smoker` 를 넣으므로 칸이 먼저 있어야 한다(마이그레이션 머리 주석).
- **롤백**: `00101-bc9` → `00100-jh4` 로 한 칸 내리면 서버가 이 칸을 읽지도 쓰지도 않아 옛 규칙(내가 비흡연자일 때만 × 0.5)으로 돌아간다. DB 칸이 남아 있어도 해롭지 않다. 칸까지 지우려면 **서버를 먼저** 되돌린 뒤 `alter table public.profiles drop column accepts_smoker;` — 칸을 지우면 새 앱(1.0.2)이 저장한 값도 같이 사라진다. 하한은 `00063` 아래 금지 + `00087` 이전 금지(§4-14)가 그대로이고, 이미지가 남은 가장 오래된 리비전은 §4-24 에서 `00086` 이다.

**배포 후 점검 목록 (다음 배포에도 같은 목록을 쓴다)**
- `/health` ok · 무인증 `GET /app/version` 의 `min_version` · 빌드 로그 `inflating: /workspace/.venv` 0줄 · 업로드 zip 크기(§2) · 새 리비전 ERROR 로그 0
- 06-1 에서 고른 "싫어요 / 상관없어요" 가 실제 카드 점수에 반영되는지 — 운영에서 본 결과는 없다(pytest 로만 확인했다). 앱 1.0.2 가 나간 뒤에야 볼 수 있다

## 4-24. 2026-11-04 배포 창고 정리 — 업로드 버킷 30일 자동 삭제 · 이미지 창고 정리 규칙 (**되돌림 하한 `00086`**)

배경: `gcloud run deploy --source` 는 배포할 때마다 소스 zip 을 업로드 버킷에 올리고 이미지를 이미지 창고에 쌓는데 지우는 규칙이 없었다. §4-22 의 `.gcloudignore` 는 앞으로 올라가는 zip 크기를 줄인 것이고, 이미 쌓인 것과 앞으로 쌓일 것은 이 절의 규칙이 맡는다. 버킷 · 저장소 이름은 대장이 전달한 값이고 프로젝트 번호는 적지 않는다.

| 항목 | 값 |
| --- | --- |
| 업로드 버킷 | `run-sources-<프로젝트 번호>-asia-northeast3`(`--source` 배포가 소스 zip 을 올리는 곳) — lifecycle 규칙: 만든 지 **30일(age 30)** 지난 객체를 자동 삭제. 적용 끝 |
| 이미지 창고 | Artifact Registry 저장소 `cloud-run-source-deploy`(asia-northeast3)의 이미지 — 정리 규칙 둘: 삭제 `delete-older-than-7d`(7일이 지난 것) + 보존 `keep-latest-15`(최근 15개는 지킨다). 규칙을 먼저 dry-run 으로만 넣어 계산을 확인한 뒤 dry-run 을 꺼 실제로 적용했다 |
| 적용 직후 남은 것 | 이미지 15개 = 리비전 **`00086` ~ `00101`**(`00088` 제외, 대장 전달) |

**되돌림 하한이 바뀐다.** 이미지가 지워진 리비전(`00085` 이하)으로는 되돌릴 수 없다 — 이미지가 남은 가장 오래된 리비전이 **`00086`** 이다. 기능상의 하한(`00063` 아래 금지 · 이 뒤로 `00087` 이전 금지, §4-14)이 더 높아 실제로 돌아갈 수 있는 가장 오래된 리비전이 `00087` 이후라는 사실은 그대로다 — 새로 생긴 제한은 "이미지가 있는 리비전만" 이다. **규칙은 계속 돈다**: 새 배포가 쌓이면 7일이 지난 이미지 가운데 최근 15개 밖의 것이 차례로 지워져, 이 하한은 배포가 늘수록 위로 올라간다. 되돌리기 전에 그 리비전의 이미지가 창고에 남아 있는지 먼저 확인한다(없으면 같은 코드를 다시 배포해야 한다 — 문서 담당 정리).

**확인 못 한 것**: 규칙을 켠 뒤 실제로 지워진 이미지의 개수 · 용량과 남은 15개의 목록은 전달받지 못했다. 업로드 버킷의 첫 자동 삭제는 규칙이 켜진 날(2026-11-04)로부터 30일 이후에 눈에 보인다.


## 4-25. 2026-11-10 ~ 11 회의 할 일 서버 묶음 — 문의하기 · O/X 댓글 · 휴대폰 문자 인증 · 친구 초대 50/25 · 홈 숫자 기준 (서버 PR #686 ~ #689 · #694) — **#686(홈 숫자 기준)만 운영 배포됨(`00102-46b`), 나머지는 main 에 merge, 운영 DB 미적용 · 서버 미배포(사용자 승인 대기)**

사용자 결정은 11-08 회의 "준석 할 일" 1·2·3·4·5·6·9·10 번과 11-10 ~ 11 에 받은 선택이다(원문은 `docs/decisions/2026-11-11-meeting1-decisions.md`). 운영 서버는 `00102-46b`(§5)인데, 이 리비전이 올린 것은 #686(홈 숫자 기준 미만 숨김)과 서버 글자 고침 #683 · 자기소개 프롬프트의 "졸업생" 뿐이다(서버 배포 ①, 사용자 승인 뒤). **그래서 이 절의 나머지(문의 · 댓글 · 문자 인증 · 친구 초대 50/25)는 운영에 없다.** 새 앱(문의하기 #691 · 댓글 #693)을 두 스토어에 내기 전에 이 절의 순서로 서버를 먼저 올려야 한다 — 새 앱은 서버에 이 경로가 없으면 문의 · 댓글이 실패한다.

| PR | 내용 | 마이그레이션 |
| --- | --- | --- |
| #686 | 홈 숫자 기준 미만 숨김(`HOME_STATS_MIN_SIGNUPS`) — **운영 배포됨(`00102-46b`)** | 없음 |
| #688 | 친구 초대 보상 새 사람 50 · 코드 주인 25하트 | `20261110120000_referral_referrer_25` |
| #687 | 문의하기 접수 · 운영 메일 알림 · 관리자 문의 API · 1년 정리 | `20261110200000_create_inquiries` |
| #689 | O/X 글 댓글 · 신고 대상 `poll_comment` · 글쓴이 푸시 · 관리자 가림 | `20261111000000_report_target_poll_comment` · `20261111000100_create_poll_comments` · `20261111000200_poll_comment_functions` |
| #694 | 휴대폰 문자 인증 서버(문자 발송기 · 보내기 · 확인 · 기본 정보 저장 연결 · 30일 정리) | `20261111010000_create_phone_verifications` |

앱 쪽은 #691(문의하기 화면) · #693(댓글 화면 · 알림 설정 칸) 이 merge 됐고 화면 규칙은 `frontend/docs/DESIGN.md` §9 · §8.11 에 있다. 휴대폰 인증 앱 화면(PR #696, 기본 정보 04-1)도 merge 됐다 — 앱 쪽 내용은 아래 "휴대폰 인증 앱 쪽"에 있다. 관리자 웹 PR #690(문의 목록) · #692(댓글 신고 가림)은 draft 이고 서버 배포 때 같이 merge 한다.

**마이그레이션 6개는 모두 운영 미적용이다**(저장소 109개 중 운영 103개, `docs/ERD.md` 상태줄). 순서는 파일 이름 순이다. 전부 **뒤 호환**이다 — 옛 서버(`00101`)는 새 표 · 칸을 부르지 않고, 바뀐 함수(`poll_feed` 의 칸 추가, `set_phone_number` 의 인증 표시, `redeem_referral` 의 금액)는 옛 서버가 고르는 칸 · 인자 그대로 돈다. 거꾸로 **새 서버를 DB 보다 먼저 올리면** 문의 · 댓글 · 번호 인증 경로가 500 이다(정리 배치의 두 단계와 기본 정보 저장의 인증 연결만 실패해도 멈추지 않게 감싸 두었다).

### 새 경로

| 경로 | 인증 | 동작 |
| --- | --- | --- |
| `POST /inquiries` | 로그인만(`get_caller` — 정지된 사람 · 학교 메일/학과 입력 전 사람도 보낼 수 있다. 탈퇴 계정은 401) | 본문 `reason`(`account` `payment` `matching` `safety` `bug` `other`) · `body`(앞뒤 공백을 자르고 1~1000자) · `reply_email`(공백 · 쉼표 · 꺾쇠 · 비ASCII 불가, 254자 이하). 201 `{ok, id}`. **하루(한국 시간 0시부터) 5건**을 넘으면 429 "오늘은 더 문의할 수 없어요". 저장이 먼저고 운영 메일은 덤이다 — 메일이 실패 · 15초 넘김이어도 201. 로그에는 문의 번호만 남긴다 |
| `GET /admin/inquiries` · `PATCH /admin/inquiries/{id}` | 관리자(§4-14 관문) | 목록은 최근 순 · 상태 필터 · 커서(`before` + `before_id`), 기본 50 최대 100. 수정은 `status`(`new` `in_progress` `answered`) · `admin_memo`(1000자) — `answered` 가 되면 `answered_at` 을 찍는다(1년 보관의 기준). 기록(`admin_actions` `inquiry_update`)을 먼저 남기고 실패하면 바꾸지 않는다. 기록에는 상태만 있고 메모 글은 없다 |
| `GET /community/polls/{poll_id}/comments` | 학교 메일 확인 · 학과 입력까지 마친 사람(`get_verified_caller`) | 오래된 순 10개 + `has_more`. 더 보려면 마지막 댓글의 `created_at` · `id` 를 `after` · `after_id` 로 같이 보낸다(하나만 오면 422). 가려진 글 · 떠난 사람의 글은 404. **작성자 id 는 어떤 응답에도 없다** — 칸은 `id` `body` `created_at` `alias_no` `is_post_author` `is_mine` `can_delete` 뿐이다 |
| `POST /community/polls/{poll_id}/comments` | 위와 같음 | 본문 1~200자(앞뒤 공백 자름). 201 로 새 댓글 한 줄. 처음 쓰는 사람은 그 글 안의 다음 번호(익명1 · 익명2 …)를 받고, **글쓴이는 번호가 없다**(`alias_no` null, `is_post_author` true). **한국 시간 하루 50개** 초과 429 "오늘은 댓글을 더 달 수 없어요". 없는 글 · 가려진 글 · 떠난 사람의 글은 404 |
| `DELETE /community/comments/{comment_id}` | 위와 같음 | 내 댓글이거나 내 글에 달린 댓글이면 행을 지운다(204). 남의 댓글이든 없는 댓글이든 같은 404 "댓글을 찾을 수 없어요"(남의 id 인지 새지 않게) |
| `POST /reports`(`target_type=poll_comment`) | 학교 메일 확인 · 학과 입력까지 마친 사람 | 화면 목록에 보이는 **남의** 댓글만 신고된다 — 없는 댓글 · 가려진 댓글 · 작성자 또는 글쓴이가 active 가 아닌 경우 · 가려진 글 · 내 댓글은 모두 같은 404. 신고해도 차단하지 않는다(익명이라 매칭 상대가 아니다). 신고에 댓글 본문이 스냅샷으로 남는다 |
| `POST /admin/content/poll-comments/{id}/blind` · `unblind` | 관리자 | 댓글 가림 / 해제(`content_status`). 신고 목록 미리보기는 질문 대신 댓글 본문 앞 부분이다 |
| `POST /phone-verification/send` | 학교 메일 확인 · 학과 입력까지 마친 사람(`get_verified_caller`) | 본문 `phone_number`. 010 번호만(해외 번호로 비싼 문자를 보내게 하는 공격 방지, 가짜 번호 규칙도 같이). 200 `{resend_after_seconds, expires_in_seconds, already_sent}`. 400 `phone_number_invalid` · 409 `phone_number_in_use`(다른 활동 계정이 문자로 인증해 저장한 번호) · 429 `phone_verification_rate_limited`(+ `retry_after_seconds`, `Retry-After` 헤더) · 503 `sms_unavailable` |
| `POST /phone-verification/verify` | 위와 같음 | 본문 `phone_number` · `code`(숫자 6자리). 200 `{verified: true}`. 400 `phone_code_mismatch`(+ `remaining_attempts`) · `phone_code_expired` · `phone_code_locked` |

**인증번호 규칙**(DB 함수 `issue_phone_verification` · `attempt_phone_verification` 이 한 잠금으로 줄 세워 판정한다 — 서버가 여러 대로 늘어도 한도가 느슨해지지 않는다): 6자리 난수(`secrets`), 유효 **3분**, 확인 시도 **5번**(넘으면 잠김, 새로 받아야 한다), 새로 보내면 옛 번호는 못 쓴다. 한도는 같은 번호 **1분에 1번 · 하루 5번**, 한 계정 **하루 10번**, 전체 **하루 `SMS_DAILY_GLOBAL_LIMIT`(기본 300)번**(한국 시간 0시부터). 같은 계정이 1분 안에 다시 누르면 문자 없이 `already_sent` + 남은 초를 돌려준다. 다른 계정이 인증한 번호면 문자를 보내지 않고 시도만 남긴다(계정 하루 한도에는 센다). 인증번호는 원문을 저장하지 않고 신원 키(`identity-hmac-key`)의 HMAC 으로만 두며 비교는 `hmac.compare_digest` 다. 문자 본문은 인증번호 한 줄뿐이다(홍보 문구를 섞으면 광고 문자가 된다). 하루 전체 한도의 마지막 한 통을 보낸 요청이 디스코드(`discord-review-webhook-url`)로 한 번 알린다 — 번호 · 인증번호 · 계정은 싣지 않는다. 문자 발송이 실패하면 그 줄을 지워 사용자의 한도를 먹지 않게 하고 503 을 준다.

**기본 정보 저장(`POST /profile-onboarding/basic-info`)과의 연결**: 맞힌 인증은 **30분 안에 한 번**만 번호 저장에 쓰인다. `PHONE_VERIFICATION_REQUIRED=true` 면 인증한 번호만 받는다(422 `phone_not_verified`, 다른 활동 계정이 인증한 번호면 409 `phone_number_in_use`) — 이 검사는 프로필 칸을 고치기 전에 먼저 본다. **기본값 false(꺼짐)** 일 때는 이 계정 · 이 번호로 쓸 수 있는 인증이 있으면 인증한 번호로 저장해 `phone_verified_at` 표시를 달고, 없으면 지금까지처럼 인증 없이 저장한다(인증 줄을 만들지 않는 옛 앱이 그대로 가입한다). 인증 조회가 실패해도(서버가 DB 보다 먼저 나간 경우 등) 옛 길로 저장해 가입을 멈추지 않는다. 번호가 바뀌면 `phone_verified_at` 을 지운다.

### 새 설정

| 이름 | 종류 | 기본 | 뜻 |
| --- | --- | --- | --- |
| `SMS_PROVIDER` | env | `fake` | `solapi` 면 솔라피로 보낸다. 그 밖은 가짜 발송기인데 **로컬 스택(`SUPABASE_URL` 이 루프백)에서만** 만들어지고, 운영 주소면 발송기가 없어 503 이다 |
| `SOLAPI_API_KEY` · `SOLAPI_API_SECRET` · `SOLAPI_SENDER` | 시크릿 | 빈 글자 | Secret Manager 이름 `solapi-api-key` · `solapi-api-secret` · `solapi-sender`(발신번호는 숫자만). 하나라도 비면 `solapi` 여도 보내지 않고 503 이다 |
| `SMS_DAILY_GLOBAL_LIMIT` | env | `300` | 하루(한국 시간) 전체 발송 상한 — 요금 폭탄의 마지막 방어선. 솔라피 하루 한도(개인 50 · 사업자 1,000)보다 낮게 둔다. 정수만(빈 값은 서버가 안 뜬다) |
| `PHONE_VERIFICATION_REQUIRED` | env | `false` | 위 "기본 정보 저장과의 연결". 새 앱이 두 스토어에 공개된 뒤에 켠다 |
| `INQUIRY_SMTP_PASSWORD` | 시크릿 | 빈 글자 | Secret Manager 이름 `inquiry-smtp-password`(구글 계정의 앱 비밀번호). 비면 문의 알림 메일만 건너뛴다(문의 저장은 된다). 지메일 SSL 465 로 보낸다(표준 `smtplib`, 새 의존성 없음) |
| `INQUIRY_NOTIFY_TO` · `INQUIRY_SMTP_USER` | env | 운영 메일 | 받는 곳 · 보내는 계정. 기본값이 코드에 있어 보통 넣지 않는다(주소는 이 문서에 적지 않는다). 받은 메일의 "답장" 이 사용자 `reply_email` 로 가도록 `Reply-To` 를 붙인다 |
| `HOME_STATS_MIN_SIGNUPS` | env | `300` | `GET /home/summary` 가 **가입 수(active)가 이보다 적으면 전달된 카드 · 가입 수 · 시작된 대화 세 숫자를 모두 0 으로 내린다.** DB 값은 그대로다. 앱은 0 인 칸을 숨기고 셋 다 0 이면 줄 전체를 숨긴다. **가입자가 300명 미만인 동안 홈 숫자 줄이 사라진다.** 기본값 300 은 11-10 회의 할 일 계획에서 대장이 정했고 사용자가 그 계획을 승인한 상태로 **`00102-46b` 에 이미 배포됐다**(env 를 따로 넣지 않아 코드 기본값이 운영 값이다). 되돌릴 리비전은 `00101-bc9` |

`backend/.env.example` 에 위 이름이 값 없이 들어 있다(공개 저장소 — 값은 적지 않는다). 새 시크릿 읽기 권한은 §1 에서 서비스 계정에 프로젝트 단위로 준 `roles/secretmanager.secretAccessor` 로 된다(이름만 새로 만들면 된다).

### 솔라피 고정 나가는 IP

솔라피 API 키는 **허용 IP** 에서 온 요청만 받는다. Cloud Run 의 기본 나가는 IP 는 요청마다 바뀌는 구글 대역이라(일회성 발송 시험이 "허용되지 않은 IP" 403 으로 막혔다) 고정 IP 를 만들어 서버를 거기에 묶는다. 아래는 모두 **운영 프로젝트에 만들어 둔 것**이고 서버는 아직 연결하지 않았다(IP 숫자는 이 문서에 적지 않는다 — 콘솔 · `gcloud compute addresses describe` 로 본다).

| 항목 | 이름 |
| --- | --- |
| 고정 IP(외부 주소) | `campusmate-egress-ip` |
| Cloud Router | `campusmate-egress-router` |
| Cloud NAT | `campusmate-egress-nat` (서울 `default` 서브넷의 나가는 길을 위 IP 하나로) |
| 네트워크 / 서브넷 | `default` / `default`(`asia-northeast3`) |

서버를 이 길에 묶는 배포 플래그는 `--network=default --subnet=default --vpc-egress=all-traffic` 이다. 솔라피 화면에서 API 키의 허용 대상에 이 고정 IP 를 등록하는 것은 사용자가 한다. **`all-traffic` 은 서버가 밖으로 부르는 모든 요청(Supabase · OpenAI · FCM · 애플 · 구글 API · 지메일 SMTP)을 NAT 로 보낸다** — 문자뿐 아니라 모든 호출이 이 길을 지나므로 0% 새 판 시험에서 문자 말고도 카드 · 채팅 · 푸시 · 아바타가 도는지 본다(Private Google Access 설정 여부는 확인하지 못했다). 달마다 드는 고정 IP · NAT 비용은 노션 비용 문서에 있다.

### 배포 순서 (사용자 승인을 그때그때 받는다)

1. **DB 6개 적용**(뒤 호환, 위). 클라우드 쓰기라 사용자 원문 승인 뒤 MCP `apply_migration` 으로 파일 내용 그대로(`docs/SUPABASE.md` §4). 함수가 새로 생기거나 바뀌었으니 필요하면 `NOTIFY pgrst, 'reload schema';`.
2. **0% 새 판 시험.** 새 리비전을 트래픽 0% 로 올리고(`--no-traffic` + 시험용 태그 주소) 위 고정 IP 플래그와 새 env · 시크릿을 `--update-env-vars` · `--update-secrets` 로 **더한다**(`--set-*` 금지, §2). 새 판에서 본다: `/health` · 문의 한 건(운영 메일이 오는지) · 댓글 쓰기 · 목록 · 삭제 · **문자 한 통(받는 번호는 사용자 시험 번호 하나뿐 — 아무 번호로 보내지 않는다)** · 위 NAT 점검 · 새 리비전 ERROR 로그. 솔라피로 보내는 요청의 `Date` 를 "…Z" 로 만드는데 실제 발송에서 거절되는지는 처음 운영 발송에서 확인한다.
3. **100%.** 시험이 끝나면 새 리비전으로 트래픽을 옮긴다. 이때 `PHONE_VERIFICATION_REQUIRED` 는 꺼진 채다.
4. **앱 빌드 · 제출.** 새 앱은 **서버 플래그와 상관없이 번호 인증이 필수**다(앱 [다음] 은 인증된 번호일 때만 켜지고 인증 경로는 `/phone-verification/*` 하나뿐이다). 그래서 앱보다 서버(솔라피 설정)를 먼저 올려야 한다 — 서버에 인증 경로가 없으면 새 앱의 가입이 04-1 에서 멈춘다.
5. **새 앱이 두 스토어에 공개된 뒤에만** `PHONE_VERIFICATION_REQUIRED=true` 를 켜고, **같은 때 `MIN_APP_VERSION` 을 휴대폰 인증을 넣은 앱 버전으로 올린다**(§2 · §4-20). 공개 전에 켜면 인증하지 못하는 옛 앱의 가입이 전부 422 로 막힌다.

### 휴대폰 인증 앱 쪽 (앱 PR #696, 2026-11-11 merge)

- **화면**: 기본 정보(04-1)의 번호 줄 아래에 "인증번호 받기" → 인증번호 줄(6자리 · 남은 시간 · 다시 받기) → "인증됐어요" / "번호 바꾸기". 규칙과 오류 문구는 `frontend/docs/DESIGN.md` §9 04-1. **[다음] 은 인증된 번호일 때만 켜진다.**
- **서버 플래그와 무관**: 새 앱은 `PHONE_VERIFICATION_REQUIRED` 가 꺼져 있어도 인증을 거친다. 그래서 **앱보다 서버(솔라피 설정 · 고정 나가는 IP)를 먼저 배포한다.** 서버 플래그를 켜는 것은 옛 앱(인증 줄을 만들지 않는)이 더는 없을 때다.
- **쓰는 경로와 응답**: `POST /phone-verification/send` 의 200(`resend_after_seconds` · `expires_in_seconds` · `already_sent`) · 400 `phone_number_invalid` · 409 `phone_number_in_use` · 429(`retry_after_seconds`) · 503 `sms_unavailable`, `POST /phone-verification/verify` 의 400 `phone_code_mismatch`(`remaining_attempts`) · `phone_code_expired` · `phone_code_locked`, 기본 정보 저장의 422 `phone_not_verified` · 409 `phone_number_in_use`. 앱은 code 로 가르고 글자는 앱이 정한다.
- **분석**: `ApiRoutePattern.routeWords` 에 `phone-verification` · `send` 낱말이 더해졌다(5xx · 연결 실패 기록의 경로 패턴).
- **기기 E2E 7건(E-ONB-05 · 06 · 07 · 10 · 11 · 16 · 17) — 2026-11-11 PR #699 로 되살렸다**(기기 실행은 아직 하지 않았다: PC 단위 시험 · 서버 시험 · `flutter analyze` 까지만 확인). 04-1 [다음] 이 인증된 번호에서만 켜지므로, 앱이 시험 번호로 [인증번호 받기] 를 누르면 PC 하네스(`e2e/phone_sms.py`)가 **로컬 서버의 가짜 발송기 로그**에서 6자리를 읽어 앱에 건넨다. 규칙은 코드가 지킨다: 받는 번호는 사용자 시험 번호 하나뿐(무작위 번호 금지, 앱도 칸의 번호가 PC 가 준 시험 번호가 아니면 누르기 전에 멈춘다) · `SUPABASE_URL` 과 `API_BASE_URL` 어느 한쪽이 운영이거나 `API_BASE_URL` 을 알 수 없으면 `blocked`. 준비물은 `frontend/run.md` "자동 E2E 하네스"의 "가짜 문자 시험 준비물". **서버 쪽 변경은 `app/phone_verification/sms.py` 한 줄**(가짜 발송기의 INFO 한 줄이 로컬 서버 로그에 나오게 함)이고 **다음 서버 배포 때 함께 나간다** — 운영에는 가짜 발송기가 없어 동작은 달라지지 않는다. (종전 서술 2026-11-11 오전: "기기 E2E 7건이 막혀 있다 … 다음 PR 에서 로컬 가짜 문자로 되살린다" — #699 merge 로 개정.) E-ONB-12 · 13 은 인증번호 받기도 꺼져 있는지 함께 본다.

**롤백**: 새 리비전 → `00102-46b` 로 트래픽을 돌리면 네트워크(고정 IP) 설정도 그 리비전 것으로 돌아온다. DB 는 추가뿐이라 되돌리지 않는다(지우려면 서버를 먼저 되돌린 뒤 사용자 승인으로 — 새 표를 먼저 지우면 새 서버가 500 이다). 하한은 `00063` 아래 금지 + `00087` 이전 금지(§4-14), 이미지 하한은 §4-24. 새 서버가 알림함에 쌓은 `poll_comment` 줄을 옛 앱이 만났을 때의 모양은 확인하지 못했다.

**배포 후 점검 목록 (다음 배포에도 같은 목록을 쓴다)**
- `/health` ok · 새 리비전 ERROR 로그 0 · env 개수가 넣은 값만큼만 늘었는지(§2) · 빌드 로그 `inflating: /workspace/.venv` 0줄
- `POST /batch/cleanup` 응답에 `deleted_inquiries` · `deleted_phone_verifications` 두 키(처음엔 0)
- 문의 한 건이 운영 메일에 도착 · 댓글 푸시가 글쓴이에게 도착(같은 글 10분 묶음) · 관리자 웹 #690 · #692 가 새 경로를 부름

**알려진 한계 · 확인 못 한 것**
- 정지된 계정은 앱의 `AuthRedirect` 때문에 문의하기 화면에 들어가지 못한다(정지 안내 화면에는 메일 주소만 있다). 서버는 정지 계정의 문의도 받는다. 별건으로 사용자에게 물을 일이다.
- 솔라피 발신번호는 **2026-11-11 부터 사용자 업무 번호(솔라피에 등록한 발신번호)** 이고, Secret Manager `solapi-sender` **버전 2** 를 쓴다(버전 1 은 꺼 둠 — 대장 전달, 이 문서 담당은 Secret Manager 를 조회하지 않았다. 번호 값은 이 문서에 적지 않는다). 발신번호는 지금도 모든 가입자에게 보인다. 통신사 번호도용 문자차단 서비스에 가입된 발신번호는 발송이 막힌다(상태 코드 3113) — 종전 개인 번호는 해지 뒤 수신 성공(4000)을 확인했다(대장 전달). **새 업무 번호 발신은 수신 확인(11-11 14:05, 사용자 확인)** — 시험 번호로 보낸 인증 문자 한 통이 statusCode 4000 으로 접수됐고 사용자가 받은 인증번호를 말해 수신을 확인했다(대장 전달, 번호 · 인증번호 값은 적지 않는다). 번호를 또 바꾸면 `solapi-sender` 새 버전만 넣는다. (종전 서술 2026-11-10: "솔라피 발신번호는 지금 개인 번호 하나이고 모든 가입자에게 보인다" — 개정.)
- 솔라피 키 만료일과 사업자 인증 뒤 하루 한도(1,000)는 대장 전달 값이다. 이 문서 담당은 솔라피 · 클라우드를 조회하지 않았다.
- 같은 글에 초당 여러 댓글이 달리면 댓글 푸시가 한 번 더 갈 수 있다(10분 묶음의 읽고 쓰는 사이 틈, 코드 주석 `shortcut`). 한 글의 댓글이 수천이 되면 `poll_feed` 의 댓글 수 세기를 집계 칸으로 바꾼다.

## 5. 현재 배포 상태 (2026-11-11 기준)

대장 전달 값이다 — 이 문서 담당이 클라우드를 조회하지 않았다. 리비전 · 마이그레이션 개수가 바뀌면 이 절 하나만 고친다.

| 항목 | 값 |
| --- | --- |
| Cloud Run 서비스 | `campus-mate-backend` (asia-northeast3) |
| 돌고 있는 리비전 | **`campus-mate-backend-00102-46b`**(2026-11-10 08:49 UTC 에 만들어짐, 트래픽 100%, 서버 배포 ①, 사용자 승인 뒤) — 서버 PR #653(§4-23)까지에 더해 **#686 홈 숫자 기준 미만 숨김 · #683 서버 글자 고침("잠시 후" · 푸시 제목 "학교 인증") · 자기소개 프롬프트의 "졸업생"** 이 들어 있다(2026-11-11 대장 전달). **그 뒤 main 에 들어간 서버 코드(문의 · 댓글 · 문자 인증 · 친구 초대 50/25, PR #687 ~ #689 · #694, §4-25)는 배포하지 않았다.** 바로 앞 리비전은 `00101-bc9` |
| 운영 마이그레이션 | **103개 적용, 저장소는 109개 — 6개가 운영 미적용(사용자 승인 대기)**. 마지막 적용은 `20261108090000_faq_graduate_certificate`(2026-11-09). 미적용 6개는 `20261110120000` · `20261110200000` · `20261111000000` · `20261111000100` · `20261111000200` · `20261111010000`(§4-25 · `docs/SUPABASE.md` §1 · `docs/ERD.md` 상태줄) |
| 되돌림 하한 | 기능상 `00063` 아래 금지(§4-4) + `00087` 이전 금지(§4-14). 이미지가 남은 가장 오래된 리비전은 **`00086`**(§4-24 — 배포가 늘수록 올라간다). 되돌리기 전에 그 리비전의 이미지가 창고에 남아 있는지 먼저 확인한다 |
| 리비전별 되돌림 | `00102` → `00101`: 홈 숫자 기준 미만 숨김 · 글자 고침 · 프롬프트 "졸업생" 만 빠진다(§4-25). `00101` → `00100`: 흡연 칸 감점 규칙만 빠진다(§4-23). `00100` → `00099`: 푸시 고치기 4건만(§4-22). `00099` → `00098`: 후보 1명 무료만(§4-21). `00098` → `00097`: `GET /app/version` 만 사라지고 앱은 막지 않는다(§4-20). `00097` → `00096`: 새벽 4시 취향 단어 다시 채우기(⑥)만(§4-19). `00096` → `00095`: 글 속 취향 부딪힘 감점만(§4-18). `00094` 아래: 첫 카드와 학번 숫자 규칙이 빠진다(§4-17) |
| 설정 | 약관 동의 판 `2026-10-20` · 홈 리뷰 띠 숨김(`STORE_RATING_COUNT=0`) · 졸업생 스위치 켜짐 · 최대 인스턴스 20 · 로그 보관 30일 · env 27개(그중 시크릿 11, §2) |
| Cloud Scheduler | 4개, 전부 OIDC(§4-3) — 카드 지급 `campus-mate-daily-cards` 매일 07:00 · 정리 `campus-mate-cleanup` 매일 04:00 · 채팅 확인 `campus-mate-chat-gate` 매시 정각 · 환불 확인(`/batch/billing-voided`) 매시 30분. 전부 Asia/Seoul · asia-northeast3 |
| Cloud Tasks 큐 | `avatar-generate`(asia-northeast3) — 재시도 1회(실효상 끔), 동시 처리 5, 호출자 서비스 계정 `avatar-task-invoker`(§4-2) |
| Storage 버킷 | `avatars`(공개) · `profile-photos` · `student-id-temp` · `heart-task-proofs` · `graduate-cert-temp`(비공개) — 정리 배치와 졸업생 정리가 비운다 |
| 애플 서버 알림 URL | 프로덕션 · 샌드박스 V2 등록(§4-10) |
| 카드 오픈 날짜 | 서울 학교 64곳은 운영 DB 에서 null(열림) — §4-17 |

**열려 있는 것 · 확인이 비어 있는 것**

1. 서울 학교 카드 오픈 날짜는 스토어 심사 통과 뒤 날짜를 정해 다시 막아야 한다(§4-17).
2. 운영 DB 의 구글 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)와 심사 계정의 심사원 로그인 비밀번호는 심사 통과 뒤 제거 · 무작위화 대상이다(§4-16).
3. 새벽 4시 정리 배치 ⑥ 의 `refilled_taste` 응답 값을 본 적이 없다(§4-19).
4. 후보 1명 무료 카드 · 흡연 칸 · 푸시 고치기의 운영 실제 결과는 전달받지 못했다(§4-21 · §4-23 · §4-22).
5. 배포 창고 정리 규칙을 켠 뒤 실제 삭제 결과는 전달받지 못했다(§4-24).
6. `MIN_APP_VERSION` 은 두 스토어에 고친 빌드가 공개된 뒤에만 올린다(§2).
7. **11-08 회의 묶음의 나머지(문의 · 댓글 · 휴대폰 인증 · 친구 초대 50/25 — 홈 숫자 기준은 `00102-46b` 로 이미 배포됐다)는 DB 6개 · 서버 · 고정 나가는 IP · 관리자 웹 #690 · #692 가 모두 승인 대기다.** 순서와 점검은 §4-25. `PHONE_VERIFICATION_REQUIRED` 는 새 앱이 두 스토어에 공개된 뒤에 켜고 `MIN_APP_VERSION` 과 같이 올린다.
