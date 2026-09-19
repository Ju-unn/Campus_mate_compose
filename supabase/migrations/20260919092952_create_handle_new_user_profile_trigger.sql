-- 조각 1a: auth.users INSERT 뒤 profiles pending 행을 만드는 트리거.
-- Before User Created 훅(FastAPI)은 auth.users 커밋 전에 불려 FK 를 못 지키므로
-- 이 트리거가 대신 만든다(2026-09-18 리뷰, 표준 Supabase 패턴).
-- 도메인을 못 찾는 경우는 Auth Hook 이 이미 거부했어야 하므로 방어적으로만 막는다.
create function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  matched_university_id uuid;
begin
  select university_id into matched_university_id
    from public.university_email_domains
    where domain = lower(split_part(new.email, '@', 2));

  if matched_university_id is null then
    raise exception 'no matching university domain for %', new.email;
  end if;

  insert into public.profiles (id, university_id) values (new.id, matched_university_id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user_profile();
