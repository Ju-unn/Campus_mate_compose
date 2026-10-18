-- 관리자 웹 대시보드 D2(설계 바탕화면 관리자_대시보드_설계_10-18.md §8 머리 · §8-2) 검증:
-- 신고 닫기 · 정지 · 해제 · 가림 해제 · 글 가림과 작업 기록을 한 번에 하는 함수 다섯. 마이그레이션 20261018030000_admin_report_review.
-- 기대값 기준: docs/superpowers/plans/2026-10-18-admin-report-review.md Task 1.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(56);

-- 준비 (postgres) -------------------------------------------------------------
-- AD = 관리자(…ad02, auth 계정 없이 id 만). 사람: E0 = 신고당한 active(온보딩 끝), E1 · E2 · E3 = 신고자,
-- E4 = 온보딩 전에 SQL 로 정지, E5 = 온보딩 끝내고 SQL 로 정지, E6 = 온보딩은 끝났지만 아직 pending, E7 = 탈퇴,
-- E8 = 자동 가림된 사람(열린 신고 셋 + 닫힌 신고 하나), E9 = 투표 글 · 지인 리뷰 작성자.
-- 신고: EA01 · EA02 · EA03 = E0 대상(열림), EA04 = E9 투표 글(열림), EA05~07 = E8 대상(열림), EA08 = E8 대상(이미 조치),
-- EA09 = 대상 계정이 지워진 신고(target_profile_id null), EA0A = E3 대상(열림, 되돌림 확인용).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000e', '테스트대학교E', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('teste.ac.kr', '00000000-0000-0000-0000-00000000000e');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e0', 'rr-0@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e1', 'rr-1@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e2', 'rr-2@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e3', 'rr-3@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e4', 'rr-4@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e5', 'rr-5@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e6', 'rr-6@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e7', 'rr-7@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e8', 'rr-8@teste.ac.kr'),
  ('00000000-0000-0000-0000-0000000000e9', 'rr-9@teste.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-00000000000e' from auth.users
where id between '00000000-0000-0000-0000-0000000000e0' and '00000000-0000-0000-0000-0000000000e9'
on conflict (id) do nothing;

-- 온보딩 체크(profiles_active_requires_onboarding)의 네 칸만 채운다. E0 은 active, E5 · E6 은 칸만 채우고 상태는 아래에서.
update public.profiles set gender = 'female', birth_year = 2003, height_cm = 165,
  nickname = case id
    when '00000000-0000-0000-0000-0000000000e0' then '신검대상'
    when '00000000-0000-0000-0000-0000000000e5' then '신검오'
    when '00000000-0000-0000-0000-0000000000e6' then '신검육'
  end
where id in ('00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-0000000000e5',
             '00000000-0000-0000-0000-0000000000e6');
update public.profiles set status = 'active' where id = '00000000-0000-0000-0000-0000000000e0';
-- 대시보드 이전에 SQL 로 정지한 두 사람(작업 기록 없음).
update public.profiles set status = 'suspended'
where id in ('00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000e5');
update public.profiles set status = 'withdrawn', withdrawn_at = now() where id = '00000000-0000-0000-0000-0000000000e7';
update public.profiles set auto_hidden_at = now() - interval '1 hour'
where id in ('00000000-0000-0000-0000-0000000000e8', '00000000-0000-0000-0000-0000000000e3');

insert into public.polls (id, author_id, question)
values ('00000000-0000-0000-0000-00000000eb01', '00000000-0000-0000-0000-0000000000e9', '신고 검수 질문');
insert into public.friend_reviews (id, reviewer_id, reviewee_id, tags)
values ('00000000-0000-0000-0000-00000000ec01', '00000000-0000-0000-0000-0000000000e9',
        '00000000-0000-0000-0000-0000000000e1', array['다정해요']);

insert into public.reports (id, reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason) values
  ('00000000-0000-0000-0000-00000000ea01', '00000000-0000-0000-0000-0000000000e1', 'profile',
   '00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-0000000000e0', '{}', 'abuse'),
  ('00000000-0000-0000-0000-00000000ea02', '00000000-0000-0000-0000-0000000000e2', 'message',
   '00000000-0000-0000-0000-00000000ed01', '00000000-0000-0000-0000-0000000000e0', '{}', 'sexual'),
  ('00000000-0000-0000-0000-00000000ea03', '00000000-0000-0000-0000-0000000000e3', 'profile',
   '00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-0000000000e0', '{}', 'spam'),
  ('00000000-0000-0000-0000-00000000ea04', '00000000-0000-0000-0000-0000000000e1', 'poll',
   '00000000-0000-0000-0000-00000000eb01', '00000000-0000-0000-0000-0000000000e9', '{}', 'abuse'),
  ('00000000-0000-0000-0000-00000000ea05', '00000000-0000-0000-0000-0000000000e1', 'profile',
   '00000000-0000-0000-0000-0000000000e8', '00000000-0000-0000-0000-0000000000e8', '{}', 'fake'),
  ('00000000-0000-0000-0000-00000000ea06', '00000000-0000-0000-0000-0000000000e2', 'profile',
   '00000000-0000-0000-0000-0000000000e8', '00000000-0000-0000-0000-0000000000e8', '{}', 'fake'),
  ('00000000-0000-0000-0000-00000000ea07', '00000000-0000-0000-0000-0000000000e3', 'profile',
   '00000000-0000-0000-0000-0000000000e8', '00000000-0000-0000-0000-0000000000e8', '{}', 'fake'),
  ('00000000-0000-0000-0000-00000000ea09', '00000000-0000-0000-0000-0000000000e2', 'profile',
   '00000000-0000-0000-0000-00000000eeee', null, '{}', 'spam'),
  ('00000000-0000-0000-0000-00000000ea0a', '00000000-0000-0000-0000-0000000000e2', 'profile',
   '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e3', '{}', 'spam');
insert into public.reports (id, reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason,
                            status, resolved_at) values
  ('00000000-0000-0000-0000-00000000ea08', '00000000-0000-0000-0000-0000000000e9', 'profile',
   '00000000-0000-0000-0000-0000000000e8', '00000000-0000-0000-0000-0000000000e8', '{}', 'abuse',
   'actioned', '2026-10-01 00:00:00+00');

-- 1. 함수 모양 · 권한 (postgres) --------------------------------------------------

-- pg_proc 의 proname · proconfig 는 "C" 정렬 규칙이라 results_eq 의 행 비교에서 values 쪽 글자(기본 규칙)와 섞이면
-- "could not determine which collation" 으로 멈춘다 — 조건을 한 쿼리 안에서 보고 개수만 비교한다(D1 시험의 ok(...) 와 같은 비교).
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_resolve_report', 'admin_suspend_profile', 'admin_unsuspend_profile',
                        'admin_unhide_profile', 'admin_set_content_status')
      and not p.prosecdef and p.proconfig = array['search_path=""']),
  5::bigint,
  '다섯 함수가 있고 모두 security invoker · search_path 빈 값이다(SUPABASE.md §5 — security definer 금지)'
);                                                                                                   -- 1
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_resolve_report', 'admin_suspend_profile', 'admin_unsuspend_profile',
                        'admin_unhide_profile', 'admin_set_content_status')
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')),
  5::bigint,
  'service_role 만 부를 수 있다 — anon · authenticated(그리고 public)는 실행 권한이 없다'
);                                                                                                   -- 2

