# backend 배포 — Google Cloud Run (asia-northeast3, 서울)

**아래 명령은 GCP 프로젝트가 준비되고 사용자가 승인한 뒤에만 실행한다** (spec §13-37).

## 0. 사전 준비 완료 (2026-09-20)

값은 전부 Secret Manager 또는 KeePassXC 에 있고, 이 문서엔 이름만 적는다 — URL·키 값은 적지 않는다.

- **Cloud Vision API** — campus-mate GCP 프로젝트에 사용 설정 완료. 별도 인증 키 없이 Cloud Run 기본 서비스 계정으로 자동 인증(조각 1b)
- **디스코드 웹훅** — `학생증-재검토` 채널 웹훅 생성, Secret Manager `discord-review-webhook-url` 로 등록 완료(조각 1b 계획 초안의 가칭 `discord-webhook-url`이 아니라 이 이름을 쓴다)
- **OpenAI API 키** — Secret Manager `open-api-key` 로 등록 완료(조각 2 아바타 변환용, 준비 가이드의 가칭 `openai-api-key`가 아니라 이 이름을 쓴다)
- **전화번호 암호화 키** — Secret Manager `phone-number-encryption-key`(version 1) 로 등록 완료(조각 2 pgcrypto)
- **Firebase** — 기존 campus-mate GCP 프로젝트에 연동, Android 앱(`io.github.juunn.campusmate`) 등록, FCM v1 사용 설정 완료(조각 4 푸시 알림용). `google-services.json`은 아직 사용자 로컬 보관 중 — 조각 3·4 구현 시 `.gitignore`에 추가한 뒤 `frontend/android/app/`에 배치할 예정

## 1. 최초 1회

**시크릿 값을 파일에서 읽어 넣을 때는 반드시 `tr -d '\r\n'` 을 거친다(2026-09-21 사고).**
윈도우에서 만든 파일은 줄 끝이 `\r\n` 이라 `--data-file=` 로 그대로 넣으면 **`\r` 이 값의 일부로 저장된다.**
눈으로는 보이지 않고 길이만 1 바이트 길어져서, `card-batch-secret` 이 이 사고로 오염돼 Cloud Scheduler 가
계속 401 을 받았다(버전 2 를 새로 올려 고쳤다 — 아래 §4). `echo -n` 으로 직접 넣을 때도 `-n` 을 빠뜨리면 같은 일이 난다.

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

# 2026-09-29 OIDC 전환으로 더는 만들지 않는다 — 서버가 읽지 않고 §4-3 6단계에서 폐기한다(기록으로 남긴다).
# 조각 4: /batch/daily-cards 를 Cloud Scheduler 만 부르게 하는 공유 비밀.
# 값은 아무 난수나 길게(예: openssl rand -base64 32) — 이 문서에 값을 적지 않는다.
echo -n "<card batch secret>" | gcloud secrets create card-batch-secret --data-file=-

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
`add-iam-policy-binding` 이 그 자리에서 거부한다(2026-09-21 배포 중 정정).

## 2. 배포

```bash
cd backend
gcloud run deploy campus-mate-backend \
  --source . \
  --region asia-northeast3 \
  --allow-unauthenticated \
  --set-env-vars SUPABASE_URL=<project-url>,GOOGLE_CLOUD_PROJECT=<PROJECT_ID>,AVATAR_TASKS_QUEUE=<큐 이름>,AVATAR_WORKER_URL=<cloud-run-url>/tasks/avatar-generate,AVATAR_TASKS_SERVICE_ACCOUNT=<큐가 쓸 서비스 계정 이메일>,BATCH_AUDIENCE=<cloud-run-url>,BATCH_SERVICE_ACCOUNT=campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --set-secrets SUPABASE_SERVICE_ROLE_KEY=supabase-service-role-key:latest,AUTH_HOOK_SIGNING_SECRET=auth-hook-signing-secret:latest,DISCORD_WEBHOOK_URL=discord-review-webhook-url:latest,IDENTITY_HMAC_KEY=identity-hmac-key:latest,OPENAI_API_KEY=open-api-key:latest,PHONE_ENCRYPTION_KEY=phone-number-encryption-key:latest,DISCORD_REPORT_WEBHOOK_URL=discord-report-webhook-url:latest
```

