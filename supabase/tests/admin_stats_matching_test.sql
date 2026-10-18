-- 관리자 웹 대시보드 D4(설계 바탕화면 관리자_대시보드_설계_10-18.md §8-4 · §8-4b · §8-4c) 검증:
-- 홈 통계 · 일별 그래프 · 미등록 도메인 · 학교별 현황 · 운영 상태판 · 매칭 현황 읽기 함수 8개와 daily_cards 인덱스.
-- 마이그레이션 20261018150000_admin_stats_matching. 기대값 기준: docs/superpowers/plans/2026-10-18-admin-stats-matching.md.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
-- 다른 시험 · 시드가 남긴 줄에 흔들리지 않게 개수는 "넣기 전과 뒤의 차이"(before_* 임시 표)로, 줄은 이 시험의 전용 id 로 단정한다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(83);

-- 준비 (postgres) -------------------------------------------------------------
-- KST 오늘 0시. 모든 시각은 이 값에서 상대로 만든다(UTC 로는 같은 날일 수 있어 자정 경계를 본다).
create temp table k as
  select (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') as t0,
         (now() at time zone 'Asia/Seoul')::date as today;
grant select on k to service_role;

-- 넣기 전의 함수 결과(차이 계산용).
create temp table before_o as select * from public.admin_stats_overview();
create temp table before_d as select * from public.admin_stats_daily(3);
grant select on before_o, before_d to service_role;

-- 학교: UX 열림 · UY 예정(앞으로 월요일 07:00) · UZ 빈 열림 학교 · UW 사람 없는 예정 학교 · UQ 따로 센 지역의 열린 학교.
insert into public.region_group_settings (region_group) values ('d4_test'), ('d4_test2');
insert into public.universities (id, name, region_group, card_opens_at) values
  ('00000000-0000-0000-0000-d40000000a01', 'D4열림대학교', 'd4_test', null),
  ('00000000-0000-0000-0000-d40000000a02', 'D4예정대학교', 'd4_test', '2099-01-05 07:00+09'),
  ('00000000-0000-0000-0000-d40000000a03', 'D4빈대학교', 'd4_test', null),
  ('00000000-0000-0000-0000-d40000000a04', 'D4예정빈대학교', 'd4_test', '2099-01-05 07:00+09'),
  ('00000000-0000-0000-0000-d40000000a05', 'D4따로대학교', 'd4_test2', null);

-- 사람. 이름 → (학교, 성별, 상태, 생성 시각, 마지막 접속, 일시중지).
--   m1 남 오늘 · m2 남 어제 23:30 · f1 여 오늘 · f2 여 정지(2일 전) · f3 여 탈퇴(7일 전 = 여덟 번째 날) · n1 성별 없음(오늘 · pending)
--   p1 남 일시중지 · old1 남 15일 전 접속 · y1 남 / y2 여(예정 학교) · q1 남 / q2 여(따로 센 지역) · ad1 관리자(남 · 오늘 · 활성)
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-d4000000' || v.n)::uuid, 'd4-' || v.n || '@example.com'
  from (values ('0001'), ('0002'), ('0003'), ('0004'), ('0005'), ('0006'), ('0007'), ('0008'), ('0009'), ('0010'),
               ('0011'), ('0012'), ('0013')) as v(n);

insert into public.profiles (id, university_id)
select u.id, '00000000-0000-0000-0000-d40000000a01' from auth.users u where u.email like 'd4-%@example.com'
on conflict (id) do nothing;

create temp table people (n text primary key, uni text, gender text, status text, created timestamptz,
                          active_at timestamptz, paused boolean);
insert into people
select v.n, v.uni, v.gender, v.status, v.created, v.active_at, v.paused
  from k, lateral (values
    ('0001', 'a01', 'male',   'active',    k.t0 + interval '30 minutes',               now(),                    false),
    ('0002', 'a01', 'male',   'active',    k.t0 - interval '30 minutes',               now(),                    false),
    ('0003', 'a01', 'female', 'active',    k.t0 + interval '30 minutes',               now(),                    false),
    ('0004', 'a01', 'female', 'suspended', k.t0 - interval '2 days' + interval '12 hours', now(),               false),
    ('0005', 'a01', 'female', 'withdrawn', k.t0 - interval '7 days' + interval '12 hours', now(),               false),
    ('0006', 'a01', null,     'pending',   k.t0 + interval '60 minutes',               now(),                    false),
    ('0007', 'a01', 'male',   'active',    k.t0 - interval '3 days' + interval '1 hour', now(),                  true),
    ('0008', 'a01', 'male',   'active',    k.t0 - interval '4 days',                   now() - interval '15 days', false),
    ('0009', 'a02', 'male',   'active',    k.t0 - interval '5 days',                   now(),                    false),
    ('0010', 'a02', 'female', 'active',    k.t0 - interval '6 days' + interval '1 hour', now(),                  false),
    ('0011', 'a05', 'male',   'active',    k.t0 - interval '1 days' + interval '2 hours', now(),                 false),
    ('0012', 'a05', 'female', 'active',    k.t0 - interval '1 days' + interval '3 hours', now(),                 false),
    ('0013', 'a01', 'male',   'active',    k.t0 + interval '45 minutes',               now(),                    false)
  ) as v(n, uni, gender, status, created, active_at, paused);

update public.profiles p set
  university_id = ('00000000-0000-0000-0000-d40000000' || pe.uni)::uuid,
  gender = pe.gender::public.gender,
  status = pe.status::public.profile_status,
  birth_year = case when pe.gender is null then null else 2002 end,
  height_cm = case when pe.gender is null then null else 170 end,
  nickname = case when pe.gender is null then null else '디포' || chr(96 + pe.n::int) end,
  created_at = pe.created, last_active_at = pe.active_at, matching_paused = pe.paused,
  withdrawn_at = case when pe.status = 'withdrawn' then now() else null end
from people pe
where p.id = ('00000000-0000-0000-0000-d4000000' || pe.n)::uuid;

-- 0013 = 관리자(프로필이 학교 · 성별까지 있는 최악의 경우 — 그래도 통계에서 빠져야 한다).
insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-d40000000013');

-- 신고: r1 m1 오늘 · r2 관리자 오늘 · r3 신고자 탈퇴(null) 어제 · r4 f1 2일 전(기각 · 닫힘). 대상은 f1(0003)이다.
insert into public.reports (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason, status, created_at, resolved_at)
values
  ('00000000-0000-0000-0000-d40000000001', 'profile', '00000000-0000-0000-0000-d40000000003', '00000000-0000-0000-0000-d40000000003',
   '{}', 'abuse', 'open', (select t0 + interval '2 hours' from k), null),
  ('00000000-0000-0000-0000-d40000000013', 'profile', '00000000-0000-0000-0000-d40000000003', '00000000-0000-0000-0000-d40000000003',
   '{}', 'abuse', 'open', (select t0 + interval '2 hours' from k), null),
  (null, 'profile', '00000000-0000-0000-0000-d40000000003', '00000000-0000-0000-0000-d40000000003',
   '{}', 'spam', 'open', (select t0 - interval '1 day' + interval '3 hours' from k), null),
  ('00000000-0000-0000-0000-d40000000003', 'profile', '00000000-0000-0000-0000-d40000000001', '00000000-0000-0000-0000-d40000000001',
   '{}', 'fake', 'dismissed', (select t0 - interval '2 days' + interval '5 hours' from k),
   (select t0 - interval '2 days' + interval '6 hours' from k));

-- 인증샷: s1 m1 오늘(검수 대기) · s2 관리자 오늘(검수 대기) · s3 f1 어제(검수 대기) · s4 m2 2일 전(반려됨).
insert into public.heart_task_submissions (profile_id, task, storage_path, status, reward_hearts, reject_reason, created_at, reviewed_at)
values
  ('00000000-0000-0000-0000-d40000000001', 'everytime_post', 'd4/s1.jpg', 'submitted', 40, null,
   (select t0 + interval '3 hours' from k), null),
  ('00000000-0000-0000-0000-d40000000013', 'everytime_post', 'd4/s2.jpg', 'submitted', 40, null,
   (select t0 + interval '3 hours' from k), null),
  ('00000000-0000-0000-0000-d40000000003', 'kakao_share', 'd4/s3.jpg', 'submitted', 40, null,
   (select t0 - interval '1 day' + interval '4 hours' from k), null),
  ('00000000-0000-0000-0000-d40000000002', 'everytime_post', null, 'rejected', 40, 'reused',
   (select t0 - interval '2 days' + interval '4 hours' from k), (select t0 - interval '2 days' + interval '5 hours' from k));

-- 미등록 도메인: a · b 는 5회(b 가 더 최근), c 는 2회, reg 는 99회지만 이미 등록된 도메인이다.
insert into public.unknown_email_domain_attempts (domain, attempt_count, first_seen_at, last_seen_at) values
  ('d4-a.ac.kr', 5, now() - interval '5 days', now() - interval '2 days'),
  ('d4-b.ac.kr', 5, now() - interval '5 days', now() - interval '1 day'),
  ('d4-c.ac.kr', 2, now() - interval '5 days', now() - interval '3 days'),
  ('d4-reg.ac.kr', 99, now() - interval '5 days', now());
insert into public.university_email_domains (domain, university_id) values ('d4-reg.ac.kr', '00000000-0000-0000-0000-d40000000a01');

-- 1. 함수 모양 · 권한 · 인덱스 (postgres) -----------------------------------------------
-- pg_proc 의 proname · proconfig 는 "C" 정렬 규칙이라 results_eq 의 행 비교와 섞이면 멈춘다 — 개수만 비교한다(D1~D3 시험과 같음).
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_stats_overview', 'admin_stats_daily', 'admin_unknown_domains', 'admin_universities_status')
      and not p.prosecdef and p.proconfig = array['search_path=""']),
  4::bigint, '네 함수가 있고 모두 security invoker · search_path 빈 값이다(SUPABASE.md §5 — security definer 금지)'
);
select has_index('public', 'daily_cards', 'daily_cards_issued_at_index', '오늘 지급분 조회용 인덱스가 있다');

