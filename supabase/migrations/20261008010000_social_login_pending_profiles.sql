-- 소셜 로그인(카카오 · 구글 · 애플) ERD v6 ① ~ ⑤ · ⑨ (사용자 승인 10-08). 시험: supabase/tests/social_login_test.sql
-- 소셜 계정은 가입 순간에 학교 메일이 없다. 학교 메일은 가입 뒤 한 번 인증하고, 그때 학교가 정해진다
-- (complete_school_email_verification, 20261008030000). 그래서 프로필이 학교 없이 먼저 생긴다.
-- GoTrue 는 소셜 가입 순간 auth.users.email_confirmed_at 을 채운다(스파이크 10-08) — 학교 메일 증거로 쓰지 않고
-- 아래 새 칸만 본다.

-- ① 학교는 학교 메일 인증 전까지 비어 있다. 이 칸을 읽는 SQL(match_candidates · card_issue_owners ·
--    region_active_counts · home_stats)은 universities 와 inner join 하거나 `=` 로 비교하므로 null 이면 그 사람이
--    빠진다 — 인증 전 사람은 후보 · 카드 · 사다리 인원 · 학교 목록에 끼지 않는다. 이 칸을 쓰는 RLS 정책은 없다
--    (모든 정책이 (select auth.uid()) = 본인 칸 꼴).
-- ② null = 학교 메일 인증 전. 정리 배치가 null 인 채 14일이 지난 계정을 지운다(list_unverified_accounts).
-- ③ 인증 시각과 학교는 ⑩ 이 한 문장으로 같이 쓴다. 대시보드에서 한쪽만 고쳐 "인증했는데 학교 없음" 이 되면
--    관문은 통과하는데 매칭에서는 조용히 빠지고, 학교 이름을 읽는 서버 응답이 깨진다 — 그 반쪽 상태를 막는다.
alter table public.profiles
  alter column university_id drop not null,
  add column school_email_verified_at timestamptz,
  add constraint profiles_verified_requires_university
    check (school_email_verified_at is null or university_id is not null);

comment on column public.profiles.university_id is
  '학교. 학교 메일 인증(complete_school_email_verification)이 정한다. null = 학교 메일 인증 전';
comment on column public.profiles.school_email_verified_at is
  '학교 메일 인증 시각. null = 인증 전(14일 뒤 정리 배치가 지운다). 소셜 가입 때 채워지는 auth.users.email_confirmed_at 과 다르다';

-- ④ 정리 배치가 "인증 전 + 오래된 순" 으로 읽는다. 인증 전은 가입 직후 잠깐뿐이라 전체 프로필보다 훨씬 적다 —
--    그 행만 담는 부분 인덱스.
create index idx_profiles_unverified_created_at
  on public.profiles (created_at)
  where school_email_verified_at is null;

-- ⑨ 기존 계정 보정. 이 파일 전까지는 학교 메일 OTP 로만 가입할 수 있었고 트리거가 도메인으로 학교를 정했다 —
--    지금 있는 프로필은 모두 학교 메일을 인증한 사람이다. 비워 두면 14일 뒤 정리 배치가 전원을 지운다.
--    칸을 더한 이 파일에서 같이 채운다 — 파일을 나눠 따로 적용하면 그 사이 서버 관문이 기존 사용자를 막는다.
--    학교가 없는 행은 이 뒤에 생긴 소셜 계정이라 건드리지 않는다.
--    기존 사용자의 school_email_claims 행은 SQL 로 못 채운다(HMAC 키가 FastAPI 에만 있다) — 서버 백필 스크립트 몫이다
--    (phone_hmac 백필과 같은 방식, 이 PR 밖). 채우기 전에는 기존 학교 메일로 새 소셜 계정이 인증될 수 있다.
update public.profiles
set school_email_verified_at = created_at
where school_email_verified_at is null
  and university_id is not null;

-- ⑤ 가입 트리거는 학교를 정하지 않는다. 학교 확인 길을 ⑩ 하나로 둔다 — 학교 도메인 구글 계정에 여기서 학교를
--    채우면 school_email_claims 에 그 메일이 안 남아 "학교 메일 1개 = 계정 1개" 가 깨진다.
--    도메인이 없어도 오류를 내지 않는다 — 카카오는 메일이 없고, 구글 · 애플 메일은 학교 메일이 아닐 수 있다.
--    email 방식 계정은 학교 메일 인증번호를 받으려고 앱이 잠깐 만드는 임시 계정이다 — 프로필을 만들지 않는다
--    (FastAPI 가 인증 뒤 지우고, 남으면 하루 뒤 배치가 지운다). provider 는 GoTrue 가 쓰는 app_metadata 라
--    사용자가 바꾸지 못한다. provider 가 없는 행(pgTAP 의 auth.users 직접 insert)은 소셜과 같이 다룬다.
-- create or replace 라 20260919095306 의 execute revoke 가 남지만, security definer 를 다시 쓰는 파일이라 다시 적는다.
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.raw_app_meta_data ->> 'provider' = 'email' then
    return new;
  end if;

  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

revoke execute on function public.handle_new_user_profile() from public, anon, authenticated;
