-- 유료 카드 제안 표(paid_card_offers)와 구매 함수(purchase_paid_card) 검증 — 수익모델 재설계 01 §3, §7, §8.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
--
-- 동시성: purchase_paid_card 는 제안 행을 `for update` 로 잠근 채 끝까지 간다. 같은 제안으로 두 요청이 겹쳐도
-- 두 번째는 첫 번째가 끝날 때까지 기다렸다가 status 가 이미 purchased 인 것을 보고 already_purchased 를 받는다.
-- 한 트랜잭션 안에서는 겹침을 만들 수 없어서 "같은 제안 두 번 부르기"(아래 4번)로 그 결과를 대신 본다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

-- 준비 --------------------------------------------------------------------
insert into public.region_group_settings (region_group) values ('paid_test');
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000003001', '유료카드테스트대학교', 'paid_test');

-- O1 = 3101(남, 하트 120) · O2 = 3111(남, 하트 10) · O3 = 3112(남, entitlements 행 없음)
-- 대상(여): 3102 정상 · 3103 replaced 용(프로필 삭제 시험도 겸함) · 3104 expired 용 · 3105 O1 이 차단 · 3106 정지
--           3107 무료 카드가 따로 나가 있음 · 3108 제약 시험용 · 3113 O2 의 대상 · 3114 O3 의 대상
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000' || n)::uuid, 'pc-' || n || '@paid.ac.kr'
from unnest(array['3101','3102','3103','3104','3105','3106','3107','3108','3111','3112','3113','3114']) as n;

update public.profiles set
  university_id = '00000000-0000-0000-0000-000000003001',
  gender = (case when right(id::text, 4) in ('3101', '3111', '3112') then 'male' else 'female' end)::public.gender,
  status = (case when right(id::text, 4) = '3106' then 'suspended' else 'active' end)::public.profile_status,
  birth_year = 2002, height_cm = 170, last_active_at = now(),
  interest_tags = array['카페가기'], my_traits = array['다정한'], ideal_traits = array['다정한'],
  nickname = 'p' || translate(right(id::text, 3), '0123456789', 'abcdefghij')
where id in (select id from auth.users where email like '%@paid.ac.kr');

insert into public.profile_vectors (profile_id, self_survey, self_embedding, want_embedding)
select id, '[1,0,0,0,0,0,0,0]',
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector
from public.profiles
where university_id = '00000000-0000-0000-0000-000000003001';

insert into public.entitlements (profile_id, heart_balance) values
  ('00000000-0000-0000-0000-000000003101', 120),
  ('00000000-0000-0000-0000-000000003111', 10);

-- 제안(offer id = …f0xx). 같은 주기에 offered 는 하나만 가능해서 offered 끼리는 주기를 다르게 둔다.
insert into public.paid_card_offers (id, owner_id, cycle_started_at, target_id, reasons, band_count, status) values
  ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-000000003101', now() - interval '1 day',  '00000000-0000-0000-0000-000000003102', '["같은 동네"]', 3, 'offered'),
  ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-000000003101', now() - interval '8 days', '00000000-0000-0000-0000-000000003103', '[]', 3, 'replaced'),
  ('00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-000000003101', now() - interval '9 days', '00000000-0000-0000-0000-000000003104', '[]', 3, 'expired'),
  ('00000000-0000-0000-0000-00000000f004', '00000000-0000-0000-0000-000000003101', now() - interval '2 days', '00000000-0000-0000-0000-000000003105', '[]', 3, 'offered'),
  ('00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-000000003101', now() - interval '3 days', '00000000-0000-0000-0000-000000003106', '[]', 3, 'offered'),
  ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-000000003101', now() - interval '4 days', '00000000-0000-0000-0000-000000003107', '[]', 3, 'offered'),
  ('00000000-0000-0000-0000-00000000f007', '00000000-0000-0000-0000-000000003111', now() - interval '1 day',  '00000000-0000-0000-0000-000000003113', '[]', 2, 'offered'),
  ('00000000-0000-0000-0000-00000000f008', '00000000-0000-0000-0000-000000003112', now() - interval '1 day',  '00000000-0000-0000-0000-000000003114', '[]', 2, 'offered');

-- 3105 는 O1 이 차단, 3107 에게는 무료 카드가 이미 나가 살아 있다(= 이제 고를 수 없는 사람).
insert into public.blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-000000003105');
insert into public.daily_cards (owner_id, target_id, source, expires_at) values
  ('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-000000003107', 'daily', now() + interval '1 day');

