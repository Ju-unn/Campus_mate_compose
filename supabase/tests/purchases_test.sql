-- 인앱결제 구매 기록(purchases)과 지급 · 환불 함수(grant_store_purchase · refund_store_purchase) 검증.
-- 기준: 바탕화면 출시준비/인앱결제_구현계획_초안.md 4-3 · 4-5(22항목), 하트_상품_첫구매보너스_안.md §4.
-- 로컬 스택에서 `supabase test db` 로 돈다. rollback 으로 흔적을 남기지 않는다.
--
-- 동시성(두 기기 동시 첫 구매)은 한 세션으로 재현하지 못한다 — grant_store_purchase 의 사람별 advisory lock 은 검토로 보고,
-- 같은 토큰 재전송 · 다른 사람의 같은 토큰(아래 7 · 8)으로 그 결과를 순차로 대신 본다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(67);

-- 준비 --------------------------------------------------------------------
-- A = …b0a1, B = …b0a2, C = …b0a3, 대학 = …b001. 토큰 해시는 64자 리터럴(repeat)로 둔다.
--   'a' A heart_100 첫 구매(보너스) → 환불     'b' A heart_200 두 번째(시험 결제)
--   'c' B heart_100 첫 구매(보너스) → 쓴 뒤 환불  'd' B 환불 뒤 heart_100(보너스 없음)
--   'e' C heart_50 → 잔액 0 에서 환불           'f' C heart_100(50 먼저 사서 보너스 없음) → 계정 삭제 뒤 환불
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000b001', '결제테스트대학교', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('billing.ac.kr', '00000000-0000-0000-0000-00000000b001');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000b0a1', 'pay-a@billing.ac.kr'),
  ('00000000-0000-0000-0000-00000000b0a2', 'pay-b@billing.ac.kr'),
  ('00000000-0000-0000-0000-00000000b0a3', 'pay-c@billing.ac.kr');

insert into public.profiles (id, university_id) values
  ('00000000-0000-0000-0000-00000000b0a1', '00000000-0000-0000-0000-00000000b001'),
  ('00000000-0000-0000-0000-00000000b0a2', '00000000-0000-0000-0000-00000000b001'),
  ('00000000-0000-0000-0000-00000000b0a3', '00000000-0000-0000-0000-00000000b001')
on conflict (id) do nothing;

-- 1. 표 · RLS ----------------------------------------------------------------
select has_table('public', 'purchases', '구매 기록 표가 있다');
select is((select relrowsecurity from pg_class where oid = 'public.purchases'::regclass), true, 'RLS 켜짐');
select has_index('public', 'purchases', 'purchases_profile_id_index', '사람별 조회 · RLS 용 profile_id 인덱스');

-- 2. enum ----------------------------------------------------------------------
select enum_has_labels('public', 'heart_reason',
  array['purchase', 'referral', 'promo', 'free_task', 'poll_vote', 'extra_card', 'avatar_regen', 'refund', 'admin_adjust',
        'first_purchase_bonus'],
  'heart_reason 은 기존 9개 + first_purchase_bonus');
select enum_has_labels('public', 'store_platform', array['play_store', 'app_store'], 'store_platform 은 play_store · app_store');
select enum_has_labels('public', 'purchase_status', array['granted', 'refunded'], 'purchase_status 는 granted · refunded');

-- 3. 함수 모양 ------------------------------------------------------------------
select has_function('public', 'grant_store_purchase',
  array['uuid', 'store_platform', 'text', 'text', 'text', 'timestamp with time zone', 'boolean'],
  'grant_store_purchase 이름 · 인자(서버 billing/repository.py 와 같은 순서)');
select has_function('public', 'refund_store_purchase', array['store_platform', 'text'],
  'refund_store_purchase 이름 · 인자');
select is(
  (select proconfig from pg_proc
    where oid = 'public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)'::regprocedure),
  array['search_path=""'], 'grant_store_purchase 의 search_path 는 빈 값');