-- service_role(FastAPI 와 같은 역할)로 돌려야 표 권한이 모자란지 드러난다.
set local role service_role;

-- 2. 홈 숫자 --------------------------------------------------------------------------
select results_eq(
  $$select a.pending_count - b.pending_count, a.active_count - b.active_count, a.suspended_count - b.suspended_count,
           a.withdrawn_count - b.withdrawn_count
      from public.admin_stats_overview() a, before_o b$$,
  $$values (1, 9, 1, 1)$$,
  'overview counts profiles by status — 관리자(활성 · 성별 있음)는 active 에 안 센다(10 이 아니라 9)'
);
select results_eq(
  $$select a.open_reports - b.open_reports, a.pending_proofs - b.pending_proofs
      from public.admin_stats_overview() a, before_o b$$,
  $$values (3, 3)$$,
  'overview counts only open reports and submitted proofs — 기각 · 반려된 줄은 안 센다'
);
select results_eq(
  $$select a.signups_today - b.signups_today, a.signups_7d - b.signups_7d
      from public.admin_stats_overview() a, before_o b$$,
  $$values (2, 10)$$,
  'overview signups use kst days — 오늘 00:30 남 · 여 2명, 7일 안(오늘 포함 7 KST 날) 10명. 성별 없음 · 관리자 · 여덟 번째 날 탈퇴자는 빠진다'
);

