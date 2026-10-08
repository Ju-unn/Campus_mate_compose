-- 소셜 로그인 ERD v6 ⑥ (사용자 결정 Q12 = B, 10-08): 소셜 제공자가 넣는 이름 · 사진을 auth 에 남기지 않는다.
-- 구글은 동의 화면에 openid 만 선언해도 토큰에 이름 · 사진을 싣고, GoTrue 가 그것을 auth.users.raw_user_meta_data 와
-- auth.identities.identity_data 에 저장한다(스파이크 10-08). 앱은 온보딩에서 받은 닉네임만 쓰고, 개인정보처리방침은
-- "이름 · 사진은 저장하지 않음" 이라 저장되기 전에 지운다. 시험: supabase/tests/social_login_test.sql
--
-- 지울 키를 나열하지 않고 남길 키만 적는다 — 제공자가 새 칸(given_name · locale · custom_claims 등)을 더해도 저절로 지워진다.
-- 남기는 키: email(계정 식별, auth.identities.email 생성 칸 · email_exists 판정이 쓴다), sub · provider_id · iss(제공자 계정
-- 식별), email_verified · phone_verified(GoTrue 가 쓰는 표시). 앱 · 서버 코드는 user_metadata 를 읽지 않는다(10-08 검색 0건).
--
-- BEFORE 트리거라 고친 NEW 가 그대로 저장된다 — 다시 UPDATE 하지 않으니 트리거가 자기를 또 부르는 일이 없다.
-- GoTrue 는 로그인마다 제공자 값으로 다시 덮어쓰므로 INSERT 와 그 칸의 UPDATE 를 둘 다 건다. 그 로그인의 응답 본문
-- user 에는 이름이 한 번 실려 갈 수 있다(저장은 안 된다) — 앱은 그 칸을 읽지 않는다.
-- 객체가 아닌 값(null 등)은 건드리지 않는다 — 여기서 오류가 나면 로그인 자체가 막힌다.
-- 표 접근이 없어 security invoker 다(supabase_auth_admin 권한으로 돈다). 트리거 함수의 실행 권한은 트리거를 만들 때만
-- 검사하므로 아래 revoke 뒤에도 GoTrue 쓰기에서 돈다(handle_new_user_profile 과 같다).
-- auth 스키마 표에 거는 트리거라 Supabase 업그레이드 뒤 남아 있는지 다시 본다(on_auth_user_created 와 같다).
create function public.scrub_social_identity_names()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  kept_keys constant text[] := array['email', 'sub', 'provider_id', 'iss', 'email_verified', 'phone_verified'];
begin
  if tg_table_name = 'users' then
    if jsonb_typeof(new.raw_user_meta_data) = 'object' then
      new.raw_user_meta_data := new.raw_user_meta_data
        - array(select k from jsonb_object_keys(new.raw_user_meta_data) k where k <> all (kept_keys));
    end if;
    return new;
  end if;

  if jsonb_typeof(new.identity_data) = 'object' then
    new.identity_data := new.identity_data
      - array(select k from jsonb_object_keys(new.identity_data) k where k <> all (kept_keys));
  end if;
  return new;
end;
$$;

comment on function public.scrub_social_identity_names() is
  '소셜 이름 · 사진 지우기(ERD v6 ⑥). auth.users.raw_user_meta_data · auth.identities.identity_data 에서 email · sub · provider_id · iss · email_verified · phone_verified 만 남긴다';

revoke execute on function public.scrub_social_identity_names() from public, anon, authenticated;

create trigger scrub_social_identity_names
  before insert or update of raw_user_meta_data on auth.users
  for each row execute function public.scrub_social_identity_names();

create trigger scrub_social_identity_names
  before insert or update of identity_data on auth.identities
  for each row execute function public.scrub_social_identity_names();
