-- 무료로 하트 모으기(18a · 18b · 18c) 표 · 권한 · DB 함수 · 검수 트리거 검증.
-- 기대값 기준: docs/superpowers/plans/2026-09-28-heart-tasks.md Task C1 · C2.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(55);

-- 준비 --------------------------------------------------------------------
-- A = ...90(주 사용자), B = ...91(남 — RLS), M = ...92(달 경계), K = ...93(단톡방 3회 · 반려),
-- P = ...94(검수 중 · 투표 줄), G = ...95(탈퇴 cascade)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000009', '테스트대학교9', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test9.ac.kr', '00000000-0000-0000-0000-000000000009');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000090', 'h-a@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000091', 'h-b@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000092', 'h-m@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000093', 'h-k@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000094', 'h-p@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000095', 'h-g@test9.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000009' from auth.users
where id between '00000000-0000-0000-0000-000000000090' and '00000000-0000-0000-0000-000000000095'
on conflict (id) do nothing;

-- C1: 표 · enum · 권한 · 버킷 ---------------------------------------------
select has_table('public', 'heart_task_submissions', 'heart_task_submissions 표가 있다');                   -- 1
select enum_has_labels('public', 'heart_task', array['everytime_post', 'kakao_share'],
  'heart_task 는 everytime_post · kakao_share');                                                            -- 2
select enum_has_labels('public', 'submission_status', array['submitted', 'approved', 'rejected'],
  'submission_status 는 submitted · approved · rejected');                                                  -- 3
select enum_has_labels('public', 'heart_task_reject_reason', array['date_missing', 'not_verified', 'reused'],
  '반려 사유는 정해진 셋(D3)');                                                                              -- 4
select ok((select relrowsecurity from pg_class where oid = 'public.heart_task_submissions'::regclass),
  'heart_task_submissions 는 RLS 가 켜져 있다');                                                             -- 5
select is((select count(*) from pg_policies where tablename = 'heart_task_submissions'), 1::bigint,
  '정책은 본인 읽기 하나뿐이다(ERD §2 85줄)');                                                                -- 6
select table_privs_are('public', 'heart_task_submissions', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'service_role 은 네 권한이 다 있다');                        -- 7
select table_privs_are('public', 'heart_task_submissions', 'authenticated', array['SELECT'],
  'authenticated 는 select 만 있다');                                                                        -- 8
select table_privs_are('public', 'heart_task_submissions', 'anon', array[]::text[],
  'anon 은 아무 권한도 없다');                                                                                -- 9
select results_eq(
  $$select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'heart-task-proofs'$$,
  $$values (false, 10485760::bigint, array['image/jpeg', 'image/png'])$$,
  'heart-task-proofs 는 비공개 · 10MB · jpeg/png 다'
);                                                                                                           -- 10

-- 제약 확인용 줄 E1(A 의 에브리타임, 검수 중). 이 절 끝에서 비운다.
insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts)
values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000090', 'everytime_post',
        'a/e1.jpg', 50);

select results_eq(
  $$select status::text, reviewed_at is null, reject_reason is null from public.heart_task_submissions
     where id = '00000000-0000-0000-0000-0000000000e1'$$,
  $$values ('submitted', true, true)$$,
  '새 줄은 검수 중 · 검수 시각 없음 · 사유 없음이다'
);                                                                                                           -- 11
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-000000000090', 'kakao_share', 'a/x.jpg', 0)$$,
  '23514', null, '약속 하트는 0보다 커야 한다'
);                                                                                                           -- 12
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-000000000090', 'kakao_share', null, 25)$$,
  '23514', null, '검수 중인 줄에는 인증샷 경로가 반드시 있다'
);                                                                                                           -- 13
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-000000000090', 'everytime_post', 'a/e9.jpg', 50)$$,
  '23505', null, '한 항목에 검수 중인 줄은 하나뿐이다 — 거의 동시에 낸 두 번째도 여기서 막힌다'
);                                                                                                           -- 14
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts, reject_reason)
    values ('00000000-0000-0000-0000-000000000090', 'kakao_share', 'a/x.jpg', 25, 'reused')$$,
  '23514', null, '반려가 아닌 줄에는 반려 사유가 없다'
);                                                                                                           -- 15
select lives_ok(
  $$insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000090', 'kakao_share',
            'a/e2.jpg', 25)$$,
  '다른 항목은 동시에 검수 중일 수 있다'
);                                                                                                           -- 16

