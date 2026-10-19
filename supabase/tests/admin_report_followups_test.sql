-- 관리자 대시보드 D2b(설계 바탕화면 관리자_대시보드_설계_10-18.md §8-2 "W2 주의" · "후속(D3 계획 10-18)") 검증:
-- 같은 대상 함께 닫기 · 가림 해제가 운영자가 **본 신고**(p_seen)만 닫고, 관리자 계정은 정지할 수 없다.
-- 마이그레이션 20261018140000_admin_report_followups. 기대값 기준: docs/superpowers/plans/2026-10-18-admin-report-followups.md Task 1.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

-- 준비 (postgres) -------------------------------------------------------------
-- AD = 관리자(…ad05), AD2 = 다른 관리자(…ad06) — 둘 다 프로필이 있다(관리자 대상 CM404 가 "프로필 없음" 으로 통과하지 않게).
-- 사람: B0 = 신고당한 사람(함께 닫기), B1~B4 = 신고자, B5 = 다른 신고당한 사람, B6 = 자동 가림(열린 신고 셋),
-- B7 = 정지할 일반 계정, B8 = 자동 가림(열린 신고 하나, 빈 목록 · 남의 신고 확인용).
-- 신고: BA01~BA04 = B0 대상(열림), BA05 · BA06 = B5 대상(열림), BB01~BB03 = B6 대상(열림), BB11 = B8 대상(열림).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000b', '테스트대학교B', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('testb.ac.kr', '00000000-0000-0000-0000-00000000000b');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b0', 'fu-0@testb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b1', 'fu-1@testb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b2', 'fu-2@testb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b3', 'fu-3@testb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b4', 'fu-4@testb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b5', 'fu-5@testb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b6', 'fu-6@testb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b7', 'fu-7@testb.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b8', 'fu-8@testb.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-00000000000b' from auth.users
where id between '00000000-0000-0000-0000-0000000000b0' and '00000000-0000-0000-0000-0000000000b8'
on conflict (id) do nothing;

update public.profiles set auto_hidden_at = now() - interval '1 hour'
where id in ('00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000b8');

insert into public.reports (id, reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason) values
  ('00000000-0000-0000-0000-00000000ba01', '00000000-0000-0000-0000-0000000000b1', 'profile',
   '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b0', '{}', 'abuse'),
  ('00000000-0000-0000-0000-00000000ba02', '00000000-0000-0000-0000-0000000000b2', 'profile',
   '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b0', '{}', 'abuse'),
  ('00000000-0000-0000-0000-00000000ba03', '00000000-0000-0000-0000-0000000000b3', 'profile',
   '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b0', '{}', 'abuse'),
  ('00000000-0000-0000-0000-00000000ba04', '00000000-0000-0000-0000-0000000000b4', 'profile',
   '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b0', '{}', 'abuse'),
  ('00000000-0000-0000-0000-00000000ba05', '00000000-0000-0000-0000-0000000000b1', 'profile',
   '00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000b5', '{}', 'spam'),
  ('00000000-0000-0000-0000-00000000ba06', '00000000-0000-0000-0000-0000000000b2', 'profile',
   '00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000b5', '{}', 'spam'),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b1', 'profile',
   '00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000b6', '{}', 'fake'),
  ('00000000-0000-0000-0000-00000000bb02', '00000000-0000-0000-0000-0000000000b2', 'profile',
   '00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000b6', '{}', 'fake'),
  ('00000000-0000-0000-0000-00000000bb03', '00000000-0000-0000-0000-0000000000b3', 'profile',
   '00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000b6', '{}', 'fake'),
  ('00000000-0000-0000-0000-00000000bb11', '00000000-0000-0000-0000-0000000000b1', 'profile',
   '00000000-0000-0000-0000-0000000000b8', '00000000-0000-0000-0000-0000000000b8', '{}', 'fake');

insert into auth.users (id, email, raw_app_meta_data) values
  ('00000000-0000-0000-0000-00000000ad05', 'operator-d2b@example.com', '{"provider": "google", "providers": ["google"]}'),
  ('00000000-0000-0000-0000-00000000ad06', 'operator-d2b-2@example.com', '{"provider": "google", "providers": ["google"]}');
insert into public.profiles (id, university_id)
values ('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000000b'),
       ('00000000-0000-0000-0000-00000000ad06', '00000000-0000-0000-0000-00000000000b')
on conflict (id) do nothing;
insert into public.admin_users (user_id) values
  ('00000000-0000-0000-0000-00000000ad05'), ('00000000-0000-0000-0000-00000000ad06');

-- 1. 함수 모양 · 권한 (postgres) --------------------------------------------------
-- proname · proconfig 는 "C" 정렬 규칙이라 조건을 한 쿼리 안에서 보고 개수만 비교한다(D2 시험과 같은 방식).

