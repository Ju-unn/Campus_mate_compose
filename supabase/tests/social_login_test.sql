-- 소셜 로그인 DB(ERD v6 ①~⑩, 사용자 승인 10-08) 검증.
-- 마이그레이션 20261008010000_social_login_pending_profiles · 20261008020000_scrub_social_identity_names ·
-- 20261008030000_create_school_email_claims.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(66);

-- 0. ⑨ 기존 계정 보정 ---------------------------------------------------------
-- 이 파일이 데이터를 넣기 전에 본다. 빈 DB(db reset)에서는 0행이라 늘 참이고, 기존 프로필이 있는 DB 위에
-- 마이그레이션을 올렸을 때 의미가 있다 — 운영 적용 직후에도 같은 조회로 0 인지 다시 본다.
select is(
  (select count(*) from public.profiles
    where university_id is not null and school_email_verified_at is null),
  0::bigint,
  '학교가 정해진 프로필은 모두 학교 메일 인증 시각이 있다(⑨ 백필)'
);                                                                                                   -- 1

-- 준비 (postgres) -------------------------------------------------------------
-- 학교 = ...5a00. K1 = 카카오(메일 없음), G1 = 구글(학교 도메인 메일 · 이름 · 사진), G2 = 구글(학교 아닌 메일),
-- E1 = 학교 메일 인증번호용 임시 email 계정, N1 = provider 없는 행(다른 시험 파일의 준비 방식),
-- L = 기존 학교 메일 가입자(⑨ 백필 뒤 모양: 학교 · 인증 시각은 있고 claims 행은 아직 없음).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000005a00', '소셜테스트대학교', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('social-test.ac.kr', '00000000-0000-0000-0000-000000005a00');

insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000005a01', null,
   '{"provider": "kakao", "providers": ["kakao"]}',
   '{"iss": "https://kauth.kakao.com", "sub": "kakao-sub-1", "provider_id": "kakao-sub-1",
     "email_verified": false, "phone_verified": false}'),
  ('00000000-0000-0000-0000-000000005a02', 'g1@social-test.ac.kr',
   '{"provider": "google", "providers": ["google"]}',
   '{"iss": "https://accounts.google.com", "sub": "google-sub-1", "provider_id": "google-sub-1",
     "email": "g1@social-test.ac.kr", "email_verified": true, "phone_verified": false,
     "name": "테스트이름", "full_name": "테스트이름", "given_name": "이름", "family_name": "테스트",
     "picture": "https://example.invalid/p.jpg", "avatar_url": "https://example.invalid/p.jpg",
     "preferred_username": "tester", "user_name": "tester", "custom_claims": {"hd": "social-test.ac.kr"}}'),
  ('00000000-0000-0000-0000-000000005a04', 'e1@social-test.ac.kr',
   '{"provider": "email", "providers": ["email"]}',
   '{"sub": "00000000-0000-0000-0000-000000005a04", "email": "e1@social-test.ac.kr",
     "email_verified": false, "phone_verified": false}');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000005a05', 'n1@social-test.ac.kr'),
  ('00000000-0000-0000-0000-000000005a06', 'legacy@social-test.ac.kr');

update public.profiles
set university_id = '00000000-0000-0000-0000-000000005a00', school_email_verified_at = created_at
where id = '00000000-0000-0000-0000-000000005a06';

-- 1. 칸 · 제약 · 인덱스 (①②③④) ------------------------------------------------

select col_is_null('public', 'profiles', 'university_id',
  'profiles.university_id 는 null 을 허용한다(①, 학교는 학교 메일 인증이 정한다)');                    -- 2
select col_type_is('public', 'profiles', 'school_email_verified_at', 'timestamp with time zone',
  'profiles.school_email_verified_at 은 timestamptz 다(②)');                                           -- 3
select col_is_null('public', 'profiles', 'school_email_verified_at',
  'school_email_verified_at 은 null 을 허용한다(null = 인증 전)');                                      -- 4
select throws_ok(
  $$update public.profiles set school_email_verified_at = now()
     where id = '00000000-0000-0000-0000-000000005a01'$$,
  '23514', null,
  '학교 없이 인증 시각만 채우면 profiles_verified_requires_university 위반이다(③)'
);                                                                                                   -- 5
select has_index('public', 'profiles', 'idx_profiles_unverified_created_at', 'created_at',
  '인증 전 계정 정리용 인덱스가 created_at 에 있다(④)');                                              -- 6
