-- 관리자 웹 대시보드 D1(설계 바탕화면 관리자_대시보드_설계_10-18.md §8 머리 · §8-1) 검증:
-- 인증샷 검수와 작업 기록을 한 번에 하는 admin_review_heart_task. 마이그레이션 20261018011200_admin_review_heart_task ·
-- 20261018035204_admin_security_hardening(맨 앞 명단 확인 admin_assert).
-- 기대값 기준: docs/superpowers/plans/2026-10-18-admin-heart-task-review.md Task 1.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- 준비 (postgres) -------------------------------------------------------------
-- AD = 관리자(…ad01). 함수가 맨 앞에서 명단을 보므로(admin_assert) auth 계정을 만들고 admin_users 에 넣는다.
-- 제출자 A = ...d0, B = ...d1, C = ...d2.
-- S1 = A 에브리타임(승인할 것), S2 = B 단톡방(반려할 것), S3 = C 에브리타임(규칙 위반 · 되돌림 확인용 — 끝까지 검수 중).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000d', '테스트대학교D', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('testd.ac.kr', '00000000-0000-0000-0000-00000000000d');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d0', 'r-a@testd.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d1', 'r-b@testd.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d2', 'r-c@testd.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-00000000000d' from auth.users
where id between '00000000-0000-0000-0000-0000000000d0' and '00000000-0000-0000-0000-0000000000d2'
on conflict (id) do nothing;

insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000d0', 'everytime_post', 'd0/f1.jpg', 40),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000d1', 'kakao_share', 'd1/f2.jpg', 25),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000d2', 'everytime_post', 'd2/f3.jpg', 40);

insert into auth.users (id, email, raw_app_meta_data)
values ('00000000-0000-0000-0000-00000000ad01', 'operator-d1@example.com', '{"provider": "google", "providers": ["google"]}');
insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-00000000ad01');

-- 1. 함수 모양 · 권한 (postgres) --------------------------------------------------

select has_function('public', 'admin_review_heart_task',
  array['uuid', 'uuid', 'submission_status', 'heart_task_reject_reason', 'inet'],
  'admin_review_heart_task(관리자, 제출, 상태, 사유, ip) 가 있다');                                       -- 1
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.admin_review_heart_task(uuid, uuid, public.submission_status, public.heart_task_reject_reason, inet)'::regprocedure),
  'security invoker · search_path 빈 값이다(SUPABASE.md §5 — security definer 금지)'
);                                                                                                   -- 2
select ok(
  has_function_privilege('service_role',
    'public.admin_review_heart_task(uuid, uuid, public.submission_status, public.heart_task_reject_reason, inet)', 'execute'),
  'service_role 은 부를 수 있다'
);                                                                                                   -- 3

-- 2. 승인 (service_role) -----------------------------------------------------------
-- FastAPI 와 같은 service_role 로 해야 표 · 원장 권한이 모자란지 드러난다(postgres 는 무엇이든 통과한다).
set local role service_role;

select results_eq(
  $$select r->>'id', r->>'status', (r->>'reward_hearts')::integer, r->'reject_reason', r->>'reviewed_at' is not null
      from (select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01',
              '00000000-0000-0000-0000-0000000000f1', 'approved', null, '203.0.113.7') as r) as call$$,
  $$values ('00000000-0000-0000-0000-0000000000f1', 'approved', 40, 'null'::jsonb, true)$$,
  '승인하면 처리 뒤 모양(id · 상태 · 보상 · 사유 null · 검수 시각)을 돌려준다'
);                                                                                                   -- 4
select results_eq(
  $$select status::text, reviewed_at is not null from public.heart_task_submissions
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  $$values ('approved', true)$$,
  '표에도 승인 · 검수 시각이 찍힌다(시각은 guard 트리거가 찍는다)'
);                                                                                                   -- 5
select results_eq(
  $$select amount, reason::text, ref_id from public.heart_transactions
     where profile_id = '00000000-0000-0000-0000-0000000000d0'$$,
  $$values (40, 'free_task', '00000000-0000-0000-0000-0000000000f1'::uuid)$$,
  '하트는 기존 지급 트리거가 같은 트랜잭션에서 준다 — free_task 40 이 제출 id 로 한 줄'
);                                                                                                   -- 6
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000d0'),
  40, '잔액이 40 늘었다'
);                                                                                                   -- 7
select results_eq(
  $$select admin_user_id, action, target_type, before, after, reason is null, ip
      from public.admin_actions where target_id = '00000000-0000-0000-0000-0000000000f1'$$,
  $$values ('00000000-0000-0000-0000-00000000ad01'::uuid, 'heart_task_approve', 'heart_task_submission',
            '{"status": "submitted"}'::jsonb, '{"status": "approved", "reward_hearts": 40}'::jsonb, true,
            '203.0.113.7'::inet)$$,
  '작업 기록 한 줄 — 누가 · 승인 · 대상 · 전후 상태 · ip'
);                                                                                                   -- 8