select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_resolve_report', 'admin_unhide_profile', 'admin_suspend_profile')
      and not p.prosecdef and p.proconfig = array['search_path=""']),
  3::bigint, '세 함수가 모두 security invoker · search_path 빈 값이다'
);                                                                                                   -- 1
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_resolve_report', 'admin_unhide_profile', 'admin_suspend_profile')
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')),
  3::bigint, 'service_role 만 부를 수 있다 — anon · authenticated(그리고 public)는 실행 권한이 없다'
);                                                                                                   -- 2
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname in ('admin_resolve_report', 'admin_unhide_profile')),
  2::bigint, '인자가 늘어도 옛 시그니처가 남지 않는다 — 두 함수 모두 하나뿐(옛 것이 남으면 "전부 닫기" 길이 열려 있다)'
);                                                                                                   -- 3

-- 2. 같은 대상 함께 닫기는 본 신고만 (service_role) ------------------------------------------
set local role service_role;

select is(
  (public.admin_resolve_report('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000ba01',
      'dismissed', '확인', true, '203.0.113.9', array['00000000-0000-0000-0000-00000000ba02']::uuid[]))->'closed_ids',
  '["00000000-0000-0000-0000-00000000ba01", "00000000-0000-0000-0000-00000000ba02"]'::jsonb,
  '함께 닫기는 이 신고와 본 신고(BA02)만 닫는다'
);                                                                                                   -- 4
select results_eq(
  $$select id::text, status::text from public.reports
     where id in ('00000000-0000-0000-0000-00000000ba01', '00000000-0000-0000-0000-00000000ba02',
                  '00000000-0000-0000-0000-00000000ba03', '00000000-0000-0000-0000-00000000ba04',
                  '00000000-0000-0000-0000-00000000ba05') order by id$$,
  $$values ('00000000-0000-0000-0000-00000000ba01', 'dismissed'), ('00000000-0000-0000-0000-00000000ba02', 'dismissed'),
           ('00000000-0000-0000-0000-00000000ba03', 'open'), ('00000000-0000-0000-0000-00000000ba04', 'open'),
           ('00000000-0000-0000-0000-00000000ba05', 'open')$$,
  '상세를 연 뒤 들어온 것처럼 목록에 없는 같은 사람의 열린 신고(BA03 · BA04)와 남의 신고(BA05)는 열린 채다'
);                                                                                                   -- 5
select is(
  (select count(*) from public.admin_actions
    where target_id in ('00000000-0000-0000-0000-00000000ba03', '00000000-0000-0000-0000-00000000ba04')),
  0::bigint, '닫히지 않은 신고에는 작업 기록도 없다'
);                                                                                                   -- 6
select throws_ok(
  $$select public.admin_resolve_report('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000ba03',
      'dismissed', null, true, null, null)$$,
  '22023', null, '함께 닫기인데 본 신고 목록이 없으면(null) 22023 — "같은 사람의 열린 신고 전부" 로 되돌아가지 않는다'
);                                                                                                   -- 7
select is(
  (select count(*) from public.reports
    where id in ('00000000-0000-0000-0000-00000000ba03', '00000000-0000-0000-0000-00000000ba04') and status = 'open'),
  2::bigint, '거절된 호출은 아무것도 닫지 않았다'
);                                                                                                   -- 8
select is(
  (public.admin_resolve_report('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000ba03',
      'actioned', null, true, null,
      array['00000000-0000-0000-0000-00000000ba05', '00000000-0000-0000-0000-00000000ba04',
            '00000000-0000-0000-0000-00000000ba01']::uuid[]))->'closed_ids',
  '["00000000-0000-0000-0000-00000000ba03", "00000000-0000-0000-0000-00000000ba04"]'::jsonb,
  '목록에 남의 신고(BA05)와 이미 닫힌 신고(BA01)가 섞여도 같은 사람의 열린 신고만 닫는다'
);                                                                                                   -- 9
select is(
  (select count(*) from public.reports
    where id in ('00000000-0000-0000-0000-00000000ba05', '00000000-0000-0000-0000-00000000ba06') and status = 'open'),
  2::bigint, '남의 신고 id 를 넘겨도 다른 사람(B5)의 신고는 닫히지 않는다'
);                                                                                                   -- 10
select is(
  (public.admin_resolve_report('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000ba05',
      'dismissed', null, false, null, array['00000000-0000-0000-0000-00000000ba06']::uuid[]))->'closed_ids',
  '["00000000-0000-0000-0000-00000000ba05"]'::jsonb,
  '함께 닫기가 아니면 본 신고 목록은 쓰지 않는다 — 그 건만 닫는다'
);                                                                                                   -- 11
select is(
  (select status::text from public.reports where id = '00000000-0000-0000-0000-00000000ba06'),
  'open', '목록에 든 BA06 은 함께 닫기가 아니라 열린 채다'
);                                                                                                   -- 12
select is(
  (public.admin_resolve_report('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000ba06',
      'dismissed', null, true, null, '{}'::uuid[]))->'closed_ids',
  '["00000000-0000-0000-0000-00000000ba06"]'::jsonb,
  '빈 목록([])의 함께 닫기는 이 신고만 닫는다'
);                                                                                                   -- 13

