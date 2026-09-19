# backend 배포 — Google Cloud Run (asia-northeast3, 서울)

**아래 명령은 GCP 프로젝트가 준비되고 사용자가 승인한 뒤에만 실행한다** (spec §13-37).

## 1. 최초 1회

```bash
gcloud config set project <PROJECT_ID>
gcloud services enable run.googleapis.com secretmanager.googleapis.com

# 시크릿 등록 (값은 여기 문서에 남기지 않는다)
echo -n "<service-role-key>" | gcloud secrets create supabase-service-role-key --data-file=-
echo -n "<hook-signing-secret>" | gcloud secrets create auth-hook-signing-secret --data-file=-
```

## 2. 배포

```bash
cd backend
gcloud run deploy campus-mate-backend \
  --source . \
  --region asia-northeast3 \
  --no-allow-unauthenticated \
  --set-env-vars SUPABASE_URL=<project-url> \
  --set-secrets SUPABASE_SERVICE_ROLE_KEY=supabase-service-role-key:latest \
  --set-secrets AUTH_HOOK_SIGNING_SECRET=auth-hook-signing-secret:latest
```

`--no-allow-unauthenticated` 로 배포하고, Supabase Auth Hook 설정에서 서비스 계정 기반 호출을 쓴다(Part C Task C3).

## 3. 배포 확인

```bash
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  https://<서비스 URL>/healthz
```

`{"status":"ok"}` 가 나오면 성공.
