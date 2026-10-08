-- 소셜 로그인 ERD v6 ⑦ · ⑧ · ⑩ (사용자 승인 10-08): 학교 메일 1개 = 계정 1개, 인증 전 계정 정리.
-- 학교 메일 인증(설계 §9-3, Q22 = B): 앱이 저장 안 하는 별도 GoTrue 클라이언트로 학교 메일 임시 계정(email 방식)을
-- 만들어 6자리 번호를 받는다 → FastAPI POST /school-email/verify 가 그 임시 토큰을 검사하고
-- complete_school_email_verification 을 부른 뒤 임시 계정을 지운다. 학교 메일 주소는 저장하지 않고 FastAPI 가 계산한
-- HMAC 만 둔다 — DB 에서 계산하면 키가 Postgres 에 들어온다(set_phone_number 와 같은 이유).
-- 시험: supabase/tests/social_login_test.sql

-- ⑦ 지금 그 학교 메일을 쓰는 계정. 탈퇴 뒤 재가입 제한은 signup_blocks 가 따로 맡는다 — 탈퇴 30일 뒤
--    auth.users 가 지워지면 이 행도 cascade 로 지워져 그 메일을 다시 쓸 수 있다.
create table public.school_email_claims (
  school_email_hmac bytea primary key,
  university_id uuid not null references public.universities (id) on delete restrict,
  -- 한 계정은 학교 메일을 하나만 가진다. 인증 뒤에는 바꾸지 못한다(설계 §9, ⑩ 의 already_verified).
  profile_id uuid not null unique references public.profiles (id) on delete cascade,
  -- 같은 메일로 다른 계정이 인증하려 하면 "카카오로 가입한 계정이 있어요" 처럼 이 값을 알려 준다.
  -- email = 소셜 로그인 전에 학교 메일 OTP 로 가입한 기존 계정(서버 백필 스크립트가 넣는다, 사용자 승인 10-08).
  provider text not null check (provider in ('kakao', 'google', 'apple', 'email')),
  -- 행마다 키 버전(2026-09-19 결정, signup_blocks · contact_blocks 와 같다). 대조는 같은 버전끼리만.
  key_version smallint not null default 1,
  verified_at timestamptz not null default now()
);

comment on table public.school_email_claims is
  '학교 메일 1개 = 계정 1개(HMAC 만). FastAPI 전용 — complete_school_email_verification 이 쓴다, 클라이언트 접근 없음';

-- FK 칸 인덱스 관례(profiles_university_id_index 와 같다). 학교를 지우려 할 때 restrict 검사가 표를 훑지 않는다.
create index school_email_claims_university_id_index on public.school_email_claims (university_id);

-- RLS: 정책 없음 = 클라이언트는 자기 행도 못 읽는다(signup_blocks 와 같다). 인증 여부는 FastAPI 가 내려준다.
alter table public.school_email_claims enable row level security;

revoke all on table public.school_email_claims from anon, authenticated, service_role;
grant select, insert, update, delete on table public.school_email_claims to service_role;

-- ⑧ 정리 배치용(사용자 결정 Q11 = B): 학교 메일 인증을 못 끝내고 p_older_than_days 일이 지난 계정, 오래된 순 p_limit 개.
--    지우는 것은 FastAPI 가 auth 관리자 API 로 한다 — 이 함수는 고르기만 한다. 지우는 일의 입력이라 잘못된 값은
--    오류로 막는다: 0 일이면 지금 인증 중인 사람까지, limit null 이면 인증 전 계정 전부가 한 번에 나간다.
--    email 방식 임시 계정은 프로필이 없어 여기 나오지 않는다(서버가 관리자 API 로 따로 고른다, ERD ⑪).
--    security invoker 다(SUPABASE.md §5) — 부르는 service_role 이 profiles select 권한을 가지고 RLS 를 우회한다.
create function public.list_unverified_accounts(p_older_than_days integer, p_limit integer default 100)
returns table (id uuid)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_older_than_days is null or p_older_than_days < 1 or p_limit is null or p_limit < 1 then
    raise exception 'list_unverified_accounts: p_older_than_days 와 p_limit 은 1 이상이어야 한다'
      using errcode = '22023';
  end if;

  return query
    select p.id
    from public.profiles p
    where p.school_email_verified_at is null
      and p.created_at < now() - make_interval(days => p_older_than_days)
    order by p.created_at
    limit p_limit;
end;
$$;