select ok(
  coalesce((select pg_get_expr(indpred, indrelid) from pg_index
             where indexrelid = 'public.idx_profiles_unverified_created_at'::regclass)
           ~ 'school_email_verified_at IS NULL', false),
  '그 인덱스는 인증 전 행만 담는 부분 인덱스다'
);                                                                                                   -- 7

-- 2. 가입 트리거 handle_new_user_profile (⑤) -----------------------------------

select ok(
  (select university_id is null and school_email_verified_at is null and status = 'pending'
     from public.profiles where id = '00000000-0000-0000-0000-000000005a01'),
  '카카오 가입은 학교 없는 pending 프로필을 만든다'
);                                                                                                   -- 8
select ok(
  (select university_id is null and school_email_verified_at is null
     from public.profiles where id = '00000000-0000-0000-0000-000000005a02'),
  '학교 도메인 구글 메일이어도 트리거는 학교를 정하지 않는다(학교 확인은 ⑩ 만)'
);                                                                                                   -- 9
select lives_ok(
  $$insert into auth.users (id, email, raw_app_meta_data) values
      ('00000000-0000-0000-0000-000000005a03', 'g2@example.com', '{"provider": "google", "providers": ["google"]}')$$,
  '화이트리스트에 없는 도메인의 소셜 가입도 오류가 나지 않는다'
);                                                                                                   -- 10
select isnt_empty(
  $$select 1 from public.profiles where id = '00000000-0000-0000-0000-000000005a03'$$,
  '그 소셜 가입도 pending 프로필이 생긴다'
);                                                                                                   -- 11
select is_empty(
  $$select 1 from public.profiles where id = '00000000-0000-0000-0000-000000005a04'$$,
  'email 방식 임시 계정에는 프로필을 만들지 않는다'
);                                                                                                   -- 12
select isnt_empty(
  $$select 1 from public.profiles where id = '00000000-0000-0000-0000-000000005a05'$$,
  'provider 가 없는 행도 프로필을 만든다(다른 시험 파일이 auth.users 에 id · email 만 넣는다)'
);                                                                                                   -- 13
select ok(
  not has_function_privilege('anon', 'public.handle_new_user_profile()', 'execute')
  and not has_function_privilege('authenticated', 'public.handle_new_user_profile()', 'execute'),
  '앱 역할은 가입 트리거 함수를 직접 부를 수 없다'
);                                                                                                   -- 14

-- 3. 이름 · 사진 지우기 scrub_social_identity_names (⑥) --------------------------

select has_trigger('auth', 'users', 'scrub_social_identity_names', 'auth.users 에 이름 지우기 트리거가 있다');      -- 15
select has_trigger('auth', 'identities', 'scrub_social_identity_names', 'auth.identities 에도 있다');               -- 16
select is(
  (select raw_user_meta_data from auth.users where id = '00000000-0000-0000-0000-000000005a02'),
  '{"iss": "https://accounts.google.com", "sub": "google-sub-1", "provider_id": "google-sub-1",
    "email": "g1@social-test.ac.kr", "email_verified": true, "phone_verified": false}'::jsonb,
  '가입 때 이름 · 사진 · 그 밖의 칸은 지우고 email · sub · provider_id · iss · email_verified · phone_verified 만 남긴다'
);                                                                                                   -- 17
select is(
  (select raw_user_meta_data from auth.users where id = '00000000-0000-0000-0000-000000005a01'),
  '{"iss": "https://kauth.kakao.com", "sub": "kakao-sub-1", "provider_id": "kakao-sub-1",
    "email_verified": false, "phone_verified": false}'::jsonb,
  '지울 칸이 없는 카카오 값은 그대로다'
);                                                                                                   -- 18

-- GoTrue 는 로그인마다 제공자 값으로 다시 덮어쓴다.
update auth.users
set raw_user_meta_data = raw_user_meta_data || '{"name": "다시들어온이름", "picture": "https://example.invalid/q.jpg"}'
where id = '00000000-0000-0000-0000-000000005a02';
select is(
  (select raw_user_meta_data ?| array['name', 'picture'] from auth.users
    where id = '00000000-0000-0000-0000-000000005a02'),
  false,
  '다시 로그인해 이름 · 사진이 덮여도 지운다(update)'
);                                                                                                   -- 19

