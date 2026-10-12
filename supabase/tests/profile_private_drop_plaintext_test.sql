-- 실명 · 카카오톡 아이디 암호화 2단계(M2, 20261012010000): 평문 real_name · kakao_id 열과 백필 함수가 사라지고,
-- 남은 암호문 열 · 함수 3개의 권한은 그대로다. 안전장치(평문만 든 행이 있으면 아무것도 안 지우고 멈춘다)는
-- 마이그레이션 본문을 그대로 다시 돌려 본다 — 로컬 CLI 가 supabase_migrations.schema_migrations 에 남긴 문장들이다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- 1. 열 · 함수가 사라졌다 ------------------------------------------------------------
select hasnt_column('public', 'profile_private', 'real_name', '평문 real_name 열이 없다');
select hasnt_column('public', 'profile_private', 'kakao_id', '평문 kakao_id 열이 없다');
select has_column('public', 'profile_private', 'real_name_enc', '실명 암호문 열은 그대로다');
select has_column('public', 'profile_private', 'kakao_id_enc', '카카오 아이디 암호문 열은 그대로다');

select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace and proname = 'backfill_profile_private_encryption'),
  0::bigint, '임시 백필 함수는 오버로드까지 하나도 남지 않았다'
);

select is(
  (select array_agg(attname::text order by attname)
     from pg_attribute
    where attrelid = 'public.profile_private'::regclass and attnum > 0 and not attisdropped
      and has_column_privilege('authenticated', attrelid, attnum, 'select')),
  array['profile_id'],
  'authenticated 가 select 할 수 있는 열은 profile_id 하나뿐이다(실명 컬럼 grant 는 열과 함께 사라졌다)'
);

-- 2. 남은 함수 3개의 권한 · 설정은 그대로다 ---------------------------------------------
select ok(
  has_function_privilege('service_role', 'public.set_real_name(uuid, text, text)', 'execute')
  and has_function_privilege('service_role', 'public.set_kakao_id(uuid, text, text)', 'execute')
  and has_function_privilege('service_role', 'public.decrypt_profile_private(uuid, text)', 'execute'),
  'service_role 은 남은 함수 3개를 실행할 수 있다'
);
select ok(
  not has_function_privilege('anon', 'public.set_real_name(uuid, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.set_kakao_id(uuid, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.decrypt_profile_private(uuid, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.set_real_name(uuid, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.set_kakao_id(uuid, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.decrypt_profile_private(uuid, text)', 'execute'),
  'anon · authenticated 는 남은 함수 3개를 실행할 수 없다'
);
select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('set_real_name', 'set_kakao_id', 'decrypt_profile_private')
      and not prosecdef
      and exists (select 1 from unnest(proconfig) cfg where cfg = 'search_path=""')),
  3::bigint, '남은 함수 3개는 그대로 security invoker 이고 search_path 가 빈 값으로 고정돼 있다'
);

-- 남은 함수가 평문 열 없이 돈다(실행 시점에 없는 열을 찾지 않는다).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'm2-d1@test-m2.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d2', 'm2-d2@test-m2.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d3', 'm2-d3@test-m2.ac.kr');

select lives_ok(
  $$select public.set_real_name('00000000-0000-0000-0000-0000000000d1', '홍길동', 'pgtap-key')$$,
  'set_real_name 은 평문 열 없이 돈다'
);
select lives_ok(
  $$select public.set_kakao_id('00000000-0000-0000-0000-0000000000d1', 'gildong_kakao', 'pgtap-key')$$,
  'set_kakao_id 는 평문 열 없이 돈다'
);
select is(
  (select row(real_name, kakao_id)::text
     from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000d1', 'pgtap-key')),
  row('홍길동', 'gildong_kakao')::text, 'decrypt_profile_private 는 평문 열 없이 암호문을 복호화한다'
);

-- 3. 안전장치: 마이그레이션 본문을 M2 앞 모양에서 다시 돌린다 ----------------------------------
create temp table m2_body as
select string_agg(s, E';\n' order by i) || ';' as sql
from supabase_migrations.schema_migrations, unnest(statements) with ordinality as t(s, i)
where version = '20261012010000';

select ok((select sql from m2_body) is not null, 'M2 본문이 로컬 마이그레이션 기록에 있다');

-- M2 앞 모양으로 되돌린다: 평문 열 2개 + 임시 함수(본문의 drop function 이 찾을 자리).
-- if not exists · or replace: M2 가 아직 안 올라간 DB(RED)에서도 오류 없이 실패로 센다.
alter table public.profile_private add column if not exists real_name text, add column if not exists kakao_id text;
create or replace function public.backfill_profile_private_encryption(p_profile uuid, p_key text)
returns void language plpgsql set search_path = '' as $$begin end;$$;

-- D2: 실명 평문만 있고 암호문이 비었다.
insert into public.profile_private (profile_id, real_name) values ('00000000-0000-0000-0000-0000000000d2', '백필안됨');

select throws_ok(
  (select sql from m2_body),
  'P0001', 'profile_private 에 암호문 없이 평문만 있는 행이 1개 있다 — 백필을 먼저 끝내야 한다',
  '실명 평문만 든 행이 있으면 마이그레이션이 멈춘다'
);
select has_column('public', 'profile_private', 'real_name', '멈췄을 때 실명 평문 열은 그대로 남는다');
select has_column('public', 'profile_private', 'kakao_id', '멈췄을 때 카카오 평문 열도 그대로 남는다');
select is(
  (select real_name from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000d2'),
  '백필안됨', '멈췄을 때 평문 값은 지워지지 않았다'
);

-- 실명은 채우고, 이번엔 카카오 평문만 있고 암호문이 빈 행(D1 은 암호문이 이미 있다).
select public.set_real_name('00000000-0000-0000-0000-0000000000d2', '백필안됨', 'pgtap-key');
insert into public.profile_private (profile_id, kakao_id) values ('00000000-0000-0000-0000-0000000000d3', 'kk-d3');

select throws_ok(
  (select sql from m2_body),
  'P0001', 'profile_private 에 암호문 없이 평문만 있는 행이 1개 있다 — 백필을 먼저 끝내야 한다',
  '카카오 평문만 든 행이 있어도 마이그레이션이 멈춘다(열마다 따로 본다)'
);

-- 다 채우고, 빈 문자열 평문(백필이 암호화하지 않은 값 — null 과 같은 뜻)만 남긴다.
select public.set_kakao_id('00000000-0000-0000-0000-0000000000d3', 'kk-d3', 'pgtap-key');
update public.profile_private set kakao_id = '' where profile_id = '00000000-0000-0000-0000-0000000000d2';

select lives_ok(
  (select sql from m2_body),
  '평문마다 암호문이 있으면(빈 문자열 평문은 세지 않는다) 마이그레이션이 끝까지 돈다'
);
select ok(
  not exists (select 1 from pg_attribute
               where attrelid = 'public.profile_private'::regclass and not attisdropped
                 and attname in ('real_name', 'kakao_id')),
  '안전장치를 통과하면 평문 열 2개가 지워진다'
);
select is(
  (select row(real_name, kakao_id)::text
     from public.decrypt_profile_private('00000000-0000-0000-0000-0000000000d3', 'pgtap-key')),
  row(null, 'kk-d3')::text, '지운 뒤에도 암호문 값은 그대로 복호화된다'
);

select * from finish();
rollback;
