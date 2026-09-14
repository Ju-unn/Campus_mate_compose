-- 조각 1 RLS · 권한 회귀 검증. 기대값 기준은 docs/ERD.md §2 "사이클 B pgTAP 기대값의 기준".
-- 전 테이블 권한(ACL) 표 · 모든 테이블 RLS · storage.objects 정책 없음은 rls_slice0_test.sql 이 누적으로 본다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 로컬 Docker 스택이 생기기 전까지는 실행하지 않는다(2026-09-13 결정).
-- 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- 준비 (postgres) -------------------------------------------------------------
-- 사용자 A = ...aa, 사용자 B = ...bb, 테스트 대학 = ...01

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'rls-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000bb', 'rls-b@test.ac.kr');

insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

insert into public.profiles (id, university_id) values
  ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-000000000001');

insert into public.profile_private (profile_id, real_name) values
  ('00000000-0000-0000-0000-0000000000aa', '김가나'),
  ('00000000-0000-0000-0000-0000000000bb', '이다라');

-- 1. 학생증 인증 상태 · 버킷 (ERD §3 · §8 · §9) ------------------------------------

select enum_has_labels(
  'public', 'verification_status',
  array['none', 'pending', 'verified', 'rejected'],
  'verification_status 값은 none pending verified rejected 다'
);

select is(
  (select student_verification from public.profiles
    where id = '00000000-0000-0000-0000-0000000000aa'),
  'none'::public.verification_status,
  '새 프로필의 학생증 인증 상태는 none 이다'
);

select throws_ok(
  $$update public.profiles set student_verification = null
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23502', null,
  '학생증 인증 상태는 비울 수 없다'
);

select is(
  (select public from storage.buckets where id = 'student-id-temp'),
  false,
  'student-id-temp 버킷은 비공개다'
);

select ok(
  (select file_size_limit = 10485760 and allowed_mime_types = array['image/jpeg', 'image/png']
     from storage.buckets where id = 'student-id-temp'),
  'student-id-temp 버킷은 10MB · image/jpeg · image/png 로 제한된다'
);

select is(
  (select relrowsecurity from pg_class
    where oid = 'public.student_verification_attempts'::regclass),
  true,
  'student_verification_attempts 는 RLS 가 켜져 있다'
);

-- 2. authenticated (사용자 A) --------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000aa", "role": "authenticated"}';

select results_eq(
  $$select profile_id, real_name from public.profile_private$$,
  $$values ('00000000-0000-0000-0000-0000000000aa'::uuid, '김가나')$$,
  'A 는 profile_private 에서 본인 실명 1행만 본다'
);

select is_empty(
  $$select real_name from public.profile_private
     where profile_id = '00000000-0000-0000-0000-0000000000bb'$$,
  'A 는 남의 실명을 볼 수 없다'
);

-- 컬럼 grant 가 profile_id · real_name 뿐이라 updated_at(이후 조각의 민감 컬럼도)이 섞이면 막힌다.
select throws_ok(
  $$select * from public.profile_private$$,
  '42501', null,
  'A 도 profile_private 를 select * 로 읽을 수 없다'
);

select throws_ok(
  $$insert into public.profile_private (profile_id, real_name)
    values ('00000000-0000-0000-0000-0000000000aa', '박바꿈')$$,
  '42501', null,
  'A 도 profile_private 에 직접 insert 할 수 없다'
);

select throws_ok(
  $$update public.profile_private set real_name = '박바꿈'
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '42501', null,
  'A 도 본인 실명을 직접 update 할 수 없다'
);

select throws_ok(
  $$delete from public.profile_private
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '42501', null,
  'A 도 본인 profile_private 행을 직접 delete 할 수 없다'
);

select throws_ok(
  $$update public.profiles set student_verification = 'verified'
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '42501', null,
  'A 도 본인 학생증 인증 상태를 직접 바꿀 수 없다'
);

select throws_ok(
  $$select id from public.student_verification_attempts$$,
  '42501', null,
  'A 도 학생증 시도 기록을 읽을 수 없다(반려 사유는 FastAPI 가 내려준다)'
);

-- 3. anon (로그인 전) ---------------------------------------------------------

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select real_name from public.profile_private$$,
  '42501', null,
  'anon 은 profile_private 를 읽을 수 없다'
);

select throws_ok(
  $$insert into public.profile_private (profile_id, real_name)
    values ('00000000-0000-0000-0000-0000000000aa', '박바꿈')$$,
  '42501', null,
  'anon 은 profile_private 에 insert 할 수 없다'
);

select throws_ok(
  $$update public.profile_private set real_name = '박바꿈'$$,
  '42501', null,
  'anon 은 profile_private 를 update 할 수 없다'
);

select throws_ok(
  $$delete from public.profile_private$$,
  '42501', null,
  'anon 은 profile_private 를 delete 할 수 없다'
);

select throws_ok(
  $$select id from public.student_verification_attempts$$,
  '42501', null,
  'anon 은 학생증 시도 기록을 읽을 수 없다'
);

select throws_ok(
  $$insert into public.student_verification_attempts (profile_id, file_path)
    values ('00000000-0000-0000-0000-0000000000aa', 'aa/student-id.jpg')$$,
  '42501', null,
  'anon 은 학생증 시도 기록을 insert 할 수 없다'
);

-- 4. service_role (FastAPI) ----------------------------------------------------

set local role service_role;
reset request.jwt.claims;

select is(
  (select count(*) from public.profile_private),
  2::bigint,
  'service_role 은 profile_private 의 모든 행을 읽는다'
);

select lives_ok(
  $$update public.profile_private set real_name = '이라마', updated_at = now()
     where profile_id = '00000000-0000-0000-0000-0000000000bb'$$,
  'service_role 은 실명을 update 한다'
);

select lives_ok(
  $$delete from public.profile_private
     where profile_id = '00000000-0000-0000-0000-0000000000bb'$$,
  'service_role 은 profile_private 행을 delete 한다'
);

select lives_ok(
  $$insert into public.profile_private (profile_id, real_name)
    values ('00000000-0000-0000-0000-0000000000bb', '이다라')$$,
  'service_role 은 profile_private 행을 insert 한다'
);

select lives_ok(
  $$update public.profiles set student_verification = 'pending'
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  'service_role 은 학생증 인증 상태를 바꾼다'
);

select lives_ok(
  $$insert into public.student_verification_attempts (profile_id, file_path)
    values ('00000000-0000-0000-0000-0000000000aa', 'aa/student-id.jpg')$$,
  'service_role 은 학생증 시도 기록 1행을 insert 한다'
);

select throws_ok(
  $$insert into public.student_verification_attempts (profile_id, file_path, result)
    values ('00000000-0000-0000-0000-0000000000aa', 'aa/student-id.jpg', 'none')$$,
  '23514', null,
  '시도 기록의 결과는 none 일 수 없다'
);

-- 5. 탈퇴 cascade (postgres) ----------------------------------------------------

reset role;

delete from auth.users where id = '00000000-0000-0000-0000-0000000000aa';

select is_empty(
  $$select 1 from public.profile_private
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '계정을 지우면 profile_private 행도 지워진다'
);

select is_empty(
  $$select 1 from public.student_verification_attempts
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '계정을 지우면 학생증 시도 기록도 지워진다'
);

select * from finish();
rollback;
