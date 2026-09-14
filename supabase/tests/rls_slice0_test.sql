-- 조각 0 RLS · 권한 회귀 검증. 기대값 기준은 docs/ERD.md §2 "사이클 B pgTAP 기대값의 기준".
-- RLS 는 틀려도 앱이 정상 동작하므로 남의 행과 클라이언트 쓰기가 실제로 막히는지 여기서 증명한다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 로컬 Docker 스택이 생기기 전까지는 실행하지 않는다(2026-09-13 결정).
-- 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- 준비 (postgres) -------------------------------------------------------------
-- 사용자 A = ...aa, 사용자 B = ...bb, 테스트 대학 = ...01

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'rls-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000bb', 'rls-b@test.ac.kr');

insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test.ac.kr', '00000000-0000-0000-0000-000000000001');

-- 1. profiles 제약 (ERD §3) ------------------------------------------------------

select lives_ok(
  $$insert into public.profiles (id, university_id) values
      ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000001'),
      ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-000000000001')$$,
  '온보딩 컬럼이 비어 있는 pending 프로필은 만들 수 있다'
);

select throws_ok(
  $$update public.profiles set status = 'active'
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23514', null,
  '필수값 없이 active 로 바꾸면 check 위반이다'
);

select lives_ok(
  $$update public.profiles
       set nickname = '가나', gender = 'male', looking_for = 'female',
           birth_year = 2002, height_cm = 178, status = 'active'
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '필수값을 채우면 active 로 바꿀 수 있다'
);

update public.profiles set nickname = 'Abc'
 where id = '00000000-0000-0000-0000-0000000000bb';

select throws_ok(
  $$update public.profiles set nickname = 'aBC'
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23505', null,
  '대소문자만 다른 닉네임은 쓸 수 없다'
);

insert into public.profile_photos (profile_id, storage_path, position) values
  ('00000000-0000-0000-0000-0000000000aa', 'aa/0.jpg', 0),
  ('00000000-0000-0000-0000-0000000000aa', 'aa/1.jpg', 1),
  ('00000000-0000-0000-0000-0000000000bb', 'bb/0.jpg', 0);

-- 2. RLS · 권한 · Storage 의 모양 (ERD §2 · §9) -----------------------------------

select is_empty(
  $$select relname from pg_class
     where relnamespace = 'public'::regnamespace
       and relkind in ('r', 'p')
       and not relrowsecurity$$,
  'public 의 모든 테이블은 RLS 가 켜져 있다'
);

-- 표에 없는 권한(특히 anon · authenticated 의 insert · update · delete)이 붙거나
-- service_role 의 select · insert · update · delete 가 하나라도 빠지면 여기서 깨진다.
-- 테이블 단위(relacl)와 컬럼 단위(attacl, "테이블.컬럼" 으로 표시), PUBLIC 에 준 권한까지 본다.
-- 모든 테이블의 anon · authenticated 쓰기 42501 은 이 검사로 보장하고, 아래 3 · 4 에서 대표로 확인한다.
-- 테이블이나 컬럼 grant 를 추가하면 이 기대값도 ERD §2 표대로 함께 고친다.
-- `supabase test db` 는 모든 조각의 마이그레이션이 올라간 DB 에서 도므로 조각 1 의 profile_private 도 여기 들어간다.
select results_eq(
  $$select g.object_name, g.grantee, g.privilege_type
      from (
        select c.relname::text as object_name,
               coalesce(r.rolname::text, 'PUBLIC') as grantee,
               a.privilege_type::text as privilege_type
          from pg_class c
          cross join lateral aclexplode(c.relacl) a
          left join pg_roles r on r.oid = a.grantee
         where c.relnamespace = 'public'::regnamespace
           and c.relkind in ('r', 'p')
        union all
        select c.relname::text || '.' || att.attname::text,
               coalesce(r.rolname::text, 'PUBLIC'),
               a.privilege_type::text
          from pg_class c
          join pg_attribute att on att.attrelid = c.oid and att.attnum > 0 and not att.attisdropped
          cross join lateral aclexplode(att.attacl) a
          left join pg_roles r on r.oid = a.grantee
         where c.relnamespace = 'public'::regnamespace
           and c.relkind in ('r', 'p')
      ) g
     where g.grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')
     order by g.object_name collate "C", g.grantee collate "C", g.privilege_type collate "C"$$,
  $$values
      ('profile_photos', 'authenticated', 'SELECT'),
      ('profile_photos', 'service_role', 'DELETE'),
      ('profile_photos', 'service_role', 'INSERT'),
      ('profile_photos', 'service_role', 'SELECT'),
      ('profile_photos', 'service_role', 'UPDATE'),
      ('profile_private', 'service_role', 'DELETE'),
      ('profile_private', 'service_role', 'INSERT'),
      ('profile_private', 'service_role', 'SELECT'),
      ('profile_private', 'service_role', 'UPDATE'),
      ('profile_private.profile_id', 'authenticated', 'SELECT'),
      ('profile_private.real_name', 'authenticated', 'SELECT'),
      ('profiles', 'authenticated', 'SELECT'),
      ('profiles', 'service_role', 'DELETE'),
      ('profiles', 'service_role', 'INSERT'),
      ('profiles', 'service_role', 'SELECT'),
      ('profiles', 'service_role', 'UPDATE'),
      ('universities', 'anon', 'SELECT'),
      ('universities', 'authenticated', 'SELECT'),
      ('universities', 'service_role', 'DELETE'),
      ('universities', 'service_role', 'INSERT'),
      ('universities', 'service_role', 'SELECT'),
      ('universities', 'service_role', 'UPDATE'),
      ('university_email_domains', 'anon', 'SELECT'),
      ('university_email_domains', 'authenticated', 'SELECT'),
      ('university_email_domains', 'service_role', 'DELETE'),
      ('university_email_domains', 'service_role', 'INSERT'),
      ('university_email_domains', 'service_role', 'SELECT'),
      ('university_email_domains', 'service_role', 'UPDATE')$$,
  'anon · authenticated · service_role 권한은 ERD §2 표대로다'
);

