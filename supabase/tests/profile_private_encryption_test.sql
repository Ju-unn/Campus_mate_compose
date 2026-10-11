-- 실명(real_name) · 카카오톡 아이디(kakao_id) 암호화 1단계(M1): 새 bytea 열 2개 + 함수 4개.
-- 옛 평문 열은 이 단계에서 그대로 둔다(서버가 이중 쓰기 → 백필 → 읽기 전환 뒤 M2 에서 지운다).
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
-- 함수가 아직 없을 때도 오류로 멈추지 않고 실패로 세도록 to_regprocedure 를 쓴다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(55);

-- 준비 --------------------------------------------------------------------
-- E1 = ...e1(profile_private 행 없음), E2 = ...e2(왕복 · 덮어쓰기 · 틀린 키 · 빈 문자열),
-- E3 = ...e3(행은 있으나 암호문 열이 둘 다 null),
-- B1 = ...b1(평문만 있음), B2 = ...b2(real_name_enc 가 이미 있음), B3 = ...b3(빈 문자열 · null 평문),
-- B4 = ...b4(행 없음)
-- on_auth_user_created 트리거가 pending profiles 행을 만든다(다른 테스트와 같은 모양).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'pe-e1@test-pe.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e2', 'pe-e2@test-pe.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e3', 'pe-e3@test-pe.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b1', 'pe-b1@test-pe.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b2', 'pe-b2@test-pe.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b3', 'pe-b3@test-pe.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b4', 'pe-b4@test-pe.ac.kr');

insert into public.profile_private (profile_id) values
  ('00000000-0000-0000-0000-0000000000e3');

-- 1. 구조 ------------------------------------------------------------------
select has_column('public', 'profile_private', 'real_name_enc', 'real_name_enc 열이 있다');
select col_type_is('public', 'profile_private', 'real_name_enc', 'bytea', 'real_name_enc 는 bytea 다');
select has_column('public', 'profile_private', 'kakao_id_enc', 'kakao_id_enc 열이 있다');
select col_type_is('public', 'profile_private', 'kakao_id_enc', 'bytea', 'kakao_id_enc 는 bytea 다');

select has_function('public', 'set_real_name', array['uuid', 'text', 'text'],
  'set_real_name(uuid, text, text) 가 있다');
select has_function('public', 'set_kakao_id', array['uuid', 'text', 'text'],
  'set_kakao_id(uuid, text, text) 가 있다');
select has_function('public', 'decrypt_profile_private', array['uuid', 'text'],
  'decrypt_profile_private(uuid, text) 가 있다');
select has_function('public', 'backfill_profile_private_encryption', array['uuid', 'text'],
  'backfill_profile_private_encryption(uuid, text) 가 있다');

select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('set_real_name', 'set_kakao_id', 'decrypt_profile_private',
                      'backfill_profile_private_encryption')),
  4::bigint,
  '새 함수 4개는 이름마다 딱 하나다(오버로드가 남으면 PostgREST 호출이 모호해진다)'
);

select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('set_real_name', 'set_kakao_id', 'decrypt_profile_private',
                      'backfill_profile_private_encryption')
      and obj_description(oid, 'pg_proc') is not null),
  4::bigint, '새 함수 4개에 모두 comment 가 있다'
);

select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('set_real_name', 'set_kakao_id', 'decrypt_profile_private',
                      'backfill_profile_private_encryption')
      and exists (select 1 from unnest(proconfig) cfg where cfg = 'search_path=""')),
  4::bigint, '새 함수 4개는 search_path 가 빈 값으로 고정돼 있다'
);

select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('set_real_name', 'set_kakao_id', 'decrypt_profile_private',
                      'backfill_profile_private_encryption')
      and not prosecdef),
  4::bigint, '새 함수 4개는 security invoker 다(권한 우회 없음)'
);