insert into auth.identities (provider_id, user_id, provider, identity_data) values
  ('google-sub-1', '00000000-0000-0000-0000-000000005a02', 'google',
   '{"iss": "https://accounts.google.com", "sub": "google-sub-1", "provider_id": "google-sub-1",
     "email": "g1@social-test.ac.kr", "email_verified": true, "phone_verified": false,
     "name": "테스트이름", "full_name": "테스트이름", "picture": "https://example.invalid/p.jpg",
     "avatar_url": "https://example.invalid/p.jpg"}');
select is(
  (select identity_data from auth.identities where provider = 'google' and provider_id = 'google-sub-1'),
  '{"iss": "https://accounts.google.com", "sub": "google-sub-1", "provider_id": "google-sub-1",
    "email": "g1@social-test.ac.kr", "email_verified": true, "phone_verified": false}'::jsonb,
  'identity_data 에서도 이름 · 사진을 지운다(insert)'
);                                                                                                   -- 20
select is(
  (select email from auth.identities where provider = 'google' and provider_id = 'google-sub-1'),
  'g1@social-test.ac.kr',
  'identity 의 email 생성 칸은 그대로 채워진다(계정 연결 · email_exists 판정이 이 칸을 쓴다)'
);                                                                                                   -- 21

update auth.identities
set identity_data = identity_data || '{"full_name": "다시들어온이름", "avatar_url": "https://example.invalid/q.jpg"}'
where provider = 'google' and provider_id = 'google-sub-1';
select is(
  (select identity_data ?| array['full_name', 'avatar_url'] from auth.identities
    where provider = 'google' and provider_id = 'google-sub-1'),
  false,
  'identity_data 가 다시 덮여도 지운다(update)'
);                                                                                                   -- 22
select ok(
  not has_function_privilege('anon', 'public.scrub_social_identity_names()', 'execute')
  and not has_function_privilege('authenticated', 'public.scrub_social_identity_names()', 'execute'),
  '앱 역할은 이름 지우기 함수를 직접 부를 수 없다'
);                                                                                                   -- 23

-- 4. school_email_claims 표 (⑦) ----------------------------------------------

select has_table('public', 'school_email_claims', 'school_email_claims 표가 있다');                  -- 24
select col_is_pk('public', 'school_email_claims', 'school_email_hmac', '학교 메일 HMAC 이 PK 다 — 메일 1개에 계정 1개'); -- 25
select col_is_unique('public', 'school_email_claims', 'profile_id', '계정 1개에 학교 메일 1개');            -- 26
select is(
  (select relrowsecurity from pg_class where oid = 'public.school_email_claims'::regclass),
  true,
  'school_email_claims 는 RLS 가 켜져 있다'
);                                                                                                   -- 27
select is_empty(
  $$select 1 from pg_policies where schemaname = 'public' and tablename = 'school_email_claims'$$,
  'school_email_claims 에는 정책이 없다(service_role 전용)'
);                                                                                                   -- 28
select throws_ok(
  $$insert into public.school_email_claims (school_email_hmac, university_id, profile_id, provider)
    values ('\x01'::bytea, '00000000-0000-0000-0000-000000005a00', '00000000-0000-0000-0000-000000005a03', 'x')$$,
  '23514', null,
  '가입 방식은 kakao · google · apple · email 만 받는다'
);                                                                                                   -- 29
select ok(
  -- 기본값 글자는 1 또는 '1'::smallint 로 나온다(판마다 다르다) — 둘 다 받는다.
  (select data_type = 'smallint' and is_nullable = 'NO' and column_default ~ '^''?1''?(::smallint)?$'
     from information_schema.columns
    where table_schema = 'public' and table_name = 'school_email_claims' and column_name = 'key_version'),
  'key_version 은 smallint not null default 1 이다(signup_blocks · contact_blocks 와 같은 모양)'
);                                                                                                   -- 30