select is(
  (select proconfig from pg_proc where oid = 'public.refund_store_purchase(public.store_platform, text)'::regprocedure),
  array['search_path=""'], 'refund_store_purchase 의 search_path 는 빈 값');
select ok(
  not (select prosecdef from pg_proc
        where oid = 'public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)'::regprocedure)
  and not (select prosecdef from pg_proc where oid = 'public.refund_store_purchase(public.store_platform, text)'::regprocedure),
  '두 함수 모두 security invoker(SUPABASE.md §5)');

-- 4. 함수 권한 — service_role 만 ------------------------------------------------
select ok(has_function_privilege('service_role',
  'public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)', 'execute'),
  'service_role 은 grant_store_purchase 를 부른다');
select ok(not has_function_privilege('anon',
  'public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)', 'execute'),
  'anon 은 grant_store_purchase 를 못 부른다');
select ok(not has_function_privilege('authenticated',
  'public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)', 'execute'),
  'authenticated 는 grant_store_purchase 를 못 부른다(앱이 직접 하트를 만들 수 없다)');
select ok(has_function_privilege('service_role', 'public.refund_store_purchase(public.store_platform, text)', 'execute'),
  'service_role 은 refund_store_purchase 를 부른다');
select ok(not has_function_privilege('anon', 'public.refund_store_purchase(public.store_platform, text)', 'execute'),
  'anon 은 refund_store_purchase 를 못 부른다');
select ok(not has_function_privilege('authenticated', 'public.refund_store_purchase(public.store_platform, text)', 'execute'),
  'authenticated 는 refund_store_purchase 를 못 부른다');

-- 5. 표 권한 — authenticated 는 읽기만, anon 은 아무것도 ---------------------------------
select ok(
  has_table_privilege('authenticated', 'public.purchases', 'select')
  and not has_table_privilege('authenticated', 'public.purchases', 'insert')
  and not has_table_privilege('authenticated', 'public.purchases', 'update')
  and not has_table_privilege('authenticated', 'public.purchases', 'delete'),
  'authenticated 는 select 만');
select ok(
  not has_table_privilege('anon', 'public.purchases', 'select')
  and not has_table_privilege('anon', 'public.purchases', 'insert'),
  'anon 은 읽지도 쓰지도 못한다');
-- 권한 목록을 한 문자열로 주면 넷 중 하나만 있어도 참이다 — 권한마다 따로 묻는다.
select ok(
  has_table_privilege('service_role', 'public.purchases', 'select')
  and has_table_privilege('service_role', 'public.purchases', 'insert')
  and has_table_privilege('service_role', 'public.purchases', 'update')
  and has_table_privilege('service_role', 'public.purchases', 'delete'),
  'service_role 은 select · insert · update · delete 를 모두 가진다');

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000b0a1", "role": "authenticated"}';
select throws_ok(
  $$insert into public.purchases (profile_id, store, product_id, token_hash, heart_amount, price_krw, purchased_at)
    values ('00000000-0000-0000-0000-00000000b0a1', 'play_store', 'heart_800', repeat('9', 64), 800, 38400, now())$$,
  '42501', null, '앱(authenticated)은 구매 기록을 직접 넣지 못한다');
reset role;

-- 6. A 첫 구매 heart_100 → 구매분 100 + 보너스 50 ----------------------------------------
set local role service_role;

select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a1', 'play_store', 'heart_100', repeat('a', 64),
                              'GPA.test-a', now() - interval '1 minute', false),
  '{"result": "granted", "hearts": 100, "bonus_hearts": 50, "heart_balance": 150}'::jsonb,
  '첫 구매(100하트 이상)는 보너스 50 과 함께 지급된다');
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-00000000b0a1'),
  150, 'A 잔액 150');
select is(
  (select array_agg(reason::text || ':' || amount order by amount desc) from public.heart_transactions
    where profile_id = '00000000-0000-0000-0000-00000000b0a1'),
  array['purchase:100', 'first_purchase_bonus:50'], '원장 두 줄 — 구매분과 보너스를 나눠 적는다');
