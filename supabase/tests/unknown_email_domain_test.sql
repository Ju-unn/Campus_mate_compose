-- 등록되지 않은 학교 메일 도메인 기록(사용자 요청 10-17: 가입 못 한 사람들의 학교를 나중에 더하려고) 검증.
-- 마이그레이션 20261017120000_create_unknown_email_domain_attempts.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(32);

-- 5000개 한도 시험이 행 수를 세므로 로컬에 남은 행을 먼저 비운다(rollback 으로 되돌아간다).
delete from public.unknown_email_domain_attempts;

-- 1. 표 모양 · 권한 (postgres) ------------------------------------------------------

select columns_are('public', 'unknown_email_domain_attempts',
  array['domain', 'attempt_count', 'first_seen_at', 'last_seen_at'],
  '칸은 도메인 · 횟수 · 처음 · 마지막 시각 넷뿐이다 — 메일 앞부분 · 사용자 id · IP 칸이 없다');            -- 1
select col_is_pk('public', 'unknown_email_domain_attempts', 'domain', '도메인 하나에 행 하나다');           -- 2
select ok((select relrowsecurity from pg_class where oid = 'public.unknown_email_domain_attempts'::regclass),
  'RLS 가 켜져 있다');                                                                                 -- 3
select is(
  (select count(*) from pg_policies
    where schemaname = 'public' and tablename = 'unknown_email_domain_attempts'),
  0::bigint,
  '정책 없음 = 앱은 읽지도 쓰지도 못한다'
);                                                                                                   -- 4
select table_privs_are('public', 'unknown_email_domain_attempts', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'service_role 은 읽기 · 쓰기 넷만 가진다');            -- 5
select table_privs_are('public', 'unknown_email_domain_attempts', 'authenticated', array[]::text[],
  'authenticated 는 표 권한이 없다');                                                                  -- 6
select table_privs_are('public', 'unknown_email_domain_attempts', 'anon', array[]::text[],
  'anon 은 표 권한이 없다');                                                                           -- 7
select throws_ok(
  $$insert into public.unknown_email_domain_attempts (domain) values ('Upper.AC.kr')$$,
  '23514', null,
  '대문자 도메인은 표의 형식 검사가 막는다'
);                                                                                                   -- 8
select throws_ok(
  $$insert into public.unknown_email_domain_attempts (domain) values ('hong@leak.ac.kr')$$,
  '23514', null,
  '"@" 가 든 값(메일 주소)은 표에 들어가지 못한다'
);                                                                                                   -- 9
select throws_ok(
  $$insert into public.unknown_email_domain_attempts (domain) values (repeat('a', 251) || '.kr')$$,
  '23514', null,
  '253 자를 넘는 도메인(254 자)은 막는다'
);                                                                                                   -- 10
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.record_unknown_email_domain(text)'::regprocedure),
  'record_unknown_email_domain 은 security invoker · search_path 빈 값이다(SUPABASE.md §5)'
);                                                                                                   -- 11
select ok(
  has_function_privilege('service_role', 'public.record_unknown_email_domain(text)', 'execute')
  and not has_function_privilege('anon', 'public.record_unknown_email_domain(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.record_unknown_email_domain(text)', 'execute'),
  'record_unknown_email_domain 은 service_role 만 부른다(PUBLIC 실행 권한도 걷었다)'
);                                                                                                   -- 12

-- 2. 기록 함수 (service_role) ------------------------------------------------------
-- 함수가 security invoker 라 부르는 쪽 권한으로 돈다 — FastAPI 와 같은 service_role 로 불러야 표 권한이 모자란지 드러난다
-- (postgres 로 부르면 무엇이든 통과한다). 3 절까지 service_role 이다.
set local role service_role;

select lives_ok(
  $$select public.record_unknown_email_domain('new-school.ac.kr')$$,
  '처음 보는 도메인을 기록한다'
);                                                                                                   -- 13
select is(
  (select attempt_count from public.unknown_email_domain_attempts where domain = 'new-school.ac.kr'),
  1,
  '처음 기록하면 횟수는 1 이다'
);                                                                                                   -- 14
select ok(
  (select first_seen_at = now() and last_seen_at = now()
     from public.unknown_email_domain_attempts where domain = 'new-school.ac.kr'),
  '처음 · 마지막 시각이 지금이다'
);                                                                                                   -- 15

-- 트랜잭션 안에서는 now() 가 그대로라 두 시각을 과거로 돌려 두고 다시 부른다.
update public.unknown_email_domain_attempts
set first_seen_at = '2000-01-01 00:00+00', last_seen_at = '2000-01-01 00:00+00'
where domain = 'new-school.ac.kr';

