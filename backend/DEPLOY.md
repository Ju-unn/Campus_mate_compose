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
  --set-secrets SUPABASE_SERVICE_ROLE_KEY=supabase-service-role-key:latest,AUTH_HOOK_SIGNING_SECRET=auth-hook-signing-secret:latest,DISCORD_WEBHOOK_URL=discord-review-webhook-url:latest,IDENTITY_HMAC_KEY=identity-hmac-key:latest,OPENAI_API_KEY=open-api-key:latest,PHONE_ENCRYPTION_KEY=phone-number-encryption-key:latest,DISCORD_REPORT_WEBHOOK_URL=discord-report-webhook-url:latest,KAKAO_ADMIN_KEY=kakao-admin-key:latest,VERIFICATION_HOOK_SECRET=verification-hook-secret:latest
```

`BATCH_AUDIENCE` · `BATCH_SERVICE_ACCOUNT` 중 하나라도 빠뜨리면 세 배치(`/batch/*`)는 **아무 요청도 통과시키지 않는다**(전부 401).
열린 채로 남는 쪽보다 닫힌 채로 실패하는 쪽을 택했다 — 카드가 안 나가면 바로 눈에 띈다.
2026-09-29 OIDC 전환 5단계로 `CARD_BATCH_SECRET` 은 이 명령과 서버 코드에서 빠졌다(§4-3).

**`KAKAO_ADMIN_KEY`(소셜 로그인 전환)** — 카카오 앱의 어드민 키. 탈퇴할 때 카카오 연결 끊기(`app/account/social_unlink.py`)에 쓴다.
비어 있으면 그 단계만 건너뛴다(경고 없이, 서버 시작은 막지 않는다). Secret Manager 에 시크릿 `kakao-admin-key` 로 등록했다(2026-10-09).
위 `--set-secrets` 목록에 `KAKAO_ADMIN_KEY=kakao-admin-key:latest` 를 더해 쓴다. 값은 이 문서에 적지 않는다.

**`APPLE_PRIVATE_KEY`(애플 토큰 철회, App Store 5.1.1(v))** — 탈퇴할 때 애플 토큰 철회(`app/account/social_unlink.py`)에 쓴다. Sign in with Apple 키(`.p8`)의 PEM 본문을 Secret Manager 에 시크릿 `apple-sign-in-private-key` 로 등록하고(`gcloud secrets create apple-sign-in-private-key --data-file=AuthKey_<키 ID>.p8`, PEM 이라 줄바꿈이 남아도 · `tr -d '\r\n'` 로 지워도 읽힌다), 위 `--set-secrets` 목록에 `APPLE_PRIVATE_KEY=apple-sign-in-private-key:latest` 를 더한다. 같이 쓰는 `APPLE_TEAM_ID`(팀 ID) · `APPLE_KEY_ID`(키 ID)는 비밀이 아니라 `--set-env-vars` 에 `APPLE_TEAM_ID=<팀 ID>,APPLE_KEY_ID=<키 ID>` 로 더한다.
셋 중 하나라도 비면 그 단계만 건너뛴다(경고 없이, 서버 시작은 막지 않는다). 앱이 탈퇴 본문에 `apple_authorization_code` 를 실어 보낸 애플 사용자만 철회한다 — 코드를 애플 `/auth/token` 으로 refresh_token 과 바꾼 뒤 `/auth/revoke` 로 바로 철회하고, 토큰은 저장하지 않는다. client_id 는 번들 ID(`io.github.juunn.campusmate`)다. 2026-10-13 기준 시크릿 등록 전이라 위 명령에는 아직 없다. 값은 이 문서에 적지 않는다.

**2026-10-14 정정 — 위 전체 명령은 지금 서비스 설정과 같지 않다(그대로 다시 돌리지 않는다).** 위 명령에는 `APPLE_TEAM_ID` · `APPLE_KEY_ID`(env)와 `APPLE_PRIVATE_KEY=apple-sign-in-private-key:latest`(시크릿)가 빠져 있다. `--set-env-vars` · `--set-secrets` 는 **목록 전체를 갈아끼우므로**, 서비스에 APPLE_* 가 들어 있는 상태에서 위 명령을 그대로 돌리면 APPLE_* 가 지워져 애플 토큰 철회가 조용히 건너뛰어진다(셋 중 하나라도 비면 건너뛴다). `settings.py` 가 읽는 값은 지금 **env 9개 · 시크릿 10개**다(위 2026-10-09 대조 뒤 `APPLE_TEAM_ID` · `APPLE_KEY_ID` · `APPLE_PRIVATE_KEY` 가 더해졌다). 위 명령을 다시 써야 하면 두 목록에 APPLE_* 를 더한 뒤 쓴다 — 시크릿 `apple-sign-in-private-key` 가 Secret Manager 에 없으면 그 명령은 실패한다. **지금 운영 서비스에 APPLE_* 가 실제로 들어 있는지는 이 문서 담당이 확인하지 못했다**(클라우드 미조회).
**2026-10-14 저녁 개정(애플 인앱결제 서버 PR #519, 종전 "env 9개 · 시크릿 10개")** — `settings.py` 가 읽는 값은 **env 11개 · 시크릿 11개**다. 아이폰 하트 구매용 `APPLE_IAP_KEY_ID` · `APPLE_IAP_ISSUER_ID`(env)와 `APPLE_IAP_PRIVATE_KEY=apple-iap-private-key:latest`(시크릿)가 더해졌다. 셋 다 비어도 서버는 뜬다. 넣는 법은 §4-10.
**2026-10-17 개정(서버 PR #565, 2026-10-17 배포 — 리비전 `00083-pwx`) — `settings.py` 가 읽는 값은 env 13개 · 시크릿 11개다**(종전 env 11개). 홈 리뷰 띠용 `STORE_RATING` · `STORE_RATING_COUNT`(글자로 받고 기본 `"0"`, 비어도 서버는 뜬다)가 더해졌다. 운영 서비스도 **24개(그중 시크릿 11)** 로 이 목록과 같다(대장 전달 값). 넣는 법 · 검증은 §4-13.
**2026-10-19 개정(관리자 웹 `ADMIN_*` 두 env 와 졸업생 스위치 — 대장이 조회로 확인한 값) — 운영 서비스는 현재 env 27개(그중 시크릿 11)다.** 2026-10-18 밤 리비전 `00086-7zf` 에서 관리자 웹용 **`ADMIN_ALLOWED_ORIGINS`**(CORS 허용 주소) · **`ADMIN_BASE_URL`**(디스코드 인증샷 알림에 싣는 검수 링크) 두 env 가 더해져 24 → 26 이 됐고, `00087-9qj` 도 26 그대로였다. **졸업생 인증 스위치 `GRADUATE_VERIFICATION_ENABLED` 는 코드 기본값이 꺼짐(`false`)이고, 운영 서비스에는 리비전 `00088-gh5` 에서 `true` 로 켰다(10-19, 사용자 승인) — 그래서 env 가 27개다**(`00089-fpm` 도 27). `settings.py` 가 아니라 `app/graduate_verification/settings.py` 의 `GraduateSettings` 가 요청마다 읽는다. 값과 뜻은 §4-14.
**2026-10-14 밤 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다) — 위 "운영 서비스에 APPLE_* 가 실제로 들어 있는지는 확인하지 못했다" 를 고친다.** 운영 리비전 **`campus-mate-backend-00075-gbw`** 에 `settings.py` 가 읽는 **env 11개 · 시크릿 11개가 모두 들어 있다** — 애플 키(Sign in with Apple 토큰 철회용 `APPLE_TEAM_ID` · `APPLE_KEY_ID` · `APPLE_PRIVATE_KEY`, 아이폰 하트 구매용 `APPLE_IAP_KEY_ID` · `APPLE_IAP_ISSUER_ID` · `APPLE_IAP_PRIVATE_KEY`) 연결 완료. 그래서 위 `--set-*` 전체 명령은 여전히 그대로 다시 돌리지 않는다(APPLE_* 가 지워진다) — 배포는 아래 "현행 배포 방식"으로 한다.

**현행 배포 방식(2026-10-13 ~ 14 배포 기준, 대장 전달 값)** — 설정을 바꾸지 않는 코드 배포는 env · 시크릿 목록을 넘기지 않는다. 그러면 새 리비전이 **직전 리비전의 env · 시크릿을 그대로 이어받는다**:

```bash
cd backend
gcloud run deploy campus-mate-backend --source . --project=<PROJECT_ID> --region=asia-northeast3 --allow-unauthenticated --quiet
```

새 env · 시크릿이 생길 때만 `--update-env-vars` · `--update-secrets`(목록에 **더하기**)를 쓴다 — `--set-*`(갈아끼우기)는 위 이유로 쓰지 않는다. 배포 뒤 리비전 이름 · 되돌림 하한은 §5.

**`IDENTITY_HMAC_KEY`·`OPENAI_API_KEY`·`PHONE_ENCRYPTION_KEY` 3개가 이 명령에서 빠져 있었다(PR #85 리뷰에서 잡음, §0 에는 시크릿 등록만 돼 있고 배포 명령에 연결이 안 됐던 것). `settings.py` 가 필수(`min_length=1` 등)로 요구하므로 빠지면 그 자리에서 기동이 실패한다.** → **2026-09-29 확인: 위 명령에 셋 다 들어 있다**(조각 6 배포 때 반영, 시크릿 이름 `identity-hmac-key` · `open-api-key` · `phone-number-encryption-key`). 조각 6 에서 `DISCORD_REPORT_WEBHOOK_URL`(`discord-report-webhook-url`, 신고 전용 채널 — 비어 있으면 신고 알림만 건너뛰고 경고 로그)이 더해졌다. `settings.py` 가 읽는 env 7개 · 시크릿 9개는 위 명령으로 전부다(2026-10-09 `settings.py` 와 다시 대조. 종전 2026-09-29 대조 뒤 더해진 `KAKAO_ADMIN_KEY` 와 `VERIFICATION_HOOK_SECRET`(`verification-hook-secret`, 학생증 검토 결과 훅의 공유 비밀 — 비어 있으면 `/hooks/verification-reviewed` 가 모든 요청을 막는다)이 명령에서 빠져 있었다). **2026-10-11 부터 `PHONE_ENCRYPTION_KEY` 는 실명 · 카카오톡 아이디 암호화에도 쓴다**(같은 키, §4-4 · `docs/SUPABASE.md` §8) — 이 키를 바꾸면 전화번호 · 실명 · 카톡 암호문을 모두 다시 암호화해야 한다

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
- **2026-10-12 갱신 — 같은 매시 배치가 하는 일이 셋 더 붙었다**(새 job · env · 시크릿 없음, 응답도 칸만 늘었다).
  지금 응답은 `{"reminded", "closed", "passed", "deferred_sent", "notifications_purged", "photos_deleted", "pending_expired"}` 모양이다.
  - `deferred_sent` — 밤에 보류한 알림을 아침에 묶어 보낸 수. `notifications_purged` — 90일 지난 알림함 줄을 지운 수.
  - **학생증 사진 정리(사용자 결정 2026-10-11, PR #463, 서버 revision `00058` 이후 — 대장 전달 값)** — `app/student_verification/retention.py`.
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

# 카드 배치는 하루 한 장이라 손으로 한 번 더 돌려도 안전하다(issuing.py). 2026-10-29 부터는 DB 유일 인덱스도 막는다(§4-17).
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

**실명 · 카카오톡 아이디 암호화 백필(2026-10-11, PR #461 · #464 · #467) — 일회용, 끝났다(2026-10-12).** 옛 평문 `profile_private.real_name` · `kakao_id` 를
암호문 열 `real_name_enc` · `kakao_id_enc` 로 옮긴다. 전화번호와 같은 `pgp_sym_encrypt` 에 **같은 키**(`PHONE_ENCRYPTION_KEY`)를 쓴다.
DB 함수 · 규칙은 `docs/SUPABASE.md` §8. **2026-10-12 M2 로 평문 열과 백필 함수가 운영에서 지워졌다 — 아래 백필은 다시 돌릴 수 없고(부를 함수가 없다)
기록으로만 남긴다.** 스크립트 `backend/scripts/backfill_encrypt_profile_private.py` 와 그 시험은 이제 죽은 코드라 지울 대상이다(코드 담당 몫).

- **실제 적용 순서(2026-10-12 끝)** — M1 → 이중 쓰기 서버(`00059`) → 백필(불일치 0, 새 서버 배포 직전에 한 번 더 돌려 다시 확인) →
  읽기 전환 서버(`00063`, PR #474 — 평문 쓰기 · 평문 폴백 읽기를 뺐다) → M2(`20261012010000_drop_plaintext_real_name_and_kakao_id`).
  아래 "순서" 의 4번 "읽기 전환 — 이미 끝났다" 는 2026-10-12 개정으로 바뀌었다 — 복호화 우선 · 평문 폴백은 읽기 전환이 아니었고,
  평문 열을 아예 안 쓰는 서버(`00063`)를 따로 배포해야 했다(종전 서술은 아래 그대로 둔다).
- **순서(2026-10-11 작성 — 기록)** — 이 순서대로, 앞 단계가 끝난 뒤에 다음으로 간다.
  1. 마이그레이션 M1 `20261011010000_encrypt_real_name_and_kakao_id` 적용(새 열 2개 + 함수 4개, 옛 열은 그대로).
  2. 이중 쓰기 서버 배포(PR #464, revision `00059`) — 실명 · 카톡을 옛 열과 새 열에 같이 쓰고, 읽을 때는 복호화 값을 먼저 쓰고 비면 평문으로 폴백한다.
  3. **그 뒤에** 백필 한 번(아래). 2 전에 돌리면 그 사이 가입한 행의 암호문이 비어 남는다.
  4. 읽기 전환 — 2 의 복호화 우선 · 평문 폴백으로 이미 끝났다(따로 배포할 것 없음).
  5. M2(옛 평문 열 · `backfill_profile_private_encryption` 함수 삭제, 별도 PR) — ~~**아직 안 했다.**~~ **2026-10-12 운영 적용(아래 "M2 실행 기록").** E2E 하네스가 평문 열을 직접 읽는 곳을 고친 뒤
     사용자 승인을 받고 한다. **M2 보다 서버가 먼저다** — 지금 서버는 평문 열에 계속 쓰고(`upsert_real_name` · `update_kakao_id`)
     복호화 값이 비면 평문 열을 select 한다(`core/postgrest.py` `_read_private`, `profile_onboarding/repository.py`). 열이 사라지면
     이 요청들이 실패하므로, 평문 쓰기 · 폴백 읽기를 뺀 서버를 먼저 배포하고 M2 를 적용한다.
- **어떻게** — 위 백필과 같은 자리(backend 폴더)에서. 실제로 쓰는 값은 `SUPABASE_URL` · `SUPABASE_SERVICE_ROLE_KEY` · `PHONE_ENCRYPTION_KEY`
  셋이다. `settings.py` 가 부팅할 때 `AUTH_HOOK_SIGNING_SECRET` · `IDENTITY_HMAC_KEY` · `DISCORD_WEBHOOK_URL` · `GOOGLE_CLOUD_PROJECT` · `OPENAI_API_KEY`
  도 요구하므로 이 다섯은 아무 더미 값이면 된다. 진짜 값은 Secret Manager 에서 env 로 넣고 여기 적지 않는다.

```bash
# 기록용 — 2026-10-12 M2 뒤에는 부를 DB 함수가 없어 실패한다. 다시 돌리지 않는다.
cd backend
.venv/Scripts/python.exe -m scripts.backfill_encrypt_profile_private
# 출력은 건수 한 줄뿐이다(실명 · 카톡 · 키 · profile_id 를 찍지 않는다):
#   requested=<함수를 부른 행> real_name_plain=<평문 있는 행> real_name_enc=<암호문 있는 행> real_name_mismatch=<복호화 ≠ 평문>
#   kakao_id_plain=… kakao_id_enc=… kakao_id_mismatch=…
# mismatch 가 하나라도 0 이 아니면 종료 코드 1 이다 — M2 전에 사람이 본다.
```

- **다시 돌려도 안전하다**: 암호문이 빈 행만 고르고, DB 함수도 암호문이 이미 있는 열은 덮지 않는다(이중 쓰기로 먼저 들어간 새 값을 지킨다).
  빈 문자열 평문은 암호문 null 과 같다.
- **운영 기록(2026-10-12, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다)**: 1 · 2 · 3 끝. 백필 대상 2행, mismatch 0. M2 대기.
  → **2026-10-12 개정(같은 날 늦게)**: 4 · 5 도 끝났다. 읽기 전환 서버 `00063` 배포 뒤 M2 를 운영에 적용했다(아래 "M2 실행 기록").
- **키 로그 노출 점검(M1 머리말 "적용 뒤 확인할 것")**: `pg_stat_statements`(대시보드 Query Performance) · Postgres 로그에서
  `pgp_sym_encrypt` · `pgp_sym_decrypt` 호출의 키 인자가 `$1` 같은 **자리표시자로만** 보이는지 본다(전화번호 함수 `20260920043638` 과 같은 위험).
  PostgREST 는 RPC 인자를 JSON 바디로 받아 바인딩하므로 보통 문제없지만, `log_statement` · `auto_explain` 같은 설정이 인자 값을 남기는지 같이 본다.
  서버는 키를 JSON 바디로만 넘기고 URL 에는 넣지 않는다(`app/profile_onboarding/encryption.py`). ~~점검 결과는 아직 이 문서에 기록이 없다.~~
  **점검 결과(2026-10-12, 대장 전달 값)**: `pg_stat_statements` 에 남은 RPC 문장은 본문이 파라미터(자리표시자)라 키가 평문으로 남지 않았다.
  운영 `log_statement` 는 `ddl` 이라 일반 문장(RPC 호출)의 인자 값은 로그에 남지 않는다.

**M2 실행 기록(2026-10-12, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다)**

- **무엇을 지웠나**: `profile_private` 의 평문 열 `real_name` · `kakao_id` 와 임시 함수 `backfill_profile_private_encryption`. 남은 함수는
  `set_real_name` · `set_kakao_id` · `decrypt_profile_private` 셋(`service_role` 전용)이고, 실명 · 카톡 아이디는 암호문(`real_name_enc` · `kakao_id_enc`)에만 있다.
  `authenticated` 의 컬럼 grant `select (real_name)` 도 열과 함께 사라졌다.
- **파일과 운영 기록 버전**: 파일 `20261012010000_drop_plaintext_real_name_and_kakao_id.sql`, 운영 기록 버전 `20261012070722` — 파일 이름과
  원격 버전이 다른 것은 정상이다(`docs/SUPABASE.md` §4, MCP `apply_migration` 이 적용 시각으로 찍는다). **운영에는 적용됐지만 파일은 아직 main 에 없다 —
  DB PR #476(`feat/profile-private-encryption-m2-db`, draft) merge 대기.** 그래서 지금 저장소 `supabase/migrations/` 는 67개, 운영은 68개다.
- **안전장치**: 파일 안의 검사("평문은 있는데 암호문이 빈 행" 을 세서 1개라도 있으면 아무것도 안 지우고 멈춤)를 통과했다.
- **뒷정리**: `drop column` 은 기존 행 안의 평문을 디스크에서 바로 지우지 않아 적용 뒤 `vacuum full public.profile_private;` 를 따로 돌렸다.
- **되돌릴 수 없다.** 롤백 마이그레이션이 없고, **사용자가 되살릴 수 있는 백업도 없다**(Supabase 백업 · PITR 은 유료 — 출시 후 결정).
  반대로 Supabase 쪽 내부 백업 · WAL 에는 보관 기간 동안 평문이 남아 있을 수 있다(M2 머리말). 지운 평문을 되살릴 길은 없다.
- **암호화 키 보관 주의**: 이제 실명 · 카톡 아이디 · 전화번호를 읽는 길은 `phone-number-encryption-key`(Secret Manager) 하나뿐이다.
  이 키를 잃거나 다른 값으로 바꾸면 세 값이 전부 못 읽는 암호문이 된다 — 키 버전을 지우거나 덮지 않고, 바꿀 때는 옛 키로 복호화 → 새 키로 다시 암호화를 먼저 한다.
- **서버 롤백 주의**: M2 뒤에는 **평문 열에 쓰거나 읽는 서버로 되돌리면 안 된다** — 학생증 제출(실명 저장) · 카톡 아이디 저장 · 계정 조회가
  42703(열 없음)으로 실패한다. main 에서 평문 쓰기 · 폴백 읽기를 뺀 것은 PR #474(`00063`)다. 대장 기록은 "`00062` 까지만 안전(`00061` 이하는 실패)" 인데,
  `00062` 의 코드인 PR #473 merge(`5accfae0`) 시점의 서버는 아직 평문 열에 쓴다(`student_verification/repository.py` `upsert_real_name` ·
  `profile_onboarding/repository.py` `update_kakao_id`). **확인 전까지는 `00063` 아래로 되돌리지 않는다**(확인 필요 — 대장 보고).
- **배포 순서 교훈**: ① 열을 지우기 전에 그 열을 쓰는 서버를 먼저 없앤다 — "복호화 우선 · 평문 폴백" 서버도 평문 열을 쓰므로 읽기 전환이 아니다.
  ② 백필 검사는 새 서버 배포 **직전**에 다시 돌리고, 새 서버 배포 **뒤**에는 돌리지 않는다(새 서버는 평문 열을 고치지 않아 사용자가 바꾼 값이
  거짓 불일치로 보이고, 빈 값으로 지운 카톡 아이디를 남은 평문으로 되살린다 — M2 머리말 3번). ③ 되돌릴 수 없는 마이그레이션은 백업이 없다는 사실을
  알고 받아들인 뒤에 적용한다.

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
2. Supabase 대시보드 → Table editor → `heart_task_submissions` 에서 `id` 로 줄을 찾고, `storage_path` 로 Storage → `heart-task-proofs` 의 파일을 연다. **2026-10-19 개정(PR #613, §4-14): 칸 이름이 `storage_paths`(경로 1~3개 배열)로 바뀌었다 — 대시보드로 열 때는 배열의 경로를 하나씩 연다. 운영 검수의 기본 길은 이제 관리자 웹의 인증샷 검수(사진 여러 장을 넘겨 본다)다.**
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

**2026-10-12 추가(대장 전달 값)**: 하트 수는 그대로다 — 에브리타임 50 · 월 1회, 단톡방 25 · 월 3회, 커뮤니티 투표 10 · 하루 첫 투표 1번만 · 한 주 최대 30.
**2026-10-16 사용자 확정으로 개정(PR #570 — DB 2026-10-16 운영 적용 · 서버 2026-10-17 배포, §4-13)**: 에브리타임 **40** · 월 1회, 단톡방 25 · 월 3회(인증 캡션 "3명 이상"), 커뮤니티 투표 **5** · 하루 첫 투표 1번만 · 한 주 최대 **15**, 친구 코드 양쪽 50 그대로. 승인 절차(위 3번)는 그대로 — 트리거는 제출 행에 적힌 `reward_hearts` 를 주므로 서버 배포(2026-10-17) 전에 낸 에브리타임 제출은 50 으로 승인된다.
승인은 위 3번처럼 `heart_task_submissions.status` 를 `approved` 로 저장하면 트리거가 `grant_hearts` 를 한 번 부른다. **운영에서 이 지급 트리거(`free_task`)는
아직 한 번도 돌아 본 적이 없다** — 첫 실제 제출을 승인할 때 원장(`heart_transactions` 의 `free_task` 한 줄)과 잔액이 늘었는지 꼭 본다.
결과 푸시는 없다(사용자는 18a 상태와 잔액으로 안다).

## 4-6. 보안 점검 반영 (2026-10-12)

점검 원문(읽기 전용 점검, 2026-10-12)은 사용자 폴더 `CampusMate_문서/출시준비/보안점검_10-12.md` 에 있다. 새 env · 시크릿 · job 은 없다.
아래는 main 에 들어간 조치(PR #469 · #472 · #473 — 운영 리비전 `00060` · `00061` · `00062`)와 운영 규칙이다.

- **API 문서 주소를 닫았다**: `/docs` · `/redoc` · `/openapi.json` 은 404 다(`app/main.py` `docs_url=None, redoc_url=None, openapi_url=None`).
  경로 목록이 필요하면 코드에서 `app.openapi()` 를 부른다 — E2E 하네스(E-HEART-49 · 51)도 운영 주소가 아니라 이 방식으로 읽는다.
- **빈 `PHONE_ENCRYPTION_KEY` 로는 서버가 뜨지 않는다**(`settings.py` `min_length=1`). 빈 키로 배포되면 전화번호 · 실명 · 카톡 아이디가 빈 키로 암호화되기 때문이다.
- **로그 · 알림 규칙** — 실명 · OCR 글자 · **사진 경로** · **디스코드 웹훅 주소**를 로그와 알림에 남기지 않는다. 디스코드 알림에는 id 만 싣는다.
  웹훅 실패 로그는 `raise_for_status` 대신 상태 코드만 찍는다(예외 문구에 웹훅 주소가 통째로 들어간다). 라우터가 잡지 않은 저장소 호출 실패(`httpx.HTTPStatusError`)는
  전역 처리기가 메서드 · 상태 코드 · 예외 이름만 남기고 500 을 준다(예외 문구에 Supabase 호스트 · 사진 경로가 든다, `app/main.py` `upstream_call_failed`).
  암호문 복호화 실패는 `profile_id` · 상태 코드만 남긴다(`core/postgrest.py` `_read_private`).
- **자유 글 서버 상한 1000자** — 자기소개 · 이상형 글(`profile_onboarding/schemas.py` `FREE_TEXT_MAX_LENGTH`). 앱 입력칸에는 아직 상한 표시가 없다.
  **2026-10-14 개정(PR #526, 마이그레이션 · env 없음)**: 온보딩 `/bio` · `/ideal-note` 와 `PATCH /me/profile` 의 자기소개가 같은 `FreeText` 타입을 쓴다 — `\r\n` · `\r` 을 `\n` 으로 줄인 뒤 1000자를 세고, 줄 바꿈이 **40줄**(`FREE_TEXT_MAX_LINES = 1000 // 25`)을 넘으면 검증 오류로 거절한다(옛 앱 · 직접 호출이 줄 바꿈만 넣어 카드를 늘이는 것을 막는다). 앱은 300자 · 6~8줄로 조용히 막는다(DESIGN.md §8.5) — 서버 1000 은 옛 긴 글을 고쳐 저장할 수 있게 그대로 둔다. 서버를 배포하기 전에도 앱은 안전하다.
- **학생증 업로드 뒤 시도 행을 쓰기 전에 실패하면 방금 올린 사진을 지운다**(PR #472) — 고아 사진이 버킷에 남지 않게.
- **유료 카드 결제 전 응답에 원본 아바타 주소 · 상대 id 를 싣지 않는다**(PR #473, 리비전 `00062`) — 서버가 8×10 JPEG 미리보기를 만들어 준다(설계 문서 §6.8).
  Pillow(`pillow>=12.3`)가 서버 의존성에 들어갔다(이미지는 그대로 `--source .` 빌드).
- **앱**: 안드로이드 `allowBackup=false`(앱 데이터가 기기 백업으로 빠져나가지 않게, `AndroidManifest.xml`).
- **GitHub 저장소**: 비밀 스캔 · 푸시 차단(push protection) · Dependabot 을 켰다.
- **아직 안 고친 것(출시 전)**: ① 가입 훅이 "재가입이 제한된 메일" 이라고 알려 주는 메시지 — E2E 하네스와 함께 정리 예정
  ② 학교 메일 로그인 방식(`amr`) 검사 — Supabase 가 실제로 주는 값을 먼저 확인해야 한다 ③ 운영 "테스트대학" 의 `gmail.com` · `naver.com` 도메인 — 출시 직전 삭제(사용자 승인 필요, 지우면 테스트 로그인이 막힌다).

## 4-7. 보낸 신청 · 친구 코드 지인 리뷰 서버 (2026-10-13)

두 기능 모두 **DB 마이그레이션 · 새 env · 새 시크릿 · 새 Scheduler job 이 없다**(코드만). 리비전은 PR 본문과 대장 전달 값이다(이 문서 담당이 클라우드를 조회하지 않았다): 보낸 신청 `GET /cards/sent` = PR #483, 운영 리비전 `00064` / 친구 코드 지인 리뷰 = PR #486, 운영 리비전 `campus-mate-backend-00065-b7n`. 앱 PR #485 · #487 은 각각 그 서버가 나간 뒤에 merge 했다. 규칙은 설계 문서 §2.2 · §2.8 개정, 화면은 DESIGN.md §8.6 · §9 20f.

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
- 두 PR 은 DB 를 건드리지 않아 리비전만 되돌리면 된다. 다만 `00064` 아래로 가면 앱의 보낸 신청 읽기가, `00065` 아래로 가면 20f 가 서버 오류를 만난다(추정 — 앱은 오류 줄 · 실패 문구로 처리한다). 이 기능이 들어간 앱 빌드가 나간 뒤에는 서버를 이 리비전 아래로 되돌리지 않는다

## 4-8. 채팅 읽음 '1' · 실시간 이벤트 · 푸시 로그 (2026-10-13 ~ 14)

설계안 원문은 사용자 폴더 `CampusMate_문서/기획·설계/채팅_실시간_전환_설계안_10-13.md`(안 A — 서버가 쏘고 앱은 사용자 채널 하나를 듣는다). **순서는 서버 → 운영 DB 정책 → 앱** 이었다(서버만 먼저 나가도 듣는 앱이 없어 무해하고, 정책 전에 나간 앱은 입장이 거부돼 폴링으로만 돈다). 리비전은 대장 전달 값이다(§5). 새 env · 시크릿 · job 은 없다.

### 채팅 API — `partner_last_read_at` (PR #501, 리비전 `00069`)

`GET /chat/matches/{match_id}`(방 머리말)와 `GET /chat/matches/{match_id}/messages`(메시지 목록) 응답에 **`partner_last_read_at`**(상대의 `match_participants.last_read_at`, ISO 시각)을 싣는다. 상대가 한 번도 안 읽었으면 `null`, `limit` 과 무관하게 늘 실린다 — 앱은 `limit=1` 로 가볍게 불러 읽음 변화를 본다. 나간 방은 종전대로 404, 상대가 나간 방은 그대로 읽히고 값도 실린다. 옛 앱은 모르는 키를 무시한다. 읽음 찍기는 종전 `PATCH /chat/matches/{id}/read`(앱이 방에 들어올 때 · 나갈 때 · 보는 동안 받은 줄 3초 묶음, `docs/ERD.md` §4). 푸시 30초 규칙(`IN_ROOM_WINDOW`)은 그대로다.

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
- **APNs 인증 키**: 아이폰(TestFlight · 출시 빌드)은 애플 운영 APNs 서버를 쓴다. 옛 키 `JT647G2N3A` 는 **샌드박스 전용**이라 운영에서 FCM 401 `Invalid APNs credential` 이 났다. **2026-10-13 새 키 `R52HCC98ZY`(Sandbox & Production 범위)를 Firebase 클라우드 메시징에 올려 해결했다**(실기기 도착 · 로그 `FCM 전송 성공 … platform=ios` 확인). 키 ID 는 비밀이 아니지만 **키 파일(.p8) 내용은 이 문서 · 채팅 · 로그 어디에도 적지 않는다.** 옛 키를 애플에서 지울지는 사용자 결정 전이다(안 지움). 서버 설정은 바뀌지 않았다(FCM 이 APNs 로 보낸다)
- **같은 종류 알림 한 장으로 합치기(서버 PR #546, 리비전 `00078-nxv`, 2026-10-16 배포 — 대장 전달 값)**: `kind` 가 `_COLLAPSED_KINDS`(지금은 **`verification_result` 하나**, `app/cards/push.py`)면 FCM v1 메시지에 안드로이드 **`android.notification.tag = <kind>`** 와 iOS **`apns.headers.apns-collapse-id = <kind>`** 를 붙인다 — 새 학생 인증 결과 알림이 앞 알림을 덮어 알림 줄에 한 장만 남는다(배경: 발송은 1번인데 앱이 읽은 뒤 지우지 않아 "학생 인증이 끝났어요" 가 계속 보였다). 다른 kind 의 payload 는 그대로다. **앱 짝(같은 PR, vc6 부터)**: 학생 인증 관문을 지나는 순간(3c 또는 홈) 한 번만 이 tag 로 결과 알림을 지운다(`frontend/lib/core/push/foreground_push.dart` `gateChanged` — 앱이 띄운 알림은 id, FCM SDK 가 띄운 알림은 tag). **kind 이름을 바꾸면 앱도 같이 바꾼다.** 한계: iOS 는 합치기만 하고 지우지는 못한다(로컬 알림 창구가 안드로이드 설정만 준비됨). 배포 순서는 서버 → 앱(vc6). 실기기 확인(통과 푸시를 받은 뒤 3c 로 들어가면 알림이 사라지는지 — 앱 앞 · 뒤 · 꺼짐)은 이 문서 정리 시점에 받지 못했다

## 4-9. 인앱결제 — 구글 플레이 하트 구매 서버 (2026-10-13, 서버 PR #499 · DB PR #498)

**배포 순서는 DB 적용 → 서버 PR merge → 서버 배포 → 앱**이었다(서버가 먼저 나가면 없는 DB 함수를 부른다). 새 env · 시크릿은 없다 — 구글 플레이 개발자 API(`androidpublisher`)는 **Cloud Run 서비스 계정(ADC)** 으로 부른다(FCM 과 같은 방식, 새 패키지 없음). 그래서 **플레이 콘솔 "사용자 및 권한" 에 이 서비스 계정을 초대**해야 구매 조회 · 소비가 된다(앱 PR #506 기준 미확인 — 플레이 콘솔 상품 5개 등록 · 라이선스 테스터와 함께 샌드박스 시험 전 준비). 표 · 함수는 `docs/ERD.md` §6, 화면은 DESIGN.md §8.10. 경로 이름에 `refund` · `purchase` · `buy` 를 쓰지 않는다(E2E 하네스 E-HEART-49 · 51 이 그런 이름의 경로를 유료 카드 하나만 허용한다).

| 경로 | 뜻 |
| --- | --- |
| `GET /billing/status` | 학생증 통과 가입자. `{account_token, first_purchase_bonus}` — `account_token` 은 결제 창의 `applicationUserName`(구글 `obfuscatedExternalAccountId`)에 싣는 계정 표시(sha256 방식), `first_purchase_bonus` 는 구매 이력이 없으면 `{hearts: 50, min_product_hearts: 100}`, 있으면 null(화면 배지용 — 실제 판정은 지급 때 DB 함수가 다시 한다) |
| `POST /billing/google/verify` | 본문 `{product_id, purchase_token}`(`heart_50` ~ `heart_800`, 토큰은 영문 · 숫자 · `. _ -` 만 1000자 이하). **200** `{result: granted \| already_granted, hearts, bonus_hearts, heart_balance}` · **202** `{result: pending}`(결제 대기 — 행을 만들지 않는다) · **409** `purchase_other_account`(다른 계정 표시 — 소비하지 않는다, 3일 안에 안 오면 구글이 환불) · **409** `purchase_token_used`(다른 사람이 이미 받은 영수증) · **422** `purchase_invalid`(결제됨이 아님 · 수량 1 아님 · 상품 불일치) · **503** `billing_unavailable`(구글 조회 실패 — 앱은 지연으로 보고 나중에 다시 보낸다). 지급 뒤 아직 소비 전이면 **서버가 소비(consume)** 한다(실패해도 다음 재전송 때 다시) — 앱은 소비하지 않는다 |
| `POST /batch/billing-voided` | 배치 전용(카드 · 채팅 · 정리 배치와 같은 OIDC 문). 구글 Voided Purchases 를 **최근 7일** 조회해 `refund_store_purchase` 로 회수하고(멱등이라 겹쳐도 된다), 5년 지난 구매 행을 지운다. 응답 `{voided, …건수, purged}`. 구글이 답하지 못하면 503 이고 아무것도 바꾸지 않는다. 회수가 모자라면(이미 쓴 하트) 경고 로그만 — 번호와 숫자만 남긴다 |

- **로그**: 구매 토큰 · 주문 번호는 남기지 않는다(`profile_id` · 상품 · 결과 · 상태 코드만). httpx INFO 가 주소(토큰 포함)를 찍지 않게 못박았다(`app/billing/play.py`)
- **알려진 한계**: verify 요청 빈도 제한 없음(출시 전 백로그) · 구글 쪽 동작은 샌드박스 시험으로 확인 전 · 계정 표시 토큰은 sha256 방식 유지
- **`/batch/billing-voided` 를 부르는 Cloud Scheduler job 은 만들어져 돈다(2026-10-20 대장 전달 값: 매시 30분 — §4-15 "서버 스케줄"; 종전 "만들었는지 확인하지 못했다" 를 고친다).** 새로 만들 일이 생기면 §4-3 의 OIDC job 만들기 명령을 경로만 바꿔 쓴다

## 4-10. 인앱결제 — 아이폰(애플) 하트 구매 서버 (2026-10-14, 서버 PR #519 · 후속 PR #521, 앱 PR #520)

계획서는 사용자 폴더 `CampusMate_문서/출시준비/애플_인앱결제_구현계획_초안.md`(끝의 "구현 편차 기록"). 사용자 결정(10-14): 첫 출시에 포함 · `cryptography` 추가 승인 · 환불 알림은 서명 체인 직접 검증 · 가격은 안드로이드와 같게(화면은 스토어 가격 우선).
**DB 마이그레이션은 없다** — §4-9 의 `purchases` 표와 두 함수를 `store = 'app_store'` 로 부른다(`docs/ERD.md` §6). **새 env 2개 · 새 시크릿 1개 · 새 서버 의존성 1개**(`cryptography>=50`, `pyproject.toml`). Scheduler job 은 없다 — 환불은 애플이 알림으로 보내 준다(구글은 우리가 매시 조회, §4-9).
코드는 `app/billing/apple.py`(애플 API 조회 · 서명 검증) · `app/billing/apple_router.py`(두 경로). 경로 이름 규칙은 §4-9 와 같다(`refund` · `purchase` · `buy` 를 쓰지 않는다). 하네스 `e2e/area3_safe.py` `VERIFIED_ROUTES` 에 `POST /billing/apple/verify` 한 줄이 더해졌다(알림은 로그인 관문이 없어 목록 대상이 아니다).

**배포 순서는 서버 → TestFlight(앱)** 다. 서버만 먼저 나가는 것은 무해하다(안드로이드 길은 그대로). 앱이 먼저 나가면 `/billing/status` 에 `apple_account_token` 이 없어 **iOS 는 결제 불가 배너만 보인다**(구글용 계정 표시로 대신 사지 않는다). **이 문서 담당은 이 서버의 운영 배포 · 리비전 · 키 등록 여부를 받지 못했다**(클라우드 미조회). **2026-10-14 밤 개정 — 배포됐다(대장 전달 값)**: 운영 리비전 `campus-mate-backend-00075-gbw`, 앱 내 구입 키 env 2개 · 시크릿 1개 연결 완료(§2 — env 11 · 시크릿 11). App Store Connect 알림 주소 설정과 TestFlight 샌드박스 시험 결과는 아직 받지 못했다.

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
- **2026-10-15 개정(서버 PR #532 — 운영 401 → 샌드박스 한 번 더).** 위 줄의 "401 이면 바로 503" 은 종전 동작이다. 개발자 멤버십이 비활성인 동안 **같은 키로 운영 주소만 401 을 주고 샌드박스는 404 로 인증을 넘은 것**이 실측됐다(2026-10-14). 그래서 지금은 **운영이 401 이면 샌드박스에 한 번 더 묻는다**(WARNING 로그 `애플 거래 조회 production:401 — 샌드박스에 한 번 더 묻는다`). 샌드박스에 거래가 있으면 종전처럼 `is_test = true` 로 지급한다. **운영 401 뒤 샌드박스에도 없으면(404) 운영 거래인지 알 수 없어 422 가 아니라 503**(앱이 다시 보낸다). 운영 403 · 429 · 5xx · 시간 초과는 샌드박스로 넘기지 않는다(일시 장애를 샌드박스 거래로 오인하지 않게). 서명 체인 · 계정 대조 · 환불 검사는 그대로다
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
| `POST /billing/apple/verify` | 학생증 통과 가입자. 본문 **`{product_id, transaction_id}`**(상품은 §4-9 의 5종, 거래 번호는 숫자 1 ~ 64자 — 그 밖은 애플에 묻기 전에 422). 앱이 준 값을 믿지 않고 서버가 App Store Server API `GET /inApps/v1/transactions/{거래 번호}` 를 **운영 주소 → (404 면) 샌드박스 주소** 순서로 묻는다(TestFlight · 심사 거래는 샌드박스 — **2026-10-15 개정: 운영 401 도 샌드박스로 넘어간다, 위 "키 · 설정" 의 PR #532 줄**). 받은 `signedTransactionInfo` 는 **코드에 내장한 Apple Root CA G3 까지 인증서 체인을 검증**한 뒤에만 믿는다. 확인 칸: `environment`(Production / Sandbox → `is_test`) · 거래 번호 · 번들 ID(`io.github.juunn.campusmate`) · 상품 · 소모품 · 직접 구매 · 수량 1. 지급은 `grant_store_purchase`(`store = app_store`), 200 응답 모양은 구글과 같다. **대기(202)는 없다**(애플 거래 조회에는 대기 상태가 없다). **애플은 소비(consume) 호출이 없다** — 서버가 지급하면 앱이 거래를 끝낸다(아래 표) |
| `POST /billing/apple/notifications` | **로그인 없는 공개 주소**(애플이 부른다). 본문 `{signedPayload}`(App Store Server Notifications **V2**). **서명 체인 검증만이 믿는 근거다.** 서명이 틀림 · 다른 앱(번들) · 알림과 거래의 `environment` 가 다름 → **400**(아무것도 바꾸지 않는다). 본문이 없으면 422. **`REFUND` · `REVOKE`** → `refund_store_purchase('app_store', …)` 로 회수하고 200 `{result: refunded \| already_refunded \| unknown}`(이미 회수했거나 우리가 지급한 적 없는 거래도 200 — 멱등). **`TEST` 와 그 밖 알림**은 로그만 남기고 200 `{result: ignored}`(소비 정보 요청 `CONSUMPTION_REQUEST` 도 답하지 않는다). **`REFUND_REVERSED`(환불 번복)는 하트를 되돌리지 않는다** — WARNING 로그만, 운영자가 App Store Connect 에서 확인한다(사용자 결정 A-6 미결). DB 실패는 500 이라 애플이 다시 보낸다 |

**App Store Connect 알림 주소** — 앱의 App Store Server Notifications 설정에 **운영(Production) 주소와 샌드박스(Sandbox) 주소를 둘 다** `https://<서비스 URL>/billing/apple/notifications` 로, 버전은 **Version 2** 로 넣는다. 서버는 주소 하나로 둘 다 받는다(샌드박스 거래는 `is_test = true` 행이다). 둘 중 하나를 비우면 그쪽 환불은 하트가 회수되지 않는다. 애플의 시험 알림(`TEST`)이 오면 로그 `애플 알림 type=TEST … — 할 일 없음` 과 200 이 남는다. **2026-10-20 대장 전달 값: 프로덕션 · 샌드박스 두 주소 모두 `/billing/apple/notifications` Version 2 로 등록됐다.** 설정 화면의 정확한 위치는 애플 쪽 UI 라 이 문서 담당이 직접 보지 않았다.

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

사용자 결정(10-15): 홈 레일(mosaic-rail)에 **모든 학교의 활성 가입자를 성별 섞어 흐린 아바타로** 보여 준다. 블러는 "중간", 후보가 모자라면 서버가 빈 목록을 주고 앱이 기본 그림 칸으로 대신한다. 본인 옵트아웃은 없고 개인정보 처리방침 한 줄과 05-12c 안내 한 줄로 알린다(**2026-10-17: 05-12c 폐기로 이 안내 줄은 가입 맨 끝 5b 리빌 설명 아래로 옮겼다**, 앱 PR #576 · DESIGN §9 5b). **DB 마이그레이션 · 새 env · 새 시크릿 · 새 job 은 없다**(코드만). 운영 리비전 **`00078-nxv`**(2026-10-16 배포, 대장 전달 값 — 무인증 호출이 401 인 것까지 확인). 화면은 `frontend/docs/DESIGN.md` §8.9 `mosaic-rail`.

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

사용자 폰 시험에서 지적된 가입 · 소개글 문제를 서버에서 고쳤다. **DB 마이그레이션 · 새 env · 새 시크릿 · 새 job 은 없다.** 운영 리비전 **`00078-nxv`**(2026-10-16 배포, 대장 전달 값). 앱 짝은 PR #543 이고, 옛 앱도 서버 422 를 일반 4xx 오류로 보여 줘서 **서버를 먼저 배포해도 안전했다**.

- **가입 전화번호 규칙(`POST /profile-onboarding/basic-info`)** — `app/profile_onboarding/phone_number.py` `to_signup_e164`. 숫자만 남겨 `+82` 를 국내 모양으로 되돌린 뒤(종전 `to_e164` 그대로) **010 + 8자리만** 받는다(옛 011 · 016~019 는 막는다 — 앱이 이미 11자리만 받았다). 뒤 8자리가 ① 전부 같은 숫자(A, 10개) ② 한 줄로 이어지는 순서(B — `0123456789` · `9876543210` 안에 통째로 든 8자리, 오름 3 · 내림 3 = **6개**) ③ 알려진 가짜 6개(C — `12341234` · `12341111` · `11112222` · `12121212` · `00001234` · `12340000`)면 거른다
  - 막힌 번호는 **아무것도 쓰지 않고** **422** `{"detail": "올바른 휴대폰 번호를 입력해 주세요", "code": "phone_number_invalid"}`(`core/errors.py` `PHONE_NUMBER_INVALID` · `CODE_PHONE_NUMBER_INVALID`). **종전 400 "전화번호를 다시 확인해 주세요"**
  - **연락처 차단 · 지인 대조는 종전 `to_e164` 그대로다** — 친구 번호가 가짜 모양이어도 지문은 등록해야 한다. 이미 가입한 사람의 번호는 건드리지 않는다
  - 규칙 근거는 사용자 폴더 `CampusMate_문서/출시준비/전화번호_인증_방법_가격.md` §3-1 · §3-2 A·B·C · §3-4(패턴 하나가 막는 번호 1,000개 이내만). **앱 `SignupPhoneNumber`(`frontend/lib/profile/model/signup_phone_number.dart`)와 같은 목록이어야 한다** — 한쪽만 고치지 않는다. 문자(SMS) 본인 인증은 사용자 결정 대기
- **성별(`BasicInfoRequest.gender`)** — `Literal["male", "female"]`(DB enum `gender` 와 같다). 그 밖의 문자열은 FastAPI 검증 오류 422 다(종전: 임의 문자열이 서버 검증을 지났다 — PR #544 배경)
- **유료 카드 이유 "MBTI가 잘 맞아요"** — 내 선호 MBTI 에 **한쪽만 고른 축이 하나도 없으면**(`{}` · 8개 전부 · 축마다 양쪽 같음 = 전부 상관없음) 계수가 1.0 이어도 이 이유를 붙이지 않는다(`matching/scoring.py` `mbti_prefers_a_side`, `cards/paid_offer.py` `_strengths`). 종전에는 8개를 전부 고르면 늘 붙었다. 점수 계산은 그대로다
- **자기소개 초안(`POST /profile-onboarding/bio-draft`)** — `app/profile_onboarding/bio_draft.py`. 프롬프트 원본은 사용자 폴더 `CampusMate_문서/출시준비/GPT_소개글_프롬프트.md` §5(대장 10-15 지시로 §7 전부 A 채택, 2~3문장)
  - 시스템 프롬프트: **한국어만**(MBTI 네 글자 · 관심사 이름의 원래 영문만 예외) · 1인칭 해요체 · MBTI 가 있으면 한 번 넣기(없으면 말하지 않기) · 성향 · 관심사 · 특징 중 3~4가지 · 2~3문장 안팎을 2~3문단으로(줄바꿈 한 번) · 120~220자 · 실명 · 학교 · 연락처 · **종교 · 흡연** · 외모 · 재산 금지
  - 사용자 프롬프트: `MBTI: <값 또는 "없음">` 을 **맨 앞 줄**로, 이어 성향 · 관심사 · 나의 특징. **종교 · 흡연은 재료에서 뺐다**(민감정보 — 이제 종교는 OpenAI 로 가지 않는다). 이상형 답변 · 닉네임 · 학교 · 학과 · 키 · 나이 · 전화번호는 종전처럼 넣지 않는다
  - 호출: `gpt-4o-mini` · `temperature=0.7` · `max_tokens=300`. 빈 줄은 줄바꿈 한 번으로 줄이고 앞뒤 공백을 자른다
  - **최대 2번 부른다**(`_ATTEMPTS = 2`): 허용된 영문 밖의 영어가 남거나 답이 비면 한 번 더 만든다. 두 번째에도 영어가 남으면 **마지막 결과를 쓴다**. 빈 답이면 앞의 초안을 지우지 않는다. **두 번 다 비면 502 이고 저장하지 않는다**(앱은 "직접 써 주세요" — 생성 실패와 같다, 빈 값을 저장하면 다음에 열어도 다시 만들지 않기 때문)
  - 초안은 사람마다 한 번 만들어 저장하므로 **이미 초안을 받은 사람은 그대로다** — 고친 뒤 새로 초안을 받는 사람부터 적용. 실제 OpenAI 호출 결과(한국어만 · 줄바꿈)는 PR 시점에 확인하지 못했다(배포 뒤 한 번 만들어 보기)
- **롤백**: DB 변경이 없어 리비전만 되돌리면 된다. 다만 `00078` 아래로 가면 가입 번호 규칙이 서버에서 풀리고(앱 vc6 의 즉시 안내만 남는다) 422 대신 옛 400 이 돌아온다(추정)

## 4-13. 2026-10-17 배포 묶음 — 받은 신청 프로필 · 리뷰 띠 env · 무료 하트 · 아바타 확인 맨 끝 · 내 프로필 두 칸 (**2026-10-17 배포 완료**, 리비전 `00083-pwx`)

**상태: 2026-10-17 배포 완료(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 사용자 결정(10-16) "서버 배포는 모든 작업이 끝난 뒤 한 번에" 대로 한 번에 나갔다. 순서: 코드를 §2 "현행 배포 방식"(env · 시크릿 이어받기)으로 배포해 `campus-mate-backend-00082-9lk` → 이어 `STORE_RATING=5.0` · `STORE_RATING_COUNT=1` 을 `--update-env-vars` 로 **더해**(`--set-*` 금지, §2) 지금 리비전 **`campus-mate-backend-00083-pwx`** 가 돈다. 직전 리비전은 `00081-md2`, 되돌림 하한 `00063` 은 그대로다(§5). 점검 결과는 아래 "배포 후 점검 목록". **아직 안 한 것: 새 앱 빌드(안드로이드 vc9 · TestFlight)** — 아래 "새 앱 빌드는 서버 배포 뒤" 원칙대로 이제 낸다.

묶음에 든 서버 PR(main `fccc5e2d` 기준 — 다섯 개 모두 `00082-9lk` · `00083-pwx` 에 들어 있다, 대장 전달 값):

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
- **넣은 값(사용자 결정 10-16 "현재는 별점5에 1명으로 고정")**: `STORE_RATING=5.0` · `STORE_RATING_COUNT=1` — 2026-10-17 리비전 `00083-pwx` 에 넣었다. 스토어에 실제 별점이 생기면 같은 두 값을 고친다(코드 배포 없이 env 갱신만, 새 리비전이 생긴다). **2026-10-20 개정(대장 전달 값), 종전 `STORE_RATING_COUNT=1`: 운영은 `STORE_RATING_COUNT=0` 으로 내려 띠를 숨긴다**(리비전 `00091-rnc`, §4-15)

```bash
# 2026-10-17 이렇게 더했다(00082-9lk → 00083-pwx). 값을 바꿀 때도 같은 명령이다 — 목록에 더하기만 한다. 값은 사용자 승인 뒤에.
gcloud run services update campus-mate-backend --project=<PROJECT_ID> --region=asia-northeast3 \
  --update-env-vars STORE_RATING=5.0,STORE_RATING_COUNT=1
```

- `settings.py` 가 읽는 값은 이제 **env 13개 · 시크릿 11개**다(§2 의 env 11개에 이 둘이 더해졌다). 둘 다 비어도 서버는 뜬다(띠만 숨는다). 운영 `00083-pwx` 도 24개(그중 시크릿 11)다

### 무료 하트 값 (PR #570, 사용자 확정 10-16 "무료하트조정 확정")

| 항목 | 값 | 어디 |
| --- | --- | --- |
| 에브리타임 홍보 | **40하트**(종전 50) · 월 1회 | 서버 `REWARD_HEARTS["everytime_post"]` — 제출할 때 금액을 행에 적고, 승인 트리거가 그 금액을 준다(이미 낸 제출은 적힌 금액으로 승인) |
| 단톡방 공유 | **25하트**(그대로) · 월 3회 | 서버 `REWARD_HEARTS["kakao_share"]`. 앱 18b 캡션은 "3명 이상이 있는 단톡방에 …"(종전 5명) |
| 커뮤니티 투표 | **하루 첫 투표 5하트**(종전 10) · **주 최대 15**(종전 30, 한국 시간 월요일 0시) | 지급은 DB `cast_poll_vote` · `poll_vote_reward_due`(마이그레이션 `20261016144525`). 서버 `POLL_VOTE_REWARD` 5 는 18a 표시용이다 |
| 친구 코드(추천) | **양쪽 50하트**(그대로) | DB `redeem_referral` |

- **DB 마이그레이션 2개**: `20261016144525_poll_vote_reward_5_cap_15`(두 함수 안 숫자만 바꾸는 `create or replace` — 이름 · 인자 · 반환형 · 권한 그대로) · `20261016144530_faq_free_heart_amounts`(FAQ "하트를 무료로 얻는 방법이 있나요?" 답의 숫자와 "학교 단톡방" → "단톡방", `update … replace` 라 두 번 돌려도 같다)
- **운영 적용 상태**: **두 파일 모두 운영에 적용됐다 — 운영 76개 = 저장소 76개**(대장 전달 값: 2026-10-16 사용자 승인 문장 뒤 `apply_migration`). FAQ 는 PR #573 이 운영 실제 문구 "하루 첫 투표에 10하트" 까지 바꾸게 고친 SQL 그대로다. 투표 함수 파일 머리말의 "초안 — 아직 어디에도 적용하지 않았다" 와 FAQ 파일 머리말의 "2026-10-17 운영에 적용했다"(대장 값과 하루 다르다)는 쓸 때의 문장이다 — SQL 파일은 고치지 않는다(`docs/SUPABASE.md` §1)
- **순서**: 투표 함수(DB)와 서버 상수(18a 표시)는 같이 간다. DB 를 먼저 올리면 옛 서버의 18a 가 "10 · 주 최대 30" 을 보이는데 실제로는 5 가 들어오고, 서버를 먼저 올리면 "5 · 주 최대 15" 를 보이는데 DB 가 10 을 준다 — **어느 쪽이든 짧게 겹치는 동안 글자만 어긋난다**(돈 · 데이터는 깨지지 않는다). 권하는 순서: DB(투표 함수) → 서버 → 확인 — **실제로 이 순서였다(DB 2026-10-16 → 서버 2026-10-17)**
- **전환 주**: 적용한 날이 든 주에 옛 10하트를 한 번 받았으면 5하트를 한 번 더 받아 15 에서 멈추고, 두 번 이상 받았으면 그 주는 더 받지 못한다(이미 받은 하트는 회수하지 않는다, 마이그레이션 머리말)
- **옛 앱 주의**: 옛 앱(빌드 15 · 16 · vc8)은 투표 토스트가 앱 상수 "하트 10개를 받았어요" 이고 18a · 15e 맨 위에 옛 내부 안내 세 줄(`heartRewardNotice`)이 남아 있다 — 서버가 아니라 앱 글자라 새 빌드로만 바뀐다. 18a 줄 글(보상 · 한도)은 서버 값이라 서버 배포(2026-10-17)로 바뀌었다

### 아바타 확인을 가입 맨 끝으로 · 다음 단계 조회의 가입 확정 (PR #574)

- **단계 순서**(`onboarding_progress.py` `_STEPS`): basic_info → kakao_id → photos → appearance_type → interests → my_traits → survey → ideal_conditions → ideal_traits → ideal_note → bio → **avatar** → complete. 종전에는 avatar 가 survey 바로 뒤였다(2026-09-25 결정). **설문을 마치면 아바타가 아직이어도 06-1 로 간다.** 조건식(`avatar_ready` = ready 행이 하나라도 있음, 5회 실패 보상의 기본 아바타 포함)은 그대로이고 작업 등록은 여전히 04-3 이다
- **가입 확정(`profiles.status` `pending` → `active`)이 두 곳**: ① 종전대로 `POST /profile-onboarding/bio` 저장 때 다음 단계가 complete 면(= 아바타가 이미 ready) 그 자리에서 ② **새로** `GET /profile-onboarding/next-step` 이 complete 를 계산했고 스냅샷 `_status` 가 `pending` 이면 `activate_profile` 을 부른 뒤 응답한다 — 06-3 저장 때 아바타가 아직이던 사람은 아바타가 끝난 뒤 앱이 단계를 다시 물을 때(리빌 "확인했어요", 앱 다시 켜기, 토큰 갱신) 가입이 끝난다
- **`activate_profile` 은 조건부 PATCH**(`status=eq.pending` 인 행만 → `active`) — 정지 · 탈퇴를 되살리지 않고, 06-3 저장과 단계 조회가 겹쳐도 한 번만 바뀐다. 이미 active 인 사람의 조회는 쓰기 0번이다(토큰 갱신마다 도는 조회라 사람마다 평생 한 번만 쓴다)
- 시험 `backend/tests/profile_onboarding/test_onboarding_progress.py` · `test_onboarding_router.py`(pending 활성화 · active · suspended · withdrawn 은 안 씀 · 아바타 미완성이면 안 씀 · 옛 앱 순서)
- **옛 앱 + 새 서버**(아바타 리빌 맨 끝 계획 §A 호환 표 — 시험으로 고정한 것은 서버 쪽): 설문 끝 · 아바타 만드는 중 → 서버가 06-1 을 줘 막힘이 풀린다 / 06-3 저장 · 아바타 완성 → 그 자리에서 활성화 → 20(리빌 없음, 지금과 같다) / 06-3 저장 · 아바타 아직 → 라우터가 05-12 로 보냄 → 완성 → "다음" → 단계 조회가 활성화 → 홈(20 · 20d 만 건너뛴다). **옛 앱이 새 서버에서 멈추지 않는다**
- **새 앱 + 옛 서버(서버를 이 묶음 아래 리비전으로 되돌렸을 때)는 피한다**: 옛 서버는 설문 뒤에 avatar 를 돌려줘 새 앱에서 아바타 확인 화면이 설문 뒤 · 06-3 뒤 두 번 뜰 수 있고(계획서 §C), 06-3 뒤에 아바타가 아직이던 사람은 단계 조회로 활성화되지 않는다(추정 — 이 문서 담당이 시험하지 않았다)

### `GET /me/profile` 두 칸 — `ideal_note` · `survey_answers` (PR #577)

- `ideal_note`: 문자열 또는 `null`(06-2a 이상형 글). `survey_answers`: `{"1": 0.5, …, "9": -1.0}` — 축 번호(1 ~ 9, `POST survey` 의 `answers` 와 같은 키) → 값(−1 ~ 1, numeric 이 정수 모양으로 와도 float 로 내린다). **설문 전이면 `{}`**
- 같은 읽기 요청의 `select` 에 `ideal_note` 와 `survey_answers(axis,value)` embed 를 넣었다 — 요청 수 1회 그대로, 내 행 아래 embed 라 남의 답은 닿지 않는다(FK `profile_id` → `profiles.id`). DB · 스키마 변경 없음. 시험 `backend/tests/me/test_me_profile.py`
- 쓰는 곳: 새 앱의 온보딩 뒤로가기(설문 · 06-2a 로 돌아갔을 때 저장한 값 채우기, 앱 PR #579). 옛 앱은 모르는 키를 무시한다. **새 앱 + 옛 서버**면 두 칸이 없어 앱이 빈 값으로 읽는다 — 돌아간 설문에서 9축을 미리 고르지 않아 직접 다시 골라야 보낼 수 있다(저장한 답을 0 으로 덮어쓰지 못하게 앱이 막는다)

### 배포 순서 · 롤백 주의

1. **DB — 끝(2026-10-16)**: `20261016144525` · `20261016144530` 을 사용자 원문 승인 뒤 `apply_migration`(운영 76개 = 저장소 76개, 대장 전달 값)
2. **서버 — 끝(2026-10-17)**: §2 "현행 배포 방식"으로 한 번에 배포(`00082-9lk`, 이 묶음 다섯 PR 이 한 리비전에 든다) → `--update-env-vars STORE_RATING=5.0,STORE_RATING_COUNT=1` → `00083-pwx`
3. **배포 뒤 점검 — 끝**(아래 목록의 결과)
4. **앱 — 아직(안드로이드 vc9 · TestFlight)**: **새 앱 빌드(안드로이드 AAB · 아이폰 TestFlight · 스토어 심사)는 서버 배포 뒤에** 시험자 · 스토어에 낸다 — 새 앱은 받은 신청 행에 "프로필 보기" 하나뿐이라 옛 서버(경로 없음 → 404)에서는 **받은 신청에 답할 수 없다**. 아바타 확인 화면 · 리빌 · 설문 채우기도 새 서버를 전제로 한다(위)

**롤백**: 테이블 · 열 변경이 없어 서버는 리비전만 되돌리면 된다(하한은 §5 의 `00063` 아래 금지 그대로). 단 **새 앱 빌드가 시험자 · 스토어에 나간 뒤에는 이 묶음이 든 리비전 아래로 되돌리지 않는다** — 새 앱의 받은 신청 답하기가 404 로 막힌다. 되돌린 사이 06-3 을 냈는데 아바타가 아직이던 사람은 서버를 다시 올린 뒤 단계 조회 때 가입이 끝난다(추정). 투표 함수는 되돌리지 않는다(되돌리려면 옛 값 10 · 30 으로 새 마이그레이션 + 승인).

### 배포 후 점검 목록 (2026-10-17 결과 — 대장 전달 값. 다음 배포에도 같은 목록을 쓴다)

- [x] `curl https://<서비스 URL>/health` → `{"status":"ok"}`(§3) — **200**
- [x] **무인증 401**: `curl -s -o /dev/null -w '%{http_code}' https://<서비스 URL>/profile-onboarding/next-step` → **`401`**. 같은 방법으로 `/cards/acceptances/<아무 id>` → `401` 은 결과를 받지 못했다(토큰 없음이 판정보다 먼저다, 설계 문서 §4.6)
- [x] **env** — **24개(그중 시크릿 11)**, `STORE_RATING=5.0` · `STORE_RATING_COUNT=1` 추가: `gcloud run services describe campus-mate-backend --region=asia-northeast3 --format='value(spec.template.spec.containers[0].env)'` 에 `STORE_RATING` · `STORE_RATING_COUNT` 가 있고 이전 env 11 · 시크릿 11 이 그대로인지(이름만 본다 — 값을 보고서 · 채팅에 적지 않는다)
- [ ] **로그**(결과를 받지 못했다): 배포 뒤 30분 동안 Cloud Run 로그에 5xx · `upstream_call_failed` · Traceback 이 새로 늘지 않는지. 실명 · 사진 경로 · 웹훅 주소가 찍히지 않는지(§4-6)
- [ ] **기능 한 번씩**(결과를 받지 못했다 — 보호 계정 · E2E 자율 허락 범위에서): 받은 신청 프로필 보기 200 · 이미 답한 건 409 / `GET /home/summary` 의 `store_rating` · `store_rating_count` 가 넣은 값 / 18a 줄 "40 · 월 1회" · "5 · 주 최대 15" / 설문만 낸 계정의 next-step 이 `ideal_conditions` · 다 낸 pending 계정이 next-step 한 번에 `active`(E2E E-ONB-33 은 서버 배포 뒤 통과 — PR #578) / `GET /me/profile` 에 `ideal_note` · `survey_answers`
- [x] 리비전 이름을 §5 에 적는다(이 문서 담당은 대장 전달 값으로 적는다) — `00083-pwx`

## 4-14. 2026-10-19 배포 묶음 — 인증샷 여러 장 · 졸업생 인증(코드 기본 꺼짐, 운영은 10-19 켬) · 저녁 알림 기본값 · 관리자 웹 env (**2026-10-19 배포 완료** — 이 묶음의 10-19 리비전은 `00089-fpm`, 10-20 ~ 10-26 리비전은 §4-15 `00091-rnc`, 10-27 이후 현재 리비전은 §4-16 `00092-2zr`)

**상태: 2026-10-19 배포 완료(대장이 조회로 확인한 값).** 2026-10-19 서버 리비전 흐름은 `00086-7zf` → `00087-9qj`(DB 마이그레이션 4개 적용 직후 배포, 스위치 꺼짐) → `00088-gh5`(**졸업생 스위치 `GRADUATE_VERIFICATION_ENABLED=true` 켬** — 사용자 직접 승인 "졸업생 스위치 켜기 승인") → `00089-fpm`(#617 졸업증명서 원본대조번호 읽기 + #619 약관 동의 판 `2026-10-19`)다. 직전 `00086-7zf` 는 2026-10-18 밤(관리자 웹 서버 · 보안 보강 · 인증샷 결과 알림까지). **지금 운영은 `campus-mate-backend-00089-fpm`, env 27개(그중 시크릿 11), 졸업생 스위치 켜짐, 운영 마이그레이션 93개(원격 버전 `20261019055736` · `055756` · `055818` · `055824` = 인증샷 여러 장 · 졸업생 표 · 졸업생 함수 · 저녁 알림 기본값), `/health` 200, 무인증 401, ERROR 로그 0.** 새 시크릿 · 새 Scheduler job · 새 Cloud Tasks 큐는 없다(env 는 `00086` 의 관리자 웹 2개 + 스위치 1개가 늘었다, §2). **되돌림 하한: `00087` 이전으로 되돌리지 않는다**(`00086` 은 인증샷 제출이 깨진다).

묶음에 든 서버 · DB 변경(앱만 바뀐 PR #591 카카오 초대 코드 공유 · #611 사진 안내문 · #612 연락처 제한 안내문은 서버가 없다):

| PR | 무엇 | 서버 파일 | DB 마이그레이션 |
| --- | --- | --- | --- |
| #613 | 인증샷 1~3장 + 단톡방 검수 중에도 월 3회까지 이어 제출 + 관리자 사진 여러 장 | `app/heart_tasks/*` · `app/admin/heart_task_review.py` · `app/admin/repository.py` | `20261019100000_heart_task_multi_photos` |
| #614 | 저녁 알림 제한(방해 금지) 기본값 꺼짐 | `app/cards/*`(알림 설정 `NOTIFICATION_DEFAULTS` · `push.notify`) | `20261019210000_notification_quiet_hours_default_off` |
| #615 | 졸업생 인증(신청 · 관리자 검수 · 정리 · 탈퇴 연동) | `app/graduate_verification/*` · `app/admin/graduate_*.py` · `app/account/*` · `app/chat/batch_router.py` · `app/student_verification/router.py` | `20261019200000_graduate_verification_tables` · `20261019200100_graduate_verification_functions` |

**운영 DB 마이그레이션 4개 추가 적용 → 운영 93개 = 저장소 93개**(대장 전달 값). 원격 기록 버전은 파일 이름이 아니라 **적용 시각**이다(`docs/SUPABASE.md` §4 관례): `20261019055736` · `20261019055756` · `20261019055818` · `20261019055824`. 파일 번호 순서대로 적용했다면 이 순서로 위 네 파일과 짝이 되지만 짝은 이 문서 담당이 확인하지 못했다.

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

**스위치: `GRADUATE_VERIFICATION_ENABLED` — 코드 기본값은 `false`(꺼짐)이고, 운영은 `00088-gh5`(2026-10-19)에서 `true` 로 켰다.** 켠 근거: 아직 공개 출시 전이라 앱 사용자는 테스터뿐이고, 사용자가 시험하려고 켜는 것을 직접 승인했다("졸업생 스위치 켜기 승인"). 켜진 서버는 `GET /me/verification-status` 의 `graduate_enabled` 가 `true` 이고 새 앱은 동의 다음에 인증 방법 고르기를 한 번 지난다(옛 앱 vc11 · vc12 는 모르는 칸을 무시하고 지금처럼 학교 메일이 바로 나온다). **꺼진 서버(코드 기본값 · 끄기 명령 후)에서는** 새 앱도 학교 메일 관문만 만나고, `PUT /me/verification-method` 의 졸업증명서 값과 `POST /graduate-verification` 은 403 `graduate_disabled` 다. 관리자 웹의 "졸업생" 화면은 신청이 들어오면 바로 쓴다.

**켜기 조건과 현재 상태** — 켜는 것은 별도 사용자 승인이 필요하다. 아래 세 가지는 **공개 출시(스토어 제출) 전까지** 끝내야 한다. 10-19 현재: 1번 **처리방침(노션)은 10-19 졸업증명서 · 학생증 정리를 반영 완료, 이용약관도 반영 완료**(대장 전달). 2번 스토어 개인정보 양식과 3번 법률 확인 · 실제 졸업증명서 샘플 판독 검증은 이 문서 담당이 끝났다는 전달을 받지 못했다.

1. **처리방침 변경 반영**: 수집 항목(졸업증명서 사진 · 이전 학교 이메일 · 문서확인번호), 목적, 보유 기간(사진 = 결정 즉시 · 최대 14일, 평문 = 결정 즉시, 해시 = 계정 존속 + 재가입 제한 기간), 처리 위탁 · 국외 이전(Google Cloud Vision), 관리자 열람 기록, 동의 방식.
2. **스토어 개인정보 양식 변경**(구글 데이터 보안 · 애플 앱 개인정보). 칸 이름은 스토어 현재 화면을 보고 확정한다. 새 앱 빌드를 **제출하기 전에** 반영한다.
3. **법률 확인 + 실제 졸업증명서 샘플 판독 검증**(계획서 0-5 · 11장).

```bash
# 켜기 — 사용자 승인 문장 뒤에만(운영은 10-19 `00088-gh5` 에서 이 명령으로 켰다). 목록에 더하기만 한다(--set-env-vars 금지, §2). 새 리비전이 생긴다.
gcloud run services update campus-mate-backend --project=<PROJECT_ID> --region=asia-northeast3 \
  --update-env-vars GRADUATE_VERIFICATION_ENABLED=true
# 끄기(되돌리기): 같은 명령에 =false, 또는 --remove-env-vars GRADUATE_VERIFICATION_ENABLED. 코드 배포 없이 끝나고 새 앱도 옛 관문으로 돌아간다.
```

- **켠 뒤 점검**(10-19 켠 뒤 /health 200 · 무인증 401 · ERROR 로그 0 만 전달받았다. 아래 신청 · 승인 · 삭제 확인은 결과를 받지 못했다): `GET /me/verification-status`(시험 계정 토큰)의 `graduate_enabled` 가 `true` → 시험 계정으로 신청 → 관리자 웹 "졸업생" 목록에 뜸 → 승인 또는 반려 → **버킷 `graduate-cert-temp` 가 비어 있음**(결정 즉시 삭제 확인) → 신청 행의 평문 3칸(`ocr_document_number` · `ocr_school_text` · `previous_school_email`)이 null. 켠 뒤 서버 안전 하한은 `00087` 이다(그 아래는 `PUT /me/verification-method` 가 404).
- **새 시크릿 없음 확인(2026-10-19)**: 스위치(env 1개, 시크릿 아님)는 `GraduateSettings`(별도 클래스, 코드 기본 `false`)가 요청마다 읽는다. 번호 · 학번 해시는 기존 **`IDENTITY_HMAC_KEY`** 를 같은 키로 쓰되 입력 앞에 `graduate-document|` · `graduate-student|` 접두사를 붙여 학교 메일 해시와 겹치지 않는다(키를 바꾸면 졸업생 해시도 모두 무효가 된다 — `key_version` 칸). 글자 인식은 기존 Vision 클라이언트 팩토리(`get_vision_client_factory`)를 그대로 쓴다 — 새 API 사용 설정 없음. 신청 알림은 학생증 때와 같은 디스코드 채널(`DISCORD_WEBHOOK_URL`)로 가며 **신청 id 와 profile_id 만** 싣는다.
- **버킷 `graduate-cert-temp`**: 마이그레이션이 만든 비공개 버킷(10MB, `image/jpeg` · `image/png`, 클라이언트 정책 없음). 경로 `{profile_id}/{request_id}.jpg|png`. 옛 `student-id-temp` 와 섞지 않았다(그 안의 옛 학생증 삭제는 사용자 승인 대기, 출시후_할일 1-1).
- **정리 배치**: 새 job 이 아니라 **기존 매시 `/batch/chat-gate`** 가 한다(§4-1). ① 14일 지난 대기 신청 → `cancelled(expired)` + 평문 비움 + 사진 삭제 ② 학교 메일로 따로 인증을 마친 사람의 대기 신청 닫기(`verified_otherwise`) ③ 결정이 났는데 `photo_path` 가 남은 줄의 사진 삭제. 응답에 키 `graduate_photos_deleted` · `graduate_pending_expired` · `graduate_verified_cancelled` 가 더해졌다(옛 학생증 키는 그대로). 졸업생 정리가 터져도 응답은 200 이고 앞 결과는 유지된다. 미인증 14일 계정 정리(`/batch/cleanup`)는 **대기 신청이 있거나 14일 안에 결정된 졸업생을 지우지 않는다**(DB 함수 `list_unverified_accounts` 교체 + 지우기 직전 재확인).
- **탈퇴**: 대기 신청을 `cancelled(account_withdrawn)` 으로 닫고 사진 폴더를 비운다(`withdraw` 단계 `graduate_request` · `graduate_files`). 재가입 제한 해시는 학교 메일 claims 가 먼저, 없으면 졸업생 학번 해시, 둘 다 없으면 없음(null)이다. 읽기가 실패하면 둘 다 503 으로 멈춘다(null 로 탈퇴시켜 제한을 잃지 않는다).
- **경로**: 신청자(로그인 + 정지 · 동의 확인) `PUT /me/verification-method` · `POST /graduate-verification`(multipart `photo` · `agreed` · 선택 `previous_school_email`, 201 `{"state":"pending","attempts_left":n}`) · `GET /me/verification-status` 새 칸 `graduate_enabled` · `verification_method` · `graduate`. 관리자(`get_admin_caller` — 로그인 → 2단계 aal2 → 명단) `GET /admin/graduate-requests` · `GET /admin/graduate-requests/{id}` · `POST .../approve` · `POST .../reject`. 오류 응답은 `{"detail": 문구, "code": 코드}`(인앱결제와 같은 모양). 반려 사유 코드 4개 `unreadable` · `not_certificate` · `unverifiable` · `school_unsupported`. 신청은 사람당 **3회**(만료로 닫힌 것은 세지 않는다), 대기는 **14일**을 넘기지 못한다.
- **푸시**: 종류 `verification_result` 를 재사용(알림 종류 check 변경 없음), `data` = `route: graduate_verification` · `state` · `reason`. 앱은 화면을 옮기지 않고 인증 관문만 다시 묻는다.
- **로그**: 사진 경로 · 문서확인번호 · 학번 · 이메일 · OCR 글자를 로그와 디스코드에 쓰지 않는다 — 신청 id 와 profile_id 만. 배포 뒤 30분 동안 로그에서 이를 확인한다(§4-6).

### 2026-10-19 후속 서버 변경 (PR #617 · #619 — `00089-fpm` 에 들어 있다, `00087-9qj` · `00088-gh5` 에는 없다)

- **PR #619 `CONSENT_VERSION` 을 `2026-10-19` 로 올림**(`backend/app/consents/policy.py`, 학생증 문구를 정리한 새 약관 — 노션 반영 완료). **`00089-fpm` 이 나간 뒤로 이미 가입한 계정은 모두 02-c-4 재동의 화면을 한 번 거친다**(신규 가입자는 새 판으로 기록, DB 제약은 날짜 형식 text 라 새 값을 막지 않는다). E2E 하네스 상수도 같은 값으로 맞췄고 서버 상수와 같은지 보는 시험이 있다.
- **PR #617 졸업증명서 번호 라벨에 "원본대조번호" 추가**(`graduate_verification/document_reader.py`): 서울대학교 양식은 문서확인번호 라벨이 "원본대조번호"라 OCR 이 번호를 못 읽었다. 라벨 목록 = 원본대조번호 · 문서확인번호 · 문서번호 · 확인번호 · 발급번호(라벨 글자 사이 공백 허용), `제 ○○ 호` · 학위등록번호는 문서확인번호가 아니라 읽지 않는다. 합성 글자로 시험했고 **실제 졸업증명서 샘플 판독 검증은 여전히 안 됐다**(결정 기록 §6 위험 1). `00089-fpm` 에 들어 있고 스위치가 켜져 있어 지금 쓰인다.

### 관리자 웹 환경변수 `ADMIN_ALLOWED_ORIGINS` · `ADMIN_BASE_URL` (리비전 `00086-7zf` 에서 더해짐)

- **`ADMIN_ALLOWED_ORIGINS`**: 쉼표 목록(관리자 웹 주소). **비어 있으면 CORS 를 붙이지 않는다**(관리자 웹 배포 전과 같다). `*` 를 넣으면 서버가 **기동하지 않는다**(`AdminWebSettings` 검사). 끝의 `/` 는 서버가 뗀다. `Settings` 가 아니라 별도 클래스가 `main.py` import 때 읽는다.
- **`ADMIN_BASE_URL`**: 관리자 웹 주소. 있으면 디스코드 인증샷 · 신고 알림에 그 건의 검수 링크를 싣는다(없으면 "Supabase 대시보드에서 확인").
- `ADMIN_MFA_MAX_AGE_HOURS`(기본 12, 관리자 2단계 인증 나이 상한)는 env 개수(24 → 26)로 보아 서비스에 넣지 않은 것으로 **추정**한다 — 이 문서 담당이 서비스를 조회하지 않았다.
- 값은 이 문서에 적지 않는다. 관리자 웹은 Vercel 에서 main 반영 때 자동 배포된다. 인증샷 여러 장 보기는 `photo_urls` 가 없는 옛 서버 응답도 읽어서 서버보다 먼저 나가도 죽지 않는다(사진은 첫 장만).
- **`admin_actions` 는 SQL 창에서 손대지 않는다**: 관리자 쓰기 경로의 작업 기록이고(보관 2년) 서버가 같은 요청 안에서 쓴다. `admin_users`(관리자 명단)는 서버가 읽기만 한다 — 등록은 사용자 승인 뒤 대장이 SQL 한 줄로 한다.

### 배포 순서 · 롤백 주의

1. **DB**(사용자 승인 뒤 `apply_migration`, 파일 번호 순서) → `20261019100000` 을 적용한 직후 **곧바로 서버**(인증샷 틈) → 관리자 웹(Vercel 자동) → **앱**(AAB · TestFlight). 앱은 서버 뒤에 나간다.
2. 서버 배포는 §2 "현행 배포 방식"(env · 시크릿 이어받기). 04:00 KST 정리 시각 전후는 피한다.
3. **롤백 하한**: 어떤 경우에도 `00063` 아래로 가지 않는다(§4-4). 이 묶음 이후에는 **`00087` 이전(`00086`)으로 되돌리지 않는다** — `storage_paths` 마이그레이션 때문에 인증샷 제출 · 관리자 사진 보기가 깨진다. 되돌림은 "고친 서버의 새 리비전"으로 한다. 스위치를 켠 운영에서는 `00087` 이전이 `PUT /me/verification-method` 404 로 새 앱의 방법 고르기도 막는다. 졸업생 기능만 끄려면 리비전을 되돌리지 말고 스위치 env 를 `false` 로 바꾸는 새 리비전을 만든다. 마이그레이션은 되돌리지 않는다.
4. **앱 빌드(10-19 시점 기록 — 10-20 현재는 §4-15 "앱 빌드")**: TestFlight 빌드 21(6개 PR: #591 #611 #612 #613 #614 #615), 빌드 22(#617 ~ #620 포함 main `db166fdc`). 안드로이드 versionCode 13 은 플레이에서 이미 사용된 번호라 14, 15 로 만들었다(14 ~ 17 은 이후 폐기 — §4-15). 새 앱 빌드를 낸 뒤에는 위 하한을 지킨다. `ITSAppUsesNonExemptEncryption = false` 는 이미 설정돼 있다(앱 안 암호화는 로그인 nonce 해시뿐이고 나머지 통신은 OS 의 HTTPS 다).

### 배포 후 점검 목록 (2026-10-19 — 대장이 조회로 확인한 항목만 체크했다)

- [x] 리비전 `campus-mate-backend-00089-fpm`(`00087-9qj` → `00088-gh5` 스위치 켬 → `00089-fpm`), env 27개(그중 시크릿 11), 졸업생 스위치 켜짐, 운영 마이그레이션 93개
- [x] `curl https://<서비스 URL>/health` → 200
- [x] 무인증 호출 401 (대장이 확인한 경로 이름은 전달받지 못했다)
- [ ] `GET /me/verification-status`(시험 계정) 의 `graduate_enabled` 가 `true` 이고 옛 칸이 그대로 (결과를 받지 못했다)
- [ ] 매시 `/batch/chat-gate` 응답에 `graduate_*` 세 키 (다음 정각 실행 로그, 결과를 받지 못했다)
- [ ] 인증샷 제출 한 번(시험 계정) + 관리자 상세에서 사진 여러 장 보기, `NOTIFY pgrst, 'reload schema'` 가 필요했는지 (결과를 받지 못했다)
- [x] ERROR 로그 0 (대장 확인). 사진 경로 · 번호 · 이메일이 로그에 없는지는 따로 확인한 결과를 받지 못했다

## 4-15. 2026-10-20 배포 묶음 — 약관 동의 판 2026-10-20 · 리뷰 띠 숨김 · 코호트 오픈 시각 · 환불 확인 배치 (**10-20 ~ 10-26 리비전 `campus-mate-backend-00091-rnc`** — 10-27 이후 현재 리비전은 §4-16 `00092-2zr`)

**상태: 2026-10-20 배포 완료(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 10-20 당시 돌던 리비전(2026-10-27 개정, 종전 "돌고 있는 리비전" — 지금은 §4-16 의 `00092-2zr`) **`campus-mate-backend-00091-rnc`**. `00089-fpm`(10-19) 뒤 `00090` 의 내용은 전달받지 못했다. 졸업생 스위치 `GRADUATE_VERIFICATION_ENABLED` 는 켜진 채이고 되돌림 하한은 그대로 **`00087` 이전 금지**(§4-14)다. env 개수는 전달받지 못했다(새 시크릿 · 새 Cloud Tasks 큐는 없는 것으로 전달받았다).

| 항목 | 값 |
| --- | --- |
| 약관 동의 판 | `CONSENT_VERSION = "2026-10-20"`(`backend/app/consents/policy.py`, PR #626 — Firebase 수집 안내를 반영한 약관 · 방침 시행일 2026-10-20). 이미 가입한 계정은 모두 02-c-4 재동의를 한 번 거친다(10-19 판 #619 와 같은 방식). E2E 하네스 상수도 같은 값(서버 상수와 같은지 보는 시험이 있다). |
| 홈 리뷰 띠 | 환경변수 **`STORE_RATING_COUNT=0`** — 평가 수가 0 이면 앱이 띠를 숨긴다(§4-13 검증 규칙). 스토어에 실제 별점이 생기기 전에 가짜 숫자(종전 5.0 · 1명, 10-17)를 보이지 않기 위해서다. 실제 별점이 생기면 `STORE_RATING` · `STORE_RATING_COUNT` 를 같이 고친다(§4-13 명령 그대로, 새 리비전이 생긴다). |
| 코호트 오픈 시각 | 서버 코드 변경이 아니라 **DB 데이터**다: 서울 학교 64곳의 `universities.card_opens_at = 2026-11-02(월) 07:00 KST`(마이그레이션 `20261020110000`, `docs/ERD.md` §3). 홈이 이 값을 읽어 오픈 대기(카운트다운)를 보인다. 시험 학교(`region_group = 'e2e'`) 1곳만 열려 있다(심사 계정용). |
| 최대 인스턴스 | **20** (Cloud Run `--max-instances`) |
| 로그 보관 | **30일** |
| 졸업생 인증 | 스위치 켜짐 유지 |

**서버 스케줄(Cloud Scheduler) 4개** — 전부 OIDC(§4-3):

| 일 | 경로 | 시각(Asia/Seoul) |
| --- | --- | --- |
| 카드 지급 | `/batch/daily-cards` | 매일 07:00 |
| 정리(탈퇴 · 미인증 계정 · 60일 지난 하트 인증샷) | `/batch/cleanup` | 매일 04:00 |
| 채팅 확인(신뢰 확인 게이트 · 알림 · 졸업생 정리) | `/batch/chat-gate` | 매시 정각 |
| 환불 확인(구글 Voided Purchases) | `/batch/billing-voided` | 매시 30분 |

**환불 정책 A (남은 하트만 회수)** — `refund_store_purchase` 는 `min(잔액, 구매분 + 보너스)` 만 거두고, 모자란 수는 `purchases.clawed_back_hearts` 와 `shortfall` 로 남긴다(`docs/ERD.md` §6). 관리자 웹 결제 화면에 **"환불이 잦은 계정"** 표가 더해졌다 — 서버 `GET /admin/billing/frequent-returns`(경로에 `refund` 를 쓰지 않는다, e2e 금지어), DB 함수 `admin_billing_returned_accounts`(`20261019220000`). 서버 코드는 PR #622 로 main 에 들어왔고 `00091-rnc`(PR #626 이후 리비전)에 포함된다(main 순서에서 본 추정 — 리비전별 목록은 전달받지 못했다). 정책 B(다른 보상 방식)는 출시 후로 미뤘다.

**앱 빌드(2026-10-20 현재)**: 애플 **TestFlight 빌드 25** + 앱 내 구입 5개가 심사 대기 중이다(TestFlight 24 는 폐기). 구글 프로덕션 **AAB `vc18`(제출 6)** 이 검토 중이다. **vc13 ~ vc17 은 폐기**했다: vc13 은 플레이에서 이미 쓴 번호였고, **vc17 까지는 안드로이드 카카오 로그인 복귀 스킴 키가 빈 값**이었다(아래 사고 기록). 국가는 대한민국만, 출시는 수동(관리형)이다. 연령 등급은 앱스토어 한국 19+, 구글 18+(타겟층). 아이폰 전용(iPad 는 호환 모드), 안드로이드는 세로 고정이 없고 접이식 기기는 시험하지 않았다.

**사고 기록 — vc13 ~ vc17 카카오 키 빈 값(2026-10-20)**: `android/app/build.gradle.kts` 는 카카오 복귀 스킴 키를 환경변수 `KAKAO_NATIVE_APP_KEY` → `android/local.properties` → 빈 문자열 순으로 읽어 `manifestPlaceholders["kakaoKey"]` 에 넣는다. 이 값은 `--dart-define` 과 **별개**라서, `--dart-define` 만 맞추고 환경변수를 빼먹으면 빌드는 되는데 매니페스트의 `kakao<키>` 스킴이 빈 값이 되어 카카오 로그인이 앱으로 돌아오지 못한다. **재발 방지 규칙**: 안드로이드 릴리스 빌드 전에 같은 셸에서 `export KAKAO_NATIVE_APP_KEY=...` 를 하고, 빌드 뒤 AAB 매니페스트에서 `kakao<키>` 스킴을 확인한다(`frontend/run.md` "AAB 빌드"). 결정 배경은 `docs/decisions/2026-10-20-launch-day-decisions.md`.

**되돌림 주의(약관 판)**: `policy.py` 는 현재 판의 동의 행만 센다. `00091-rnc` 아래의 약관 판(`2026-10-19`)으로 되돌리면 2026-10-20 판만 동의한 신규 가입자는 02-c-4 를 다시 만난다(코드 근거, 시험하지 않았다).

## 4-16. 2026-10-27 배포 묶음 — 관리자 매칭 현황 "대화 신청" 목록 · 구글 심사용 시험 데이터 (**10-27 ~ 10-28 리비전 `campus-mate-backend-00092-2zr`** — 10-29 이후 현재 리비전은 §4-17 `00095-7sz`)

**상태: 2026-10-27 배포 완료(대장이 이 세션에서 직접 확인한 값을 전달받았다 — 이 문서 담당이 클라우드를 조회하지 않았다).** 10-27 당시 돌던 리비전(2026-10-29 개정, 종전 "돌고 있는 리비전" — 지금은 §4-17 의 `00095-7sz`) **`campus-mate-backend-00092-2zr`**(트래픽 100%). 흐름: PR #631 merge(`2bef6188`) → 운영 DB 함수 `admin_matching_requests` 적용(원격 버전 `20261027053822`) → 서버 배포 `00092-2zr`. 확인: `/health` 200, 무인증 `GET /admin/matching/requests` 401. 관리자 웹은 `admin-web.yml` 자동 배포가 성공했다. 이 PR 의 변경 파일 13개에는 설정 · 배포 · 시크릿 파일이 없어 새 env · 시크릿 · job 은 없는 것으로 읽는다(env 개수는 전달받지 못했다). **승인(사용자 원문, 대장이 이 세션에서 직접 본 것):** 「대화 신청 목록 운영 DB 적용하고 서버 배포해」. 운영 DB 적용은 campus-supabase 가 MCP 로 했고, 서버 배포는 자동 권한 검사가 대장의 실행을 막아 사용자가 `!` 로 직접 `gcloud run deploy --source` 를 실행했다(설정값은 바꾸지 않았다) → `00092-2zr`. PR #631 은 사용자 「631 머지해줘」 뒤 CI 통과를 확인하고 대장이 머지했고, PR #630 은 「630 머지해줘」 뒤 머지했다.

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

**구글 심사용 시험 데이터 — 운영 DB 에 들어 있다, 출시 전 반드시 제거 (2026-10-26 ~ 27, 대장 전달 · 메모 기록)**
- 구글 Play 심사 대응으로 운영 DB 에 시험 데이터를 넣었다: 시험 학교(`region_group = 'e2e'`) 소속 가상 계정 **20개** + 심사 계정 앞으로 오늘 카드 **1장**(**만료 2026-10-28 07:00 KST**, 아직 결정 없음) + 채팅방 **3개**(메시지 합 16). 알림 · 푸시 행은 0, 네 표의 트리거 · 웹훅은 0건이었다. 사용자 승인 원문(메모 기록): 「실사용자 없어 승인해줄게」(10-26, 이 한 건 한정).
- **제거**: 구글 심사 통과를 확인한 뒤 **사용자에게 먼저 묻고** 지운다. 되돌림 스크립트와 manifest 는 저장소가 아니라 바탕화면 `E2E_결과\심사용_시험계정_10-27\` 에 있다(`rollback.py` — 먼저 dry-run, 승인 환경변수를 줘야 `--apply`, manifest 에 든 id 만 지운다).
- **그 전에는 하네스 전체 cleanup 을 돌리지 않는다**(시험 계정까지 지운다). 카드는 10-28 07:00 에 만료되므로 심사가 그보다 늦어지면 연장할지 사용자에게 묻는다(운영 쓰기 → 승인 문장 필요).
- 관리자 대화 신청 목록에 보이는 "수락" 2건은 이 시험 데이터일 가능성이 크다(대장 전달 추정, 확인하지 못했다).

**같은 날 서버가 아닌 변경 (PR #630)**: 홈페이지 `site/index.html` 바닥글의 사업자 정보(상호 · 대표자 · 사업자등록번호 · 통신판매업 신고번호 · 주소)를 자리 표시에서 개인정보처리방침 `site/privacy/index.html` 맨 아래 회사 정보와 같은 값으로 채웠다. `site.yml` 로 Vercel 배포 성공, 운영 홈페이지에 자리 표시가 남지 않은 것을 확인했다(대장 전달). 값은 이 문서에 적지 않는다.

**후속 (사소, 아직 하지 않은 것)**: 수락 + 매칭인 줄의 응답 시각을 매칭 시각으로 맞출지(지금은 응답이 수락이면 응답 시각, 상대 카드로 먼저 매칭된 줄이면 매칭 시각), 화면 배지 색 · 간격의 pen 대조.

## 4-17. 2026-10-29 배포 묶음 — 학번 숫자 규칙 · 가입 직후 첫 카드 · 무료 카드 하루 한 장 (**현재 리비전 `campus-mate-backend-00095-7sz`**)

**상태: 2026-10-29 배포 완료(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 돌고 있는 리비전 **`campus-mate-backend-00095-7sz`**(트래픽 100%, `/health` 200 · 무인증 호출 401 · ERROR 로그 0). 흐름: `00092-2zr`(10-27, §4-16) → **`00093-5s8`**(10-28 밤, PR #633 매칭 점수 개편 — 이 절 끝 "10-28 묶음") → PR #634 merge(`7651b72a`) 뒤 **`00094-26m`**(100%, 같은 세 가지 확인) → PR #635 merge(`9474e731`) 뒤 **`00095-7sz`**(학번 오류 문구만 바꾼 후속). 직전 `00094-26m` 은 #634 까지만 담았다. 두 PR 의 변경 파일에 설정 · 배포 · 시크릿 파일이 없어 새 env · 시크릿 · job 은 없는 것으로 읽는다(env 개수는 전달받지 못했다). **승인(원문)**: 운영 DB 인덱스는 사용자 「db승인해줄게 완전히 막아야지」(대장 전달). PR #634 의 merge · 배포는 「검토 끝나면 머지하고 배포해」 · 「배포해줘」(메모 기록, 이 문서 담당이 직접 보지 않았다). PR #635 의 merge · 배포 승인 원문은 전달받지 못했다. DB 적용과 서버 배포의 선후는 전달받지 못했다(아래 "배포 순서" 는 코드 근거).

| 항목 | 값 |
| --- | --- |
| 학번 규칙 | `POST /school-info` 가 `student_number` 가 `[0-9]{1,3}`(숫자 1~3자리)이 아니면 **422 + 문자열 `detail` "숫자를 입력해 주세요"** 를 돌려준다(`backend/app/core/errors.py` `STUDENT_NUMBER_INVALID`, `student_verification/schemas.py` `has_valid_student_number`, 라우터 `save_school_info`). 거절하는 것: 글자 · **전각 숫자**(`\d` 가 아니라 `[0-9]` 로 썼다) · 앞뒤 공백 · 4자리 이상. 순서는 정지 계정 거절 → 학교 메일 관문 → 이 검사 → 저장이다. 목록 모양 `detail`(pydantic `pattern`)로 걸지 않고 라우터에서 문자열로 거절하는 이유: 목록이면 앱이 "알 수 없는 오류" 를 띄운다. 문구 이력: PR #634(`00094-26m`)는 "학번은 숫자 3자리까지 입력해 주세요" 였고, 사용자 결정(10-29)으로 PR #635(`00095-7sz`)가 **"숫자를 입력해 주세요" 한 문구**로 바꿨다(글자 · 4자리 이상도 같은 문구). **기존 저장값은 그대로**(고치는 마이그레이션 없음). 앱(vc18 · TestFlight 25)은 문자열 `detail` 을 학번 칸 아래 오류 줄에 그대로 띄워 **앱 변경 없음** |
| 첫 카드 | `GET /cards/today` 가 응답을 만들기 전에 `issue_first_card`(`backend/app/cards/issuing.py`)를 부른다. **무료 카드(`source = 'daily'`)를 한 번도 못 받은 사람**(`CardRepository.has_had_daily_card` — 만료 · 결정 상관없이)에게 그 자리에서 한 장: 몫은 배치와 같고(`_issue_to_owner` — 유료 제안 확보 → 무료 상위 20~90% 구간에서 지급), 만료 = 다음 지급 시각(`ladder.next_issue_at`), **알림 없음**(화면을 이미 보고 있다). 자격은 `card_issue_owners()` 와 같다: `status = 'active'` · 매칭 쉼 아님 · 자동 가림 아님 · 학교 카드 오픈(`card_opens_at` 이 null 이거나 지남) · 벡터 있음 — **14일 접속 조건만 지금 열었으니 뺐다.** 지역 설정이 없으면 건너뛴다. **실패해도 오늘 탭은 200**(예외를 삼키고 `첫 카드 지급 실패 owner=<profile_id>` 로그만). 이유(사용자 결정 10-29): 목요일 가입자가 월요일 지급까지 100시간 넘게 빈 화면을 보다 떠난다(코드 주석) |
| 배치 | `issue_daily_cards` 가 **사람마다 지급 직전** `has_had_daily_card(since = 오늘 자정(KST))` 를 다시 본다 — 대상 목록을 배치 시작 때 한 번 읽어서, 그 뒤 앱이 첫 카드를 줬을 수 있다(카드 오픈일 07:00 에 겹친다). `insert_card` 의 **23505** 는 `DailyCardConflict` 로 읽어 **조용히 건너뛴다(`failed` 로 세지 않는다)**. 23505 만 본다 — FK 위반(23503, 상대가 그사이 지워짐)도 PostgREST 가 409 로 주지만 "이미 받았다" 가 아니므로 오류로 남는다 |
| 운영 DB | 마이그레이션 `20261029090000_daily_cards_one_free_per_day.sql` — `create unique index daily_cards_one_free_per_day on public.daily_cards (owner_id, ((issued_at at time zone 'Asia/Seoul')::date)) where source = 'daily'`. **무료 카드는 한 사람에게 서울 날짜당 한 장**, 산 카드(`purchased`)는 규칙 밖. 표 · 열 변경 없음(인덱스 하나). **만료 시각(`expires_at`)을 키로 쓰지 않은 이유**: 주 중에 사다리가 오르면(주 1회 → 주 2회) 월요일 카드와 목요일 카드의 만료가 같은 다음 월요일이 되어, 월요일 카드를 이미 정한 사람의 목요일 정상 카드가 막힌다(검토 권고). 2026-10-29 운영 적용 — 적용 전 같은 사람 · 같은 서울 날짜 무료 카드 2장 이상 **0건**을 읽어 확인했고(파일 머리말에도 있다), 적용 뒤 **unique · valid** 를 확인했다. 운영 마이그레이션 **100개 = 저장소 100개**(원격 버전 값은 전달받지 못했다). `docs/ERD.md` §4 · `docs/ERD_DECISIONS.md` §11-34 |
| 시험 | pgTAP `supabase/tests/daily_card_one_per_cycle_test.sql` 7개(인덱스 있음 · 같은 서울 날짜 둘째 장 23505 · 서울 날짜가 바뀌면 허용 · 다른 사람 허용 · 산 카드 제외 · 날짜별 두 장 · 유일 인덱스) — 파일 이름의 `one_per_cycle` 은 주기 기준이던 첫 안의 이름이 남은 것으로 보인다(추정). 합계 pgTAP **Files=42 Tests=1330**, 백엔드 pytest **3203**(대장 전달 값). pytest: `backend/tests/cards/test_issuing.py` · `test_card_repository.py` · `test_paid_card_router.py`, `backend/tests/student_verification/test_router.py`. 하네스 `e2e/` 는 학번을 숫자('21' · '22')로 바꾸고, 배치 알림 시나리오는 옛 카드 1장(`_old_card`)으로 첫 카드를 막고 지급 시각을 후보마다 하루씩 벌린다. e2e 단위는 main 과 같은 실패 5건이 남아 있다(메모 기록) |

**알려진 한계 (문서에 남긴다 — 사용자 결정 대기)**
- **후보가 1명뿐이면 무료 카드가 0장이다**(첫 카드 · 배치 모두). 유료 제안(`ensure_offer`)이 그 1명을 먼저 가져가고, 무료는 그 사람을 뺀 구간에서 뽑기 때문이다. 상위 90% 로 넓히는 규칙(`_issue_to_owner`)도 제외된 그 1명은 되살리지 못한다. 출시 전 서울 여자 후보가 1명이라 실제로 겪었다(대장 전달). **무료와 유료 중 누구를 우선할지는 사용자 결정 대기**다(설계 §13-45).
- **앱 화면 11**: 카드 0 + 후보 있음이면 "오늘 카드는 확인했어요" 를 띄워, 처음 연 사람에게는 어색하다(`frontend/docs/DESIGN.md` §9 11, 출시 후 문구 손질).
- 출시 후(앱 업데이트) 할 일 5건 + 위 문구 1건은 `frontend/docs/DESIGN.md` §13-154 에 모았다.

**배포 순서 · 롤백 주의 (코드 근거 — 시험하지 않았다)**
- 순서는 평소대로 **머지 → DB(인덱스) → 서버**가 맞다. 서버가 먼저 나가도 동작은 같고 동시 요청을 막는 마지막 방어만 비어 있다. DB 가 먼저여도 옛 서버(`00093`)의 배치는 이미 "오늘 받은 사람은 건너뜀" 이라 충돌이 거의 없다(겹치면 옛 서버는 그 한 줄을 `failed` 로 센다, 추정).
- **롤백**: `00094` 에서 `00093` 으로 내리면 첫 카드와 학번 숫자 규칙이 빠진다(가입 직후 빈 화면이 돌아오고 학번에 글자가 들어간다). 인덱스는 남아도 옛 서버에 무해하다. `00095` 에서 `00094` 로 내리면 학번 오류 문구만 옛 문구("학번은 숫자 3자리까지 입력해 주세요")가 된다. 하한은 그대로 **`00063` 아래 금지 + `00087` 이전 금지**(§4-14).
- 인덱스를 내려야 하면 `drop index public.daily_cards_one_free_per_day`(데이터는 안 건드린다)를 새 마이그레이션 파일로 만들고, 운영 쓰기라 사용자 원문 승인 뒤에만 적용한다. 서버 `00094` 이상이 도는 동안 지우면 동시 요청 방어만 빠진다.

**배포 후 점검 목록 (2026-10-29 — 대장이 확인한 항목만 체크했다)**
- [x] `00094-26m` 100% — `/health` 200 · 무인증 401 · ERROR 로그 0
- [x] `00095-7sz` 100% — `/health` 200 · 무인증 401 · ERROR 로그 0
- [x] 운영 인덱스 `daily_cards_one_free_per_day` — 적용 전 중복 0건, 적용 뒤 unique · valid, 운영 마이그레이션 100개 = 저장소 100개
- [ ] 실제 가입자의 첫 오늘 탭 결과 · 배치와 겹친 날의 `failed` 수(결과를 전달받지 못했다)

**10-28 묶음 (이 문서가 처음 적는다 — 메모 기록 · PR 제목 · 마이그레이션 머리말 기준)**: PR #633 merge(`431f54d5`) 뒤 서버 **`00093-5s8`**. 운영 DB 에 먼저 마이그레이션 2개가 적용돼 99개가 됐다 — `20261028090000_profile_vectors_text_facets`(`profile_vectors` 에 글 정리 칸 2개 `self_facets` · `want_facets`) · `20261028100000_match_candidates_face_fields`(함수 `match_candidates` 가 후보의 얼굴상 · 인상 4칸 + 글 정리 2칸을 더 돌려주고 성향 최대 거리 상수를 5.657 → 4.472 로 바꾼다, 반환 타입 그대로). 승인 원문(메모 기록): 「매칭 개편 마이그레이션 2개 운영 적용 승인 db승인」. PR 제목: "매칭 점수 개편: 무료 카드 20~90% · MBTI/얼굴 비중 · 종교 0.6 · 성향 축 · 글 정리 5%". **무료 카드는 이제 점수 상위 20~90% 구간에서 뽑는다**(상위 20% 는 유료 전용, 하위 10% 제외, 그 구간에 뽑을 사람이 없을 때만 상위 90% 전체로 넓힘 — `backend/app/matching/band.py` · `cards/issuing.py` 에서 확인, 설계 §6.8 에 개정 표시를 달았다). 점수 공식의 나머지 바뀐 값(가중치 · 계수)은 이 라운드에서 설계 문서에 옮기지 못했다.

## 5. 현재 배포 상태 (2026-10-29 기준)

**현재 (2026-10-29, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 돌고 있는 리비전 **`campus-mate-backend-00095-7sz`**(10-29, 트래픽 100%, `/health` 200 · 무인증 401 · ERROR 0). 직전 `00094-26m`(PR #634), 그 앞 `00093-5s8`(10-28 밤, PR #633). 약관 동의 판 `2026-10-20` · 홈 리뷰 띠 숨김(`STORE_RATING_COUNT=0`) · 졸업생 스위치 켜짐 · 최대 인스턴스 20 · 로그 보관 30일은 10-20 값에서 바뀌었다는 전달이 없다. 운영 마이그레이션 **100개 = 저장소 100개**(마지막 `20261029090000_daily_cards_one_free_per_day`). Cloud Scheduler 4개(카드 07:00 · 정리 04:00 · 채팅 확인 매시 · 환불 확인 매시 30분)와 애플 서버 알림 URL 등록도 바뀌었다는 전달이 없다. 되돌림 하한은 `00063` 아래 금지 + `00087` 이전 금지(§4-14)가 그대로이고, `00094` 아래로 내리면 첫 카드와 학번 숫자 규칙이 빠진다(§4-17). 앱은 이번 묶음에서 바뀌지 않았다 — 앱 빌드 · 스토어 심사는 10-20 에 애플 TestFlight 25 + 앱 내 구입 5개, 구글 AAB vc18 을 제출한 것까지가 문서에 있는 사실이고(§4-15), 그 뒤 두 스토어의 심사 결과는 이 문서 담당이 전달받지 못했다. **운영 DB 에 구글 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)가 들어 있다 — 출시 전 제거 필수**(§4-16). **알려진 한계: 후보가 1명뿐이면 무료 카드 0장 — 무료/유료 우선은 사용자 결정 대기**(§4-17). 자세한 내용은 §4-17. 아래 날짜별 갱신 줄은 접어 두었다(내용 그대로, 최신 순).

<details><summary>이전 갱신 이력 — 2026-09-26 ~ 2026-10-27 (2026-10-20 · 10-27 · 10-29 문서 정리로 접었다)</summary>

**2026-10-27 갱신(문서 정리 때의 현재 상태 — 2026-10-29 문서 정리로 여기에 접었다, 내용 그대로, 대장이 이 세션에서 직접 확인한 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 돌고 있는 리비전 **`campus-mate-backend-00092-2zr`**(10-27, 트래픽 100%, `/health` 200). 약관 동의 판 `2026-10-20` · 홈 리뷰 띠 숨김(`STORE_RATING_COUNT=0`) · 졸업생 스위치 켜짐 · 최대 인스턴스 20 · 로그 보관 30일은 10-20 값에서 바뀌었다는 전달이 없다. 운영 마이그레이션 **97개 = 저장소 97개**(마지막 `20261027100000_admin_matching_requests`, 원격 버전 `20261027053822`). Cloud Scheduler 4개(카드 07:00 · 정리 04:00 · 채팅 확인 매시 · 환불 확인 매시 30분)와 애플 서버 알림 URL 등록도 바뀌었다는 전달이 없다. 되돌림 하한은 `00063` 아래 금지 + `00087` 이전 금지(§4-14)가 그대로이고, `00092` 에서 `00091` 로 내리면 관리자 대화 신청 목록만 404 이며 앱은 영향이 없다(§4-16). 앱 빌드 · 스토어 심사: 10-20 에 애플 TestFlight 25 + 앱 내 구입 5개, 구글 AAB vc18 을 제출한 것까지가 문서에 있는 사실이고(§4-15), 그 뒤 두 스토어의 심사 결과는 이 문서 담당이 전달받지 못했다. **운영 DB 에 구글 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)가 들어 있다 — 출시 전 제거 필수**(§4-16). 자세한 내용은 §4-16. 아래 날짜별 갱신 줄은 접어 두었다(내용 그대로, 최신 순).

**2026-10-20 갱신(대장 전달 값 — 2026-10-27 문서 정리로 여기에 접었다, 내용 그대로).** 돌고 있는 리비전 **`campus-mate-backend-00091-rnc`**(10-20). 약관 동의 판 `2026-10-20`(PR #626) · 홈 리뷰 띠 숨김(`STORE_RATING_COUNT=0`) · 졸업생 스위치 켜짐 · 최대 인스턴스 20 · 로그 보관 30일. 운영 마이그레이션 **96개 = 저장소 96개**(마지막 `20261020110000_close_seoul_schools_until_cohort_open`). Cloud Scheduler 4개(카드 07:00 · 정리 04:00 · 채팅 확인 매시 · 환불 확인 매시 30분). 애플 서버 알림 URL 프로덕션 · 샌드박스 V2 등록. 앱 빌드: TestFlight 25(심사 대기) · 구글 AAB vc18(검토 중). 되돌림 하한은 `00063` 아래 금지 + `00087` 이전 금지(§4-14). 자세한 내용은 §4-15. 아래 날짜별 갱신 줄은 접어 두었다(내용 그대로, 최신 순).

**2026-10-19 갱신(대장이 조회로 확인한 값).** **2026-10-19 배포 완료** — 돌고 있는 리비전 **`campus-mate-backend-00089-fpm`**. 흐름: `00086-7zf`(10-18 밤) → `00087-9qj`(DB 4개 적용 직후 배포, 스위치 꺼짐) → `00088-gh5`(**졸업생 스위치 켬**, 사용자 승인) → `00089-fpm`(#617 + #619). 담은 서버 변경: PR #613(인증샷 여러 장 · 이어서 제출) · #614(저녁 알림 기본값) · #615(졸업생 인증, 코드 기본 꺼짐 · 운영은 켬) · #617(원본대조번호) · #619(약관 판 2026-10-19 — 전원 재동의) — §4-14. env **27개(그중 시크릿 11)**(`00086-7zf` 에서 `ADMIN_ALLOWED_ORIGINS` · `ADMIN_BASE_URL` 이 더해져 24 → 26, `00088` 에서 스위치 1개가 더해져 27). 새 시크릿 · job 없음. **운영 마이그레이션 93개 = 저장소 93개**(10-19 네 파일 추가 적용, 원격 버전은 적용 시각 `20261019055736` · `055756` · `055818` · `055824`). **되돌림**: `00063` 아래 금지는 그대로이고 이 묶음 이후에는 **`00087` 이전으로 되돌리지 않는다**(`storage_paths` 마이그레이션 — 인증샷 제출 · 관리자 사진 보기가 깨진다, §4-14). 직전 `00084` ~ `00086` 이 담은 PR(학생증 제거 서버 · 관리자 웹 서버 #592 ~ #608 · 인증샷 결과 알림 · 서버 보안 보강)은 대장 전달 값으로 정확한 리비전별 경계를 받지 못했다(`00083 → 00085` 가 10-17 ~ 18 학생증 제거 서버 묶음, `00086` 이 관리자 웹 서버 + 보안 보강 — 10-18 밤). `00086` 아래로 내리면 관리자 · 신고 함수 시그니처가 안 맞고(관리자만 영향), 학생증 제거 서버(`00084`/`00085`) 아래로 새 앱이 나간 뒤 내리면 가입이 막힌다. **앱 빌드**: TestFlight 빌드 21(PR #591 #611 #612 #613 #614 #615), 22(#617 ~ #620 포함 main `db166fdc`, 진행 중). 안드로이드 AAB vc13 은 플레이에서 이미 사용된 번호라 vc14, vc15(진행 중).

**2026-10-17 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** **2026-10-17 배포 완료** — 돌고 있는 리비전 **`campus-mate-backend-00083-pwx`**(안전 하한 `00063` 그대로). 코드 배포 `00082-9lk` 뒤에 `STORE_RATING=5.0` · `STORE_RATING_COUNT=1` 을 더한 리비전이다. 담은 서버 변경: PR #565(리뷰 띠 env) · #568(받은 신청 프로필 API) · #570(무료 하트 값) · #574(아바타 확인 맨 끝 · 가입 확정) · #577(`/me/profile` 두 칸) — §4-13. env 24개(그중 시크릿 11), `/health` 200, 무인증 next-step 401 확인. 새 시크릿 · job 없음. 직전 `00081-md2` 와 `00079` ~ `00080` 이 담은 PR 목록은 받지 못했다. **운영 마이그레이션 76개 = 저장소 76개**(무료 하트 두 파일은 2026-10-16 적용). **아직 안 한 것: 새 앱 빌드(안드로이드 vc9 · TestFlight)** — 서버 배포 뒤에 낸다는 원칙대로 이제 낸다. **되돌림**: 새 앱 빌드가 나간 뒤에는 `00082` 아래로 내리지 않는다(새 앱의 받은 신청 답하기가 404 로 막힌다, §4-13 "배포 순서 · 롤백 주의").

**2026-10-16 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 돌고 있는 리비전 **`campus-mate-backend-00078-nxv`**(2026-10-16 배포). 담은 서버 변경: 온보딩 서버 묶음 PR #544(가입 번호 422 · 성별 · MBTI 이유 · 소개글, §4-12) · 인증 결과 푸시 tag · collapse-id PR #546(§4-8) · 홈 레일 `GET /home/people` PR #549(§4-11). **DB 변경 · 새 env · 새 시크릿 · 새 job 은 없다** — env · 시크릿은 `settings.py` 목록 그대로 22개(env 11 · 시크릿 11, §2). 배포 뒤 `/health` 200, `/home/people` 무인증 호출 401 을 확인했다. 운영 마이그레이션 **74개**(마지막 `20261015120000_poll_feed_tabs`). 배포 순서는 서버 → 앱이고, 세 PR 의 앱 짝(#543 · #546 앱 쪽 · #547 · #548 · #550)은 **안드로이드 vc6 · 아이폰 다음 빌드에 들어간다**(이 문서 정리 시점에 vc6 미빌드). **되돌림**: 세 PR 모두 DB 를 건드리지 않아 리비전만 내리면 된다 — `00077` 로 내리면 가입 번호 규칙 · 레일 사람 칸 · 푸시 합치기가 빠진다(레일은 기본 칸이 된다, 추정). 하한은 아래 10-14 줄(`00063` 아래 금지)이 그대로다.

**2026-10-15 밤 갱신(대장 할 일 문서 `내일_할일_10-12.md` 11차의 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 리비전 **`campus-mate-backend-00077-q89`** — 커뮤니티 탭 줄 서버(PR #540)가 운영에 나갔고, 그 전에 운영 DB 에 `poll_feed_tabs` 를 적용해 **74개**가 됐다(아래 10-15 줄의 "아직 운영에 없다" 를 고친다). 가입 번호 규칙 PR #544 는 이 리비전에 없었다(위 10-16 줄의 `00078` 에서 나갔다).

**2026-10-15 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 돌고 있는 리비전 **`campus-mate-backend-00076-7r2`**. 이 리비전이 담은 PR 목록은 받지 못했다. 운영 마이그레이션 **73개** — 마지막 `faq_support_email`(파일 `20261014130000`, FAQ 문의 메일만 바꾸는 데이터 갱신, `docs/SUPABASE.md` §1). **커뮤니티 탭 줄(서버 · DB PR #540)은 아직 운영에 없다** — main 의 저장소 74번째 `20261015120000_poll_feed_tabs` 는 운영 미적용이고 서버 `GET /community/polls?tab=` 는 배포 전이다. **서버 배포 순서: DB(`poll_feed_tabs` 적용) → 서버 → 앱(커뮤니티 탭 — 앱 PR #542 는 main 에 들어왔다, 앱 빌드 배포는 서버 뒤).** DB 를 먼저 올려도 옛 서버는 `p_tab` 기본값 `'all'` 로 그대로 돈다. 서버가 먼저 나가면 `p_tab` 을 보내 옛 5인자 함수와 맞지 않아 피드 읽기가 실패하고, 앱이 먼저 나가면 옛 서버가 선언하지 않은 `tab` 을 무시해 어느 탭이든 전체 피드가 온다(둘 다 추정 — 이 문서 담당이 시험하지 않았다). 새 env · 시크릿 · job 은 없다. 애플 운영 401 → 샌드박스 재조회(PR #532)는 §4-10.

**2026-10-14 밤 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 돌고 있는 리비전 **`campus-mate-backend-00075-gbw`**. env 11개 · 시크릿 11개가 `settings.py` 목록과 같다(애플 키 연결 완료, §2 · §4-10). 운영 마이그레이션 **72개** — 마지막 `faq_avatar_regen_cost_20`(파일 `20261014120000`, 원격 버전 `20261014080438`, FAQ 문구만 바꾸는 데이터 갱신, `docs/SUPABASE.md` §1). 그 사이 main 에 들어온 서버 변경은 애플 인앱결제(PR #519 · #521), 아바타 모델 `gpt-image-2.5-flare` · 프롬프트 v2-8(PR #517), 아바타 다시 만들기 20하트(`AVATAR_REGEN_HEARTS`, PR #523), 자기소개 · 이상형 글 줄 끝 통일 · 40줄 상한(`FreeText`, PR #526) — 모두 새 job · 마이그레이션(위 FAQ 하나 말고) 없음. **`00075-gbw` 가 이 가운데 어디까지 담았는지와 `00071` ~ `00074` 의 내용은 받지 못했다.** 되돌림 하한은 아래 10-14 줄(`00063` 아래 금지)이 그대로이고, 애플 경로가 든 앱 빌드가 나간 뒤에는 애플 경로가 없는 리비전으로 내리지 않는다(§4-10 "알려진 한계 · 롤백").

**2026-10-14 저녁 추가.** 애플 인앱결제 서버(PR #519 · #521)가 main(`369a420e`)에 들어왔다. 새 env 2개 · 새 시크릿 1개(§4-10), 마이그레이션 없음. **운영 배포 여부 · 리비전 이름은 이 문서 담당이 받지 못했다** — 아래 10-14 줄의 `00070-jz7` 은 그 전 값이다.

**2026-10-14 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 돌고 있는 리비전 **`campus-mate-backend-00070-jz7`**(채팅 실시간 서버 PR #508 포함). **되돌림 1순위는 `00069-p8f`**(읽음 시각 `partner_last_read_at` · 푸시 로그 · 인앱결제 서버까지, PR #499 · #500 · #501 — `00070` 은 실시간 쏘기만 더했다). **어떤 경우에도 `00063` 아래로 되돌리지 않는다**(M2 평문 열 삭제 뒤 `00062` 이하는 없는 열에 써서 깨진다, §4-4 "서버 롤백 주의"). `00064` · `00065` 아래로 가면 보낸 신청 · 친구 코드 리뷰가(§4-7) 서버 오류를 만나고, `00069` 아래로 가면 앱이 읽음 '1' 을 그리지 않고(`partner_last_read_at` 키가 없으면 옛 서버로 본다) 하트 구매 확인이 없는 경로를 만난다(추정). **`00070` 아래(`00069`)로 되돌리면 실시간 이벤트가 멈추는데, 앱은 채널이 붙어(SUBSCRIBED) 있으면 폴링을 30초로 늦춘 채라 목록 · '1' 이 최대 30초 늦어진다**(§4-8 — 폴링 안전망이 받친다). 배포는 §2 "현행 배포 방식"(env · 시크릿 이어받기)으로 했다. 운영 마이그레이션 **71개** — 마지막 `user_channel_realtime_policy`(원격 `20261013154505`, `docs/ERD.md` 상태줄). 새 env · 시크릿은 없다(인앱결제 구글 API 는 Cloud Run 서비스 계정 ADC — 플레이 콘솔에 그 서비스 계정을 초대해야 한다, §4-9). 실시간 쏘기는 기존 `SUPABASE_URL` · 서비스 키를 쓴다(§4-8)

**2026-10-13 갱신(PR 본문 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 리비전 `00064`(보낸 신청 `GET /cards/sent`, PR #483) → `campus-mate-backend-00065-b7n`(친구 코드 지인 리뷰, PR #486). 두 PR 모두 마이그레이션 · env · 시크릿 · job 이 없다(§4-7). 아래 10-12 값 뒤에 다른 변동이 있었는지는 확인하지 못했다.

**2026-10-12 저녁 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 돌고 있는 리비전 **`campus-mate-backend-00063-c79`**.
그 사이 리비전: `00060`(보안 점검 수정 PR #469 + 하네스) · `00061`(학생증 고아 사진 정리 PR #472) · `00062`(유료 카드 서버 미리보기 + Pillow 12.3, PR #473) ·
`00063`(평문 열을 안 쓰는 서버, PR #474). 운영 마이그레이션 **68개** — 마지막은 M2 `drop_plaintext_real_name_and_kakao_id`(파일 `20261012010000`,
운영 기록 버전 `20261012070722`). 저장소 main 은 아직 **67개**다(M2 파일은 DB PR #476 merge 대기, §4-4 "M2 실행 기록"). 새 env · 시크릿 · job 은 없다.
**롤백은 §4-4 "서버 롤백 주의" 를 먼저 본다.** 아래 같은 날 아침 갱신은 기록으로 남긴다.

**2026-10-12 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 운영 마이그레이션 **67개**(저장소 `supabase/migrations/` 도 67개,
마지막 `20261011010000_encrypt_real_name_and_kakao_id`). 서버는 학생증 사진 정리(§4-1, `00058` 이후)와 실명 · 카톡 이중 쓰기(§4-4, `00059`)까지 나갔다.
실명 · 카톡 백필 끝(2행, 불일치 0), M2 대기. 새 env · 시크릿 · job 은 없다. iOS 푸시용 `apns` 블록(PR #465, `app/cards/push.py` — 소리 있는 일반 알림 ·
우선순위 10)도 서버 코드뿐이라 배포 설정이 따로 없다. 아래 2026-09-29 표는 그 뒤로 갱신하지 않았다.

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

</details>