-- 3. 일별 그래프 ------------------------------------------------------------------------
select results_eq(
  $$select d.day, d.male_signups - b.male_signups, d.female_signups - b.female_signups
      from public.admin_stats_daily(3) d join before_d b using (day) order by d.day$$,
  $$select k.today - 2, 0, 1 from k union all select k.today - 1, 2, 1 from k union all select k.today, 1, 1 from k order by 1$$,
  'daily buckets by kst midnight and separates male and female — 어제는 m2(23:30) · q1 · q2, 오늘 00:30 남 · 여는 오늘, 성별 없음 · 관리자는 없다'
);
select results_eq(
  $$select d.day, d.report_count - b.report_count, d.proof_count - b.proof_count
      from public.admin_stats_daily(3) d join before_d b using (day) order by d.day$$,
  $$select k.today - 2, 1, 1 from k union all select k.today - 1, 1, 1 from k union all select k.today, 1, 1 from k order by 1$$,
  'daily excludes admin signups reporters and submitters — 관리자가 낸 신고 · 인증샷은 안 세고, 신고자가 탈퇴해 null 인 신고는 센다'
);
select results_eq(
  $$select count(*), min(day), max(day) from public.admin_stats_daily(3)$$,
  $$select 3::bigint, k.today - 2, k.today from k$$,
  'daily returns exactly p_days rows zero filled — 3줄 · 첫 줄 오늘−2 · 마지막 오늘(KST)'
);
select is(
  (select count(*) from public.admin_stats_daily(90) where day = (select today - 89 from k)),
  1::bigint, 'daily 90 reaches 89 days back — 없는 날도 줄이 있다'
);
select ok(
  (select bool_and(male_signups >= 0 and female_signups >= 0 and report_count >= 0 and proof_count >= 0) and count(*) = 30
     from public.admin_stats_daily(30)),
  'daily fills every day of 30 with non-negative counts'
);
select throws_ok($$select * from public.admin_stats_daily(0)$$, '22023', null, 'daily rejects 0');
select throws_ok($$select * from public.admin_stats_daily(91)$$, '22023', null, 'daily rejects 91');
select throws_ok($$select * from public.admin_stats_daily(null)$$, '22023', null, 'daily rejects null');

-- 4. 미등록 도메인 ----------------------------------------------------------------------
select results_eq(
  $$select domain from public.admin_unknown_domains(500) where domain like 'd4-%'$$,
  $$values ('d4-b.ac.kr'), ('d4-a.ac.kr'), ('d4-c.ac.kr')$$,
  'unknown domains ordered by count then recency, and hide registered ones — 같은 5회면 최근 시도(b)가 먼저, 등록된 reg(99회)는 안 나온다'
);
select results_eq(
  $$select attempt_count, (last_seen_at is not null and first_seen_at is not null) from public.admin_unknown_domains(500)
     where domain = 'd4-a.ac.kr'$$,
  $$values (5, true)$$, 'unknown domains return count and both times'
);
select is((select count(*) from public.admin_unknown_domains(1)), 1::bigint, 'unknown domains limit 1 gives one row');
select throws_ok($$select * from public.admin_unknown_domains(0)$$, '22023', null, 'unknown domains rejects limit 0');
select throws_ok($$select * from public.admin_unknown_domains(501)$$, '22023', null, 'unknown domains rejects limit 501');

-- 5. 학교별 현황 ------------------------------------------------------------------------
select results_eq(
  $$select id::text, male_active, female_active from public.admin_universities_status(true)
     where id in ('00000000-0000-0000-0000-d40000000a01', '00000000-0000-0000-0000-d40000000a02') order by id$$,
  $$values ('00000000-0000-0000-0000-d40000000a01', 2, 1), ('00000000-0000-0000-0000-d40000000a02', 1, 1)$$,
  'universities count active by gender with the card rules — 정지 · 일시중지 · 15일 전 접속 · 성별 없음 · 관리자는 안 센다'
);
select results_eq(
  $$select id::text, is_open from public.admin_universities_status(true)
     where id in ('00000000-0000-0000-0000-d40000000a01', '00000000-0000-0000-0000-d40000000a02') order by id$$,
  $$values ('00000000-0000-0000-0000-d40000000a01', true), ('00000000-0000-0000-0000-d40000000a02', false)$$,
  'universities is_open follows card_opens_at — null 은 열림, 미래는 아직'
);
select results_eq(
  $$select id::text from public.admin_universities_status(false) where region_group = 'd4_test' order by id$$,
  $$values ('00000000-0000-0000-0000-d40000000a01'), ('00000000-0000-0000-0000-d40000000a02'),
           ('00000000-0000-0000-0000-d40000000a04')$$,
  'universities include_empty false — 활성 0 이어도 오픈 시각이 있는 학교(a04)는 남고, 활성 0 · 오픈 시각 없음(a03)은 빠진다'
);
select results_eq(
  $$select id::text from public.admin_universities_status(true) where region_group = 'd4_test' order by id$$,
  $$values ('00000000-0000-0000-0000-d40000000a01'), ('00000000-0000-0000-0000-d40000000a02'),
           ('00000000-0000-0000-0000-d40000000a03'), ('00000000-0000-0000-0000-d40000000a04')$$,
  'universities include_empty true — 전부'
);
select results_eq(
  $$select name, card_opens_at is not null from public.admin_universities_status(true) where id = '00000000-0000-0000-0000-d40000000a04'$$,
  $$values ('D4예정빈대학교', true)$$, 'universities show name and card_opens_at'
);
select results_eq(
  $$select coalesce(sum(male_active), 0)::bigint, coalesce(sum(female_active), 0)::bigint
      from public.admin_universities_status(true) where region_group = 'd4_test2' and is_open$$,
  $$select coalesce(sum(active_count) filter (where gender = 'male'), 0)::bigint,
           coalesce(sum(active_count) filter (where gender = 'female'), 0)::bigint
      from public.region_active_counts() where region_group = 'd4_test2'$$,
  'universities sums equal region_active_counts for open schools — 카드 주기가 쓰는 숫자와 같다(관리자 없는 지역)'
);
select throws_ok($$select * from public.admin_universities_status(null)$$, '22023', null, 'universities rejects null include_empty');

