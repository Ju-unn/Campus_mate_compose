-- 조각 1 스키마 2/5: 민감 정보 분리 테이블. 조각 1 에는 실명만 담는다.
-- 기준 문서: docs/ERD.md §2 · §3 · §11-2
-- 초안(2026-09-14, 미적용). phone_number · kakao_id 는 조각 2, phone_hmac 은 조각 6 에서 추가한다.

create table public.profile_private (
  -- 3b 에서 만든다. profiles 행은 이메일 인증 직후 FastAPI 가 먼저 만들어 둔다.
  -- 계정을 지워 profiles 가 cascade 로 지워지면 이 행도 지워진다(탈퇴 30일 뒤, ERD §11-19).
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  -- 민감. 3b 에서 사용자가 입력하고 학생증 이미지와 대조한다. 본인만 16e 에서 조회하고 남에게 가는 응답에는 담지 않는다.
  real_name text,
  -- FastAPI 가 쓸 때 함께 갱신한다.
  updated_at timestamptz not null default now()
);

comment on table public.profile_private is '민감 정보. 본인은 실명만 읽고, 나머지 컬럼은 FastAPI 만 다룬다';

-- RLS: 본인 행 읽기만. 쓰기는 FastAPI 가 한다(ERD §2).
alter table public.profile_private enable row level security;

create policy "profile private is readable by owner"
  on public.profile_private
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

-- 권한(ERD §2): anon 은 없음, authenticated 는 profile_id · real_name 컬럼 select 만, service_role 은 select·insert·update·delete.
-- RLS 는 컬럼을 가리지 못하므로 컬럼 grant 로 뺀다. 앱은 select * 대신 컬럼을 지정해야 한다(select * 는 42501).
-- 이후 조각에서 컬럼을 추가해도 authenticated 에는 grant 하지 않는다. 본인 kakao_id 도 FastAPI 가 내려준다(ERD §11-20).
revoke all on table public.profile_private from anon, authenticated, service_role;
grant select (profile_id, real_name) on table public.profile_private to authenticated;
grant select, insert, update, delete on table public.profile_private to service_role;
