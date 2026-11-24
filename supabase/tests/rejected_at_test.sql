-- 거절 되돌리기 칸(1.0.7 #20) 검증. 마이그레이션 20261123161541_card_decisions_rejected_at.sql.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
-- 서버의 조건부 PATCH(아직 거절 · 7일 안인 행만 accept 로)가 두 번째 요청에서 0행인지도 SQL 로 같은 조건을 돌려 본다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- 1. 칸 · 권한 ------------------------------------------------------------------------------------------
select has_column('public', 'card_decisions', 'rejected_at', 'card_decisions 에 rejected_at 이 있다');
select col_type_is('public', 'card_decisions', 'rejected_at', 'timestamp with time zone', 'timestamptz 다');
select col_is_null('public', 'card_decisions', 'rejected_at', 'null 을 받는다(되돌린 적 없음)');
select col_hasnt_default('public', 'card_decisions', 'rejected_at', '기본값이 없다 — 서버만 채운다');
select has_column('public', 'acceptance_responses', 'rejected_at', 'acceptance_responses 에 rejected_at 이 있다');
select col_type_is('public', 'acceptance_responses', 'rejected_at', 'timestamp with time zone', 'timestamptz 다');
select col_is_null('public', 'acceptance_responses', 'rejected_at', 'null 을 받는다(되돌린 적 없음)');
select col_hasnt_default('public', 'acceptance_responses', 'rejected_at', '기본값이 없다 — 서버만 채운다');
-- 앱(anon · authenticated)은 두 표를 여전히 못 읽는다 — 칸 하나가 늘어도 권한은 그대로다.
select ok(not has_table_privilege('authenticated', 'public.card_decisions', 'select'),
          'authenticated 는 card_decisions 를 읽지 못한다');
select ok(not has_table_privilege('anon', 'public.acceptance_responses', 'select'),
          'anon 은 acceptance_responses 를 읽지 못한다');

-- 2. 조건부 PATCH 와 같은 update — 한 번만 ---------------------------------------------------------------
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-0000000020a1', '테스트대학교R', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('reapply.ac.kr', '00000000-0000-0000-0000-0000000020a1');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000020a2', 'r1@reapply.ac.kr'),
  ('00000000-0000-0000-0000-0000000020a3', 'r2@reapply.ac.kr');

insert into public.daily_cards (id, owner_id, target_id, source, issued_at, expires_at) values
  ('00000000-0000-0000-0000-0000000020c1', '00000000-0000-0000-0000-0000000020a2',
   '00000000-0000-0000-0000-0000000020a3', 'daily', now() - interval '4 days', now() - interval '1 day');
insert into public.card_decisions (card_id, decision, decided_at) values
  ('00000000-0000-0000-0000-0000000020c1', 'reject', now() - interval '3 days');

-- 서버가 보내는 PATCH 와 같은 조건 · 값.
create temporary table undo_runs (run int, changed int) on commit drop;
with changed as (
  update public.card_decisions
  set decision = 'accept', rejected_at = decided_at, decided_at = now()
  where card_id = '00000000-0000-0000-0000-0000000020c1'
    and decision = 'reject' and decided_at > now() - interval '7 days'
  returning 1
) insert into undo_runs select 1, count(*) from changed;
with changed as (
  update public.card_decisions
  set decision = 'accept', rejected_at = decided_at, decided_at = now()
  where card_id = '00000000-0000-0000-0000-0000000020c1'
    and decision = 'reject' and decided_at > now() - interval '7 days'
  returning 1
) insert into undo_runs select 2, count(*) from changed;

select is((select changed from undo_runs where run = 1), 1, '첫 다시 신청은 한 행을 바꾼다');
select is((select changed from undo_runs where run = 2), 0, '두 번째(연타 · 동시)는 0행 — 신청이 두 건이 되지 않는다');
select is((select rejected_at from public.card_decisions where card_id = '00000000-0000-0000-0000-0000000020c1'),
          now() - interval '3 days', '원래 거절 시각이 rejected_at 에 남는다');

-- 7일이 지난 거절은 조건에 걸리지 않는다.
update public.card_decisions set decision = 'reject', decided_at = now() - interval '7 days', rejected_at = null
where card_id = '00000000-0000-0000-0000-0000000020c1';
with changed as (
  update public.card_decisions
  set decision = 'accept', rejected_at = decided_at, decided_at = now()
  where card_id = '00000000-0000-0000-0000-0000000020c1'
    and decision = 'reject' and decided_at > now() - interval '7 days'
  returning 1
) insert into undo_runs select 3, count(*) from changed;
select is((select changed from undo_runs where run = 3), 0, '거절 뒤 7일이 지나면 바뀌지 않는다');

select * from finish();
rollback;