-- 5. list_unverified_accounts (⑧) ---------------------------------------------
-- A1 · A2 = 오래된 인증 전, A3 = 13일 된 인증 전, AV = 가장 오래됐지만 인증함.
-- 가입 시각을 2000 년대로 둬 이 DB 의 어떤 프로필보다 오래되게 한다 — limit · 정렬이 다른 데이터와 섞이지 않는다.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000005a11', 'a1@social-test.ac.kr'),
  ('00000000-0000-0000-0000-000000005a12', 'a2@social-test.ac.kr'),
  ('00000000-0000-0000-0000-000000005a13', 'a3@social-test.ac.kr'),
  ('00000000-0000-0000-0000-000000005a14', 'av@social-test.ac.kr');
update public.profiles set created_at = '2002-01-01 00:00+09' where id = '00000000-0000-0000-0000-000000005a12';
update public.profiles set created_at = '2001-01-01 00:00+09' where id = '00000000-0000-0000-0000-000000005a11';
update public.profiles set created_at = now() - interval '13 days' where id = '00000000-0000-0000-0000-000000005a13';
update public.profiles
set created_at = '2000-01-01 00:00+09', university_id = '00000000-0000-0000-0000-000000005a00',
    school_email_verified_at = '2000-01-01 00:00+09'
where id = '00000000-0000-0000-0000-000000005a14';

-- 함수가 security invoker 라 부르는 쪽 권한으로 돈다 — FastAPI 와 같은 service_role 로 불러야 표 권한이 모자란지 드러난다
-- (postgres 로 부르면 무엇이든 통과한다). 6 절까지 service_role 이다.
set local role service_role;

select results_eq(
  $$select id from public.list_unverified_accounts(14, 2)$$,
  $$values ('00000000-0000-0000-0000-000000005a11'::uuid), ('00000000-0000-0000-0000-000000005a12'::uuid)$$,
  '인증 전이고 14일이 지난 계정을 오래된 순으로 준다(인증한 AV 는 더 오래돼도 빠진다)'
);                                                                                                   -- 31
select results_eq(
  $$select id from public.list_unverified_accounts(14, 1)$$,
  $$values ('00000000-0000-0000-0000-000000005a11'::uuid)$$,
  'p_limit 만큼만 준다'
);                                                                                                   -- 32
select ok(
  exists (select 1 from public.list_unverified_accounts(12, 1000) where id = '00000000-0000-0000-0000-000000005a13')
  and not exists (select 1 from public.list_unverified_accounts(14, 1000) where id = '00000000-0000-0000-0000-000000005a13'),
  '일수 기준: 13일 된 계정은 12일 기준엔 나오고 14일 기준엔 안 나온다'
);                                                                                                   -- 33
select lives_ok(
  $$select * from public.list_unverified_accounts(14)$$,
  'p_limit 을 빼면 기본값(100)으로 부른다'
);                                                                                                   -- 34
select throws_ok(
  $$select * from public.list_unverified_accounts(0)$$,
  '22023', null,
  '0일 기준은 거절한다 — 지금 인증 중인 사람까지 지우게 된다'
);                                                                                                   -- 35
select throws_ok(
  $$select * from public.list_unverified_accounts(14, null)$$,
  '22023', null,
  'limit null 은 거절한다 — 인증 전 계정 전부가 한 번에 나간다'
);                                                                                                   -- 36
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.list_unverified_accounts(integer, integer)'::regprocedure),
  'list_unverified_accounts 는 security invoker · search_path 빈 값이다(SUPABASE.md §5)'
);                                                                                                   -- 37
select ok(
  has_function_privilege('service_role', 'public.list_unverified_accounts(integer, integer)', 'execute')
  and not has_function_privilege('anon', 'public.list_unverified_accounts(integer, integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.list_unverified_accounts(integer, integer)', 'execute'),
  'list_unverified_accounts 는 service_role 만 부른다'
);                                                                                                   -- 38

-- 6. complete_school_email_verification (⑩) — service_role ------------------------
-- AV 는 기존 학교 메일 가입자다. 서버 백필 스크립트처럼 provider = email 로 claims 행을 넣는다(key_version 은 기본값).
select lives_ok(
  $$insert into public.school_email_claims (school_email_hmac, university_id, profile_id, provider)
    values ('\xe0e0'::bytea, '00000000-0000-0000-0000-000000005a00', '00000000-0000-0000-0000-000000005a14', 'email')$$,
  'service_role 은 기존 email 가입자의 claims 행을 provider = email 로 넣을 수 있다(서버 백필 길, key_version 은 기본 1)'
);                                                                                                   -- 39

