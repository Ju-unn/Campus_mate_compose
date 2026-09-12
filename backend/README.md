# backend

FastAPI 비즈니스 로직 서버 자리. 2026-09-12 확정(설계 문서 §1·§7)이지만
아직 시작하지 않았다 — 매칭/결제 조각(조각 4)에서 첫 엔드포인트가 붙는다.

담당 범위는 Supabase JWT 검증 후의 비즈니스 로직이다. Auth·DB·RLS·Storage 는 Supabase 가 계속 맡는다.

- 설계 근거: `../docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §7
- 미결: 호스팅 업체·플랜 (같은 문서 §13 미결38) — 조각 4 착수 전 확정 필요
