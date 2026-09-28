-- grant_hearts(원장 + 잔액 캐시를 한 함수에서 쓴다, ERD §6)의 동작을 못박는다.
-- 적립(투표 보상 · 5회 실패 보상 · 추천 · 하트 과제)은 양수, 쓰기(아바타 다시 만들기, 계획서 2026-09-27-me-edit.md)는 음수다.
-- 로컬 스택에서 `supabase test db` 로 돈다. rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- 준비 --------------------------------------------------------------------
-- A = ...da(잔액 5 로 시작), B = ...db(잔액 행이 아예 없다), C = ...dc(적립만 본다, 행 없음에서 시작), 대학 = ...d1
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-0000000000d1', '하트테스트대학교', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('hearts.ac.kr', '00000000-0000-0000-0000-0000000000d1');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000da', 'h-a@hearts.ac.kr'),
  ('00000000-0000-0000-0000-0000000000db', 'h-b@hearts.ac.kr'),
  ('00000000-0000-0000-0000-0000000000dc', 'h-c@hearts.ac.kr');

insert into public.profiles (id, university_id) values
  ('00000000-0000-0000-0000-0000000000da', '00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000db', '00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000dc', '00000000-0000-0000-0000-0000000000d1')
on conflict (id) do nothing;

-- 함수 모양 · 권한 — 고친 뒤에도 그대로다 ----------------------------------------
select has_function('public', 'grant_hearts', array['uuid', 'integer', 'heart_reason', 'uuid'],
  'grant_hearts 이름 · 인자가 그대로다');
select ok(has_function_privilege('service_role', 'public.grant_hearts(uuid, integer, public.heart_reason, uuid)', 'execute'),
  'service_role 은 부를 수 있다');
select ok(not has_function_privilege('anon', 'public.grant_hearts(uuid, integer, public.heart_reason, uuid)', 'execute'),
  'anon 은 못 부른다');
select ok(not has_function_privilege('authenticated', 'public.grant_hearts(uuid, integer, public.heart_reason, uuid)', 'execute'),
  'authenticated 는 못 부른다(앱이 직접 하트를 만들 수 없다)');
select is(
  (select proconfig from pg_proc where oid = 'public.grant_hearts(uuid, integer, public.heart_reason, uuid)'::regprocedure),
  array['search_path=""'],
  'search_path 는 빈 값으로 고정돼 있다(advisor WARN 조치 유지)'
);

-- 적립 — 지금과 같다 --------------------------------------------------------------
select lives_ok(
  $$select public.grant_hearts('00000000-0000-0000-0000-0000000000dc', 10, 'poll_vote')$$,
  '잔액 행이 없는 사람에게 적립하면 통과한다'
);
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000dc'),
  10,
  '잔액 행이 없으면 적립액으로 새로 생긴다'
);
select public.grant_hearts('00000000-0000-0000-0000-0000000000dc', 10, 'admin_adjust');
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000dc'),
  20,
  '잔액 행이 있으면 더해진다'
);
select is(
  (select count(*)::int from public.heart_transactions where profile_id = '00000000-0000-0000-0000-0000000000dc'),
  2,
  '적립마다 원장 한 줄'
);

-- 쓰기 --------------------------------------------------------------------------
select public.grant_hearts('00000000-0000-0000-0000-0000000000da', 5, 'promo');

select throws_ok(
  $$select public.grant_hearts('00000000-0000-0000-0000-0000000000da', -10, 'avatar_regen')$$,
  '23514', null,
  '잔액 5 에서 10 을 쓰면 잔액 음수 금지에 막힌다'
);
select is(
  (select count(*)::int from public.heart_transactions
    where profile_id = '00000000-0000-0000-0000-0000000000da' and reason = 'avatar_regen'),
  0,
  '막힌 쓰기는 원장에도 남지 않는다(함수째 되돌아간다)'
);
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000da'),
  5,
  '막힌 쓰기 뒤 잔액은 그대로다'
);
select throws_ok(
  $$select public.grant_hearts('00000000-0000-0000-0000-0000000000db', -10, 'avatar_regen')$$,
  '23514', null,
  '잔액 행이 아예 없는 사람도 음수 쓰기는 막힌다'
);
select ok(
  not exists (select 1 from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000db')
  and not exists (select 1 from public.heart_transactions where profile_id = '00000000-0000-0000-0000-0000000000db'),
  '막힌 쓰기는 잔액 행(0 으로 만든 것)도 원장 줄도 남기지 않는다'
);
select lives_ok(
  $$select public.grant_hearts('00000000-0000-0000-0000-0000000000da', -5, 'avatar_regen',
                                '00000000-0000-0000-0000-00000000a001')$$,
  '잔액만큼은 쓸 수 있다'
);
select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000da'),
  0,
  '다 쓰면 잔액 0'
);
select ok(
  (select amount = -5 and reason = 'avatar_regen'::public.heart_reason from public.heart_transactions
    where ref_id = '00000000-0000-0000-0000-00000000a001'),
  '성공한 쓰기의 원장 줄은 금액 -5 · 사유 avatar_regen 이다'
);
select is(
  (select coalesce(sum(amount), 0)::int from public.heart_transactions
    where profile_id = '00000000-0000-0000-0000-0000000000da'),
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000da'),
  '잔액 캐시는 원장 합과 같다(ERD §6)'
);

select * from finish();
rollback;
