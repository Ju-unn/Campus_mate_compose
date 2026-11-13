-- email 방식으로 먼저 생긴 계정에 소셜(카카오 · 구글 · 애플)이 연결될 때도 pending 프로필을 만든다
-- (출시 전 점검 11-13). 시험: supabase/tests/social_login_test.sql 9번.
-- GoTrue 는 같은 메일의 소셜 로그인을 이미 있는 계정에 연결한다(새 auth.users 행이 없다). 가입 트리거
-- on_auth_user_created 는 insert 에만 걸려 있어, 학교 메일 인증번호용 임시 email 계정(프로필 없음)에 소셜이
-- 연결되면 그 계정은 프로필이 영영 생기지 않았다.
-- 연결 때 GoTrue 는 raw_app_meta_data 만 다시 쓴다. provider 는 처음 방식(email)으로 남고 providers 배열에
-- 소셜이 더해지므로 둘 다 본다. 소셜 집합은 서버 SOCIAL_PROVIDERS(backend/app/school_email/router.py)와 같다.
-- update 에서는 소셜이 "생긴" 순간(옛 값에 없고 새 값에 있음)에만 만든다 — GoTrue 는 소셜 로그인 때마다
-- raw_app_meta_data 를 다시 쓰므로 그때마다 profiles 에 넣어 보지 않게 한다. 프로필이 이미 있는 계정(10-08 전
-- 학교 메일 가입자)에 소셜이 연결돼도 on conflict 로 조용히 지나간다 — 여기서 오류가 나면 GoTrue 로그인이 깨진다.
-- insert 때 동작은 20261008010000 ⑤ 그대로다(email 방식이면 만들지 않고, 그 밖에는 학교 없는 pending).
-- 이미 굳은 계정 메우기는 넣지 않는다(운영 조회 0건).
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  social constant text[] := array['kakao', 'google', 'apple'];
begin
  if tg_op = 'UPDATE' then
    if not coalesce(new.raw_app_meta_data ->> 'provider' = any (social)
                    or new.raw_app_meta_data -> 'providers' ?| social, false)
       or coalesce(old.raw_app_meta_data ->> 'provider' = any (social)
                   or old.raw_app_meta_data -> 'providers' ?| social, false) then
      return new;
    end if;
  elsif new.raw_app_meta_data ->> 'provider' = 'email' then
    return new;
  end if;

  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

-- create or replace 라 앞선 revoke 가 남지만, security definer 를 다시 쓰는 파일이라 다시 적는다.
revoke execute on function public.handle_new_user_profile() from public, anon, authenticated;

-- auth 스키마 표에 거는 트리거라 Supabase 업그레이드 뒤 남아 있는지 다시 본다(on_auth_user_created 와 같다).
create trigger on_auth_user_social_linked
  after update of raw_app_meta_data on auth.users
  for each row execute function public.handle_new_user_profile();
