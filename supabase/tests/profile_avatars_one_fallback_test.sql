-- 기본 아바타(5회 실패 보상) 행은 한 사람에 한 줄(20261018100000_profile_avatars_one_fallback, 10-18 보안 점검).
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

-- 준비 --------------------------------------------------------------------
-- A = ...f1, B = ...f2, 테스트 대학 = ...0f
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000f', '테스트대학교FB', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('testfb.ac.kr', '00000000-0000-0000-0000-00000000000f');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'fb-a@testfb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000f2', 'fb-b@testfb.ac.kr');

insert into public.profiles (id, university_id) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000000f'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-00000000000f')
on conflict (id) do nothing;

insert into public.profile_avatars (profile_id, storage_path, status, is_fallback)
values ('00000000-0000-0000-0000-0000000000f1', 'f1/fallback-1.png', 'ready', true);

-- 검사 --------------------------------------------------------------------
select has_index('public', 'profile_avatars', 'profile_avatars_one_fallback',
  '기본 아바타 부분 유일 인덱스가 있다');                                                                -- 1

select throws_ok(
  $$insert into public.profile_avatars (profile_id, storage_path, status, is_fallback)
    values ('00000000-0000-0000-0000-0000000000f1', 'f1/fallback-2.png', 'ready', true)$$,
  '23505', null,
  '같은 사람의 두 번째 기본 아바타 행은 23505 다(서버는 하트를 건너뛴다)'
);                                                                                                      -- 2

select lives_ok(
  $$insert into public.profile_avatars (profile_id, storage_path, status)
    values ('00000000-0000-0000-0000-0000000000f1', 'f1/regen-1.png', 'ready'),
           ('00000000-0000-0000-0000-0000000000f1', 'f1/regen-2.png', 'ready')$$,
  '보통 아바타(is_fallback=false) 행은 여럿이어도 된다(다시 만들기)'
);                                                                                                      -- 3

select lives_ok(
  $$insert into public.profile_avatars (profile_id, storage_path, status, is_fallback)
    values ('00000000-0000-0000-0000-0000000000f2', 'f2/fallback-1.png', 'ready', true)$$,
  '다른 사람의 기본 아바타 행은 막지 않는다'
);                                                                                                      -- 4

select * from finish();
rollback;
