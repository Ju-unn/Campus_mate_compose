-- 조각 2 RLS · 권한 회귀 검증. 기대값 기준은 docs/ERD.md §2 "사이클 B pgTAP 기대값의 기준".
-- 전 테이블 권한(ACL) 표 · 모든 테이블 RLS · storage.objects 정책 없음은 rls_slice0_test.sql 이 누적으로 본다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 로컬 Docker 스택이 생기기 전까지는 실행하지 않는다(2026-09-13 결정).
-- 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

-- 준비 (postgres) -------------------------------------------------------------
-- 사용자 A = ...aa, 사용자 B = ...bb, 테스트 대학 = ...01

-- on_auth_user_created 트리거(조각 1a, handle_new_user_profile)가 auth.users insert 직후 도메인으로
-- university_email_domains 를 찾으므로, 그 행이 auth.users 보다 먼저 있어야 한다(조각1 리뷰 관례).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test.ac.kr', '00000000-0000-0000-0000-000000000001');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'rls2-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000bb', 'rls2-b@test.ac.kr');

-- 위 auth.users insert 때 트리거가 이미 pending 행 2개를 만들어 뒀다.
insert into public.profiles (id, university_id) values
  ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

-- 1. 구조 검증 (postgres, RLS 우회) ------------------------------------------

select throws_ok(
  $$update public.profiles
     set preferred_animal_types = array['dog', 'cat', 'fox', 'bear']::public.animal_type[]
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23514', null,
  'preferred_animal_types 는 3개를 넘을 수 없다'
);

select throws_ok(
  $$update public.profiles
     set preferred_impression_types = array['arab', 'tofu', 'kind', 'chic']::public.impression_type[]
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23514', null,
  'preferred_impression_types 는 3개를 넘을 수 없다'
);

select throws_ok(
  $$update public.profiles
     set my_traits = array['a', 'b', 'c', 'd', 'e', 'f']
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23514', null,
  'my_traits 는 5개를 넘을 수 없다'
);

select throws_ok(
  $$update public.profiles
     set ideal_traits = array['a', 'b', 'c', 'd', 'e', 'f']
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23514', null,
  'ideal_traits 는 5개를 넘을 수 없다'
);

select throws_ok(
  $$select looking_for from public.profiles limit 1$$,
  '42703', null,
  'looking_for 컬럼은 더 이상 존재하지 않는다'
);

select is(
  (select relrowsecurity from pg_class where oid = 'public.profile_avatars'::regclass),
  true,
  'profile_avatars 는 RLS 가 켜져 있다'
);

select is(
  (select relrowsecurity from pg_class where oid = 'public.survey_answers'::regclass),
  true,
  'survey_answers 는 RLS 가 켜져 있다'
);

select is(
  (select relrowsecurity from pg_class where oid = 'public.entitlements'::regclass),
  true,
  'entitlements 는 RLS 가 켜져 있다'
);

select is(
  (select relrowsecurity from pg_class where oid = 'public.heart_transactions'::regclass),
  true,
  'heart_transactions 는 RLS 가 켜져 있다'
);

select is(
  (select public from storage.buckets where id = 'avatars'),
  true,
  'avatars 버킷은 공개다'
);

select is(
  (select public from storage.buckets where id = 'profile-photos'),
  false,
  'profile-photos 버킷은 비공개다'
);

select is(
  (select count(*) from pg_proc
     where pronamespace = 'public'::regnamespace
       and proname in ('decrypt_phone_number', 'set_phone_number', 'grant_hearts')
       and proconfig is not null
       and exists (select 1 from unnest(proconfig) cfg where cfg like 'search_path=%')),
  3::bigint,
  'decrypt_phone_number·set_phone_number·grant_hearts 는 search_path 가 고정돼 있다(advisor WARN 조치)'
);

-- 각 테이블에 A·B 한 행씩 준비한다(RLS 우회 상태에서).
insert into public.profile_avatars (profile_id, storage_path, status) values
  ('00000000-0000-0000-0000-0000000000aa', 'avatars/aa/1.png', 'ready'),
  ('00000000-0000-0000-0000-0000000000bb', 'avatars/bb/1.png', 'ready');

insert into public.survey_answers (profile_id, axis, value) values
  ('00000000-0000-0000-0000-0000000000aa', 1, 0.5),
  ('00000000-0000-0000-0000-0000000000bb', 1, -0.5);

insert into public.entitlements (profile_id, heart_balance) values
  ('00000000-0000-0000-0000-0000000000aa', 0),
  ('00000000-0000-0000-0000-0000000000bb', 0);

insert into public.heart_transactions (profile_id, amount, reason) values
  ('00000000-0000-0000-0000-0000000000aa', 10, 'admin_adjust'),
  ('00000000-0000-0000-0000-0000000000bb', 10, 'admin_adjust');

-- 2. authenticated (사용자 A) --------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000aa", "role": "authenticated"}';

select results_eq(
  $$select profile_id from public.profile_avatars$$,
  $$values ('00000000-0000-0000-0000-0000000000aa'::uuid)$$,
  'A 는 본인 아바타 행만 본다'
);

