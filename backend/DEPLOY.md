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
  --set-env-vars SUPABASE_URL=<project-url>,GOOGLE_CLOUD_PROJECT=<PROJECT_ID> \
  --set-secrets SUPABASE_SERVICE_ROLE_KEY=supabase-service-role-key:latest,AUTH_HOOK_SIGNING_SECRET=auth-hook-signing-secret:latest,DISCORD_WEBHOOK_URL=discord-review-webhook-url:latest,CARD_BATCH_SECRET=card-batch-secret:latest
```

`CARD_BATCH_SECRET` 을 빠뜨리면 `/batch/daily-cards` 는 **아무 요청도 통과시키지 않는다**(전부 401).
열린 채로 남는 쪽보다 닫힌 채로 실패하는 쪽을 택했다 — 카드가 안 나가면 바로 눈에 띈다.

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

- 헤더 값은 위에서 만든 `card-batch-secret` 과 **같은 값**이어야 한다. 서버는 `hmac.compare_digest` 로 맞춰 본다.
- Cloud Run 이 `--allow-unauthenticated` 라 이 엔드포인트는 스스로를 지킨다(조각 1a auth hook 과 같은 이유).
- 비밀이 없거나 틀리면 401 이고, 그때는 아무 카드도 나가지 않는다.
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

- **새 시크릿을 만들지 않는다.** 카드 배치와 같은 `card-batch-secret` 을 쓴다 — 둘 다 우리 스케줄러만
  부르는 엔드포인트라 비밀을 나눌 이유가 없다. 시크릿 버전을 올리면 이 job 의 헤더도 같이 고쳐야 한다.
- 실행 결과는 `{"reminded": 2, "closed": 1}` 모양이고 Cloud Logging 에 남는다.
- **매시 정각을 건너뛰면 그 시간에 걸린 리마인드는 다시 오지 않는다.** 보낼 시각을 한 시간짜리 창으로
  판정하기 때문이다("보냈다" 표시 컬럼을 두지 않으려고 고른 방식). 마감(`chat_closed_at`)은 다음 시간에
  따라잡으므로 문제가 없다.
- 새벽(22~8시)에 걸린 리마인드는 서버가 **아침 8시로 미뤄** 보낸다. 조용한 시간에 버려지면 창이 한 번뿐이라
  영영 못 가기 때문이다.

**주의:** 이 job 도 조각 5 의 `messages` 마이그레이션이 클라우드에 적용된 뒤에 만든다.

## 5. 현재 배포 상태 (2026-09-21 기준)

| 항목 | 값 |
| --- | --- |
| Cloud Run 서비스 | `campus-mate-backend` (asia-northeast3) |
| 돌고 있는 revision | `campus-mate-backend-00009-*` — 조각 4 까지 반영 |
| Cloud Scheduler job | `campus-mate-daily-cards` (asia-northeast3), `0 7 * * *` · Asia/Seoul |
| `card-batch-secret` | **version 2** 를 쓴다 — version 1 은 값에 `\r` 이 섞여 401 이 나던 것이라 폐기했다 |

`--set-secrets` 는 `card-batch-secret:latest` 를 참조하므로 새 버전을 올리면 재배포 없이 따라간다.
반대로 **Scheduler 헤더 값은 자동으로 따라가지 않는다** — 시크릿 버전을 올렸으면 job 도 같이 고친다:

```bash
gcloud scheduler jobs update http campus-mate-daily-cards \
  --location=asia-northeast3 \
  --update-headers="X-Batch-Secret=<새 값>"
```