select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005a01', '\xaa01'::bytea, '00000000-0000-0000-0000-000000005a00', 'kakao'),
  'ok',
  '처음 인증하면 ok'
);                                                                                                   -- 40
select ok(
  (select university_id = '00000000-0000-0000-0000-000000005a00' and school_email_verified_at is not null
     from public.profiles where id = '00000000-0000-0000-0000-000000005a01'),
  '인증하면 프로필에 학교와 인증 시각이 채워진다'
);                                                                                                   -- 41
select results_eq(
  $$select profile_id, university_id, provider from public.school_email_claims where school_email_hmac = '\xaa01'::bytea$$,
  $$values ('00000000-0000-0000-0000-000000005a01'::uuid, '00000000-0000-0000-0000-000000005a00'::uuid, 'kakao'::text)$$,
  '인증하면 claims 에 그 계정 · 학교 · 가입 방식이 남는다'
);                                                                                                   -- 42
select is(
  (select key_version from public.school_email_claims where school_email_hmac = '\xaa01'::bytea),
  1::smallint,
  'p_key_version 을 빼고 부르면 key_version 1 로 남는다'
);                                                                                                   -- 43
select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005a01', '\xaa01'::bytea, '00000000-0000-0000-0000-000000005a00', 'kakao'),
  'ok',
  '같은 계정 · 같은 메일로 다시 불러도 ok(멱등)'
);                                                                                                   -- 44
select is(
  (select count(*) from public.school_email_claims where profile_id = '00000000-0000-0000-0000-000000005a01'),
  1::bigint,
  '다시 불러도 claims 행은 하나다'
);                                                                                                   -- 45
select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005a03', '\xaa01'::bytea, '00000000-0000-0000-0000-000000005a00', 'google'),
  'kakao',
  '다른 계정이 쓰는 메일이면 그 계정의 가입 방식을 돌려준다'
);                                                                                                   -- 46
select ok(
  (select university_id is null and school_email_verified_at is null
     from public.profiles where id = '00000000-0000-0000-0000-000000005a03')
  and not exists (select 1 from public.school_email_claims where profile_id = '00000000-0000-0000-0000-000000005a03'),
  '그때는 아무것도 바꾸지 않는다'
);                                                                                                   -- 47
select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005a03', '\xe0e0'::bytea, '00000000-0000-0000-0000-000000005a00', 'google'),
  'email',
  '기존 email 가입자가 쓰는 메일이면 email 을 돌려준다'
);                                                                                                   -- 48
select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005a01', '\xbb02'::bytea, '00000000-0000-0000-0000-000000005a00', 'kakao'),
  'already_verified',
  '이미 인증한 계정이 다른 메일로 오면 already_verified(인증 뒤 학교 메일 변경 금지)'
);                                                                                                   -- 49
select is_empty(
  $$select 1 from public.school_email_claims where school_email_hmac = '\xbb02'::bytea$$,
  '그때 새 메일은 claims 에 남지 않는다'
);                                                                                                   -- 50
select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005a06', '\xcc03'::bytea, '00000000-0000-0000-0000-000000005a00', 'google'),
  'already_verified',
  'claims 행이 없는 기존 가입자(⑨ 백필)도 이미 인증한 계정이다'
);                                                                                                   -- 51
select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005aff', '\xdd04'::bytea, '00000000-0000-0000-0000-000000005a00', 'kakao'),
  'no_profile',
  '프로필이 없으면 no_profile'
);                                                                                                   -- 52
select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005a04', '\xdd05'::bytea, '00000000-0000-0000-0000-000000005a00', 'kakao'),
  'no_profile',
  '임시 email 계정 id 를 넘겨도 no_profile(프로필이 없다)'
);                                                                                                   -- 53
select is_empty(
  $$select 1 from public.school_email_claims where school_email_hmac in ('\xcc03'::bytea, '\xdd04'::bytea, '\xdd05'::bytea)$$,
  'already_verified · no_profile 때는 claims 에 아무것도 남지 않는다'
);                                                                                                   -- 54
select throws_ok(
  $$select public.complete_school_email_verification(
      '00000000-0000-0000-0000-000000005a03', '\xee06'::bytea, '00000000-0000-0000-0000-000000005a00', 'x')$$,
  '23514', null,
  '가입 방식이 kakao · google · apple · email 이 아니면 오류로 끝난다(아무것도 남지 않는다)'
);                                                                                                   -- 55
select is(
  public.complete_school_email_verification(
    '00000000-0000-0000-0000-000000005a03', '\xab09'::bytea, '00000000-0000-0000-0000-000000005a00', 'google', 2::smallint),
  'ok',
  'p_key_version 을 넘겨 부를 수 있다'
);                                                                                                   -- 56
select is(
  (select key_version from public.school_email_claims where school_email_hmac = '\xab09'::bytea),
  2::smallint,
  '넘긴 key_version 이 그대로 남는다(키를 바꾼 뒤 대조는 같은 버전끼리)'
);                                                                                                   -- 57
select ok(
  obj_description('public.complete_school_email_verification(uuid, bytea, uuid, text, smallint)'::regprocedure, 'pg_proc')
    ~ 'already_verified'
  and obj_description('public.complete_school_email_verification(uuid, bytea, uuid, text, smallint)'::regprocedure, 'pg_proc')
    ~ 'apple \| email',
  '함수 주석에 돌려주는 값 규칙이 적혀 있다(email 포함)'
);                                                                                                   -- 58
select ok(
  pg_get_functiondef('public.complete_school_email_verification(uuid, bytea, uuid, text, smallint)'::regprocedure) ~* 'for update'
  and pg_get_functiondef('public.complete_school_email_verification(uuid, bytea, uuid, text, smallint)'::regprocedure) ~* 'on conflict',
  '프로필을 for update 로 잠그고 메일 충돌을 on conflict 로 받는다(동시 호출)'
);                                                                                                   -- 59
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.complete_school_email_verification(uuid, bytea, uuid, text, smallint)'::regprocedure),
  'complete_school_email_verification 은 security invoker · search_path 빈 값이다(SUPABASE.md §5)'
);                                                                                                   -- 60
select ok(
  has_function_privilege('service_role', 'public.complete_school_email_verification(uuid, bytea, uuid, text, smallint)', 'execute')
  and not has_function_privilege('anon', 'public.complete_school_email_verification(uuid, bytea, uuid, text, smallint)', 'execute')
  and not has_function_privilege('authenticated', 'public.complete_school_email_verification(uuid, bytea, uuid, text, smallint)', 'execute'),
  'complete_school_email_verification 은 service_role 만 부른다'
);                                                                                                   -- 61