-- 2. 권한 ------------------------------------------------------------------
select ok(
  has_function_privilege('service_role',
    to_regprocedure('public.set_real_name(uuid, text, text)'), 'execute')
  and has_function_privilege('service_role',
    to_regprocedure('public.set_kakao_id(uuid, text, text)'), 'execute')
  and has_function_privilege('service_role',
    to_regprocedure('public.decrypt_profile_private(uuid, text)'), 'execute')
  and has_function_privilege('service_role',
    to_regprocedure('public.backfill_profile_private_encryption(uuid, text)'), 'execute'),
  'service_role 은 새 함수 4개를 실행할 수 있다'
);
select ok(
  not has_function_privilege('anon',
    to_regprocedure('public.set_real_name(uuid, text, text)'), 'execute')
  and not has_function_privilege('anon',
    to_regprocedure('public.set_kakao_id(uuid, text, text)'), 'execute')
  and not has_function_privilege('anon',
    to_regprocedure('public.decrypt_profile_private(uuid, text)'), 'execute')
  and not has_function_privilege('anon',
    to_regprocedure('public.backfill_profile_private_encryption(uuid, text)'), 'execute'),
  'anon 은 새 함수 4개를 실행할 수 없다'
);
select ok(
  not has_function_privilege('authenticated',
    to_regprocedure('public.set_real_name(uuid, text, text)'), 'execute')
  and not has_function_privilege('authenticated',
    to_regprocedure('public.set_kakao_id(uuid, text, text)'), 'execute')
  and not has_function_privilege('authenticated',
    to_regprocedure('public.decrypt_profile_private(uuid, text)'), 'execute')
  and not has_function_privilege('authenticated',
    to_regprocedure('public.backfill_profile_private_encryption(uuid, text)'), 'execute'),
  'authenticated 는 새 함수 4개를 실행할 수 없다'
);

select ok(
  not has_column_privilege('authenticated', 'public.profile_private', 'real_name_enc', 'select')
  and not has_column_privilege('authenticated', 'public.profile_private', 'kakao_id_enc', 'select')
  and not has_column_privilege('anon', 'public.profile_private', 'real_name_enc', 'select')
  and not has_column_privilege('anon', 'public.profile_private', 'kakao_id_enc', 'select'),
  'authenticated · anon 은 새 암호문 열 2개를 select 할 수 없다'
);
select ok(
  has_column_privilege('service_role', 'public.profile_private', 'real_name_enc', 'select')
  and has_column_privilege('service_role', 'public.profile_private', 'kakao_id_enc', 'select')
  and has_column_privilege('service_role', 'public.profile_private', 'real_name_enc', 'update')
  and has_column_privilege('service_role', 'public.profile_private', 'kakao_id_enc', 'update'),
  'service_role 은 새 암호문 열 2개를 select · update 할 수 있다'
);

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000e2", "role": "authenticated"}';

select throws_ok(
  $$select public.set_real_name('00000000-0000-0000-0000-0000000000e2', '홍길동', 'k')$$,
  '42501', null, 'authenticated 는 set_real_name 을 실행할 수 없다(42501)'
);
select throws_ok(
  $$select public.set_kakao_id('00000000-0000-0000-0000-0000000000e2', 'kk', 'k')$$,
  '42501', null, 'authenticated 는 set_kakao_id 를 실행할 수 없다(42501)'
);
select throws_ok(
  $$select * from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e2', 'k')$$,
  '42501', null, 'authenticated 는 decrypt_profile_private 를 실행할 수 없다(42501)'
);
select throws_ok(
  $$select public.backfill_profile_private_encryption('00000000-0000-0000-0000-0000000000e2', 'k')$$,
  '42501', null, 'authenticated 는 backfill_profile_private_encryption 을 실행할 수 없다(42501)'
);
select throws_ok(
  $$select real_name_enc from public.profile_private$$,
  '42501', null, 'authenticated 가 real_name_enc 를 select 하면 42501 이다'
);

reset role;
reset request.jwt.claims;