-- 3. 가림 해제는 본 신고만 기각 (service_role) -------------------------------------------------

select results_eq(
  $$select r->'auto_hidden_at', r->'dismissed_ids'
      from (select public.admin_unhide_profile('00000000-0000-0000-0000-00000000ad05',
              '00000000-0000-0000-0000-0000000000b6', '오신고 확인', '203.0.113.9',
              array['00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-00000000bb02']::uuid[]) as r) as call$$,
  $$values ('null'::jsonb, '["00000000-0000-0000-0000-00000000bb01", "00000000-0000-0000-0000-00000000bb02"]'::jsonb)$$,
  '가림 해제는 시각을 비우고 본 신고 둘만 기각했다고 돌려준다'
);                                                                                                   -- 14
select results_eq(
  $$select id::text, status::text from public.reports
     where id in ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-00000000bb02',
                  '00000000-0000-0000-0000-00000000bb03') order by id$$,
  $$values ('00000000-0000-0000-0000-00000000bb01', 'dismissed'), ('00000000-0000-0000-0000-00000000bb02', 'dismissed'),
           ('00000000-0000-0000-0000-00000000bb03', 'open')$$,
  '상세를 연 뒤 들어온 새 신고(BB03)는 가림이 풀려도 열린 채다'
);                                                                                                   -- 15
select results_eq(
  $$select (select count(*) from public.admin_actions where action = 'profile_unhide'
             and target_id = '00000000-0000-0000-0000-0000000000b6'),
           (select count(*) from public.admin_actions where action = 'report_resolve'
             and target_id in ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-00000000bb02')),
           (select count(*) from public.admin_actions where target_id = '00000000-0000-0000-0000-00000000bb03')$$,
  $$values (1::bigint, 2::bigint, 0::bigint)$$,
  '기록은 가림 해제 한 줄 + 기각한 신고마다 한 줄, 새 신고에는 한 줄도 없다'
);                                                                                                   -- 16
select throws_ok(
  $$select public.admin_unhide_profile('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-0000000000b8',
      '사유', null, null)$$,
  '22023', null, '본 신고 목록이 없으면(null) 가림을 풀지 않는다 — 22023'
);                                                                                                   -- 17
select ok(
  (select auto_hidden_at is not null from public.profiles where id = '00000000-0000-0000-0000-0000000000b8'),
  '거절된 호출은 가림을 풀지 않았다'
);                                                                                                   -- 18
select is(
  public.admin_unhide_profile('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-0000000000b8',
    '사유', null, array['00000000-0000-0000-0000-00000000bb03']::uuid[])->'dismissed_ids',
  '[]'::jsonb, '남의 신고(BB03, B6 대상)만 넘기면 이 사람의 신고는 기각 0건이다'
);                                                                                                   -- 19
select is(
  (select count(*) from public.reports
    where id in ('00000000-0000-0000-0000-00000000bb03', '00000000-0000-0000-0000-00000000bb11') and status = 'open'),
  2::bigint, '남의 신고도 이 사람의 본 적 없는 신고도 열린 채다'
);                                                                                                   -- 20
select ok(
  (select auto_hidden_at is null from public.profiles where id = '00000000-0000-0000-0000-0000000000b8'),
  '본 신고가 없어도 가림 시각은 비워졌다'
);                                                                                                   -- 21

-- 4. 관리자 계정은 정지하지 않는다 (service_role) -----------------------------------------------

select throws_ok(
  $$select public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000ad06',
      '다른 관리자', null)$$,
  'CM404', null, 'admin target is CM404 — 다른 관리자는 정지하지 못한다'
);                                                                                                   -- 22
select throws_ok(
  $$select public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000ad05',
      '본인', null)$$,
  'CM404', null, 'admin target is CM404 — 본인도 정지하지 못한다'
);                                                                                                   -- 23
select results_eq(
  $$select (select string_agg(status::text, ',' order by id) from public.profiles
             where id in ('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000ad06')),
           (select count(*) from public.admin_actions where action = 'profile_suspend')$$,
  $$values ('pending,pending', 0::bigint)$$,
  '관리자 프로필은 그대로이고 정지 기록도 없다'
);                                                                                                   -- 24
select is(
  public.admin_suspend_profile('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-0000000000b7',
    '반복 욕설', null)->>'status',
  'suspended', '일반 계정은 지금처럼 정지된다'
);                                                                                                   -- 25

-- 5. 앱 역할로 직접 ---------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000b0", "role": "authenticated"}';

select throws_ok(
  $$select public.admin_unhide_profile('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b6',
      '내가 푼다', null, '{}'::uuid[])$$,
  '42501', null, 'authenticated 는 새 가림 해제 함수를 부를 수 없다'
);                                                                                                   -- 26

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(
  $$select public.admin_resolve_report('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-00000000bb03',
      'dismissed', null, true, null, '{}'::uuid[])$$,
  '42501', null, 'anon 은 새 신고 닫기 함수를 부를 수 없다'
);                                                                                                   -- 27

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
