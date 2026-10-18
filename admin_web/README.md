# admin_web — CampusMate 관리자 웹

운영자 전용 대시보드(Flutter 웹). 앱(`../frontend/`)과 **따로 빌드**하고 서로 import 하지 않는다.
설계: 관리자 대시보드 설계서(10-18) §4~§10. 화면 기준은 pen 웹 시안(영역 WOjcG · 컴포넌트 보드 UUkLx).

## 실행 · 시험

```sh
flutter pub get
flutter analyze
flutter test
# 로컬 실행 — 이 주소(http://localhost:3000)가 Supabase Redirect URLs 에 있어야 구글 로그인이 돌아온다
flutter run -d chrome --web-port 3000 \
  --dart-define=SUPABASE_URL=<주소> \
  --dart-define=SUPABASE_ANON_KEY=<anon 키> \
  --dart-define=API_BASE_URL=<서버 주소>
```

값은 코드 · 문서 · 커밋에 쓰지 않는다. 하나라도 비면 첫 화면이 "설정 누락"이다.

## 배포

`.github/workflows/admin-web.yml` — main 반영 때 `flutter build web --release` 뒤 Vercel 로 올린다.
GitHub 저장소 변수 `ADMIN_SUPABASE_URL` · `ADMIN_API_BASE_URL`, 비밀값 `ADMIN_SUPABASE_ANON_KEY` ·
`VERCEL_TOKEN` · `VERCEL_ORG_ID` · `VERCEL_PROJECT_ID` 를 쓴다. `VERCEL_TOKEN` 이 없으면 배포 단계만 건너뛴다.
`web/vercel.json` 이 빌드 결과에 같이 들어가 모든 주소를 `index.html` 로 돌리고 검색 제외 · 액자 금지 헤더를 단다.

## 구조

| 폴더 | 내용 |
| --- | --- |
| `lib/theme/` | 웹 전용 토큰(앱 토큰 사본에서 시작, pen 웹 변수로 맞춤 — 앱과 따로 바뀐다) |
| `lib/widgets/` | pen `Web/` 컴포넌트와 1:1 부품(단추 · 코드 칸 · SideNav · TopBar · 관문 카드 · 칩 · 상태 배지 · 빈 목록 틀 · 대화상자) |
| `lib/auth/` · `lib/gate/` · `lib/router/` | 구글 로그인 → 2단계(TOTP) → `GET /admin/me` 관문과 go_router 가드 |
| `lib/api/` | 관리자 서버 클라이언트(Bearer 토큰 · JSON · 403 이유) |
| `lib/screens/` · `lib/shell/` | 관문 화면들 · 메뉴 틀과 자리 표시 화면 |
| `lib/heart_tasks/` | A3 인증샷 검수(`/heart-tasks`, 디스코드 링크 `/heart-tasks/{id}`) — 모델 · 컨트롤러 · 화면 · 사진 보기 |