-- 사진 업로드 · 조회는 서명 URL 로만 한다. 버킷이 늘어도 storage.objects 정책은 두지 않는다(ERD §9).
select is(
  (select public from storage.buckets where id = 'profile-photos'),
  false,
  'profile-photos 버킷은 비공개다'
);

select is_empty(
  $$select policyname from pg_policies
     where schemaname = 'storage'
       and tablename = 'objects'$$,
  'storage.objects 에는 정책이 없다'
);

-- 3. authenticated (사용자 A) --------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000aa", "role": "authenticated"}';

select results_eq(
  $$select id from public.profiles$$,
  $$values ('00000000-0000-0000-0000-0000000000aa'::uuid)$$,
  'A 는 profiles 에서 본인 행만 본다'
);

select results_eq(
  $$select storage_path from public.profile_photos order by position$$,
  $$values ('aa/0.jpg'), ('aa/1.jpg')$$,
  'A 는 profile_photos 에서 본인 사진만 본다'
);

select isnt_empty(
  $$select 1 from public.universities$$,
  'authenticated 는 학교 목록을 읽는다'
);

select throws_ok(
  $$insert into public.profile_photos (profile_id, storage_path, position)
    values ('00000000-0000-0000-0000-0000000000aa', 'aa/2.jpg', 2)$$,
  '42501', null,
  'A 도 본인 사진 행을 직접 insert 할 수 없다'
);

select throws_ok(
  $$update public.profiles set status = 'suspended'
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '42501', null,
  'A 도 본인 프로필을 직접 update 할 수 없다 (status 우회 차단)'
);

select throws_ok(
  $$delete from public.profile_photos
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '42501', null,
  'A 도 본인 사진 행을 직접 delete 할 수 없다'
);

-- 4. anon (로그인 전) ---------------------------------------------------------

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select isnt_empty(
  $$select 1 from public.universities$$,
  'anon 은 학교 목록을 읽는다'
);

select isnt_empty(
  $$select 1 from public.university_email_domains$$,
  'anon 은 메일 도메인을 읽는다'
);

select throws_ok(
  $$select 1 from public.profiles$$,
  '42501', null,
  'anon 은 profiles 를 읽을 수 없다'
);

select throws_ok(
  $$select 1 from public.profile_photos$$,
  '42501', null,
  'anon 은 profile_photos 를 읽을 수 없다'
);

select throws_ok(
  $$insert into public.university_email_domains (domain, university_id)
    values ('evil.ac.kr', '00000000-0000-0000-0000-000000000001')$$,
  '42501', null,
  'anon 은 메일 도메인 화이트리스트에 쓸 수 없다'
);

-- 5. 탈퇴 cascade (postgres) ----------------------------------------------------

reset role;

delete from auth.users where id = '00000000-0000-0000-0000-0000000000aa';

select is_empty(
  $$select 1 from public.profiles where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '계정을 지우면 프로필도 지워진다'
);

-- Storage 파일은 cascade 로 지워지지 않는다. 파일 삭제는 FastAPI 몫이다(ERD §3).
select is_empty(
  $$select 1 from public.profile_photos where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '계정을 지우면 사진 행도 지워진다'
);

select * from finish();
rollback;