-- 3. 행이 없을 때 --------------------------------------------------------------
select is(
  (select count(*) from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e1', 'pgtap-key')),
  0::bigint, '행이 없는 사람을 복호화하면 0행이다'
);

select lives_ok(
  $$select public.set_kakao_id('00000000-0000-0000-0000-0000000000e1', 'kk-e1', 'pgtap-key')$$,
  '행이 없는 사람에게 set_kakao_id 를 불러도 오류가 아니다'
);
select is(
  (select count(*) from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000e1'),
  0::bigint, 'set_kakao_id 는 행을 만들지 않는다(update 전용 — 서버가 ensure_private_row 로 보장한다)'
);

select lives_ok(
  $$select public.set_real_name('00000000-0000-0000-0000-0000000000e1', '이일번', 'pgtap-key')$$,
  '행이 없는 사람에게 set_real_name 을 부르면 오류 없이 된다'
);
select is(
  (select count(*) from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000e1'),
  1::bigint, 'set_real_name 은 행이 없으면 만든다(upsert)'
);
select is(
  (select real_name from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e1', 'pgtap-key')),
  '이일번', 'upsert 로 만든 행에서 실명이 복호화된다'
);
select is(
  (select kakao_id from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e1', 'pgtap-key')),
  null, '카카오 아이디를 안 넣은 열은 복호화하면 null 이다'
);

-- 4. 왕복 · 덮어쓰기 · 암호문 · 틀린 키 -------------------------------------------
insert into public.profile_private (profile_id) values ('00000000-0000-0000-0000-0000000000e2');

select public.set_real_name('00000000-0000-0000-0000-0000000000e2', '홍길동', 'pgtap-key');
select public.set_kakao_id('00000000-0000-0000-0000-0000000000e2', 'gildong_kakao', 'pgtap-key');

select is(
  (select row(real_name, kakao_id)::text
     from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e2', 'pgtap-key')),
  row('홍길동', 'gildong_kakao')::text, '저장한 실명과 카카오 아이디가 그대로 복호화된다(왕복)'
);

select ok(
  (select position(convert_to('홍길동', 'UTF8') in real_name_enc) = 0
      and position(convert_to('gildong_kakao', 'UTF8') in kakao_id_enc) = 0
      and real_name_enc is not null and kakao_id_enc is not null
     from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000e2'),
  '저장된 암호문에 평문 바이트가 들어 있지 않다'
);

select is(
  (select real_name from public.profile_private
    where profile_id = '00000000-0000-0000-0000-0000000000e2'),
  null, '새 함수는 옛 평문 열을 건드리지 않는다(이중 쓰기는 서버 몫)'
);

select throws_ok(
  $$select * from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e2', 'wrong-key')$$,
  '39000', null, '틀린 키로 복호화하면 오류가 난다(pgcrypto Wrong key or corrupt data)'
);

select lives_ok(
  $$select public.set_real_name('00000000-0000-0000-0000-0000000000e2', '김바꿈', 'pgtap-key')$$,
  '같은 사람에게 set_real_name 을 다시 부를 수 있다'
);
select is(
  (select real_name from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e2', 'pgtap-key')),
  '김바꿈', '다시 부르면 실명이 덮어써진다'
);
select is(
  (select kakao_id from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e2', 'pgtap-key')),
  'gildong_kakao', '실명을 덮어써도 카카오 아이디 암호문은 그대로다'
);
select is(
  (select count(*) from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000e2'),
  1::bigint, '덮어써도 행은 하나다'
);

-- 빈 문자열은 암호화하지 않고 암호문을 null 로 비운다.
select public.set_real_name('00000000-0000-0000-0000-0000000000e2', '', 'pgtap-key');
select public.set_kakao_id('00000000-0000-0000-0000-0000000000e2', '', 'pgtap-key');
select ok(
  (select real_name_enc is null and kakao_id_enc is null
     from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000e2'),
  '빈 문자열을 저장하면 암호문이 null 이 된다(빈 값을 암호화해 남기지 않는다)'
);
select is(
  (select row(real_name, kakao_id)::text
     from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e2', 'pgtap-key')),
  row(null, null)::text, '비워진 열은 복호화하면 null 이다(키가 틀려도 null 열은 오류가 아니다)'
);

-- 5. 암호문 열이 둘 다 null 인 행 -----------------------------------------------------
select is(
  (select row(real_name, kakao_id)::text
     from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e3', 'pgtap-key')),
  row(null, null)::text, '행은 있고 암호문이 없으면 (null, null) 한 행이다'
);
select is(
  (select count(*) from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e3', 'pgtap-key')),
  1::bigint, '행은 있고 암호문이 없어도 결과는 1행이다(행 없음의 0행과 구분된다)'
);

-- 5-1. 키가 비면 오류 -------------------------------------------------------------
select throws_ok(
  $$select public.set_real_name('00000000-0000-0000-0000-0000000000e2', '홍길동', null)$$,
  '22023', 'encryption key is required', 'set_real_name 은 키가 null 이면 오류다(암호문을 null 로 덮지 않는다)'
);
select throws_ok(
  $$select public.set_kakao_id('00000000-0000-0000-0000-0000000000e2', 'kk', '')$$,
  '22023', 'encryption key is required', 'set_kakao_id 는 키가 빈 문자열이면 오류다'
);
select throws_ok(
  $$select * from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000e3', null)$$,
  '22023', 'encryption key is required', 'decrypt_profile_private 는 키가 null 이면 오류다(전부 null 로 보이지 않는다)'
);
select throws_ok(
  $$select public.backfill_profile_private_encryption('00000000-0000-0000-0000-0000000000b1', null)$$,
  '22023', 'encryption key is required', 'backfill 은 키가 null 이면 오류다'
);

-- 6. backfill_profile_private_encryption ------------------------------------------
-- B1: 평문만 있다 → 채운다.
insert into public.profile_private (profile_id, real_name, kakao_id) values
  ('00000000-0000-0000-0000-0000000000b1', '백필일', 'kk-b1');
-- B2: real_name_enc 가 이미 있고 평문은 다른 값 → real_name_enc 는 덮지 않고 kakao_id 만 채운다.
insert into public.profile_private (profile_id) values ('00000000-0000-0000-0000-0000000000b2');
select public.set_real_name('00000000-0000-0000-0000-0000000000b2', '원본이름', 'pgtap-key');
update public.profile_private
set real_name = '다른이름', kakao_id = 'kk-b2'
where profile_id = '00000000-0000-0000-0000-0000000000b2';
-- B3: 빈 문자열 · null 평문 → 암호문도 null 로 둔다.
insert into public.profile_private (profile_id, real_name, kakao_id) values
  ('00000000-0000-0000-0000-0000000000b3', '', null);

select lives_ok(
  $$select public.backfill_profile_private_encryption('00000000-0000-0000-0000-0000000000b1', 'pgtap-key')$$,
  'backfill 을 부를 수 있다'
);
select is(
  (select row(real_name, kakao_id)::text
     from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000b1', 'pgtap-key')),
  row('백필일', 'kk-b1')::text, '평문만 있던 행은 backfill 뒤 암호문으로 복호화된다'
);
select ok(
  (select real_name = '백필일' and kakao_id = 'kk-b1'
     from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000b1'),
  'backfill 은 옛 평문 열을 지우지 않는다(지우기는 M2 몫)'
);

create temp table b1_snapshot as
select real_name_enc, kakao_id_enc from public.profile_private
where profile_id = '00000000-0000-0000-0000-0000000000b1';

select lives_ok(
  $$select public.backfill_profile_private_encryption('00000000-0000-0000-0000-0000000000b1', 'pgtap-key')$$,
  'backfill 을 한 번 더 불러도 오류가 아니다'
);
select ok(
  (select p.real_name_enc = s.real_name_enc and p.kakao_id_enc = s.kakao_id_enc
     from public.profile_private p, b1_snapshot s
    where p.profile_id = '00000000-0000-0000-0000-0000000000b1'),
  'backfill 재실행은 이미 채운 암호문을 다시 만들지 않는다(바이트가 같다)'
);

select public.backfill_profile_private_encryption('00000000-0000-0000-0000-0000000000b2', 'pgtap-key');
select is(
  (select real_name from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000b2', 'pgtap-key')),
  '원본이름', 'real_name_enc 가 이미 있으면 backfill 이 덮지 않는다'
);
select is(
  (select kakao_id from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000b2', 'pgtap-key')),
  'kk-b2', '같은 행에서 비어 있던 kakao_id_enc 는 채운다(열마다 따로 판단한다)'
);

select public.backfill_profile_private_encryption('00000000-0000-0000-0000-0000000000b3', 'pgtap-key');
select ok(
  (select real_name_enc is null and kakao_id_enc is null
     from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000b3'),
  '빈 문자열 · null 평문은 backfill 해도 암호문이 null 로 남는다'
);

select lives_ok(
  $$select public.backfill_profile_private_encryption('00000000-0000-0000-0000-0000000000b4', 'pgtap-key')$$,
  '행이 없는 사람에게 backfill 을 불러도 오류가 아니다'
);
select is(
  (select count(*) from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000b4'),
  0::bigint, 'backfill 은 행을 만들지 않는다'
);

select * from finish();
rollback;
