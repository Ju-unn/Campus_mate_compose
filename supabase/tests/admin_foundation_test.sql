-- 관리자 웹 대시보드 D0(설계 바탕화면 관리자_대시보드_설계_10-18.md §6 · §7) 검증.
-- 마이그레이션 20261018002858_create_admin_users · 20261018002902_create_admin_actions ·
-- 20261018002907_exclude_admins_from_unverified_cleanup.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

-- 준비 (postgres) -------------------------------------------------------------
-- AD = 관리자(운영자 전용 구글 계정 — 학교 메일 없음), NA = 관리자 아닌 학교 메일 인증 전 구글 계정.
-- 가입 시각을 2000 년으로 둬 이 DB 의 어떤 프로필보다 오래되게 한다 — 정리 함수의 limit · 정렬이 다른 데이터와 섞이지 않는다.
insert into auth.users (id, email, raw_app_meta_data) values
  ('00000000-0000-0000-0000-00000000ad01', 'operator@example.com', '{"provider": "google", "providers": ["google"]}'),
  ('00000000-0000-0000-0000-00000000ad02', 'someone@example.com', '{"provider": "google", "providers": ["google"]}');
update public.profiles set created_at = '2000-01-01 00:00+09' where id = '00000000-0000-0000-0000-00000000ad01';
update public.profiles set created_at = '2000-01-02 00:00+09' where id = '00000000-0000-0000-0000-00000000ad02';
insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-00000000ad01');

-- 1. 표 모양 (postgres) ----------------------------------------------------------

select has_table('public', 'admin_users', 'admin_users 표가 있다');                                    -- 1
select columns_are('public', 'admin_users', array['user_id', 'created_at'],
  'admin_users 칸은 사용자 id · 등록 시각 둘뿐이다');                                                  -- 2
select col_is_pk('public', 'admin_users', 'user_id', '관리자 한 명에 행 하나다');                       -- 3
select fk_ok('public', 'admin_users', 'user_id', 'auth', 'users', 'id',
  'admin_users.user_id 는 auth.users 를 가리킨다');                                                    -- 4
select has_table('public', 'admin_actions', 'admin_actions 표가 있다');                                -- 5
select columns_are('public', 'admin_actions',
  array['id', 'admin_user_id', 'action', 'target_type', 'target_id', 'before', 'after', 'reason', 'ip', 'created_at'],
  'admin_actions 칸은 설계 §7 의 열 개다');                                                            -- 6
select hasnt_fk('public', 'admin_actions',
  'admin_actions 에는 FK 가 없다 — 관리자 계정이 지워져도 기록이 남는다');                              -- 7
select col_type_is('public', 'admin_actions', 'ip', 'inet', 'ip 는 inet 이다');                         -- 8
select has_index('public', 'admin_actions', 'admin_actions_created_at_index', '최근 순 조회 인덱스가 있다');          -- 9
select has_index('public', 'admin_actions', 'admin_actions_target_created_at_index', '대상별 조회 인덱스가 있다');     -- 10
select has_index('public', 'admin_actions', 'admin_actions_admin_user_id_created_at_index',
  '관리자별 조회 인덱스가 있다');                                                                      -- 11

-- 2. RLS · 권한 (postgres) -------------------------------------------------------

select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.admin_users'::regclass, 'public.admin_actions'::regclass)),
  '두 표 모두 RLS 가 켜져 있다'
);                                                                                                   -- 12
select is(
  (select count(*) from pg_policies
    where schemaname = 'public' and tablename in ('admin_users', 'admin_actions')),
  0::bigint,
  '정책 없음 = 앱 · 브라우저는 읽지도 쓰지도 못한다'
);                                                                                                   -- 13
select table_privs_are('public', 'admin_users', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'admin_users: service_role 은 읽기 · 쓰기 넷을 가진다');  -- 14
select table_privs_are('public', 'admin_actions', 'service_role',
  array['SELECT', 'INSERT'], 'admin_actions: service_role 은 읽기 · 넣기만 가진다(고치기 · 지우기 없음)');  -- 15