-- 6. 앱 역할은 못 부른다 ------------------------------------------------------------------
reset role;
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_stats_overview', 'admin_stats_daily', 'admin_unknown_domains', 'admin_universities_status')
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')),
  4::bigint, 'service_role 만 부를 수 있다 — anon · authenticated(그리고 public)는 실행 권한이 없다'
);
set local role authenticated;
select throws_ok($$select * from public.admin_stats_overview()$$, '42501', null, 'authenticated 는 admin_stats_overview 를 부를 수 없다');
select throws_ok($$select * from public.admin_stats_daily(3)$$, '42501', null, 'authenticated 는 admin_stats_daily 를 부를 수 없다');
select throws_ok($$select * from public.admin_unknown_domains(10)$$, '42501', null, 'authenticated 는 admin_unknown_domains 를 부를 수 없다');
select throws_ok($$select * from public.admin_universities_status(true)$$, '42501', null, 'authenticated 는 admin_universities_status 를 부를 수 없다');
reset role;
set local role anon;
select throws_ok($$select * from public.admin_stats_overview()$$, '42501', null, 'anon 은 admin_stats_overview 를 부를 수 없다');
reset role;

-- ===== Task 2. 운영 상태판 admin_health ====================================================
-- 인자: (카드 여유 분, 방 시간, 탈퇴 일, 아바타 시간, 푸시 시간). 기본 묶음 = (0, 50, 31, 24, 12).
-- 개수는 "넣기 전 / 뒤의 차이"로 본다 — 먼저 인자 묶음별 기준 표를 담는다(postgres).
create temp table hb_p0 as select * from public.admin_health(0, 50, 31, 24, 12);
create temp table hb_grace as select * from public.admin_health(1440, 50, 31, 24, 12);
create temp table hb_room60 as select * from public.admin_health(0, 60, 31, 24, 12);
create temp table hb_wd29 as select * from public.admin_health(0, 50, 29, 24, 12);
grant select on hb_p0, hb_grace, hb_room60, hb_wd29 to service_role;

-- 지역 d4h: 처음엔 오늘이 지급 요일이 아니다(아래에서 바꿔 가며 본다). 지역 d4h_other 는 늘 오늘이 아니다.
insert into public.region_group_settings (region_group, issue_weekdays, issue_time) values
  ('d4h', array[(extract(isodow from (now() at time zone 'Asia/Seoul'))::int % 7) + 1]::smallint[], '00:00'),
  ('d4h_other', array[(extract(isodow from (now() at time zone 'Asia/Seoul'))::int % 7) + 1]::smallint[], '00:00');
insert into public.universities (id, name, region_group, card_opens_at) values
  ('00000000-0000-0000-0000-d40000000a11', 'D4상태열림대학교', 'd4h', null),
  ('00000000-0000-0000-0000-d40000000a12', 'D4상태다른지역대학교', 'd4h_other', null);

-- 사람 13명(번호 = 끝 네 자리): 1 허브 · 2~8 방 상대 · 9 · 10 카드 받을 사람(d4h, 벡터 있음) · 11 다른 지역(벡터 있음) · 12 · 13 탈퇴.
-- 7 = 정지, 8 = 방금 탈퇴, 12 = 32일 전 탈퇴, 13 = 30일 전 탈퇴.
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-d4000002' || lpad(i::text, 4, '0'))::uuid, 'd4h-' || i || '@example.com'
  from generate_series(1, 13) as i;
insert into public.profiles (id, university_id)
select u.id, '00000000-0000-0000-0000-d40000000a12' from auth.users u where u.email like 'd4h-%@example.com'
on conflict (id) do nothing;
update public.profiles p set
  university_id = case when right(p.id::text, 4)::int in (9, 10) then '00000000-0000-0000-0000-d40000000a11'::uuid
                       else '00000000-0000-0000-0000-d40000000a12'::uuid end,
  gender = (case when right(p.id::text, 1)::int % 2 = 1 then 'male' else 'female' end)::public.gender,
  status = (case right(p.id::text, 4)::int when 7 then 'suspended' when 8 then 'withdrawn' when 12 then 'withdrawn'
                 when 13 then 'withdrawn' else 'active' end)::public.profile_status,
  withdrawn_at = case right(p.id::text, 4)::int when 8 then now() when 12 then now() - interval '32 days'
                      when 13 then now() - interval '30 days' else null end,
  birth_year = 2002, height_cm = 170, nickname = '헬스' || chr(96 + right(p.id::text, 4)::int),
  last_active_at = now()
where p.id::text like '00000000-0000-0000-0000-d4000002%';

insert into public.profile_vectors (profile_id, self_survey, self_embedding, want_embedding)
select id, '[1,0,0,0,0,0,0,0]',
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector
  from public.profiles
 where id in ('00000000-0000-0000-0000-d40000020009', '00000000-0000-0000-0000-d40000020010', '00000000-0000-0000-0000-d40000020011');

-- 방(허브 × 2~8, 허브 id 가 더 작아 profile_a < profile_b 를 지킨다). 2 = 51시간 · 둘 다 남음(세어야 함) · 3 = 10시간 ·
-- 4 = 51시간 공유 완료 · 5 = 51시간 닫힘 · 6 = 51시간 · 6 번 사람이 나감 · 7 = 51시간 · 7 번 정지 · 8 = 51시간 · 8 번 탈퇴.
insert into public.matches (profile_a, profile_b, created_at, trust_passed_at, chat_closed_at)
select '00000000-0000-0000-0000-d40000020001'::uuid, ('00000000-0000-0000-0000-d4000002' || lpad(v.n::text, 4, '0'))::uuid,
       now() - v.age, v.shared, v.closed
  from (values
    (2, interval '51 hours', null::timestamptz, null::timestamptz),
    (3, interval '10 hours', null, null),
    (4, interval '51 hours', now() - interval '1 hour', null),
    (5, interval '51 hours', null, now() - interval '1 hour'),
    (6, interval '51 hours', null, null),
    (7, interval '51 hours', null, null),
    (8, interval '51 hours', null, null)
  ) as v(n, age, shared, closed);
insert into public.match_participants (match_id, profile_id)
select m.id, x.pid from public.matches m, lateral (values (m.profile_a), (m.profile_b)) as x(pid)
 where m.profile_a = '00000000-0000-0000-0000-d40000020001';
update public.match_participants set left_at = now() where profile_id = '00000000-0000-0000-0000-d40000020006';