select is_empty(
  $$select 1 from public.profile_avatars
     where profile_id = '00000000-0000-0000-0000-0000000000bb'$$,
  'A 는 남의 아바타 행을 볼 수 없다'
);

select throws_ok(
  $$insert into public.profile_avatars (profile_id, storage_path)
    values ('00000000-0000-0000-0000-0000000000aa', 'avatars/aa/2.png')$$,
  '42501', null,
  'A 도 profile_avatars 에 직접 insert 할 수 없다'
);

select throws_ok(
  $$update public.profile_avatars set status = 'failed'
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '42501', null,
  'A 도 본인 아바타 행을 직접 update 할 수 없다'
);

select throws_ok(
  $$delete from public.profile_avatars
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '42501', null,
  'A 도 본인 아바타 행을 직접 delete 할 수 없다'
);

select results_eq(
  $$select profile_id from public.survey_answers$$,
  $$values ('00000000-0000-0000-0000-0000000000aa'::uuid)$$,
  'A 는 본인 설문 답변만 본다'
);

select is_empty(
  $$select 1 from public.survey_answers
     where profile_id = '00000000-0000-0000-0000-0000000000bb'$$,
  'A 는 남의 설문 답변을 볼 수 없다'
);

select results_eq(
  $$select profile_id from public.entitlements$$,
  $$values ('00000000-0000-0000-0000-0000000000aa'::uuid)$$,
  'A 는 본인 하트 잔액만 본다'
);

select is_empty(
  $$select 1 from public.entitlements
     where profile_id = '00000000-0000-0000-0000-0000000000bb'$$,
  'A 는 남의 하트 잔액을 볼 수 없다'
);

select results_eq(
  $$select profile_id from public.heart_transactions$$,
  $$values ('00000000-0000-0000-0000-0000000000aa'::uuid)$$,
  'A 는 본인 하트 내역만 본다'
);

select is_empty(
  $$select 1 from public.heart_transactions
     where profile_id = '00000000-0000-0000-0000-0000000000bb'$$,
  'A 는 남의 하트 내역을 볼 수 없다'
);

-- 3. anon (로그인 전) ---------------------------------------------------------

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select profile_id from public.profile_avatars$$,
  '42501', null,
  'anon 은 profile_avatars 를 읽을 수 없다'
);

select throws_ok(
  $$insert into public.profile_avatars (profile_id, storage_path)
    values ('00000000-0000-0000-0000-0000000000aa', 'avatars/aa/3.png')$$,
  '42501', null,
  'anon 은 profile_avatars 에 insert 할 수 없다'
);

select throws_ok(
  $$select profile_id from public.survey_answers$$,
  '42501', null,
  'anon 은 survey_answers 를 읽을 수 없다'
);

select throws_ok(
  $$select profile_id from public.entitlements$$,
  '42501', null,
  'anon 은 entitlements 를 읽을 수 없다'
);

select throws_ok(
  $$select profile_id from public.heart_transactions$$,
  '42501', null,
  'anon 은 heart_transactions 를 읽을 수 없다'
);

-- 4. service_role (FastAPI) ----------------------------------------------------

set local role service_role;
reset request.jwt.claims;

select is(
  (select count(*) from public.profile_avatars),
  2::bigint,
  'service_role 은 profile_avatars 의 모든 행을 읽는다'
);

select lives_ok(
  $$insert into public.profile_photos (profile_id, storage_path, position, is_avatar_source)
    values ('00000000-0000-0000-0000-0000000000aa', 'aa/photo1.jpg', 0, true)$$,
  'service_role 은 아바타 원본 사진 1장을 지정한다'
);

select throws_ok(
  $$insert into public.profile_photos (profile_id, storage_path, position, is_avatar_source)
    values ('00000000-0000-0000-0000-0000000000aa', 'aa/photo2.jpg', 1, true)$$,
  '23505', null,
  '같은 프로필에 아바타 원본 사진을 2장 지정할 수 없다'
);

select throws_ok(
  $$insert into public.survey_answers (profile_id, axis, value)
    values ('00000000-0000-0000-0000-0000000000aa', 2, 0.3)$$,
  '23514', null,
  '설문 답변 값은 5점 척도 밖일 수 없다'
);

select lives_ok(
  $$update public.entitlements set heart_balance = 10, updated_at = now()
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  'service_role 은 하트 잔액을 update 한다'
);

select lives_ok(
  $$insert into public.heart_transactions (profile_id, amount, reason)
    values ('00000000-0000-0000-0000-0000000000aa', -5, 'avatar_regen')$$,
  'service_role 은 하트 내역을 insert 한다'
);

-- 5. 탈퇴 cascade (postgres) ----------------------------------------------------

reset role;

delete from auth.users where id = '00000000-0000-0000-0000-0000000000aa';

select is_empty(
  $$select 1 from public.profile_avatars
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '계정을 지우면 profile_avatars 행도 지워진다'
);

select is_empty(
  $$select 1 from public.survey_answers
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '계정을 지우면 survey_answers 행도 지워진다'
);

select is_empty(
  $$select 1 from public.entitlements
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '계정을 지우면 entitlements 행도 지워진다'
);

select is_empty(
  $$select 1 from public.heart_transactions
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '계정을 지우면 heart_transactions 행도 지워진다'
);

select * from finish();
rollback;