select table_privs_are('public', 'admin_users', 'authenticated', array[]::text[],
  'admin_users: authenticated 는 표 권한이 없다');                                                     -- 16
select table_privs_are('public', 'admin_users', 'anon', array[]::text[],
  'admin_users: anon 은 표 권한이 없다');                                                              -- 17
select table_privs_are('public', 'admin_actions', 'authenticated', array[]::text[],
  'admin_actions: authenticated 는 표 권한이 없다');                                                   -- 18
select table_privs_are('public', 'admin_actions', 'anon', array[]::text[],
  'admin_actions: anon 은 표 권한이 없다');                                                            -- 19

-- 3. 작업 기록 (service_role) ------------------------------------------------------
-- FastAPI 와 같은 service_role 로 해야 권한이 모자라거나 남는지 드러난다(postgres 는 무엇이든 통과한다). 4 절까지 service_role 이다.
set local role service_role;

select lives_ok(
  $$insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
    values ('00000000-0000-0000-0000-00000000ad01', 'heart_task_approve', 'heart_task_submission', 'sub-1',
            '{"status": "submitted"}', '{"status": "approved"}', '캡처 확인', '203.0.113.7')$$,
  'service_role 은 작업 기록을 넣는다'
);                                                                                                   -- 20
select throws_ok(
  $$update public.admin_actions set reason = '고친 사유' where admin_user_id = '00000000-0000-0000-0000-00000000ad01'$$,
  '42501', null,
  'service_role 도 작업 기록을 고치지 못한다'
);                                                                                                   -- 21
select throws_ok(
  $$delete from public.admin_actions where admin_user_id = '00000000-0000-0000-0000-00000000ad01'$$,
  '42501', null,
  'service_role 도 작업 기록을 지우지 못한다'
);                                                                                                   -- 22
select throws_ok(
  $$insert into public.admin_actions (admin_user_id, action)
    values ('00000000-0000-0000-0000-00000000ad01', 'Heart-Task')$$,
  '23514', null,
  '동작 이름은 소문자 · 숫자 · 밑줄만(대문자 · 하이픈은 형식 검사가 막는다)'
);                                                                                                   -- 23
select throws_ok(
  $$insert into public.admin_actions (admin_user_id, action)
    values ('00000000-0000-0000-0000-00000000ad01', 'ab')$$,
  '23514', null,
  '동작 이름은 3자 이상이다'
);                                                                                                   -- 24
select throws_ok(
  $$insert into public.admin_actions (admin_user_id, action)
    values ('00000000-0000-0000-0000-00000000ad01', 'a' || repeat('b', 64))$$,
  '23514', null,
  '동작 이름은 64자까지다(65자는 막는다)'
);                                                                                                   -- 25
select throws_ok(
  $$insert into public.admin_actions (admin_user_id, action, reason)
    values ('00000000-0000-0000-0000-00000000ad01', 'profile_suspend', repeat('가', 501))$$,
  '23514', null,
  '사유는 500자까지다(501자는 막는다)'
);                                                                                                   -- 26
select lives_ok(
  $$insert into public.admin_actions (admin_user_id, action, reason)
    values ('00000000-0000-0000-0000-00000000ad01', 'profile_suspend', repeat('가', 500))$$,
  '사유 500자는 받는다'
);                                                                                                   -- 27
select throws_ok(
  $$insert into public.admin_actions (admin_user_id, action) values (null, 'profile_suspend')$$,
  '23502', null,
  '누가 했는지(admin_user_id)는 비울 수 없다'
);                                                                                                   -- 28

-- 4. 14일 정리 함수가 관리자를 빼는지 (service_role) --------------------------------