-- 1. 표 구조 · 권한 -----------------------------------------------------------
select has_table('public', 'paid_card_offers', '유료 카드 제안 표가 있다');
select has_index('public', 'paid_card_offers', 'paid_card_offers_one_offered_per_cycle', '주기마다 offered 하나 — 부분 유일 인덱스');
select has_index('public', 'paid_card_offers', 'paid_card_offers_owner_created_index', '사람별 최근 제안 인덱스');
select is((select relrowsecurity from pg_class where oid = 'public.paid_card_offers'::regclass), true, 'RLS 켜짐');
select is((select count(*) from pg_policies where schemaname = 'public' and tablename = 'paid_card_offers'), 0::bigint, '정책 없음 = 클라이언트 접근 없음');
select ok(
  not has_table_privilege('authenticated', 'public.paid_card_offers', 'select')
  and not has_table_privilege('anon', 'public.paid_card_offers', 'select')
  and not has_table_privilege('authenticated', 'public.paid_card_offers', 'insert')
  and not has_table_privilege('anon', 'public.paid_card_offers', 'insert'),
  'anon · authenticated 는 읽지도 쓰지도 못한다'
);
select ok(has_table_privilege('service_role', 'public.paid_card_offers', 'select, insert, update'), 'service_role 은 읽고 쓴다');
select ok(
  not has_function_privilege('authenticated', 'public.purchase_paid_card(uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.purchase_paid_card(uuid, uuid)', 'execute')
  and has_function_privilege('service_role', 'public.purchase_paid_card(uuid, uuid)', 'execute'),
  'purchase_paid_card 는 service_role 만 부른다'
);

-- 2. 제약 ----------------------------------------------------------------------
select throws_ok(
  $$insert into public.paid_card_offers (owner_id, cycle_started_at, target_id, band_count, status)
    select owner_id, cycle_started_at, '00000000-0000-0000-0000-000000003108', 3, 'offered'
    from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001'$$,
  '23505', null, '같은 주기에 offered 를 둘 둘 수 없다'
);

select lives_ok(
  $$insert into public.paid_card_offers (owner_id, cycle_started_at, target_id, band_count, status)
    select owner_id, cycle_started_at, '00000000-0000-0000-0000-000000003108', 3, 'replaced'
    from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001'$$,
  '같은 주기라도 replaced 는 여럿 쌓일 수 있다'
);

select throws_ok(
  $$insert into public.paid_card_offers (owner_id, cycle_started_at, target_id, band_count)
    values ('00000000-0000-0000-0000-000000003101', now() - interval '20 days', '00000000-0000-0000-0000-000000003108', 0)$$,
  '23514', null, '후보 폭(band_count)은 1 이상이다'
);

select throws_ok(
  $$insert into public.paid_card_offers (owner_id, cycle_started_at, target_id, band_count, status, purchased_card_id)
    select '00000000-0000-0000-0000-000000003101', now() - interval '21 days', '00000000-0000-0000-0000-000000003108', 3, 'offered', id
    from public.daily_cards limit 1$$,
  '23514', null, 'purchased 가 아닌 제안은 구매 카드를 가질 수 없다'
);

select is(
  (select status::text from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001'),
  'offered', '제안의 기본 상태는 offered 다'
);

-- 옛 제안을 replaced 로 돌리면 같은 주기에 새 offered 를 넣을 수 있다(서버의 재선정).
-- f004 를 바꾸고 새 행을 넣은 뒤, 아래 시험 흐름을 위해 되돌린다.
update public.paid_card_offers set status = 'replaced' where id = '00000000-0000-0000-0000-00000000f004';
select lives_ok(
  $$insert into public.paid_card_offers (id, owner_id, cycle_started_at, target_id, band_count, status)
    select '00000000-0000-0000-0000-00000000f0ff', owner_id, cycle_started_at,
           '00000000-0000-0000-0000-000000003108', 3, 'offered'
    from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f004'$$,
  'replaced 로 바뀐 뒤에는 같은 주기에 새 offered 를 넣을 수 있다'
);
delete from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f0ff';
update public.paid_card_offers set status = 'offered' where id = '00000000-0000-0000-0000-00000000f004';

-- 3. 구매 ------------------------------------------------------------------------
set local role service_role;

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000f001') ->> 'result',
  'ok', '정상 구매는 ok 다'
);

select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000003101'),
  70, '하트가 50 빠진다(120 -> 70)'
);

select is(
  (select count(*) from public.daily_cards
    where owner_id = '00000000-0000-0000-0000-000000003101' and target_id = '00000000-0000-0000-0000-000000003102'
      and source = 'purchased' and expires_at is null),
  1::bigint, '만료 없는 구매 카드가 한 장 생긴다'
);

select is(
  (select status::text from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001'),
  'purchased', '제안은 purchased 가 된다'
);

select is(
  (select purchased_card_id from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001'),
  (select id from public.daily_cards
    where owner_id = '00000000-0000-0000-0000-000000003101' and target_id = '00000000-0000-0000-0000-000000003102'),
  '제안이 만든 카드를 가리킨다'
);

select is(
  (select count(*) from public.heart_transactions
    where profile_id = '00000000-0000-0000-0000-000000003101' and amount = -50
      and reason = 'extra_card' and ref_id = '00000000-0000-0000-0000-00000000f001'),
  1::bigint, '원장에 -50 · extra_card · 제안 id 한 줄이 남는다'
);

-- 4. 같은 제안 두 번 -------------------------------------------------------------
select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000f001') ->> 'result',
  'already_purchased', '같은 제안을 다시 사면 already_purchased 다'
);

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000f001') ->> 'card_id',
  (select purchased_card_id::text from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001'),
  'already_purchased 는 처음 만든 카드 id 를 돌려준다'
);

select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000003101')
  || '/' ||
  (select count(*) from public.daily_cards
    where owner_id = '00000000-0000-0000-0000-000000003101' and target_id = '00000000-0000-0000-0000-000000003102'),
  '70/1', '두 번 불러도 하트는 한 번만 빠지고 카드는 한 장이다'
);