-- 2. 신고 닫기 (service_role) ---------------------------------------------------------
-- FastAPI 와 같은 service_role 로 해야 표 권한이 모자란지 드러난다(postgres 는 무엇이든 통과한다).
set local role service_role;

select results_eq(
  $$select r->>'id', r->>'status', r->'closed_ids'
      from (select public.admin_resolve_report('00000000-0000-0000-0000-00000000ad02',
              '00000000-0000-0000-0000-00000000ea01', 'actioned', '욕설 확인', false, '203.0.113.9') as r) as call$$,
  $$values ('00000000-0000-0000-0000-00000000ea01', 'actioned', '["00000000-0000-0000-0000-00000000ea01"]'::jsonb)$$,
  '조치 완료하면 그 건만 닫았다고 돌려준다'
);                                                                                                   -- 3
select results_eq(
  $$select id::text, status::text, resolved_at is not null from public.reports
     where id in ('00000000-0000-0000-0000-00000000ea01', '00000000-0000-0000-0000-00000000ea02',
                  '00000000-0000-0000-0000-00000000ea03') order by id$$,
  $$values ('00000000-0000-0000-0000-00000000ea01', 'actioned', true),
           ('00000000-0000-0000-0000-00000000ea02', 'open', false),
           ('00000000-0000-0000-0000-00000000ea03', 'open', false)$$,
  '표에는 그 건만 조치 · 처리 시각이 찍히고 같은 사람의 다른 신고는 열린 채다'
);                                                                                                   -- 4
select results_eq(
  $$select admin_user_id, action, target_type, before, after, reason, ip
      from public.admin_actions where target_id = '00000000-0000-0000-0000-00000000ea01'$$,
  $$values ('00000000-0000-0000-0000-00000000ad02'::uuid, 'report_resolve', 'report',
            '{"status": "open"}'::jsonb, '{"status": "actioned"}'::jsonb, '욕설 확인', '203.0.113.9'::inet)$$,
  '작업 기록 한 줄 — 누가 · 닫기 · 대상 · 전후 상태 · 메모 · ip'
);                                                                                                   -- 5
select throws_ok(
  $$select public.admin_resolve_report('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000ea01',
      'dismissed', null, false, null)$$,
  'CM409', null, 'second resolve raises CM409 — 이미 닫힌 신고'
);                                                                                                   -- 6
select throws_ok(
  $$select public.admin_resolve_report('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000eeee',
      'dismissed', null, false, null)$$,
  'CM404', null, '없는 신고는 CM404(서버 404)'
);                                                                                                   -- 7
select throws_ok(
  $$select public.admin_resolve_report('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000ea02',
      'open', null, false, null)$$,
  '22023', null, '결과가 open 이면 닫기가 아니다 — 22023(서버 422)'
);                                                                                                   -- 8
select throws_ok(
  $$select public.admin_resolve_report('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000ea02',
      null, null, false, null)$$,
  '22023', null, '결과가 비면 22023'
);                                                                                                   -- 9