-- 아바타: failed 2시간 전(세어야 함) · ready · pending · failed 30시간 전.
insert into public.profile_avatars (profile_id, storage_path, status, created_at) values
  ('00000000-0000-0000-0000-d40000020001', 'd4/a1.png', 'failed', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-d40000020002', 'd4/a2.png', 'ready', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-d40000020003', 'd4/a3.png', 'pending', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-d40000020004', 'd4/a4.png', 'failed', now() - interval '30 hours');

-- 보류 푸시: 13시간 전(세어야 함) · 1시간 전.
insert into public.pending_pushes (profile_id, kind, title, body, created_at) values
  ('00000000-0000-0000-0000-d40000020001', 'match_made', 't', 'b', now() - interval '13 hours'),
  ('00000000-0000-0000-0000-d40000020002', 'match_made', 't', 'b', now() - interval '1 hour');

-- 모양 · 인자 범위
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = 'admin_health'
      and not p.prosecdef and p.proconfig = array['search_path=""']
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')),
  1::bigint, 'admin_health 는 invoker · search_path 빈 값 · service_role 만 실행'
);
set local role service_role;
select throws_ok($$select * from public.admin_health(-1, 50, 31, 24, 12)$$, '22023', null, 'health rejects grace -1');
select throws_ok($$select * from public.admin_health(1441, 50, 31, 24, 12)$$, '22023', null, 'health rejects grace 1441');
select throws_ok($$select * from public.admin_health(0, 0, 31, 24, 12)$$, '22023', null, 'health rejects room hours 0');
select throws_ok($$select * from public.admin_health(0, 50, 1001, 24, 12)$$, '22023', null, 'health rejects withdrawn days 1001');
select throws_ok($$select * from public.admin_health(0, 50, 31, 0, 12)$$, '22023', null, 'health rejects avatar hours 0');
select throws_ok($$select * from public.admin_health(0, 50, 31, 24, 1001)$$, '22023', null, 'health rejects push hours 1001');
select throws_ok($$select * from public.admin_health(0, 50, 31, 24, null)$$, '22023', null, 'health rejects null');

-- ① 카드 도착 — 목적은 "지급 배치가 아예 안 돌았는지". 점검 대상 = 오늘이 지급 요일 · 시각 + 여유가 지남 · (오늘 카드가 나갔거나 받을 사람이 있는) 지역.
-- cards_issued = 점검 대상 중 오늘 무료 카드가 한 장이라도 나간 지역 수(받을 사람이 다 받아 card_issue_owners 에서 빠져도 센다). 판정은 서버.
select results_eq(
  $$select a.cards_checked - b.cards_checked, a.cards_issued - b.cards_issued
      from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (0, 0)$$, 'cards check skips a region on a non-issue weekday — 오늘이 지급 요일이 아니면 점검 대상이 아니다'
);
reset role;
update public.region_group_settings set issue_weekdays = array[extract(isodow from (now() at time zone 'Asia/Seoul'))::int]::smallint[]
 where region_group = 'd4h';
set local role service_role;
select results_eq(
  $$select a.cards_checked - b.cards_checked, a.cards_issued - b.cards_issued
      from public.admin_health(1440, 50, 31, 24, 12) a, hb_grace b$$,
  $$values (0, 0)$$, 'cards check skips before issue time plus grace — 지급 시각 + 여유(1440분)가 아직 안 지났으면 점검 대상이 아니다'
);
select results_eq(
  $$select a.cards_checked - b.cards_checked, a.cards_issued - b.cards_issued
      from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (1, 0)$$, 'cards check flags a due region with eligible owners and no card today — 받을 사람이 있는데 오늘 카드가 0장'
);
reset role;
insert into public.daily_cards (owner_id, target_id, source, issued_at, expires_at)
values ('00000000-0000-0000-0000-d40000020009', '00000000-0000-0000-0000-d40000020010', 'daily', now(), now() + interval '3 days');
set local role service_role;
select results_eq(
  $$select a.cards_checked - b.cards_checked, a.cards_issued - b.cards_issued
      from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (1, 1)$$, 'cards check counts a region once a card was issued today — 오늘 카드가 한 장이라도 나갔으면 지급됨'
);
reset role;
insert into public.daily_cards (owner_id, target_id, source, issued_at, expires_at)
values ('00000000-0000-0000-0000-d40000020010', '00000000-0000-0000-0000-d40000020009', 'daily', now(), now() + interval '3 days');
set local role service_role;
select results_eq(
  $$select a.cards_checked - b.cards_checked, a.cards_issued - b.cards_issued
      from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (1, 1)$$, 'cards check stays issued when everyone was served — 받을 사람이 모두 받아 card_issue_owners 가 비어도 na 로 빠지지 않는다'
);
reset role;
delete from public.daily_cards where owner_id in ('00000000-0000-0000-0000-d40000020009', '00000000-0000-0000-0000-d40000020010');
insert into public.daily_cards (owner_id, target_id, source, issued_at, expires_at) values
  ('00000000-0000-0000-0000-d40000020009', '00000000-0000-0000-0000-d40000020010', 'purchased', now(), null),
  ('00000000-0000-0000-0000-d40000020011', '00000000-0000-0000-0000-d40000020001', 'daily', now(), now() + interval '3 days');
set local role service_role;
select results_eq(
  $$select a.cards_checked - b.cards_checked, a.cards_issued - b.cards_issued
      from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (1, 0)$$, 'cards check ignores purchased cards and other regions — 유료 카드 · 다른 지역에 나간 카드는 이 지역의 오늘 지급분이 아니다'
);
reset role;
update public.region_group_settings set issue_weekdays = array[extract(isodow from (now() at time zone 'Asia/Seoul'))::int]::smallint[]
 where region_group = 'd4h_other';
set local role service_role;
select results_eq(
  $$select a.cards_checked - b.cards_checked, a.cards_issued - b.cards_issued
      from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (2, 1)$$, 'cards check reports partial zero — 두 지역 중 한 곳만 0장이어도 지급된 지역이 있다(서버는 정상으로 본다)'
);
reset role;
delete from public.daily_cards where owner_id = '00000000-0000-0000-0000-d40000020011';
update public.universities set card_opens_at = '2099-01-05 07:00+09'
 where id in ('00000000-0000-0000-0000-d40000000a11', '00000000-0000-0000-0000-d40000000a12');