-- 3. 반려 (service_role) -----------------------------------------------------------

select results_eq(
  $$select r->>'status', r->>'reject_reason', (r->>'reward_hearts')::integer, r->>'reviewed_at' is not null
      from (select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01',
              '00000000-0000-0000-0000-0000000000f2', 'rejected', 'reused', null) as r) as call$$,
  $$values ('rejected', 'reused', 25, true)$$,
  '반려하면 상태 · 사유를 돌려준다'
);                                                                                                   -- 9
select results_eq(
  $$select status::text, reject_reason::text, reviewed_at is not null from public.heart_task_submissions
     where id = '00000000-0000-0000-0000-0000000000f2'$$,
  $$values ('rejected', 'reused', true)$$,
  '표에도 반려 · 사유 · 검수 시각이 남는다'
);                                                                                                   -- 10
select is(
  (select count(*) from public.heart_transactions where profile_id = '00000000-0000-0000-0000-0000000000d1'),
  0::bigint, '반려는 하트 원장을 건드리지 않는다'
);                                                                                                   -- 11
select results_eq(
  $$select action, before, after, ip is null
      from public.admin_actions where target_id = '00000000-0000-0000-0000-0000000000f2'$$,
  $$values ('heart_task_reject', '{"status": "submitted"}'::jsonb,
            '{"status": "rejected", "reward_hearts": 25, "reject_reason": "reused"}'::jsonb, true)$$,
  '반려 기록에는 사유가 after 에 실린다. ip 를 모르면 비운다'
);                                                                                                   -- 12

-- 4. 이미 검수된 건 · 없는 건 (service_role) -----------------------------------------
-- 두 탭에서 같은 건을 누른 것과 같다 — 두 번째는 조건부 update 가 0줄이라 CM409(서버 409).

select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f1',
      'approved', null, null)$$,
  'CM409', null, 'second review raises CM409 — 승인한 건을 다시 승인'
);                                                                                                   -- 13
select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f1',
      'rejected', 'date_missing', null)$$,
  'CM409', null, 'second review raises CM409 — 승인한 건을 반려'
);                                                                                                   -- 14
select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f2',
      'approved', null, null)$$,
  'CM409', null, 'second review raises CM409 — 반려한 건을 승인'
);                                                                                                   -- 15
select results_eq(
  $$select (select count(*) from public.heart_transactions where profile_id = '00000000-0000-0000-0000-0000000000d0'),
           (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000d0'),
           (select status::text from public.heart_task_submissions where id = '00000000-0000-0000-0000-0000000000f1')$$,
  $$values (1::bigint, 40, 'approved')$$,
  '두 번째 검수 시도 뒤에도 원장 1줄 · 잔액 40 · 승인 그대로 — 하트는 한 번만'
);                                                                                                   -- 16
select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000ee',
      'approved', null, null)$$,
  'CM404', null, '없는 제출은 CM404(서버 404)'
);                                                                                                   -- 17

-- 5. 상태 · 사유 규칙 (service_role) — 모두 S3 에 대고, S3 은 끝까지 검수 중이어야 한다 ------------

