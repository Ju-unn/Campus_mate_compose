-- 흡연 "상관없어요" 칸(2026-11-04 사용자 승인, 1.0.2 A6 · pen 06-1 `dFTqN`).
-- 06-1 이상형 조건의 "흡연하는 사람 [싫어요] [상관없어요]" 를 담는다. 참 = 상관없어요, 거짓 = 싫어요.
-- 값 없음 = 내 흡연 여부를 따른다(비흡연이면 싫어요, 흡연이면 상관없어요) — 지금 감점 규칙(scoring.py SMOKING_PENALTY)과 같아서
-- 기존 회원 · 이 칸을 모르는 옛 앱(1.0.0 · 1.0.1)은 결과가 바뀌지 않는다. 그래서 기본값도 백필도 없다.
-- 감점은 카드를 받는 사람 쪽 값만 보므로 match_candidates 는 바꾸지 않는다(서버가 owner 행에서 읽는다).
-- 읽기 권한은 표 권한 그대로다: authenticated 는 RLS 로 본인 행만, 쓰기는 service_role(FastAPI)만.
-- 배포 순서: 이 칸이 DB 에 먼저 있어야 한다 — 새 서버가 profiles 조회(fetch_owner · GET /me/profile)에 accepts_smoker 를 넣는다.
--
-- 되돌리기: 서버를 먼저 되돌린 뒤
--   alter table public.profiles drop column accepts_smoker;
alter table public.profiles add column accepts_smoker boolean;

comment on column public.profiles.accepts_smoker is
  '흡연하는 사람: true = 상관없어요, false = 싫어요, null = 내 흡연 여부를 따른다(is_smoker 거짓이면 싫어요)';