set local role service_role;
select results_eq(
  $$select a.cards_checked - b.cards_checked, a.cards_issued - b.cards_issued
      from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (0, 0)$$, 'cards check skips regions whose schools are not open yet — 11/2 전 코호트(받을 사람 0 · 오늘 카드 0)는 점검 대상이 아니다'
);

-- ② 안 닫힌 방 --------------------------------------------------------------------------
select results_eq(
  $$select a.stuck_rooms - b.stuck_rooms from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (1)$$,
  'stuck rooms count rooms past the deadline and ignore rooms the batch skips on purpose — 공유 · 닫힘 · 한쪽 나감 · 정지 · 탈퇴 · 10시간 방은 안 센다'
);
select results_eq(
  $$select a.stuck_rooms - b.stuck_rooms from public.admin_health(0, 60, 31, 24, 12) a, hb_room60 b$$,
  $$values (0)$$, 'stuck rooms honor p_room_hours — 60시간 기준이면 51시간 방은 아직'
);

-- ③ 탈퇴 미삭제 ------------------------------------------------------------------------
select results_eq(
  $$select a.overdue_withdrawn - b.overdue_withdrawn from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (1)$$, 'overdue withdrawn counts only withdrawn past the cutoff — 32일 전 탈퇴만(30일 전 · 방금 탈퇴 · 활성은 안 센다)'
);
select results_eq(
  $$select a.overdue_withdrawn - b.overdue_withdrawn from public.admin_health(0, 50, 29, 24, 12) a, hb_wd29 b$$,
  $$values (2)$$, 'overdue withdrawn honors p_withdrawn_days — 29일 기준이면 30일 전 탈퇴도 센다'
);

-- ④ 아바타 실패 ------------------------------------------------------------------------
select results_eq(
  $$select a.avatar_failures - b.avatar_failures from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (1)$$, 'avatar failures count failed rows inside the window — 2시간 전 failed 만(ready · pending · 30시간 전 failed 는 안 센다)'
);

-- ⑤ 오래 쌓인 푸시 ----------------------------------------------------------------------
select results_eq(
  $$select a.stuck_pushes - b.stuck_pushes from public.admin_health(0, 50, 31, 24, 12) a, hb_p0 b$$,
  $$values (1)$$, 'stuck pushes count rows older than the window — 13시간 전만(1시간 전은 안 센다)'
);
reset role;
set local role authenticated;
select throws_ok($$select * from public.admin_health(0, 50, 31, 24, 12)$$, '42501', null, 'authenticated 는 admin_health 를 부를 수 없다');
reset role;

-- ===== Task 3. 매칭 현황 ====================================================================
create temp table bm_s as select * from public.admin_matching_summary();
create temp table bm_d as select * from public.admin_matching_daily(3);
grant select on bm_s, bm_d to service_role;

-- 사람 9명(번호 = 끝 네 자리): 홀수 = D4열림대학교(a01), 짝수 = D4예정대학교(a02), 9 = D4빈대학교(a03).
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-d4000003' || lpad(i::text, 4, '0'))::uuid, 'd4m-' || i || '@example.com'
  from generate_series(1, 9) as i;
insert into public.profiles (id, university_id)
select u.id, '00000000-0000-0000-0000-d40000000a01' from auth.users u where u.email like 'd4m-%@example.com'
on conflict (id) do nothing;
update public.profiles p set
  university_id = (case when right(p.id::text, 4)::int = 9 then '00000000-0000-0000-0000-d40000000a03'
                        when right(p.id::text, 4)::int % 2 = 1 then '00000000-0000-0000-0000-d40000000a01'
                        else '00000000-0000-0000-0000-d40000000a02' end)::uuid,
  gender = (case when right(p.id::text, 4)::int % 2 = 1 then 'male' else 'female' end)::public.gender,
  status = 'active', birth_year = 2002, height_cm = 170, nickname = '매칭' || chr(96 + right(p.id::text, 4)::int)
where p.id::text like '00000000-0000-0000-0000-d4000003%';

-- 매칭 여섯 쌍(profile_a < profile_b). 한 줄에 시각 · 공유 · 닫힘을 모두 적는다.
--   M1 (1,2) 어제 10시 매칭 · 오늘 01시 공유 / M2 (3,4) 어제 12시 · 대화 중 / M3 (5,6) 어제 12시(M2 와 같은 시각) · 어제 20시 닫힘 /
--   M4 (7,8) 그제 01시 · 8 번이 나감 / M5 (1,4) 오늘 00:30 매칭 · 00:40 공유 · 4 번이 나감(공유가 끝난 방은 나가도 공유 완료) /
--   M6 (1,9) 3일 전 · 대화 중(학교 필터가 B 쪽도 보는지 보려고 9 번은 다른 학교).
insert into public.matches (id, profile_a, profile_b, created_at, trust_passed_at, chat_closed_at)
select v.id::uuid, ('00000000-0000-0000-0000-d4000003' || lpad(v.a::text, 4, '0'))::uuid,
       ('00000000-0000-0000-0000-d4000003' || lpad(v.b::text, 4, '0'))::uuid, v.created, v.shared, v.closed
  from k, lateral (values
    ('00000000-0000-0000-0000-d40000030a01', 1, 2, k.t0 - interval '1 day' + interval '10 hours', k.t0 + interval '1 hour', null::timestamptz),
    ('00000000-0000-0000-0000-d40000030a02', 3, 4, k.t0 - interval '1 day' + interval '12 hours', null, null),
    ('00000000-0000-0000-0000-d40000030a03', 5, 6, k.t0 - interval '1 day' + interval '12 hours', null, k.t0 - interval '1 day' + interval '20 hours'),
    ('00000000-0000-0000-0000-d40000030a04', 7, 8, k.t0 - interval '2 days' + interval '1 hour', null, null),
    ('00000000-0000-0000-0000-d40000030a05', 1, 4, k.t0 + interval '30 minutes', k.t0 + interval '40 minutes', null),
    ('00000000-0000-0000-0000-d40000030a06', 1, 9, k.t0 - interval '3 days' + interval '1 hour', null, null)
  ) as v(id, a, b, created, shared, closed);
