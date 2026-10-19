# backend

FastAPI 비즈니스 로직 서버. 2026-09-12 확정(설계 문서 §1·§7)이고 지금은 Cloud Run(서울)에서 운영 중이다
(2026-10-19 갱신, 옛 문장: "아직 시작하지 않았다"). 배포 · 환경변수 · 배치 · 롤백 하한은 `DEPLOY.md`, 모듈은 `app/` 아래 기능 폴더(`student_verification` · `graduate_verification` · `cards` · `chat` · `heart_tasks` · `admin` …)다.

담당 범위는 Supabase JWT 검증 후의 비즈니스 로직이다. Auth·DB·RLS·Storage 는 Supabase 가 계속 맡는다.

- 설계 근거: `../docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §7
- 미결: 호스팅 업체·플랜 (같은 문서 §13 미결37) — 조각 1 착수 전 확정 필요