select results_eq(
  $$select id from public.list_unverified_accounts(14, 1000)
     where id in ('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-00000000ad02')$$,
  $$values ('00000000-0000-0000-0000-00000000ad02'::uuid)$$,
  '학교 메일 인증 전이고 오래된 두 계정 가운데 관리자는 정리 대상에서 빠진다'
);                                                                                                   -- 29
delete from public.admin_users where user_id = '00000000-0000-0000-0000-00000000ad01';
select ok(
  exists (select 1 from public.list_unverified_accounts(14, 1000) where id = '00000000-0000-0000-0000-00000000ad01'),
  '명단에서 빼면 다시 정리 대상이 된다 — 빠진 이유는 admin_users 하나뿐이다'
);                                                                                                   -- 30
insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-00000000ad01');
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.list_unverified_accounts(integer, integer)'::regprocedure),
  '다시 만든 list_unverified_accounts 도 security invoker · search_path 빈 값이다(SUPABASE.md §5)'
);                                                                                                   -- 31
select ok(
  has_function_privilege('service_role', 'public.list_unverified_accounts(integer, integer)', 'execute')
  and not has_function_privilege('anon', 'public.list_unverified_accounts(integer, integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.list_unverified_accounts(integer, integer)', 'execute'),
  '다시 만든 뒤에도 list_unverified_accounts 는 service_role 만 부른다'
);                                                                                                   -- 32

-- 5. 앱 역할로 직접 ---------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000ad02", "role": "authenticated"}';

select throws_ok(
  $$select user_id from public.admin_users$$,
  '42501', null,
  'authenticated 는 관리자 명단을 읽을 수 없다'
);                                                                                                   -- 33
select throws_ok(
  $$insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-00000000ad02')$$,
  '42501', null,
  'authenticated 는 자기를 관리자로 넣을 수 없다'
);                                                                                                   -- 34
select throws_ok(
  $$select id from public.admin_actions$$,
  '42501', null,
  'authenticated 는 작업 기록을 읽을 수 없다'
);                                                                                                   -- 35
select throws_ok(
  $$insert into public.admin_actions (admin_user_id, action)
    values ('00000000-0000-0000-0000-00000000ad02', 'profile_suspend')$$,
  '42501', null,
  'authenticated 는 작업 기록을 넣을 수 없다'
);                                                                                                   -- 36

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select user_id from public.admin_users$$,
  '42501', null,
  'anon 은 관리자 명단을 읽을 수 없다'
);                                                                                                   -- 37

-- 6. 관리자 계정이 지워질 때 (postgres) ----------------------------------------------

reset role;

delete from auth.users where id = '00000000-0000-0000-0000-00000000ad01';

select is_empty(
  $$select 1 from public.admin_users where user_id = '00000000-0000-0000-0000-00000000ad01'$$,
  'auth 계정을 지우면 관리자 명단에서도 빠진다(cascade)'
);                                                                                                   -- 38
select is(
  (select count(*) from public.admin_actions where admin_user_id = '00000000-0000-0000-0000-00000000ad01'),
  2::bigint,
  '그 관리자의 작업 기록(이 시험이 넣은 2줄)은 남는다'
);                                                                                                   -- 39

-- 7. 표 주인도 기록을 고치거나 지우지 못한다 (postgres) ---------------------------------
-- 권한(42501)이 아니라 트리거(CM409)가 막는다 — 대시보드 SQL 창 · 표 편집기의 손 실수 방어(사용자 결정 10-18 B).

select throws_ok(
  $$update public.admin_actions set reason = '고친 사유'
     where admin_user_id = '00000000-0000-0000-0000-00000000ad01'$$,
  'CM409', null,
  'postgres 도 작업 기록을 고치지 못한다(트리거)'
);                                                                                                   -- 40
select throws_ok(
  $$delete from public.admin_actions where admin_user_id = '00000000-0000-0000-0000-00000000ad01'$$,
  'CM409', null,
  'postgres 도 작업 기록을 지우지 못한다(트리거)'
);                                                                                                   -- 41
select throws_ok(
  $$truncate public.admin_actions$$,
  'CM409', null,
  'postgres 도 작업 기록을 truncate 로 비우지 못한다(트리거)'
);                                                                                                   -- 42
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.admin_actions_append_only()'::regprocedure),
  '막는 트리거 함수는 security invoker · search_path 빈 값이다(SUPABASE.md §5)'
);                                                                                                   -- 43

select * from finish();
rollback;