-- 7. 앱 역할로 직접 ------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000005a01", "role": "authenticated"}';

select throws_ok(
  $$select school_email_hmac from public.school_email_claims$$,
  '42501', null,
  'authenticated 는 자기 claims 행도 읽을 수 없다'
);                                                                                                   -- 62
select throws_ok(
  $$select public.complete_school_email_verification(
      '00000000-0000-0000-0000-000000005a13', '\xff07'::bytea, '00000000-0000-0000-0000-000000005a00', 'kakao')$$,
  '42501', null,
  'authenticated 는 학교 메일 인증 함수를 직접 부를 수 없다(인증번호 검사를 건너뛰는 길)'
);                                                                                                   -- 63
select throws_ok(
  $$select * from public.list_unverified_accounts(14)$$,
  '42501', null,
  'authenticated 는 인증 전 계정 목록을 부를 수 없다'
);                                                                                                   -- 64

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select school_email_hmac from public.school_email_claims$$,
  '42501', null,
  'anon 은 claims 를 읽을 수 없다'
);                                                                                                   -- 65

-- 8. 탈퇴 cascade (postgres) ----------------------------------------------------

reset role;

delete from auth.users where id = '00000000-0000-0000-0000-000000005a01';

select is_empty(
  $$select 1 from public.school_email_claims where profile_id = '00000000-0000-0000-0000-000000005a01'$$,
  '계정을 지우면 claims 행도 지워진다 — 그 학교 메일로 다시 인증할 수 있다(재가입 제한은 signup_blocks 몫)'
);                                                                                                   -- 66

select * from finish();
rollback;