-- B 의 줄 E3 — A 가 못 봐야 한다.
insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts)
values ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-000000000091', 'kakao_share',
        'b/e3.jpg', 25);

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000090", "role": "authenticated"}';

select results_eq(
  $$select id from public.heart_task_submissions order by id$$,
  $$values ('00000000-0000-0000-0000-0000000000e1'::uuid), ('00000000-0000-0000-0000-0000000000e2'::uuid)$$,
  'A 는 본인 줄 둘만 본다'
);                                                                                                           -- 17
select is_empty(
  $$select 1 from public.heart_task_submissions where profile_id = '00000000-0000-0000-0000-000000000091'$$,
  'A 는 B 의 줄을 볼 수 없다'
);                                                                                                           -- 18
select throws_ok(
  $$insert into public.heart_task_submissions (profile_id, task, storage_path, reward_hearts)
    values ('00000000-0000-0000-0000-000000000090', 'kakao_share', 'a/y.jpg', 25)$$,
  '42501', null, 'A 는 직접 insert 할 수 없다'
);                                                                                                           -- 19
select throws_ok(
  $$update public.heart_task_submissions set status = 'approved'
     where id = '00000000-0000-0000-0000-0000000000e1'$$,
  '42501', null, 'A 는 자기 줄을 승인할 수 없다'
);                                                                                                           -- 20
select throws_ok(
  $$delete from public.heart_task_submissions where id = '00000000-0000-0000-0000-0000000000e1'$$,
  '42501', null, 'A 는 직접 delete 할 수 없다'
);                                                                                                           -- 21

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select 1 from public.heart_task_submissions$$,
  '42501', null, 'anon 은 읽을 수도 없다'
);                                                                                                           -- 22

reset role;
reset request.jwt.claims;
delete from public.heart_task_submissions;

-- C2: 제출 함수 · 검수 트리거 · 상태 함수 ------------------------------
-- 시각은 전부 고정한다. 트랜잭션 안의 now() 는 테스트를 돌린 날이라 달 경계를 못 잡는다.

-- A: 에브리타임 제출 → 검수 중 막힘 → 고정 칸 막힘 → 승인 한 번 → 끝 상태
select lives_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000090',
      'everytime_post', 'a/f1.jpg', 50, '2026-09-15 12:00:00+09')$$,
  '처음 제출은 들어간다'
);                                                                                                           -- 23
select throws_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000090',
      'everytime_post', 'a/f2.jpg', 50, '2026-09-15 12:00:01+09')$$,
  'CM409', null, '검수 중인 항목은 다시 낼 수 없다(서버 409)'
);                                                                                                           -- 24
select throws_ok(
  $$update public.heart_task_submissions set reward_hearts = 999
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  'CM409', null, '약속 하트는 운영자도 못 바꾼다'
);                                                                                                           -- 25
select throws_ok(
  $$update public.heart_task_submissions set storage_path = null
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  'CM409', null, '검수 중에는 인증샷 경로를 바꿀 수 없다'
);                                                                                                           -- 26
select throws_ok(
  $$update public.heart_task_submissions set status = 'rejected'
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  '23514', null, '사유 없이 반려할 수 없다(대시보드에서는 두 칸을 한 번에 저장)'
);                                                                                                           -- 27

