-- 조각 6: 지인(연락처) 차단. 이름은 기기에만 저장하고 서버에는 HMAC 만 둔다.
create table public.contact_blocks (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  contact_hmac bytea not null,
  -- 기기에 저장한 이름과 짝지을 키(ERD §5).
  id uuid not null default gen_random_uuid() unique,
  key_version smallint not null default 1,
  created_at timestamptz not null default now(),
  primary key (owner_id, contact_hmac)
);

comment on table public.contact_blocks is
  '지인(연락처) 차단. FastAPI 전용, 클라이언트 접근 없음 — 이름은 기기에만 있다';

-- 매칭 후보 대조용(상대 phone_hmac 과 맞춰 본다).
create index contact_blocks_contact_hmac_index on public.contact_blocks (contact_hmac);

alter table public.contact_blocks enable row level security;

revoke all on table public.contact_blocks from anon, authenticated, service_role;
grant select, insert, update, delete on table public.contact_blocks to service_role;

-- 신원 HMAC 칸. 키는 FastAPI 에만 있다(설계 §7.6b) — 채우기는 조각 6 서버(PR 3)의
-- set_phone_number 교체 + 한 번 쓰는 백필 스크립트. 유니크는 걸지 않는다
-- (2026-09-22 사용자 결정 "한 번호 한 계정 강제 안 함", ERD 검토 5).
-- authenticated 에는 grant 하지 않는다(profile_private 는 컬럼 단위 grant 라 새 칸은 자동으로 막힌다).
alter table public.profile_private
  add column phone_hmac bytea,
  add column phone_hmac_key_version smallint not null default 1;

-- 행마다 키 버전(2026-09-19 결정). 대조는 같은 버전끼리만.
alter table public.signup_blocks
  add column key_version smallint not null default 1;