-- 3. 같은 대상 함께 닫기 (service_role) --------------------------------------------------

select is(
  (public.admin_resolve_report('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000ea02',
      'dismissed', null, true, null))->'closed_ids',
  '["00000000-0000-0000-0000-00000000ea02", "00000000-0000-0000-0000-00000000ea03"]'::jsonb,
  '같은 대상 함께 닫기는 같은 사람(E0)의 열린 신고 둘을 닫았다고 돌려준다'
);                                                                                                   -- 10
select results_eq(
  $$select id::text, status::text, resolved_at is not null from public.reports
     where id in ('00000000-0000-0000-0000-00000000ea02', '00000000-0000-0000-0000-00000000ea03',
                  '00000000-0000-0000-0000-00000000ea04') order by id$$,
  $$values ('00000000-0000-0000-0000-00000000ea02', 'dismissed', true),
           ('00000000-0000-0000-0000-00000000ea03', 'dismissed', true),
           ('00000000-0000-0000-0000-00000000ea04', 'open', false)$$,
  '다른 사람(E9)을 향한 신고는 그대로 열려 있다'
);                                                                                                   -- 11
select is(
  (select count(*) from public.admin_actions
    where target_id in ('00000000-0000-0000-0000-00000000ea02', '00000000-0000-0000-0000-00000000ea03')
      and action = 'report_resolve' and after = '{"status": "dismissed"}'::jsonb),
  2::bigint, '닫힌 신고마다 기록 한 줄'
);                                                                                                   -- 12
select is(
  (public.admin_resolve_report('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000ea09',
      'actioned', null, true, null))->'closed_ids',
  '["00000000-0000-0000-0000-00000000ea09"]'::jsonb,
  '대상 계정이 지워진 신고(target_profile_id null)는 함께 닫기여도 그 건만 닫는다'
);                                                                                                   -- 13
select is(
  (select count(*) from public.reports
    where id in ('00000000-0000-0000-0000-00000000ea04', '00000000-0000-0000-0000-00000000ea05',
                 '00000000-0000-0000-0000-00000000ea06', '00000000-0000-0000-0000-00000000ea07',
                 '00000000-0000-0000-0000-00000000ea0a')
      and status = 'open'),
  5::bigint, '대상 없는 함께 닫기가 대상 없는 다른 신고 · 남의 신고를 건드리지 않았다'
);                                                                                                   -- 14

-- 4. 정지 · 해제 (service_role) -------------------------------------------------------