select ok(
  (select bool_and(t.ref_id = p.id) and count(*) = 2
     from public.heart_transactions t
     join public.purchases p on p.token_hash = repeat('a', 64)
    where t.profile_id = '00000000-0000-0000-0000-00000000b0a1'),
  '원장 두 줄 모두 ref_id = 그 구매 행 id');
select ok(
  (select status = 'granted' and refunded_at is null and price_krw = 5700 and store_order_id = 'GPA.test-a'
          and heart_amount = 100 and bonus_hearts = 50 and not is_test
     from public.purchases where token_hash = repeat('a', 64)),
  '구매 행: granted · 판매가 5700 · 주문 번호 · 수량 · 보너스');

-- 7. 같은 토큰 다시(재전송 · 두 번 누름) ----------------------------------------------------
select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a1', 'play_store', 'heart_100', repeat('a', 64),
                              'GPA.test-a', now() - interval '1 minute', false),
  '{"result": "already_granted", "hearts": 100, "bonus_hearts": 50, "heart_balance": 150}'::jsonb,
  '같은 사람의 같은 토큰은 already_granted — 하트는 그대로');
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-00000000b0a1'),
  150, '재전송 뒤 A 잔액 150 그대로');
select is((select count(*)::int from public.purchases where token_hash = repeat('a', 64)), 1, '구매 행은 하나');
select is((select count(*)::int from public.heart_transactions where profile_id = '00000000-0000-0000-0000-00000000b0a1'),
  2, '원장은 두 줄 그대로');

-- 8. 같은 토큰을 다른 사람(B)이 -------------------------------------------------------------
select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a2', 'play_store', 'heart_100', repeat('a', 64),
                              'GPA.test-a', now() - interval '1 minute', false),
  '{"result": "token_used"}'::jsonb, '다른 사람이 이미 받은 토큰은 token_used');
select ok(not exists (select 1 from public.entitlements where profile_id = '00000000-0000-0000-0000-00000000b0a2'),
  'B 에게는 잔액 행도 생기지 않는다');

-- 9 · 20. A 두 번째 구매 heart_200(시험 결제) → 보너스 없음 · is_test 저장 -------------------------
select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a1', 'play_store', 'heart_200', repeat('b', 64),
                              null, now(), true),
  '{"result": "granted", "hearts": 200, "bonus_hearts": 0, "heart_balance": 350}'::jsonb,
  '두 번째 구매는 보너스 없이 200');
select is(
  (select count(*)::int from public.heart_transactions
    where profile_id = '00000000-0000-0000-0000-00000000b0a1' and reason = 'first_purchase_bonus'),
  1, 'first_purchase_bonus 원장은 여전히 한 줄');
select is((select is_test from public.purchases where token_hash = repeat('b', 64)), true, 'is_test 는 넘긴 값대로 저장된다');
select ok((select store_order_id is null and price_krw = 10800 from public.purchases where token_hash = repeat('b', 64)),
  '주문 번호가 없어도 저장된다 · heart_200 판매가 10800');

-- 10. C: heart_50 먼저 → 보너스 없음, 이어서 heart_100 → 이미 산 사람이라 보너스 없음(결정 I-6) ---------
select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a3', 'play_store', 'heart_50', repeat('e', 64),
                              'GPA.test-e', now(), false) ->> 'bonus_hearts',
  '0', '50하트 첫 구매에는 보너스가 없다');
select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a3', 'play_store', 'heart_100', repeat('f', 64),
                              'GPA.test-f', now(), false) ->> 'bonus_hearts',
  '0', '50하트를 먼저 산 사람의 100하트에도 보너스가 없다(구매 이력 0건일 때만)');

-- 11. 모르는 상품 -----------------------------------------------------------------------------
select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a1', 'play_store', 'heart_999', repeat('1', 64),
                              null, now(), false),
  '{"result": "unknown_product"}'::jsonb, '상품표에 없는 상품은 unknown_product');
select is((select count(*)::int from public.purchases where token_hash = repeat('1', 64)), 0, '모르는 상품은 행을 만들지 않는다');