select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f3',
      'approved', 'reused', null)$$,
  '22023', null, '승인에 사유를 붙이면 22023(서버 422)'
);                                                                                                   -- 18
select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f3',
      'rejected', null, null)$$,
  '22023', null, '사유 없는 반려는 22023'
);                                                                                                   -- 19
select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f3',
      'submitted', null, null)$$,
  '22023', null, '검수 중으로 "검수" 하는 것은 22023'
);                                                                                                   -- 20
select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f3',
      null, null, null)$$,
  '22023', null, '상태가 비면 22023'
);                                                                                                   -- 21

-- 6. 기록이 실패하면 · 명단에 없으면 조치도 없던 일 (service_role) -------------------------------
-- 기록 insert 권한을 이 트랜잭션 안에서만 잠깐 뺀다 — 명단 확인 · update · 지급 트리거까지 간 뒤 기록 insert 에서 42501 로 멈춘다.
-- (예전에는 p_admin 을 비워 23502 를 냈지만 이제 맨 앞 admin_assert 가 먼저 막는다 — 오류 글자로 둘을 가른다.)
-- 함수 하나 = 한 트랜잭션이라 승인 · 하트도 함께 되돌아가야 한다(설계 §8 머리 "기록 없는 조치 금지").
reset role;
revoke insert on public.admin_actions from service_role;
set local role service_role;
select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f3',
      'approved', null, null)$$,
  '42501', 'permission denied for table admin_actions', '기록을 남기지 못하면 검수할 수 없다(기록 insert 가 막는다)'
);                                                                                                   -- 22
reset role;
grant insert on public.admin_actions to service_role;
set local role service_role;
select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000f3',
      'approved', null, null)$$,
  '42501', 'not admin', '명단에 없는 id(제출자 본인)로는 검수하지 않는다 — admin_assert 가 42501'
);                                                                                                   -- 23
select throws_ok(
  $$select public.admin_review_heart_task(null, '00000000-0000-0000-0000-0000000000f3', 'approved', null, null)$$,
  '42501', 'not admin', '누가 했는지 없이는 검수할 수 없다 — admin_assert 가 먼저 막는다'
);                                                                                                   -- 24
select results_eq(
  $$select s.status::text, s.reviewed_at is null,
           (select count(*) from public.heart_transactions h where h.profile_id = s.profile_id)
      from public.heart_task_submissions s where s.id = '00000000-0000-0000-0000-0000000000f3'$$,
  $$values ('submitted', true, 0::bigint)$$,
  '기록이 실패한 승인 · 명단에 없는 id 의 승인은 상태 · 검수 시각 · 하트가 모두 그대로다'
);                                                                                                   -- 25
select is(
  (select count(*) from public.admin_actions
    where target_id in ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2',
                        '00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000ee')),
  2::bigint, '실패한 호출(13~24)은 작업 기록을 한 줄도 늘리지 않는다 — 성공한 승인 · 반려 두 줄뿐'
);                                                                                                   -- 26

-- 7. 앱 역할로 직접 ---------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000d2", "role": "authenticated"}';

select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000f3',
      'approved', null, null)$$,
  '42501', null, 'authenticated 는 자기 제출을 승인하는 함수를 부를 수 없다'
);                                                                                                   -- 27

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select public.admin_review_heart_task('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000f3',
      'approved', null, null)$$,
  '42501', null, 'anon 은 부를 수 없다'
);                                                                                                   -- 28

reset role;
reset request.jwt.claims;

select ok(
  not has_function_privilege('authenticated',
        'public.admin_review_heart_task(uuid, uuid, public.submission_status, public.heart_task_reject_reason, inet)', 'execute')
  and not has_function_privilege('anon',
        'public.admin_review_heart_task(uuid, uuid, public.submission_status, public.heart_task_reject_reason, inet)', 'execute'),
  '앱 역할에는 실행 권한 자체가 없다'
);                                                                                                   -- 29

select * from finish();
rollback;