comment on function public.list_unverified_accounts(integer, integer) is
  '학교 메일 인증 전 + p_older_than_days 일 지난 프로필 id, 오래된 순 p_limit 개(기본 100). 정리 배치(FastAPI) 전용';

revoke all on function public.list_unverified_accounts(integer, integer) from public, anon, authenticated;
grant execute on function public.list_unverified_accounts(integer, integer) to service_role;

-- ⑩ 학교 메일 인증 완료를 한 트랜잭션에(claims 기록 + 프로필의 학교 · 인증 시각). FastAPI 가 임시 계정 토큰을 검사한 뒤 부른다.
--    동시 호출: 프로필 행을 for update 로 잠가 같은 계정의 두 호출을 줄 세운다. 서로 다른 두 계정이 같은 메일로 동시에
--    오면 PK 충돌을 on conflict do nothing 으로 받는다 — 먼저 넣은 쪽의 커밋을 기다렸다가 그쪽 가입 방식을 돌려준다.
--    가입 방식 검사는 표의 check 가 한다(함수에 같은 목록을 또 두지 않는다).
--    키 버전은 withdraw_account · set_phone_number 처럼 인자로 받는다 — 키를 바꿀 때 인자를 늘리면 옛 서버 호출이
--    깨져 drop/create 를 해야 하므로(20260927030000 머리말) 처음부터 기본값 1 로 둔다. HMAC 은 키마다 값이 달라
--    찾기는 HMAC 만으로 한다.
--    security invoker 다(SUPABASE.md §5) — 부르는 service_role 이 profiles(select · update, for update 는 update 권한)와
--    school_email_claims(select · insert, on conflict do nothing 은 insert 만) 권한을 가지고 RLS 를 우회한다.
create function public.complete_school_email_verification(
  p_profile uuid,
  p_email_hmac bytea,
  p_university uuid,
  p_provider text,
  p_key_version smallint default 1
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_verified_at timestamptz;
  v_owner uuid;
  v_owner_provider text;
begin
  select school_email_verified_at into v_verified_at
  from public.profiles
  where id = p_profile
  for update;

  if not found then
    return 'no_profile';
  end if;

  select profile_id, provider into v_owner, v_owner_provider
  from public.school_email_claims
  where school_email_hmac = p_email_hmac;

  if v_owner = p_profile then
    return 'ok';
  end if;
  if v_owner is not null then
    return v_owner_provider;
  end if;

  -- 기존 가입자(⑨ 백필)는 인증 시각만 있고 claims 행이 아직 없을 수 있다. 반대로 claims 행만 남은 경우도 인증된 계정으로
  -- 본다 — 그대로 넣으면 profile_id unique 위반(23505)으로 끝난다.
  if v_verified_at is not null
     or exists (select 1 from public.school_email_claims where profile_id = p_profile) then
    return 'already_verified';
  end if;

  insert into public.school_email_claims (school_email_hmac, university_id, profile_id, provider, key_version)
  values (p_email_hmac, p_university, p_profile, p_provider, p_key_version)
  on conflict (school_email_hmac) do nothing;

  if not found then
    select provider into v_owner_provider
    from public.school_email_claims
    where school_email_hmac = p_email_hmac;
    return v_owner_provider;
  end if;

  update public.profiles
  set university_id = p_university, school_email_verified_at = now()
  where id = p_profile;

  return 'ok';
end;
$$;

comment on function public.complete_school_email_verification(uuid, bytea, uuid, text, smallint) is
  '학교 메일 인증 완료(ERD v6 ⑩). FastAPI 전용. 돌려주는 값: '
  'ok = 기록함(같은 계정 · 같은 메일로 다시 불러도 ok, 멱등) / '
  'kakao | google | apple | email = 그 메일을 다른 계정이 쓰고 있다, 그 계정의 가입 방식'
  '(email = 소셜 로그인 전 학교 메일로 가입한 기존 계정, 아무것도 안 바꿈) / '
  'already_verified = 이 계정은 이미 다른 학교 메일로 인증함, 인증 뒤 변경 금지(아무것도 안 바꿈) / '
  'no_profile = 프로필 없음(임시 email 계정 id 를 넘겼거나 지워진 계정). '
  '가입 방식이 넷 밖이면 23514 오류. p_key_version 기본 1';

revoke all on function public.complete_school_email_verification(uuid, bytea, uuid, text, smallint) from public, anon, authenticated;
grant execute on function public.complete_school_email_verification(uuid, bytea, uuid, text, smallint) to service_role;