-- 12. A 첫 구매 환불(잔액 충분) → 구매분 + 보너스 150 회수 ---------------------------------------
select is(
  public.refund_store_purchase('play_store', repeat('a', 64)),
  '{"result": "refunded", "profile_id": "00000000-0000-0000-0000-00000000b0a1", "clawed_back": 150, "shortfall": 0}'::jsonb,
  '잔액이 충분하면 구매분 + 보너스를 다 회수한다');
select ok(
  (select status = 'refunded' and refunded_at is not null and clawed_back_hearts = 150
     from public.purchases where token_hash = repeat('a', 64)),
  '구매 행: refunded · refunded_at · 회수량 150');
select ok(
  (select amount = -150 and ref_id = (select id from public.purchases where token_hash = repeat('a', 64))
     from public.heart_transactions
    where profile_id = '00000000-0000-0000-0000-00000000b0a1' and reason = 'refund'),
  '원장 refund -150, ref_id = 그 구매');

-- 13. 같은 환불 다시 -------------------------------------------------------------------------
select is(public.refund_store_purchase('play_store', repeat('a', 64)), '{"result": "already_refunded"}'::jsonb,
  '같은 환불은 already_refunded');
select is(
  (select count(*)::int from public.heart_transactions
    where profile_id = '00000000-0000-0000-0000-00000000b0a1' and reason = 'refund'),
  1, '원장 refund 는 한 줄 그대로');

-- 14. 쓴 뒤 환불: B 첫 구매 150 → 120 씀 → 잔액 30 에서 150 회수 -----------------------------------
select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a2', 'play_store', 'heart_100', repeat('c', 64),
                              'GPA.test-c', now(), false) ->> 'bonus_hearts',
  '50', 'B 첫 구매에도 보너스');
select public.grant_hearts('00000000-0000-0000-0000-00000000b0a2', -120, 'extra_card');
select is(
  public.refund_store_purchase('play_store', repeat('c', 64)),
  '{"result": "refunded", "profile_id": "00000000-0000-0000-0000-00000000b0a2", "clawed_back": 30, "shortfall": 120}'::jsonb,
  '이미 쓴 하트는 남은 만큼만 회수한다(결정 I-1) — 모자람 120');
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-00000000b0a2'),
  0, 'B 잔액 0 — 음수가 되지 않는다');
select is((select clawed_back_hearts from public.purchases where token_hash = repeat('c', 64)), 30, '구매 행 회수량 30');

-- 17. 첫 구매가 환불된 사람의 다음 heart_100 → 보너스 없음(환불된 기록도 센다) ------------------------
select is(
  public.grant_store_purchase('00000000-0000-0000-0000-00000000b0a2', 'play_store', 'heart_100', repeat('d', 64),
                              'GPA.test-d', now(), false),
  '{"result": "granted", "hearts": 100, "bonus_hearts": 0, "heart_balance": 100}'::jsonb,
  '첫 구매가 환불돼도 보너스는 다시 주지 않는다');

-- 15. 잔액 0 에서 환불: C 가 150 을 다 쓴 뒤 heart_50 환불 → 원장 줄 없음 ----------------------------
select public.grant_hearts('00000000-0000-0000-0000-00000000b0a3', -150, 'extra_card');
select is(
  public.refund_store_purchase('play_store', repeat('e', 64)),
  '{"result": "refunded", "profile_id": "00000000-0000-0000-0000-00000000b0a3", "clawed_back": 0, "shortfall": 50}'::jsonb,
  '잔액 0 이면 0 회수 · 모자람 50');
select is(
  (select count(*)::int from public.heart_transactions
    where profile_id = '00000000-0000-0000-0000-00000000b0a3' and reason = 'refund'),
  0, '0 회수는 원장 줄을 만들지 않는다(amount <> 0 제약 보호)');
select is((select status::text from public.purchases where token_hash = repeat('e', 64)), 'refunded', '그래도 행은 refunded');