update public.heart_task_submissions set status = 'approved'
 where id = '00000000-0000-0000-0000-0000000000f1';

select results_eq(
  $$select amount, reason::text, ref_id from public.heart_transactions
     where profile_id = '00000000-0000-0000-0000-000000000090'$$,
  $$values (50, 'free_task', '00000000-0000-0000-0000-0000000000f1'::uuid)$$,
  '승인하면 원장에 free_task 50 이 제출 id 로 한 줄 생긴다'
);                                                                                                           -- 28
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000090'),
  50, '잔액도 50 이다'
);                                                                                                           -- 29
select ok(
  (select reviewed_at is not null from public.heart_task_submissions
    where id = '00000000-0000-0000-0000-0000000000f1'),
  '승인하면 검수 시각이 찍힌다'
);                                                                                                           -- 30
select lives_ok(
  $$update public.heart_task_submissions set status = 'approved'
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  '승인 → 승인 다시 저장은 통과한다'
);                                                                                                           -- 31
select throws_ok(
  $$update public.heart_task_submissions set status = 'rejected', reject_reason = 'reused'
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  'CM409', null, '승인 → 반려는 막힌다(끝 상태)'
);                                                                                                           -- 32
select results_eq(
  $$select (select count(*) from public.heart_transactions
             where profile_id = '00000000-0000-0000-0000-000000000090'),
           (select heart_balance from public.entitlements
             where profile_id = '00000000-0000-0000-0000-000000000090')$$,
  $$values (1::bigint, 50)$$,
  '다시 저장 · 반려 시도 뒤에도 원장 1줄 · 잔액 50 — 두 번 주지도 회수하지도 않는다'
);                                                                                                           -- 33
select throws_ok(
  $$update public.heart_task_submissions set storage_path = 'a/other.jpg'
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  'CM409', null, '검수 뒤 인증샷 경로를 다른 값으로 바꿀 수 없다'
);                                                                                                           -- 34
select lives_ok(
  $$update public.heart_task_submissions set storage_path = null
     where id = '00000000-0000-0000-0000-0000000000f1'$$,
  '검수 뒤 인증샷 경로 비우기(60일 정리)는 된다'
);                                                                                                           -- 35
select throws_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-000000000090',
      'everytime_post', 'a/f3.jpg', 50, '2026-09-20 12:00:00+09')$$,
  'CM429', null, '에브리타임은 한 달 1회 — 승인된 달에는 더 못 낸다(서버 429)'
);                                                                                                           -- 36

-- M: 달 경계. 한국 시간 10월 1일 0시 = UTC 9월 30일 15시.
-- 준비용 호출은 do 블록의 perform 으로 한다 — 맨 select 는 빈 줄을 TAP 출력에 섞는다.
do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-000000000092',
    'everytime_post', 'm/f4.jpg', 50, '2026-09-30 23:59:59+09');
  update public.heart_task_submissions set status = 'approved'
   where id = '00000000-0000-0000-0000-0000000000f4';
end $$;

select throws_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-000000000092',
      'everytime_post', 'm/f5.jpg', 50, '2026-09-30 23:59:59.9+09')$$,
  'CM429', null, '9월 30일 23:59:59.9(한국)는 아직 9월이다'
);                                                                                                           -- 37
select lives_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-000000000092',
      'everytime_post', 'm/f6.jpg', 50, '2026-10-01 00:00:00+09')$$,
  '10월 1일 0시(한국)부터 새 달이다 — UTC 로는 아직 9월 30일이어도'
);                                                                                                           -- 38

-- K: 단톡방. 반려는 한도에서 빠지고 끝 상태다. 승인 3번이면 그 달은 끝.
do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000093',
    'kakao_share', 'k/a1.jpg', 25, '2026-09-10 12:00:00+09');
  update public.heart_task_submissions set status = 'rejected', reject_reason = 'date_missing'
   where id = '00000000-0000-0000-0000-0000000000a1';
end $$;

