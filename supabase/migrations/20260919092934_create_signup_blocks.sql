-- 조각 1a: 재가입 제한 표. 쓰기(탈퇴 시 삽입)는 조각 6에서 채운다 — 이 조각은
-- Auth Hook 이 가입 시점에 읽기만 한다. 관계가 없는 독립 테이블이다(ERD.md §11-12).
create table public.signup_blocks (
  -- 원본 이메일을 남기지 않으려고 FastAPI 환경변수 키로 계산한 HMAC 만 저장한다.
  email_hmac bytea primary key,
  -- 탈퇴 요청 시각 + 2개월. 정지 중 탈퇴는 infinity 로 기간 없이 막는다(ERD.md §11-22).
  blocked_until timestamptz not null
);

comment on table public.signup_blocks is '탈퇴 후 재가입 제한. FastAPI Auth Hook 전용, 클라이언트 접근 없음';

-- RLS: 클라이언트는 존재 자체를 몰라도 된다. anon·authenticated 정책을 두지 않는다(default deny).
alter table public.signup_blocks enable row level security;

revoke all on table public.signup_blocks from anon, authenticated, service_role;
grant select, insert, update, delete on table public.signup_blocks to service_role;