select is(
  public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e0',
    '반복 욕설', '203.0.113.9'),
  '{"id": "00000000-0000-0000-0000-0000000000e0", "status": "suspended"}'::jsonb,
  '정지하면 처리 뒤 모양을 돌려준다'
);                                                                                                   -- 15
select is(
  (select status::text from public.profiles where id = '00000000-0000-0000-0000-0000000000e0'),
  'suspended', '표에도 정지'
);                                                                                                   -- 16
select results_eq(
  $$select action, target_type, before, after, reason, ip from public.admin_actions
     where target_id = '00000000-0000-0000-0000-0000000000e0' and action = 'profile_suspend'$$,
  $$values ('profile_suspend', 'profile', '{"status": "active"}'::jsonb, '{"status": "suspended"}'::jsonb,
            '반복 욕설', '203.0.113.9'::inet)$$,
  '정지 기록의 before 에 직전 상태(active)가 남는다 — 해제가 이 값으로 되돌린다'
);                                                                                                   -- 17
select throws_ok(
  $$select public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e0',
      '다시', null)$$,
  'CM409', null, 'second suspend raises CM409 — 이미 정지된 계정'
);                                                                                                   -- 18
select throws_ok(
  $$select public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e7',
      '탈퇴한 사람', null)$$,
  'CM409', null, '탈퇴한 계정은 정지하지 않는다 — CM409'
);                                                                                                   -- 19
select throws_ok(
  $$select public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000eeee',
      '없는 사람', null)$$,
  'CM404', null, '없는 계정은 CM404'
);                                                                                                   -- 20
select throws_ok(
  $$select public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e1',
      '   ', null)$$,
  '22023', null, '공백뿐인 사유로는 정지하지 않는다 — 22023'
);                                                                                                   -- 21
select throws_ok(
  $$select public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e1',
      null, null)$$,
  '22023', null, '사유 없이는 정지하지 않는다 — 22023'
);                                                                                                   -- 22
select is(
  public.admin_unsuspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e0',
    '소명 확인', null)->>'status',
  'active', '대시보드로 정지한 active 계정은 해제하면 active 로 돌아간다'
);                                                                                                   -- 23
select results_eq(
  $$select before, after, reason from public.admin_actions
     where target_id = '00000000-0000-0000-0000-0000000000e0' and action = 'profile_unsuspend'$$,
  $$values ('{"status": "suspended"}'::jsonb, '{"status": "active"}'::jsonb, '소명 확인')$$,
  '해제 기록 한 줄'
);                                                                                                   -- 24
select throws_ok(
  $$select public.admin_unsuspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e0',
      '다시', null)$$,
  'CM409', null, '정지 중이 아닌 계정을 해제하면 CM409'
);                                                                                                   -- 25
select is(
  public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e6',
    '확인 중', null)->>'status',
  'suspended', '온보딩은 끝났지만 아직 pending 인 계정도 정지할 수 있다'
);                                                                                                   -- 26
select is(
  public.admin_unsuspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e6',
    '확인 끝', null)->>'status',
  'pending', '해제는 기록의 직전 상태(pending)로 — 온보딩이 끝났어도 active 로 올리지 않는다'
);                                                                                                   -- 27
select is(
  public.admin_unsuspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e5',
    '옛 정지 해제', null)->>'status',
  'active', 'SQL 로 정지해 기록이 없으면 온보딩 체크 네 칸을 채운 계정은 active'
);                                                                                                   -- 28
select is(
  public.admin_unsuspend_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e4',
    '옛 정지 해제', null)->>'status',
  'pending', 'SQL 로 정지해 기록이 없고 온보딩 전이면 pending(active 고정이면 온보딩 체크가 23514 로 막는다)'
);                                                                                                   -- 29
select results_eq(
  $$select id::text, status::text from public.profiles
     where id in ('00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-0000000000e4',
                  '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000e6') order by id$$,
  $$values ('00000000-0000-0000-0000-0000000000e0', 'active'), ('00000000-0000-0000-0000-0000000000e4', 'pending'),
           ('00000000-0000-0000-0000-0000000000e5', 'active'), ('00000000-0000-0000-0000-0000000000e6', 'pending')$$,
  '표에도 되돌린 상태 그대로'
);                                                                                                   -- 30

-- 5. 자동 가림 해제 (service_role) -----------------------------------------------------
-- 시각만 지우면 열린 신고 셋이 그대로라 다음 신고 한 건에 다시 가려진다(safety/repository.py count_open_reporters).