insert into public.match_participants (match_id, profile_id)
select m.id, x.pid from public.matches m, lateral (values (m.profile_a), (m.profile_b)) as x(pid)
 where m.id::text like '00000000-0000-0000-0000-d40000030a%';
update public.match_participants set left_at = now()
 where (match_id, profile_id) in (('00000000-0000-0000-0000-d40000030a04', '00000000-0000-0000-0000-d40000030008'),
                                  ('00000000-0000-0000-0000-d40000030a05', '00000000-0000-0000-0000-d40000030004'));

-- 수락: c1 1→2 오늘 00:30 수락 / c2 2→1 오늘 00:40 거절 / c3 3→4 어제 23:30 수락 / c4 3→5 어제 09시 수락(같은 사람 두 번) /
-- c5 5→6 유료 카드 오늘 00:50 수락. 수락 = 오늘 2 · 어제 2 · 누적 4, 수락한 사람 = 1 · 3 · 5 세 명.
insert into public.daily_cards (id, owner_id, target_id, source, issued_at, expires_at)
select v.id::uuid, ('00000000-0000-0000-0000-d4000003' || lpad(v.o::text, 4, '0'))::uuid,
       ('00000000-0000-0000-0000-d4000003' || lpad(v.t::text, 4, '0'))::uuid, v.src::public.card_source, now(), v.exp
  from (values
    ('00000000-0000-0000-0000-d40000030c01', 1, 2, 'daily', now() + interval '3 days'),
    ('00000000-0000-0000-0000-d40000030c02', 2, 1, 'daily', now() + interval '3 days'),
    ('00000000-0000-0000-0000-d40000030c03', 3, 4, 'daily', now() + interval '3 days'),
    ('00000000-0000-0000-0000-d40000030c04', 3, 5, 'daily', now() + interval '3 days'),
    ('00000000-0000-0000-0000-d40000030c05', 5, 6, 'purchased', null::timestamptz)
  ) as v(id, o, t, src, exp);
insert into public.card_decisions (card_id, decision, decided_at)
select v.id::uuid, v.d::public.card_decision, v.at
  from k, lateral (values
    ('00000000-0000-0000-0000-d40000030c01', 'accept', k.t0 + interval '30 minutes'),
    ('00000000-0000-0000-0000-d40000030c02', 'reject', k.t0 + interval '40 minutes'),
    ('00000000-0000-0000-0000-d40000030c03', 'accept', k.t0 - interval '30 minutes'),
    ('00000000-0000-0000-0000-d40000030c04', 'accept', k.t0 - interval '1 day' + interval '9 hours'),
    ('00000000-0000-0000-0000-d40000030c05', 'accept', k.t0 + interval '50 minutes')
  ) as v(id, d, at);

set local role service_role;

-- 모양 · 권한 (아래 6 번에서 함수 여덟 개를 한꺼번에 다시 본다)
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_matching_summary', 'admin_matching_daily', 'admin_matching_pairs')
      and not p.prosecdef and p.proconfig = array['search_path=""']),
  3::bigint, '매칭 함수 셋이 있고 모두 security invoker · search_path 빈 값이다'
);

-- 요약 ---------------------------------------------------------------------------------
select results_eq(
  $$select a.accepts_today - b.accepts_today, a.accepts_yesterday - b.accepts_yesterday, a.accepts_total - b.accepts_total,
           a.accepters_total - b.accepters_total
      from public.admin_matching_summary() a, bm_s b$$,
  $$values (2, 2, 4::bigint, 3::bigint)$$,
  'summary counts accepts by kst day, ignores rejects, counts accepters once, includes purchased cards — 오늘 2 · 어제 2(23:30 포함) · 누적 4 · 사람 3(1 · 3 · 5)'
);
select results_eq(
  $$select a.matches_total - b.matches_total, a.shared_total - b.shared_total from public.admin_matching_summary() a, bm_s b$$,
  $$values (6::bigint, 2::bigint)$$, 'summary matches and shared — 매칭 6쌍, 공유 완료(trust_passed_at 있음) 2쌍'
);

-- 일별 ---------------------------------------------------------------------------------
select results_eq(
  $$select d.day, d.accept_count - b.accept_count, d.match_count - b.match_count, d.share_count - b.share_count
      from public.admin_matching_daily(3) d join bm_d b using (day) order by d.day$$,
  $$select k.today - 2, 0, 1, 0 from k union all select k.today - 1, 2, 3, 0 from k union all select k.today, 2, 1, 2 from k order by 1$$,
  'matching daily counts each event on its own kst day — M1 은 어제 매칭 · 오늘 공유, 거절은 안 세고, 유료 카드 수락은 센다'
);
select results_eq(
  $$select count(*), min(day), max(day) from public.admin_matching_daily(3)$$,
  $$select 3::bigint, k.today - 2, k.today from k$$, 'matching daily returns exactly p_days rows — 3줄 · 마지막 오늘(KST)'
);
select is((select count(*) from public.admin_matching_daily(90)), 90::bigint, 'matching daily 90 gives 90 rows zero filled');
select throws_ok($$select * from public.admin_matching_daily(0)$$, '22023', null, 'matching daily rejects 0');
select throws_ok($$select * from public.admin_matching_daily(91)$$, '22023', null, 'matching daily rejects 91');
select throws_ok($$select * from public.admin_matching_daily(null)$$, '22023', null, 'matching daily rejects null');