select results_eq(
  $$select used, task_limit, reviewing, last_status::text, last_reject_reason::text
      from public.heart_task_status('00000000-0000-0000-0000-000000000093', '2026-09-15 12:00:00+09')
     where task = 'kakao_share'$$,
  $$values (0, 3, false, 'rejected', 'date_missing')$$,
  '반려는 쓴 횟수에 안 들어가고, 마지막 상태 · 사유로 보인다'
);                                                                                                           -- 39
select throws_ok(
  $$update public.heart_task_submissions set status = 'approved', reject_reason = null
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  'CM409', null, '반려 → 승인은 막힌다(끝 상태)'
);                                                                                                           -- 40
select is(
  (select count(*) from public.heart_transactions where profile_id = '00000000-0000-0000-0000-000000000093'),
  0::bigint, '반려 → 승인 시도로는 하트가 나가지 않는다'
);                                                                                                           -- 41

do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000093',
    'kakao_share', 'k/a2.jpg', 25, '2026-09-11 12:00:00+09');
  update public.heart_task_submissions set status = 'approved' where id = '00000000-0000-0000-0000-0000000000a2';
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000093',
    'kakao_share', 'k/a3.jpg', 25, '2026-09-12 12:00:00+09');
  update public.heart_task_submissions set status = 'approved' where id = '00000000-0000-0000-0000-0000000000a3';
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000093',
    'kakao_share', 'k/a4.jpg', 25, '2026-09-13 12:00:00+09');
  update public.heart_task_submissions set status = 'approved' where id = '00000000-0000-0000-0000-0000000000a4';
end $$;

select results_eq(
  $$select used, task_limit, last_status::text
      from public.heart_task_status('00000000-0000-0000-0000-000000000093', '2026-09-15 12:00:00+09')
     where task = 'kakao_share'$$,
  $$values (3, 3, 'approved')$$,
  '단톡방은 반려 1 + 승인 3 이면 3/3 이다'
);                                                                                                           -- 42
select throws_ok(
  $$select public.submit_heart_task('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000093',
      'kakao_share', 'k/a5.jpg', 25, '2026-09-15 12:00:00+09')$$,
  'CM429', null, '단톡방은 한 달 3회까지다'
);                                                                                                           -- 43
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000093'),
  75, '단톡방 승인 3번 = 75하트'
);                                                                                                           -- 44

-- P: 검수 중 표시 · 투표 줄. 2026-09-14 가 월요일이다(주 시작). 09-14 05:00(한국)은 UTC 로 아직 09-13 이라
-- 주를 UTC 로 세면 1 이 나온다 — 한국 시간 주 경계를 여기서 잡는다.
do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000094',
    'everytime_post', 'p/b1.jpg', 50, '2026-09-15 12:00:00+09');
end $$;
insert into public.heart_transactions (profile_id, amount, reason, created_at) values
  ('00000000-0000-0000-0000-000000000094', 10, 'poll_vote', '2026-09-13 10:00:00+09'),
  ('00000000-0000-0000-0000-000000000094', 10, 'poll_vote', '2026-09-14 05:00:00+09'),
  ('00000000-0000-0000-0000-000000000094', 10, 'poll_vote', '2026-09-15 10:00:00+09');

select results_eq(
  $$select used, task_limit, reviewing, last_status::text
      from public.heart_task_status('00000000-0000-0000-0000-000000000094', '2026-09-15 12:00:00+09')
     where task = 'everytime_post'$$,
  $$values (1, 1, true, 'submitted')$$,
  '검수 중인 제출은 쓴 횟수에 들어가고 reviewing 이다'
);                                                                                                           -- 45
select results_eq(
  $$select used, task_limit, reviewing
      from public.heart_task_status('00000000-0000-0000-0000-000000000094', '2026-09-15 12:00:00+09')
     where task = 'poll_vote'$$,
  $$values (2, 3, false)$$,
  '투표 줄은 이번 주(월요일 0시부터) 적립 횟수 — 지난 일요일 것은 빠진다'
);                                                                                                           -- 46
select results_eq(
  $$select task, used, task_limit
      from public.heart_task_status('00000000-0000-0000-0000-000000000095', '2026-09-15 12:00:00+09')
     order by task$$,
  $$values ('everytime_post', 0, 1), ('kakao_share', 0, 3), ('poll_vote', 0, 3)$$,
  '처음 온 사람도 세 줄을 받는다'
);                                                                                                           -- 47