-- 16. 모르는 토큰 환불 ------------------------------------------------------------------------
select is(public.refund_store_purchase('play_store', repeat('0', 64)), '{"result": "unknown"}'::jsonb,
  '지급한 적 없는 토큰(확인 전 자동 환불 등)은 unknown');
select is(public.refund_store_purchase('app_store', repeat('b', 64)), '{"result": "unknown"}'::jsonb,
  '같은 해시라도 스토어가 다르면 다른 구매다');

-- 21. 원장 합 = 잔액(ERD §6) ------------------------------------------------------------------
select is(
  (select sum(amount)::int from public.heart_transactions where profile_id = '00000000-0000-0000-0000-00000000b0a1'),
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-00000000b0a1'),
  'A 원장 합 = 잔액(100 + 50 + 200 − 150)');
select is(
  (select sum(amount)::int from public.heart_transactions where profile_id = '00000000-0000-0000-0000-00000000b0a2'),
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-00000000b0a2'),
  'B 원장 합 = 잔액');
select is(
  (select sum(amount)::int from public.heart_transactions where profile_id = '00000000-0000-0000-0000-00000000b0a3'),
  (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-00000000b0a3'),
  'C 원장 합 = 잔액');

reset role;

-- 19. RLS — 본인 구매만 읽기 ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000b0a1", "role": "authenticated"}';
select is((select count(*)::int from public.purchases), 2, 'A 는 자기 구매 두 건만 본다');
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000b0a2", "role": "authenticated"}';
select is(
  (select count(*)::int from public.purchases where profile_id = '00000000-0000-0000-0000-00000000b0a1'),
  0, 'B 는 A 의 구매를 못 본다');
set local role anon;
set local request.jwt.claims to '{"role": "anon"}';
select throws_ok($$select count(*) from public.purchases$$, '42501', null, 'anon 은 구매 기록을 읽을 권한 자체가 없다');
reset role;

-- 22. 제약 ----------------------------------------------------------------------------------
select throws_ok(
  $$update public.purchases set refunded_at = now() where token_hash = repeat('d', 64)$$,
  '23514', null, 'granted 인데 refunded_at 을 넣을 수 없다(purchases_refund_consistent)');
select throws_ok(
  $$insert into public.purchases (profile_id, store, product_id, token_hash, heart_amount, price_krw, purchased_at)
    values ('00000000-0000-0000-0000-00000000b0a1', 'play_store', 'heart_50', 'not-a-hash', 50, 3000, now())$$,
  '23514', null, '토큰 해시는 sha256 16진수 64자만(원문 토큰을 실수로 넣지 못한다)');
select throws_ok(
  $$insert into public.purchases (profile_id, store, product_id, token_hash, heart_amount, price_krw, purchased_at)
    values ('00000000-0000-0000-0000-00000000b0a2', 'play_store', 'heart_50', repeat('d', 64), 50, 3000, now())$$,
  '23505', null, '같은 스토어 · 같은 토큰 해시는 한 번뿐(purchases_token_once)');

-- 18. 계정 삭제 뒤 — 구매 행은 남고(5년 보관) 환불은 회수 없이 기록만 -------------------------------------
delete from auth.users where id = '00000000-0000-0000-0000-00000000b0a3';
select is(
  (select count(*)::int from public.purchases where token_hash in (repeat('e', 64), repeat('f', 64)) and profile_id is null),
  2, '계정이 지워져도 구매 행은 남고 profile_id 만 비워진다');

set local role service_role;
select is(
  public.refund_store_purchase('play_store', repeat('f', 64)),
  '{"result": "refunded", "profile_id": null, "clawed_back": 0, "shortfall": 0}'::jsonb,
  '지워진 계정의 구매 환불은 회수할 사람이 없어 0 · 모자람으로 세지 않는다');
select ok(
  (select status = 'refunded' and clawed_back_hearts = 0 from public.purchases where token_hash = repeat('f', 64)),
  '그 행은 refunded · 회수량 0');
reset role;

select * from finish();
rollback;