-- 누가 누구랑 (학교 a01 로 이 시험의 매칭만 거른다 — 다른 시험의 매칭과 섞이지 않게) ------------------
select results_eq(
  $$select match_id::text from public.admin_matching_pairs(null, '00000000-0000-0000-0000-d40000000a01', null, null, 101)$$,
  $$values ('00000000-0000-0000-0000-d40000030a05'), ('00000000-0000-0000-0000-d40000030a03'),
           ('00000000-0000-0000-0000-d40000030a02'), ('00000000-0000-0000-0000-d40000030a01'),
           ('00000000-0000-0000-0000-d40000030a04'), ('00000000-0000-0000-0000-d40000030a06')$$,
  'pairs ordered newest first with id tie break — M2 · M3 은 같은 시각이라 id 큰 쪽(M3)이 먼저'
);
select results_eq(
  $$select match_id::text from public.admin_matching_pairs(null, '00000000-0000-0000-0000-d40000000a01',
      (select t0 - interval '1 day' + interval '12 hours' from k), '00000000-0000-0000-0000-d40000030a03', 101)$$,
  $$values ('00000000-0000-0000-0000-d40000030a02'), ('00000000-0000-0000-0000-d40000030a01'),
           ('00000000-0000-0000-0000-d40000030a04'), ('00000000-0000-0000-0000-d40000030a06')$$,
  'pairs cursor returns only older rows — M3 다음 쪽은 같은 시각의 M2 부터, 겹치지 않는다'
);
select throws_ok(
  $$select * from public.admin_matching_pairs(null, null, now(), null, 10)$$, '22023', null, 'pairs cursor needs both parts (시각만)');
select throws_ok(
  $$select * from public.admin_matching_pairs(null, null, null, '00000000-0000-0000-0000-d40000030a03', 10)$$, '22023', null,
  'pairs cursor needs both parts (id 만)');
select results_eq(
  $$select match_id::text, status from public.admin_matching_pairs('shared', '00000000-0000-0000-0000-d40000000a01', null, null, 101)$$,
  $$values ('00000000-0000-0000-0000-d40000030a05', 'shared'), ('00000000-0000-0000-0000-d40000030a01', 'shared')$$,
  'pairs status shared — 공유가 끝난 방은 이후 한 사람이 나가도(M5) shared 로 남는다'
);
select results_eq(
  $$select match_id::text, status from public.admin_matching_pairs('closed', '00000000-0000-0000-0000-d40000000a01', null, null, 101)$$,
  $$values ('00000000-0000-0000-0000-d40000030a03', 'closed'), ('00000000-0000-0000-0000-d40000030a04', 'closed')$$,
  'pairs status closed — 닫힘(M3)과 공유 전에 한 사람이 나감(M4)'
);
select results_eq(
  $$select match_id::text, status from public.admin_matching_pairs('chatting', '00000000-0000-0000-0000-d40000000a01', null, null, 101)$$,
  $$values ('00000000-0000-0000-0000-d40000030a02', 'chatting'), ('00000000-0000-0000-0000-d40000030a06', 'chatting')$$,
  'pairs status chatting — 아무 일도 없는 방'
);
select throws_ok($$select * from public.admin_matching_pairs('ended', null, null, null, 10)$$, '22023', null, 'pairs rejects an unknown status');
select throws_ok($$select * from public.admin_matching_pairs('shared,closed', null, null, null, 10)$$, '22023', null, 'pairs rejects a list of statuses');
select throws_ok($$select * from public.admin_matching_pairs('', null, null, null, 10)$$, '22023', null, 'pairs rejects an empty status');
select results_eq(
  $$select match_id::text from public.admin_matching_pairs(null, '00000000-0000-0000-0000-d40000000a03', null, null, 101)$$,
  $$values ('00000000-0000-0000-0000-d40000030a06')$$,
  'pairs university filter matches either side — M6 은 B 쪽(9 번)의 학교로도, A 쪽(1 번)의 학교(위 목록)로도 나온다'
);
select results_eq(
  $$select a_nickname, a_university, b_nickname, b_university from public.admin_matching_pairs(null,
      '00000000-0000-0000-0000-d40000000a03', null, null, 10)$$,
  $$values ('매칭a', 'D4열림대학교', '매칭i', 'D4빈대학교')$$, 'pairs show nicknames and university names'
);
select results_eq(
  $$select pg_get_function_result('public.admin_matching_pairs(text,uuid,timestamptz,uuid,integer)'::regprocedure)$$,
  $$values ('TABLE(match_id uuid, matched_at timestamp with time zone, status text, shared_at timestamp with time zone, a_id uuid, a_nickname text, a_university text, b_id uuid, b_nickname text, b_university text)')$$,
  'pairs result columns are exactly the allowed list — 사진 · 카톡 아이디 · 대화 · 전화 칸이 슬쩍 더해지면 이 시험이 떨어진다'
);
select is((select count(*) from public.admin_matching_pairs(null, null, null, null, 1)), 1::bigint, 'pairs limit 1 gives one row');
select throws_ok($$select * from public.admin_matching_pairs(null, null, null, null, 0)$$, '22023', null, 'pairs rejects limit 0');
select throws_ok($$select * from public.admin_matching_pairs(null, null, null, null, 102)$$, '22023', null, 'pairs rejects limit 102');

-- 6. 새 함수 여덟 개 모두 service_role 만 부른다 -----------------------------------------------
reset role;
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_stats_overview', 'admin_stats_daily', 'admin_unknown_domains', 'admin_universities_status',
                        'admin_health', 'admin_matching_summary', 'admin_matching_daily', 'admin_matching_pairs')
      and not p.prosecdef
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')),
  8::bigint, '새 함수 여덟 개 모두 invoker 이고 service_role 만 실행한다(anon · authenticated 없음)'
);
set local role authenticated;
select throws_ok($$select * from public.admin_matching_summary()$$, '42501', null, 'authenticated 는 admin_matching_summary 를 부를 수 없다');
select throws_ok($$select * from public.admin_matching_daily(3)$$, '42501', null, 'authenticated 는 admin_matching_daily 를 부를 수 없다');
select throws_ok($$select * from public.admin_matching_pairs(null, null, null, null, 10)$$, '42501', null, 'authenticated 는 admin_matching_pairs 를 부를 수 없다');
reset role;

select * from finish();
rollback;