select lives_ok(
  $$select public.record_unknown_email_domain('new-school.ac.kr')$$,
  '같은 도메인을 다시 기록한다'
);                                                                                                   -- 16
select ok(
  (select attempt_count = 2 and last_seen_at = now() and first_seen_at = '2000-01-01 00:00+00'
     from public.unknown_email_domain_attempts where domain = 'new-school.ac.kr'),
  '다시 기록하면 2 가 되고 마지막 시각만 지금으로 바뀐다(처음 시각은 그대로)'
);                                                                                                   -- 17
select lives_ok(
  $$select public.record_unknown_email_domain('  New-School.AC.KR  ')$$,
  '대문자 · 앞뒤 공백이 섞인 도메인도 오류 없이 받는다'
);                                                                                                   -- 18
select ok(
  (select attempt_count = 3 from public.unknown_email_domain_attempts where domain = 'new-school.ac.kr')
  and (select count(*) = 1 from public.unknown_email_domain_attempts),
  '소문자 · 공백 제거로 정리해 같은 행을 올린다(새 행이 생기지 않는다)'
);                                                                                                   -- 19
select lives_ok(
  $$select public.record_unknown_email_domain(d)
      from unnest(array[null, '', '   ', 'hong@new-school.ac.kr', 'localhost', 'bad domain.ac.kr',
                        'under_score.ac.kr', '.ac.kr', 'ac.kr.', repeat('a', 251) || '.kr']) as d$$,
  '이상한 입력(빈 값 · 메일 주소 · 점 없음 · 공백 · 밑줄 · 앞뒤 점 · 254 자)도 오류를 내지 않는다'
);                                                                                                   -- 20
select is(
  (select count(*) from public.unknown_email_domain_attempts),
  1::bigint,
  '이상한 입력은 아무것도 기록하지 않는다(메일 주소를 잘못 넘겨도 남지 않는다)'
);                                                                                                   -- 21

-- 3. 5000개 한도 (남용 방어) --------------------------------------------------------
-- 지금 1행이다. 4998행을 채워 4999행으로 만든다.
insert into public.unknown_email_domain_attempts (domain)
select 'filler-' || g || '.ac.kr' from generate_series(1, 4998) as g;

select lives_ok(
  $$select public.record_unknown_email_domain('edge.ac.kr')$$,
  '4999행일 때 새 도메인을 기록한다'
);                                                                                                   -- 22
select ok(
  exists (select 1 from public.unknown_email_domain_attempts where domain = 'edge.ac.kr')
  and (select count(*) = 5000 from public.unknown_email_domain_attempts),
  '한도 바로 아래에서는 새 도메인이 들어가 5000행이 된다'
);                                                                                                   -- 23
select lives_ok(
  $$select public.record_unknown_email_domain('over.ac.kr')$$,
  '5000행에서 새 도메인을 불러도 오류가 없다(서버는 최선만으로 부른다)'
);                                                                                                   -- 24
select ok(
  not exists (select 1 from public.unknown_email_domain_attempts where domain = 'over.ac.kr')
  and (select count(*) = 5000 from public.unknown_email_domain_attempts),
  '5000행이면 새 도메인은 기록하지 않는다 — 임의 도메인으로 표를 부풀리지 못한다'
);                                                                                                   -- 25
select lives_ok(
  $$select public.record_unknown_email_domain('new-school.ac.kr')$$,
  '5000행에서 기존 도메인을 기록한다'
);                                                                                                   -- 26
select is(
  (select attempt_count from public.unknown_email_domain_attempts where domain = 'new-school.ac.kr'),
  4,
  '5000행이어도 기존 도메인의 횟수는 오른다'
);                                                                                                   -- 27

-- 4. 앱 역할로 직접 ---------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000d001", "role": "authenticated"}';

select throws_ok(
  $$select domain from public.unknown_email_domain_attempts$$,
  '42501', null,
  'authenticated 는 기록을 읽을 수 없다'
);                                                                                                   -- 28
select throws_ok(
  $$insert into public.unknown_email_domain_attempts (domain) values ('app.ac.kr')$$,
  '42501', null,
  'authenticated 는 표에 직접 쓸 수 없다'
);                                                                                                   -- 29
select throws_ok(
  $$select public.record_unknown_email_domain('app.ac.kr')$$,
  '42501', null,
  'authenticated 는 기록 함수를 부를 수 없다(앱이 표를 부풀리는 길)'
);                                                                                                   -- 30

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select domain from public.unknown_email_domain_attempts$$,
  '42501', null,
  'anon 은 기록을 읽을 수 없다'
);                                                                                                   -- 31
select throws_ok(
  $$select public.record_unknown_email_domain('app.ac.kr')$$,
  '42501', null,
  'anon 은 기록 함수를 부를 수 없다'
);                                                                                                   -- 32

reset role;

select * from finish();
rollback;