-- 5. 하트 부족 -----------------------------------------------------------------
select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003111', '00000000-0000-0000-0000-00000000f007'),
  '{"result": "not_enough_hearts"}'::jsonb, '하트가 모자라면 not_enough_hearts 만 돌려준다(예외가 아니다)'
);

select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000003111'),
  10, '하트 부족이면 잔액이 그대로다'
);

select is(
  (select count(*) from public.daily_cards where owner_id = '00000000-0000-0000-0000-000000003111')
  + (select count(*) from public.heart_transactions where profile_id = '00000000-0000-0000-0000-000000003111'),
  0::bigint, '하트 부족이면 카드도 원장 줄도 생기지 않는다(부분 커밋 없음)'
);

select is(
  (select status::text from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f007'),
  'offered', '하트 부족이면 제안은 그대로 offered 다(충전 뒤 다시 살 수 있다)'
);

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003112', '00000000-0000-0000-0000-00000000f008') ->> 'result'
  || '/' || (select count(*) from public.entitlements where profile_id = '00000000-0000-0000-0000-000000003112'),
  'not_enough_hearts/0', '하트 행 자체가 없는 사람도 not_enough_hearts 이고 빈 행이 남지 않는다'
);

-- 6. 못 사는 제안 ---------------------------------------------------------------
select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003111', '00000000-0000-0000-0000-00000000f004') ->> 'result',
  'offer_gone', '남의 제안은 offer_gone 이다'
);

select is(
  (select status::text from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f004'),
  'offered', '남의 제안으로 불러도 그 제안의 상태는 바뀌지 않는다(주인이 아닌 사람이 남의 제안을 replaced 로 만들 수 없다)'
);

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000f002') ->> 'result',
  'offer_gone', 'replaced 제안은 offer_gone 이다'
);

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000f003') ->> 'result',
  'offer_gone', 'expired 제안은 offer_gone 이다'
);

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000ffff') ->> 'result',
  'offer_gone', '없는 제안도 offer_gone 이다'
);

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000f004') ->> 'result',
  'offer_gone', '대상을 내가 차단했으면 offer_gone 이다'
);

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000f005') ->> 'result',
  'offer_gone', '대상이 정지됐으면 offer_gone 이다'
);

select is(
  public.purchase_paid_card('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-00000000f006') ->> 'result',
  'offer_gone', '대상에게 다른 카드가 이미 살아 있으면 offer_gone 이다(중복 지급 방지)'
);

select is(
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000003101'),
  70, '못 산 제안들은 하트를 한 푼도 빼지 않았다'
);

select is(
  (select string_agg(status::text, ',' order by id) from public.paid_card_offers
    where id in ('00000000-0000-0000-0000-00000000f004', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-00000000f006')),
  'replaced,replaced,replaced',
  '대상이 자격을 잃은 제안은 replaced 로 바뀐다(서버가 같은 낡은 제안을 계속 보여 주지 않게)'
);

select is(
  (select status::text from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f003'),
  'expired', '이미 expired 인 제안은 불러도 상태가 그대로다'
);

reset role;

-- 7. 지우기 규칙 ------------------------------------------------------------------
-- 카드를 지우면 제안의 구매 카드 칸만 비고 제안은 남는다.
delete from public.daily_cards
 where id = (select purchased_card_id from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001');
select is(
  (select purchased_card_id from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001'),
  null, '카드가 지워지면 purchased_card_id 가 null 이 된다'
);
select is(
  (select status::text from public.paid_card_offers where id = '00000000-0000-0000-0000-00000000f001'),
  'purchased', '카드가 지워져도 제안 행과 purchased 상태는 남는다'
);

-- 대상 프로필을 지우면 그 제안도 같이 지워진다(탈퇴).
delete from public.profiles where id = '00000000-0000-0000-0000-000000003103';
select is_empty(
  $$select 1 from public.paid_card_offers where target_id = '00000000-0000-0000-0000-000000003103'$$,
  '대상 프로필이 지워지면 제안도 cascade 로 지워진다'
);
-- 주인 프로필을 지워도 마찬가지.
delete from public.profiles where id = '00000000-0000-0000-0000-000000003112';
select is_empty(
  $$select 1 from public.paid_card_offers where owner_id = '00000000-0000-0000-0000-000000003112'$$,
  '주인 프로필이 지워지면 제안도 cascade 로 지워진다'
);

select * from finish();
rollback;