`BATCH_AUDIENCE` · `BATCH_SERVICE_ACCOUNT` 중 하나라도 빠뜨리면 세 배치(`/batch/*`)는 **아무 요청도 통과시키지 않는다**(전부 401).
열린 채로 남는 쪽보다 닫힌 채로 실패하는 쪽을 택했다 — 카드가 안 나가면 바로 눈에 띈다.
2026-09-29 OIDC 전환 5단계로 `CARD_BATCH_SECRET` 은 이 명령과 서버 코드에서 빠졌다(§4-3).

**`IDENTITY_HMAC_KEY`·`OPENAI_API_KEY`·`PHONE_ENCRYPTION_KEY` 3개가 이 명령에서 빠져 있었다(PR #85 리뷰에서 잡음, §0 에는 시크릿 등록만 돼 있고 배포 명령에 연결이 안 됐던 것). `settings.py` 가 필수(`min_length=1` 등)로 요구하므로 빠지면 그 자리에서 기동이 실패한다.** → **2026-09-29 확인: 위 명령에 셋 다 들어 있다**(조각 6 배포 때 반영, 시크릿 이름 `identity-hmac-key` · `open-api-key` · `phone-number-encryption-key`). 조각 6 에서 `DISCORD_REPORT_WEBHOOK_URL`(`discord-report-webhook-url`, 신고 전용 채널 — 비어 있으면 신고 알림만 건너뛰고 경고 로그)이 더해졌다. `settings.py` 가 읽는 env · 시크릿은 위 한 줄로 전부다(2026-09-29 `settings.py` 와 대조)

**Auth OTP expiry — Supabase 대시보드 Authentication 설정의 OTP 유효시간을 300초(5분)로 맞춘다.** 기본값(3600초)과 앱의 인증 코드 화면 카운트다운(5분)이 어긋나 있었다(운영에서는 아직 3600초, 승인 대기 중).

`--allow-unauthenticated` 로 배포한다 — Supabase HTTP Auth Hook은 GCP IAM 아이덴티티 토큰을 발급할 수 없어서, IAM 인증을 걸면 훅 호출 자체가 막힌다. 대신 요청 인증은 Standard Webhooks HMAC 서명 검증 + timestamp ±5분 범위 검사(코드에 구현됨)가 담당한다.

## 3. 배포 확인

엔드포인트가 `--allow-unauthenticated`라 토큰 없이 바로 확인한다:

```bash
curl https://<서비스 URL>/health
```

`{"status":"ok"}` 가 나오면 성공.

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
  --uri="https://<cloud-run-url>/batch/daily-cards" \
  --http-method=POST \
  --headers="X-Batch-Secret=<card-batch-secret 값>" \
  --attempt-deadline=600s
```

**2026-09-29 OIDC 로 바꿨다(§4-3).** 위 `--headers` 줄은 옛 방식이고 지금 서버는 그 헤더를 받지 않는다 —
job 을 새로 만들면 `--headers` 대신 §4-3 의 `--oidc-service-account-email` · `--oidc-token-audience` 를 쓴다.

- Cloud Run 이 `--allow-unauthenticated` 라 이 엔드포인트는 스스로를 지킨다(조각 1a auth hook 과 같은 이유).
- 토큰이 없거나 틀리면 401 이고, 그때는 아무 카드도 나가지 않는다.
- 실행 결과는 `{"issued": 3, "no_candidate": 1, "skipped_regions": ["busan"]}` 모양으로 돌아오고
  Cloud Logging 에 남는다. `skipped_regions` 는 오늘이 지급 요일이 아닌 지역그룹이다.
- 실행 시간이 600초를 넘기 시작하면 지역그룹별로 job 을 나눈다(백로그).

손으로 한 번 돌려 보려면:

```bash
gcloud scheduler jobs run campus-mate-daily-cards --location=asia-northeast3
```

**주의:** 이 배치는 조각 4 의 DB 마이그레이션(`region_group_settings` · `daily_cards` …)이 클라우드에
적용된 뒤에야 돈다. 적용 전에 job 을 만들면 매일 500 이 쌓인다 — 마이그레이션 적용 뒤에 만든다.

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
  --uri="https://<cloud-run-url>/batch/chat-gate" \
  --http-method=POST \
  --headers="X-Batch-Secret=<card-batch-secret 값>" \
  --attempt-deadline=600s
```

**2026-09-29 OIDC 로 바꿨다(§4-3).** 위 `--headers` 줄은 옛 방식이다 — 카드 배치와 같은 스케줄러 계정 ·
audience 를 쓴다(둘 다 우리 스케줄러만 부르는 엔드포인트라 나눌 이유가 없다).

- 실행 결과는 `{"reminded": 2, "closed": 1, "passed": 0}` 모양이고 Cloud Logging 에 남는다.
  `passed` 는 **양쪽이 수락했는데 통과 도장이 빠진 방을 배치가 대신 찍어 준 수**다. 0 이 정상이고,
  계속 올라오면 `/trust` 가 중간에 끊기고 있다는 뜻이다.
- **매시 정각을 건너뛰면 그 시간에 걸린 리마인드는 다시 오지 않는다.** 보낼 시각을 한 시간짜리 창으로
  판정하기 때문이다("보냈다" 표시 컬럼을 두지 않으려고 고른 방식). 마감(`chat_closed_at`)은 다음 시간에
  따라잡으므로 문제가 없다.
- 새벽(22~8시)에 걸린 리마인드는 서버가 **아침 8시로 미뤄** 보낸다. 조용한 시간에 버려지면 창이 한 번뿐이라
  영영 못 가기 때문이다.

**주의:** 이 job 도 조각 5 의 `messages` 마이그레이션이 클라우드에 적용된 뒤에 만든다.

## 4-2. 아바타 작업 큐 (조각 2 후속, 2026-09-26)

아바타를 만드는 데 1분 가까이 걸려서 요청 안에서 만들지 않는다. 04-3 의 "다음"은 **작업만 등록하고**
바로 다음 질문으로 넘어가고, Cloud Tasks 가 워커(`/tasks/avatar-generate`)를 따로 부른다.
스케줄러가 아니라 **큐**라 무료 한도 3 job 과는 상관이 없다.

**전제: 큐 리전 = Cloud Run 리전(`asia-northeast3`).** 코드가 리전을 모듈 상수로 박고 있어서
(`app/profile_onboarding/avatar_tasks.py`), 큐를 다른 리전에 만들면 작업 등록이 **조용히 404 로
실패**한다. 화면에는 "잠시 뒤 다시 시도해 주세요"만 뜬다.

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
# 2026-09-26 사용자 결정으로 개정, 종전 roles/iam.serviceAccountTokenCreator — 실기기에서 아바타 등록이
# 403 으로 막혀서 잡힌 오류였다. oidcToken 을 붙인 작업을 만드는 호출자는 그 계정에 대해
# iam.serviceAccounts.actAs 가 있어야 한다(Google Cloud "Create HTTP target tasks" 문서).
# 토큰 자체는 Cloud Tasks 서비스 에이전트가 만든다(roles/cloudtasks.serviceAgent, API 를 켜면 자동 부여).
gcloud iam service-accounts add-iam-policy-binding <계정 이메일> \
  --member="serviceAccount:<Cloud Run 서비스 계정>" \
  --role="roles/iam.serviceAccountUser"
```

- **이 역할이 빠지면**: `POST /avatar/generate` 가 502, 백엔드 로그에 "아바타 작업 등록 실패" + Cloud Tasks 403, 앱에는 "알 수 없는 오류"가 뜬다. → **2026-09-26 PR #117 로 개정: 앱은 502 · 503 을 "잠시 뒤 다시 시도해 주세요" 로 보인다**(`ServerUnavailableFailure`). 그 밖의 5xx 는 여전히 "알 수 없는 오류" 다.
- 운영에는 2026-09-26 `serviceAccountUser` 를 추가했다. 종전 `serviceAccountTokenCreator` 는 아직 남아 있고, 빼는 것은 **결정 대기**다(둘 다 있어도 동작엔 지장 없지만 최소 권한 원칙상 정리할지는 사용자가 정한다).

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

**필수 업로드 — 기본 아바타 원본 `avatars/defaults/fallback-avatar.png`** (결함 D-02, 2026-10-05).
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

§4 · §4-1 의 job 2개는 `X-Batch-Secret` 헤더에 공유 열쇠를 실어 온다. 열쇠가 job 설정과 서버 양쪽에
복사돼 있어서 **한쪽만 바꾸면 그 사이 배치가 전부 401** 이다(§1 의 `\r` 사고). OIDC 로 바꾸면 job 이
구글이 서명한 ID 토큰을 달고 오고, 서버는 공개키로 검증한 뒤 발급 계정까지 본다(`app/core/batch_auth.py`)
— 복사해 둘 열쇠가 없어진다.

**2026-09-29 진행: 1~4단계 끝**(대장 — revision `00039-mbr`, job 셋 다 `auth=oidc` 200). **5단계 = 공유 열쇠 코드
삭제 PR.** 6단계는 그 배포 뒤에 남았다.

서버는 4단계까지 **둘 다 받았다** — 옛 헤더가 맞거나 **또는** ID 토큰이 맞으면 통과했다. 그래서 아래 순서대로
가면 401 창이 없다. **각 단계의 "확인" 이 된 뒤에 다음 단계로 간다.** 5단계부터는 ID 토큰만 받는다.

환경변수 2개가 새로 생긴다. 비밀이 아니라서 `--set-secrets` 가 아니라 §2 의 `--set-env-vars` 에 들어 있다.

- `BATCH_AUDIENCE` — Cloud Run 서비스 URL, **경로 없이**(끝에 `/` 도 없이). 두 job 이 이 값 하나를 같이 쓴다.
- `BATCH_SERVICE_ACCOUNT` — 스케줄러 서비스 계정 이메일 `campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com`.
- **둘 중 하나라도 비어 있으면 OIDC 로는 아무도 못 들어온다** — 5단계 전에는 옛 헤더가 대신 열었지만, 5단계 뒤에는 배치가 전부 401 이다.

§2 70행과 아래 `<cloud-run-url>` 은 이 명령이 찍는 값 그대로다(`https://` 포함, 경로 · 끝 `/` 없이):

```bash
gcloud run services describe campus-mate-backend --region=asia-northeast3 --format='value(status.url)'
```

**1단계 — 서비스 계정 만들고 권한 주기**

```bash
gcloud iam service-accounts create campus-mate-scheduler --display-name="campus mate scheduler"

# job 이 부를 Cloud Run 서비스에 호출 권한을 준다.
gcloud run services add-iam-policy-binding campus-mate-backend \
  --region=asia-northeast3 \
  --member="serviceAccount:campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/run.invoker"

# 3단계에서 job 에 이 계정을 붙이는 사람(= gcloud 로그인 계정)은 그 계정에 대해
# iam.serviceAccounts.actAs 가 있어야 한다 — §4-2 의 403 과 같은 교훈이다.
# 프로젝트 소유자면 이미 있지만, 없으면 3단계가 PERMISSION_DENIED 로 멈춘다.
gcloud iam service-accounts add-iam-policy-binding campus-mate-scheduler@<PROJECT_ID>.iam.gserviceaccount.com \
  --member="user:<gcloud 로그인 이메일>" \
  --role="roles/iam.serviceAccountUser"
```

확인: `gcloud run services get-iam-policy campus-mate-backend --region=asia-northeast3` 에 `roles/run.invoker` 와 `campus-mate-scheduler@…` 가 같이 보인다.

**2단계 — 이 서버를 배포하기**

§2 명령으로 배포한다. **`BATCH_AUDIENCE` · `BATCH_SERVICE_ACCOUNT` 는 §2 명령에도 넣어 두었다** —
`--set-env-vars` 는 전체 교체라 빠뜨리면 3단계 뒤 배치가 전부 401 이다.

확인: 새 서버가 떴고 job 이 아직 옛 헤더로 들어오는지 본다. 옛 revision 도 200 을 주므로 200 만으로는
배포 실패나 env 오류를 못 잡는다.

```bash
# 새 revision 의 env. BATCH_AUDIENCE 가 위에서 본 status.url 출력과 글자까지 같아야 한다
# (Cloud Run URL 은 모양이 두 가지다 — …a.run.app 과 …<프로젝트 번호>.asia-northeast3.run.app).
gcloud run services describe campus-mate-backend --region=asia-northeast3 --format=yaml | grep -A1 BATCH_

# 카드 배치는 하루 한 장이라 손으로 한 번 더 돌려도 안전하다(issuing.py).
gcloud scheduler jobs run campus-mate-daily-cards --location=asia-northeast3

# 1~2분 뒤. /batch/daily-cards 가 200 이면 된다. chat-gate 는 다음 정각 실행을 같은 명령으로 본다.
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="campus-mate-backend" AND httpRequest.requestUrl:"/batch/"' \
  --freshness=15m --limit=5 --format='value(timestamp,httpRequest.requestUrl,httpRequest.status)'

# "batch /batch/daily-cards auth=secret" 이 보여야 통과다 — 이 로그 줄은 새 코드만 찍는다.
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="campus-mate-backend" AND textPayload:"auth="' \
  --freshness=15m --limit=10 --format='value(timestamp,textPayload)'
```

**`auth=secret` 이 안 보이면 새 서버가 아직 안 떴다 — 3단계로 가면 배치가 전부 401.**

**3단계 — job 2개를 OIDC 로 바꾸고 옛 헤더 빼기**

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

**2026-09-29 실제로 한 순서다.** 처음 적었던 `--remove-headers=X-Batch-Secret`(OIDC 플래그와 한 명령)은
`gcloud scheduler jobs update http --help` 에는 있지만 SDK 586 에서 `TypeError` 로 죽었다. 그래서 OIDC 를 먼저
따로 붙이고 헤더는 `--clear-headers` 로 뺐다. `--update-headers` 는 헤더를 **더하거나 고치는** 플래그라 여기 맞지 않는다.

확인: `gcloud scheduler jobs describe campus-mate-daily-cards --location=asia-northeast3 --format='yaml(httpTarget)'`
에 `oidcToken`(계정 · audience)이 있고 `X-Batch-Secret` 이 없다. `campus-mate-chat-gate` 도 같다.

**4단계 — 손으로 돌려 `auth=oidc` 확인**

```bash
gcloud scheduler jobs run campus-mate-daily-cards --location=asia-northeast3
gcloud scheduler jobs run campus-mate-chat-gate --location=asia-northeast3

# 1~2분 뒤. 두 경로 모두 200 이어야 한다 — 헤더를 뺐으니 200 이면 토큰으로 들어온 것이다.
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="campus-mate-backend" AND httpRequest.requestUrl:"/batch/"' \
  --freshness=15m --limit=5 --format='value(timestamp,httpRequest.requestUrl,httpRequest.status)'

# 서버가 남기는 한 줄. "batch /batch/daily-cards auth=oidc" · "batch /batch/chat-gate auth=oidc" 가 보이면 된다.
# 로깅 설정이 없어 파이썬 레벨이 severity 로 옮겨지지 않는다 — severity 조건은 걸지 않는다.
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="campus-mate-backend" AND textPayload:"auth="' \
  --freshness=15m --limit=10 --format='value(timestamp,textPayload)'
```

- `auth=secret` 이 보이면 그 job 의 헤더가 아직 남아 있다 — 3단계 확인으로 돌아간다.
- 401 이면 대개 audience 가 어긋난 것이다. job 의 `--oidc-token-audience` 와 `BATCH_AUDIENCE` 가 **글자 하나까지**
  같은지(경로 · 끝 `/`) 본다. 급하면 옛 헤더를 다시 넣어(§5 의 `--update-headers` 명령) 바로 되살린다 — 5단계 전까지는 서버가 받는다.
- chat-gate 를 손으로 돌리면 그 시간 리마인드 대상에게 알림이 한 번 더 갈 수 있다(`app/chat/gate.py` 의 한 시간 창). 한 번만 돌린다.

**5단계 — 공유 열쇠 코드 삭제 (별도 작은 PR)**

4단계가 확인된 뒤에 연다. 지우는 것: `settings.card_batch_secret` · `verify_batch_caller` 의 옛 헤더 분기 ·
관련 테스트 · §2 `--set-secrets` 의 `CARD_BATCH_SECRET=card-batch-secret:latest`. 두 배치 라우터의
`auth=` 로그 줄(`logger.warning`, 전환 확인용)도 같이 지운다.
**이 PR 과 한 번에 넣지 않는 이유:** merge · 배포 순간 job 이 아직 옛 헤더라 배치가 전부 401 이 된다.

**2026-09-29 한 것:** 옛 헤더 분기를 지우면 `verify_batch_caller` 가 할 일이 없어서 통째로 지웠다 — 세 배치
라우터(카드 · 채팅 · 정리)가 아바타 워커처럼 `verify_oidc_token` 을 바로 부른다. `auth=` 로그 줄도 세 곳 다
지웠으니 이 배포 뒤로는 2 · 4단계의 `textPayload:"auth="` 조회에 아무것도 안 나온다 — 200 은 첫 `logging read`
(`httpRequest.status`)로 본다.

확인: 배포 뒤 다음 정각 chat-gate · 04:00 cleanup · 07:00 daily-cards 가 200(4단계의 첫 `logging read`).

**6단계 — 시크릿 폐기**

**먼저 서비스에서 `CARD_BATCH_SECRET` 참조를 뺀다.** `--source` 만 주는 배포(`cm_deploy.sh`)는 서비스에 붙은
`--set-secrets` 참조를 그대로 두어서 5단계 배포 뒤에도 남아 있다. 서버는 이 env 를 읽지 않으니 남아 있어도
기동은 된다(`tests/test_settings.py`) — 하지만 남은 채로 버전을 끄면 새 인스턴스가 시크릿을 못 읽어 뜨지 못한다.

```bash
# 새 revision 이 하나 생긴다(이미지 · 다른 env · 시크릿은 그대로).
gcloud run services update campus-mate-backend --region=asia-northeast3 --remove-secrets=CARD_BATCH_SECRET

# 0 이 나와야 한다.
gcloud run services describe campus-mate-backend --region=asia-northeast3 --format=yaml | grep -c card-batch-secret

gcloud secrets versions list card-batch-secret
gcloud secrets versions disable <쓰던 버전 번호> --secret=card-batch-secret

# 하루 지켜보고 배치가 계속 200 이면 통째로 지운다.
gcloud secrets delete card-batch-secret
```

확인: 다음 날 세 job 모두 200 이고, `gcloud secrets list` 에 `card-batch-secret` 이 없다.

**새 job 은 처음부터 OIDC 로 만든다** — 세 번째 job(정리 배치)도 `--oidc-service-account-email` ·
`--oidc-token-audience=<cloud-run-url>` 로 만들고 `--headers` 는 붙이지 않는다. 계정 · 권한 · 서버 설정은 위 것을 그대로 쓴다.
주소는 `--uri=<cloud-run-url>/batch/<경로>` 다 — 여기 `<cloud-run-url>` 은 `https://` 를 포함하므로 §4 처럼
`https://` 를 또 붙이면 `https://https://` 가 된다.

## 4-4. 탈퇴 · 지인 차단 · 정리 배치 (조각 6 PR 3, 2026-09-27)

**적용 순서 — 이 순서대로, 앞 단계가 끝난 뒤에 다음 단계로 간다.**

1. 마이그레이션 클라우드 적용 — `20260927030000_set_phone_number_with_hmac` · `20260927030100_create_withdraw_account`.
2. `NOTIFY pgrst, 'reload schema';` (SQL 편집기) — 새 서버의 5인자 `set_phone_number` 호출이 옛 스키마 캐시에 걸리지 않게 한 번 새로 고친다.
3. 새 서버 배포(§2 명령 그대로, 새 env · 시크릿 없음).
4. 백필 한 번(아래) — 새 서버 배포 **뒤**에 돌린다. 그 전에는 옛 서버의 3인자 호출이 `phone_hmac` 을 null 로 덮고, null 행은 지인 차단 대조에서 빠진다.

**백필** — 조각 6 전에 저장된 번호에 지인 차단 해시를 채운다. 한 번 쓰고 버리는 스크립트라 컨테이너에는 없다
(`backend/scripts/`). 다시 돌려도 안전하다(빈 칸인 행만 고르고 빈 칸일 때만 쓴다).

```bash
cd backend
# settings.py 가 §2 의 env 와 시크릿을 전부 요구한다. 시크릿은 Secret Manager 에서 env 로 넣는다 — 값은 여기 적지 않는다.
#   예: export PHONE_ENCRYPTION_KEY="$(gcloud secrets versions access latest --secret=phone-number-encryption-key)"
.venv/Scripts/python.exe -m scripts.backfill_phone_hmac
# 출력은 건수뿐이다: filled=<채운 행> skipped=<휴대전화가 아니거나 복호화 결과가 없는 행>
```

**정리 배치 job** — 매일 04:00 Asia/Seoul 에 `/batch/cleanup`. **처음부터 OIDC 다**(§4-3 의 계정 · 권한 ·
`BATCH_AUDIENCE` 를 그대로 쓰고 `--headers` 는 붙이지 않는다). 무료 한도 3 job 중 세 번째다. 3단계 배포 뒤에 만든다.
**2026-09-29 만들었다**(대장 — OIDC · 헤더 없음, 손으로 돌려 200 확인).

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
  - **2026-09-28 개정(무료 하트 인증 #154)**: ① 의 버킷은 **4개**다 — `avatars` · `profile-photos` · `student-id-temp` · `heart-task-proofs`(`app/account/batch_router.py` `STORAGE_BUCKETS`). **⑤ 검수 끝나고 60일 지난 무료 하트 인증샷**을 하루 100장씩 지운다(파일 먼저, 경로 비우기는 나중 — `app/heart_tasks/cleanup.py`). `heart-task-proofs` 버킷이 운영에 없으면 ① 이 그 버킷에서 막혀 탈퇴 계정이 전부 `skipped` 가 된다 — 무료 하트 마이그레이션(§4-5)이 먼저다.
  - **2026-09-29 확인**: ② 는 `resolved_at` 기준이다(#165). 그 전 코드는 `created_at` 기준이라 1년 넘게 열린 신고까지 지웠다.
- 결과는 `{"deleted_accounts", "skipped_accounts", "deleted_reports", "deleted_signup_blocks", "stale_key_rows"}` 모양이다. **2026-09-28 부터 `"deleted_heart_proofs"` 칸이 하나 더 붙는다**(⑤).
  `skipped_accounts` 는 파일 삭제가 실패해 **내일 다시** 할 사람이다. 며칠째 같은 수면 로그의 `탈퇴 계정 정리 건너뜀` 을 본다.
  `stale_key_rows` 가 0 이 아니면 `identity-hmac-key` 를 바꾼 뒤 옛 행이 남은 것이다(`app/signup_policy.py` 의 `IDENTITY_KEY_VERSION`).
- 확인: `gcloud scheduler jobs run campus-mate-cleanup --location=asia-northeast3` 뒤 §4-3 4단계의 `logging read` 로
  `/batch/cleanup` 200 을 본다(`auth=` 한 줄은 §4-3 5단계에서 지웠다). 다시 돌려도 안전하다(두 번째는 전부 0).

## 4-5. 무료로 하트 모으기 — 검수 운영 절차 (2026-09-28, 계획서 `2026-09-28-heart-tasks.md`)

새 env · 시크릿 · job 은 없다. 제출 알림은 학생증 재검토와 같은 디스코드 채널(`DISCORD_WEBHOOK_URL`)로 가고, 60일 정리는 §4-4 정리 배치 ⑤ 가 한다.

**적용 순서(2026-09-28 적용 끝)**: 마이그레이션 번호 순서 그대로 한 번에 — `20260928010000_create_referrals` → `20260928020000_fix_grant_hearts_spend` → `20260928030000_create_heart_task_submissions` → `20260928030100_create_heart_task_functions` → `20260928040000_create_friend_reviews` → `NOTIFY pgrst, 'reload schema';` → 서버 배포. **서버를 먼저 배포하면** 목록 · 제출이 500 이고, 정리 배치가 없는 버킷에서 막혀 탈퇴 계정이 전부 skipped 된다. 코호트(`20260928050000`)도 서버(`/home/summary` 의 `cohort`)보다 먼저다.

**검수(운영자)**

1. 디스코드 "무료 하트 인증 1건 (제출: `<id>`, 계정: `<profile_id>`, 항목: `everytime_post`)" 을 본다. 사진 · 경로 · 이름은 싣지 않는다.
2. Supabase 대시보드 → Table editor → `heart_task_submissions` 에서 `id` 로 줄을 찾고, `storage_path` 로 Storage → `heart-task-proofs` 의 파일을 연다.
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

## 5. 현재 배포 상태 (2026-09-26 기준)

**2026-09-29 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).**

| 항목 | 값 |
| --- | --- |
| 돌고 있는 revision | **`campus-mate-backend-00039-mbr`**(2026-09-29, `00038-ggj` 에 OIDC env 두 개만 더했다 — 코드는 00038 과 같다). `00038-ggj` 는 가입 동의 서버 #170 까지다. 대장 기록에 남은 그 사이 revision: `00026-phq` · `00027-hbs` · `00030-9gn` · `00032-xfr` · `00033-tk6` · `00034-gxd` · `00035-rhd` · `00036-rtl` · `00037-kbv`(빠진 번호는 기록 없음) |
| 마이그레이션 | 저장소 `supabase/migrations/` **52개**(2026-09-29 이 문서 담당이 셌다). 운영 마지막 적용 = `create_faq`(운영 기록 `20260929054505`), 그 앞 `create_user_consents`(`20260929051356`). 운영 쪽 개수는 세지 않았다 |
| 조각 6 이후 새 시크릿 | `discord-report-webhook-url` → `DISCORD_REPORT_WEBHOOK_URL`(신고 전용 채널, version 1) |
| 새 env | `BATCH_AUDIENCE` · `BATCH_SERVICE_ACCOUNT`(§4-3) — `00039-mbr` 에 들어 있다. 호출 계정 `campus-mate-scheduler`(`roles/run.invoker`) |
| Cloud Scheduler job | **3개, 전부 OIDC · `X-Batch-Secret` 헤더 없음**(2026-09-29 대장이 gcloud 로 확인, 로그 `auth=oidc` 200 셋 다) — `campus-mate-daily-cards`(`0 7 * * *`) · `campus-mate-chat-gate`(`0 * * * *`) · `campus-mate-cleanup`(`0 4 * * *`, 09-29 새로 만듦). 셋 다 Asia/Seoul · asia-northeast3, 무료 한도 3개가 찼다. §4-3 은 1~4단계 끝, 5단계(공유 열쇠 코드 삭제) 배포 → 시크릿 참조 빼기 → 6단계가 남았다 |
| Storage 버킷 | `avatars`(공개) · `profile-photos` · `student-id-temp` · `heart-task-proofs`(비공개 · 10MB · jpeg/png, 2026-09-28) — 정리 배치가 넷 다 비운다 |

아래는 2026-09-26 기준 옛 표다(기록으로 남긴다).

| 항목 | 값 |
| --- | --- |
| Cloud Run 서비스 | `campus-mate-backend` (asia-northeast3) |
| 돌고 있는 revision | `campus-mate-backend-00024-wjn`(2026-09-26 사용자 결정으로 개정, 종전 `campus-mate-backend-00022-jpl` — PR #103 학생증 재검토 사유 기록 포함) — PR #106 아바타 비동기 포함, 트래픽 100%(2026-09-26 배포, 배포 후 30분 오류 0) |
| Cloud Scheduler job | **2개** — `campus-mate-daily-cards` (`0 7 * * *` · Asia/Seoul) · `campus-mate-chat-gate` (**매시 정각**, `0 * * * *` · Asia/Seoul). 둘 다 asia-northeast3, 무료 한도 3개 안 |
| Cloud Tasks 큐 | `avatar-generate`(asia-northeast3) — 재시도 1회(실효상 끔), 동시 처리 5, 호출자 서비스 계정 `avatar-task-invoker`(이메일 마스킹, §4-2) |
| 마이그레이션 | **33개**(2026-09-26 사용자 결정으로 개정, 종전 32개 — 09-22 작성된 `sender_index` 마이그레이션이 누락돼 있다가 이번 배포에 같이 들어갔다, 저장소 `supabase/migrations/` 기준) |
| `card-batch-secret` | **version 2** 를 쓴다 — version 1 은 값에 `\r` 이 섞여 401 이 나던 것이라 폐기했다. **두 job 이 같은 비밀을 쓴다**(§4-1) |

**2026-09-29 OIDC 전환 뒤로는 아래 절차를 쓰지 않는다** — job 에 헤더가 없고 서버도 읽지 않는다. 시크릿은 §4-3 6단계에서 폐기한다.

`--set-secrets` 는 `card-batch-secret:latest` 를 참조하므로 새 버전을 올리면 재배포 없이 따라간다.
반대로 **Scheduler 헤더 값은 자동으로 따라가지 않는다** — 시크릿 버전을 올렸으면 job 도 같이 고친다:

```bash
# job 이 둘이므로 둘 다 고친다 — 하나만 고치면 다른 하나가 401 로 조용히 멈춘다.
gcloud scheduler jobs update http campus-mate-daily-cards \
  --location=asia-northeast3 \
  --update-headers="X-Batch-Secret=<새 값>"

gcloud scheduler jobs update http campus-mate-chat-gate \
  --location=asia-northeast3 \
  --update-headers="X-Batch-Secret=<새 값>"
```