select results_eq(
  $$select r->'auto_hidden_at', r->'dismissed_ids'
      from (select public.admin_unhide_profile('00000000-0000-0000-0000-00000000ad02',
              '00000000-0000-0000-0000-0000000000e8', '오신고 확인', '203.0.113.9') as r) as call$$,
  $$values ('null'::jsonb, '["00000000-0000-0000-0000-00000000ea05", "00000000-0000-0000-0000-00000000ea06",
                              "00000000-0000-0000-0000-00000000ea07"]'::jsonb)$$,
  '가림 해제는 시각을 비우고 그 사람의 열린 신고 셋을 기각했다고 돌려준다'
);                                                                                                   -- 31
select ok(
  (select auto_hidden_at is null from public.profiles where id = '00000000-0000-0000-0000-0000000000e8'),
  '표에서도 auto_hidden_at 이 비었다'
);                                                                                                   -- 32
select results_eq(
  $$select id::text, status::text, resolved_at from public.reports
     where id in ('00000000-0000-0000-0000-00000000ea05', '00000000-0000-0000-0000-00000000ea08') order by id$$,
  $$values ('00000000-0000-0000-0000-00000000ea05', 'dismissed', now()),
           ('00000000-0000-0000-0000-00000000ea08', 'actioned', '2026-10-01 00:00:00+00'::timestamptz)$$,
  '열린 신고는 지금 시각으로 기각되고, 이미 조치한 신고는 상태 · 처리 시각이 그대로다'
);                                                                                                   -- 33
select is(
  (select count(distinct reporter_id) from public.reports
    where target_profile_id = '00000000-0000-0000-0000-0000000000e8' and status = 'open'),
  0::bigint, 'unhide leaves no open reporters — 다음 신고는 0명부터 센다'
);                                                                                                   -- 34
select results_eq(
  $$select action, count(*), bool_and(reason = '오신고 확인') from public.admin_actions
     where (target_type = 'profile' and target_id = '00000000-0000-0000-0000-0000000000e8')
        or (target_type = 'report' and target_id in ('00000000-0000-0000-0000-00000000ea05',
            '00000000-0000-0000-0000-00000000ea06', '00000000-0000-0000-0000-00000000ea07'))
     group by action order by action$$,
  $$values ('profile_unhide', 1::bigint, true), ('report_resolve', 3::bigint, true)$$,
  '기록은 가림 해제 한 줄 + 기각한 신고마다 한 줄, 모두 같은 사유'
);                                                                                                   -- 35
select results_eq(
  $$select before ? 'auto_hidden_at', after from public.admin_actions
     where action = 'profile_unhide' and target_id = '00000000-0000-0000-0000-0000000000e8'
    union all
    select null, after from public.admin_actions
     where action = 'report_resolve' and target_id = '00000000-0000-0000-0000-00000000ea05'$$,
  $$values (true, '{"auto_hidden_at": null}'::jsonb),
           (null::boolean, '{"status": "dismissed", "via": "profile_unhide"}'::jsonb)$$,
  '가림 해제 기록의 before 에 지운 시각, 기각 기록의 after 에 무엇 때문에 닫았는지'
);                                                                                                   -- 36
select throws_ok(
  $$select public.admin_unhide_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e8',
      '다시', null)$$,
  'CM409', null, '가려지지 않은 사람의 가림 해제는 CM409'
);                                                                                                   -- 37
select throws_ok(
  $$select public.admin_unhide_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000eeee',
      '없는 사람', null)$$,
  'CM404', null, '없는 계정은 CM404'
);                                                                                                   -- 38
select throws_ok(
  $$select public.admin_unhide_profile('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000e3',
      '', null)$$,
  '22023', null, '빈 사유로는 가림을 풀지 않는다 — 22023'
);                                                                                                   -- 39

-- 6. 투표 글 · 지인 리뷰 가림 (service_role) ---------------------------------------------