-- 함수 권한
select ok(
  not has_function_privilege('authenticated',
        'public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)', 'execute')
  and not has_function_privilege('anon',
        'public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)', 'execute'),
  '앱 역할은 제출 함수를 부를 수 없다'
);                                                                                                           -- 48
select ok(
  not has_function_privilege('authenticated', 'public.heart_task_status(uuid, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.heart_task_status(uuid, timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.heart_task_monthly_limit(public.heart_task)', 'execute')
  and not has_function_privilege('anon', 'public.heart_task_monthly_limit(public.heart_task)', 'execute'),
  '앱 역할은 상태 · 한도 함수를 부를 수 없다'
);                                                                                                           -- 49
select ok(
  has_function_privilege('service_role',
    'public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)', 'execute')
  and has_function_privilege('service_role', 'public.heart_task_status(uuid, timestamptz)', 'execute'),
  'service_role 은 두 함수를 부를 수 있다'
);                                                                                                           -- 50
select ok(
  not has_function_privilege('authenticated', 'public.heart_task_submissions_grant()', 'execute')
  and not has_function_privilege('authenticated', 'public.heart_task_submissions_guard()', 'execute')
  and not has_function_privilege('anon', 'public.heart_task_submissions_grant()', 'execute')
  and not has_function_privilege('anon', 'public.heart_task_submissions_guard()', 'execute'),
  '앱 역할은 트리거 함수를 직접 부를 수 없다'
);                                                                                                           -- 51

-- G: 탈퇴 30일 뒤 auth 사용자를 지우면 제출도 cascade 로 사라진다.
do $$
begin
  perform public.submit_heart_task('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000095',
    'kakao_share', 'g/c1.jpg', 25, '2026-09-15 12:00:00+09');
end $$;
delete from auth.users where id = '00000000-0000-0000-0000-000000000095';

select is(
  (select count(*) from public.heart_task_submissions where profile_id = '00000000-0000-0000-0000-000000000095'),
  0::bigint, '탈퇴로 지워진 사람의 제출은 남지 않는다'
);                                                                                                           -- 52

select is(
  (select count(*) from pg_proc
     where pronamespace = 'public'::regnamespace
       and proname in ('heart_task_monthly_limit', 'heart_task_status', 'submit_heart_task',
                       'heart_task_submissions_guard', 'heart_task_submissions_grant')
       and exists (select 1 from unnest(proconfig) cfg where cfg like 'search_path=%')),
  5::bigint, '다섯 함수 모두 search_path 가 고정돼 있다(advisor function_search_path_mutable)'
);                                                                                                           -- 53

-- 검수 뒤 칸 하나씩(K 의 반려된 a1): guard 끝 상태 블록의 사유 줄 · 검수 시각 줄을 따로 못 박는다(검토 09-28).
select throws_ok(
  $$update public.heart_task_submissions set reject_reason = 'reused'
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  'CM409', null, '반려 뒤 사유만 바꿀 수도 없다 — 사용자에게 보이는 사유가 바뀐다'
);                                                                                                           -- 54
select throws_ok(
  $$update public.heart_task_submissions set reviewed_at = reviewed_at - interval '1 day'
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  'CM409', null, '검수 시각도 검수 뒤에는 고칠 수 없다'
);                                                                                                           -- 55

select * from finish();
rollback;