select is(
  public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll', '00000000-0000-0000-0000-00000000eb01',
    'blinded', '욕설 글', '203.0.113.9'),
  '{"id": "00000000-0000-0000-0000-00000000eb01", "status": "blinded"}'::jsonb,
  '투표 글을 가리면 처리 뒤 모양을 돌려준다'
);                                                                                                   -- 40
select results_eq(
  $$select action, target_type, before, after, reason from public.admin_actions
     where target_id = '00000000-0000-0000-0000-00000000eb01'$$,
  $$values ('content_blind', 'poll', '{"status": "visible"}'::jsonb, '{"status": "blinded"}'::jsonb, '욕설 글')$$,
  '글 가림 기록 — 대상 종류 poll · 전후 상태 · 사유'
);                                                                                                   -- 41
select throws_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll',
      '00000000-0000-0000-0000-00000000eb01', 'blinded', '다시', null)$$,
  'CM409', null, '이미 가린 글을 다시 가리면 CM409'
);                                                                                                   -- 42
select is(
  public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll', '00000000-0000-0000-0000-00000000eb01',
    'visible', '잘못 가림', null)->>'status',
  'visible', '가린 글을 다시 보이게 한다'
);                                                                                                   -- 43
select is(
  public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'friend_review',
    '00000000-0000-0000-0000-00000000ec01', 'blinded', '비방 리뷰', null)->>'status',
  'blinded', '지인 리뷰도 같은 함수로 가린다'
);                                                                                                   -- 44
select results_eq(
  $$select (select status::text from public.polls where id = '00000000-0000-0000-0000-00000000eb01'),
           (select status::text from public.friend_reviews where id = '00000000-0000-0000-0000-00000000ec01'),
           (select action || ':' || target_type from public.admin_actions
             where target_id = '00000000-0000-0000-0000-00000000ec01')$$,
  $$values ('visible', 'blinded', 'content_blind:friend_review')$$,
  '표에도 투표 글 보임 · 리뷰 가림, 리뷰 기록의 대상 종류는 friend_review'
);                                                                                                   -- 45
select throws_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'profile',
      '00000000-0000-0000-0000-0000000000e0', 'blinded', '프로필', null)$$,
  '22023', null, '글이 아닌 대상(profile · message)은 22023'
);                                                                                                   -- 46
select throws_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll',
      '00000000-0000-0000-0000-00000000eeee', 'blinded', '없는 글', null)$$,
  'CM404', null, '없는 글은 CM404'
);                                                                                                   -- 47
select throws_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll',
      '00000000-0000-0000-0000-00000000eb01', 'blinded', ' ', null)$$,
  '22023', null, '공백 사유로는 글을 가리지 않는다 — 22023'
);                                                                                                   -- 48

-- 7. 기록이 실패하면 조치도 없던 일 (service_role) ----------------------------------------
-- 누가 했는지(admin_actions.admin_user_id not null)를 비우면 바꾼 뒤 기록 insert 에서 23502 로 멈춘다.
-- 함수 하나 = 한 트랜잭션이라 바꾼 것도 함께 되돌아가야 한다(설계 §8 머리 "기록 없는 조치 금지").

select throws_ok(
  $$select public.admin_resolve_report(null, '00000000-0000-0000-0000-00000000ea04', 'actioned', null, true, null)$$,
  '23502', null, '누가 했는지 없이는 신고를 닫을 수 없다'
);                                                                                                   -- 49
select throws_ok(
  $$select public.admin_suspend_profile(null, '00000000-0000-0000-0000-0000000000e1', '사유', null)$$,
  '23502', null, '누가 했는지 없이는 정지할 수 없다'
);                                                                                                   -- 50
select throws_ok(
  $$select public.admin_unhide_profile(null, '00000000-0000-0000-0000-0000000000e3', '사유', null)$$,
  '23502', null, '누가 했는지 없이는 가림을 풀 수 없다'
);                                                                                                   -- 51
select results_eq(
  $$select (select status::text from public.reports where id = '00000000-0000-0000-0000-00000000ea04'),
           (select status::text from public.profiles where id = '00000000-0000-0000-0000-0000000000e1'),
           (select auto_hidden_at is not null from public.profiles where id = '00000000-0000-0000-0000-0000000000e3'),
           (select status::text from public.reports where id = '00000000-0000-0000-0000-00000000ea0a')$$,
  $$values ('open', 'pending', true, 'open')$$,
  '기록이 실패한 닫기 · 정지 · 가림 해제는 신고 · 상태 · 가림 · 열린 신고가 모두 그대로다'
);                                                                                                   -- 52
select is(
  (select count(*) from public.admin_actions where admin_user_id = '00000000-0000-0000-0000-00000000ad02'),
  17::bigint, '성공한 조치의 기록만 남았다 — 닫기 4 · 정지 2 · 해제 4 · 가림 해제 4 · 글 3'
);                                                                                                   -- 53

-- 8. 앱 역할로 직접 ---------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000e0", "role": "authenticated"}';

select throws_ok(
  $$select public.admin_unsuspend_profile('00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-0000000000e0',
      '내가 나를', null)$$,
  '42501', null, 'authenticated 는 정지를 푸는 함수를 부를 수 없다'
);                                                                                                   -- 54
select throws_ok(
  $$select public.admin_unhide_profile('00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-0000000000e3',
      '내가 푼다', null)$$,
  '42501', null, 'authenticated 는 가림을 푸는 함수를 부를 수 없다'
);                                                                                                   -- 55

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select public.admin_resolve_report('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-00000000ea04',
      'dismissed', null, false, null)$$,
  '42501', null, 'anon 은 신고를 닫는 함수를 부를 수 없다'
);                                                                                                   -- 56

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
