-- 관리자 웹 대시보드 D3(설계 바탕화면 관리자_대시보드_설계_10-18.md §8-3 · §8-4b · §8-5) 검증:
-- 하트 조정 · 탈퇴 대행과 작업 기록을 한 번에 하는 함수 둘, 결제 읽기 함수 둘(30일 그래프 · 못 거둔 하트), 주문 번호 인덱스.
-- 마이그레이션 20261018120000_admin_users_billing(맨 앞 명단 확인 admin_assert 는 20261018035204),
-- 7절 환불이 잦은 계정은 20261019220000_admin_billing_returned_accounts.
-- 기대값 기준: docs/superpowers/plans/2026-10-18-admin-users-billing.md Task 1.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(70);

-- 준비 (postgres) -------------------------------------------------------------
-- AD = 관리자(…ad03), AD2 = 다른 관리자(…ad04). 둘 다 프로필이 있다(관리자 대상 CM404 가 "프로필 없음" 으로 통과하지 않게).
-- 사람: F1 = 잔액 10 인 active, F2 = 잔액 행 없는 active, F3 = 탈퇴, F4 = 탈퇴 대행할 active, F5 = 정지 중(탈퇴 대행),
-- F6 = 학교 메일 해시 없는 active(탈퇴 대행), F7 = 기록 실패 되돌림 확인용 active.
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000f', '테스트대학교F', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('testf.ac.kr', '00000000-0000-0000-0000-00000000000f');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'ub-1@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000f2', 'ub-2@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000f3', 'ub-3@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000f4', 'ub-4@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000f5', 'ub-5@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000f6', 'ub-6@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000f7', 'ub-7@testf.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-00000000000f' from auth.users
where id between '00000000-0000-0000-0000-0000000000f1' and '00000000-0000-0000-0000-0000000000f7'
on conflict (id) do nothing;

update public.profiles
   set gender = 'female', birth_year = 2003, height_cm = 165, nickname = '유저' || chr(96 + right(id::text, 1)::int)
 where id between '00000000-0000-0000-0000-0000000000f1' and '00000000-0000-0000-0000-0000000000f7';
update public.profiles set status = 'active'
 where id in ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2',
              '00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000f6',
              '00000000-0000-0000-0000-0000000000f7');
update public.profiles set status = 'suspended' where id = '00000000-0000-0000-0000-0000000000f5';
update public.profiles set status = 'withdrawn', withdrawn_at = now() where id = '00000000-0000-0000-0000-0000000000f3';

insert into public.entitlements (profile_id, heart_balance) values ('00000000-0000-0000-0000-0000000000f1', 10);

insert into auth.users (id, email, raw_app_meta_data) values
  ('00000000-0000-0000-0000-00000000ad03', 'operator-d3@example.com', '{"provider": "google", "providers": ["google"]}'),
  ('00000000-0000-0000-0000-00000000ad04', 'operator-d3b@example.com', '{"provider": "google", "providers": ["google"]}');
insert into public.profiles (id, university_id)
values ('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-00000000000f'),
       ('00000000-0000-0000-0000-00000000ad04', '00000000-0000-0000-0000-00000000000f')
on conflict (id) do nothing;
insert into public.admin_users (user_id) values
  ('00000000-0000-0000-0000-00000000ad03'), ('00000000-0000-0000-0000-00000000ad04');

-- 결제 준비. 그래프: 오늘 0:30(KST) 판매 · 어제 23:30(KST) 판매(UTC 로는 같은 날일 수 있어 자정 경계를 본다) ·
-- 오늘 시험 결제 · 오늘 환불(profile null). 못 거둔 하트: 40일 전 구매 여섯 건(아래 주석).
insert into public.purchases
  (profile_id, store, product_id, store_order_id, token_hash, heart_amount, bonus_hearts, price_krw, status, is_test,
   clawed_back_hearts, purchased_at, refunded_at)
select p, 'play_store', pid, 'GPA.' || n, repeat('0', 63) || n, h, b, price, st::public.purchase_status, t, c, at, ref
from (values
  ('00000000-0000-0000-0000-0000000000f1'::uuid, 'heart_50', '1', 50, 0, 3000, 'granted', false, null::integer,
   (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') + interval '30 minutes', null::timestamptz),
  ('00000000-0000-0000-0000-0000000000f1', 'heart_100', '2', 100, 0, 5700, 'granted', false, null,
   (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') - interval '30 minutes', null),
  ('00000000-0000-0000-0000-0000000000f1', 'heart_800', '3', 800, 50, 1000000, 'granted', true, null,
   (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') + interval '60 minutes', null),
  (null, 'heart_200', '4', 200, 0, 10800, 'refunded', false, 0,
   (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') + interval '90 minutes', now()),
  -- 못 거둔 하트: 5 = 부분 회수(지급 100 + 보너스 50 중 60 회수) · 6 = 전부 회수 · 7 = granted · 8 = 시험 환불 ·
  -- 9 = 계정이 지워진 환불 · a = 회수 null 인 환불(f2, 하루 전 환불)
  ('00000000-0000-0000-0000-0000000000f1', 'heart_100', '5', 100, 50, 5700, 'refunded', false, 60, now() - interval '40 days', now()),
  ('00000000-0000-0000-0000-0000000000f1', 'heart_50', '6', 50, 0, 3000, 'refunded', false, 50, now() - interval '40 days', now()),
  ('00000000-0000-0000-0000-0000000000f1', 'heart_50', '7', 50, 0, 3000, 'granted', false, null, now() - interval '40 days', null),
  ('00000000-0000-0000-0000-0000000000f1', 'heart_50', '8', 50, 0, 3000, 'refunded', true, 0, now() - interval '40 days', now()),
  (null, 'heart_50', '9', 50, 0, 3000, 'refunded', false, 0, now() - interval '40 days', now()),
  ('00000000-0000-0000-0000-0000000000f2', 'heart_50', 'a', 50, 0, 3000, 'refunded', false, null, now() - interval '40 days', now() - interval '1 day')
) as v(p, pid, n, h, b, price, st, t, c, at, ref);

-- service_role 로 돌리는 동안 호출 결과를 담아 두는 임시 표(함수 반환값 · 기록 id 를 나중에 대조한다).
create temp table cap (k text primary key, r jsonb);
grant all on cap to service_role;

-- 1. 함수 모양 · 권한 · 인덱스 (postgres) -----------------------------------------------
-- pg_proc 의 proname · proconfig 는 "C" 정렬 규칙이라 results_eq 의 행 비교와 섞이면 멈춘다 — 개수만 비교한다(D1 · D2 시험과 같음).
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_adjust_hearts', 'admin_close_account', 'admin_billing_daily', 'admin_billing_shortfall')
      and not p.prosecdef and p.proconfig = array['search_path=""']),
  4::bigint,
  '네 함수가 있고 모두 security invoker · search_path 빈 값이다(SUPABASE.md §5 — security definer 금지)'
);
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('admin_adjust_hearts', 'admin_close_account', 'admin_billing_daily', 'admin_billing_shortfall')
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')),
  4::bigint,
  'service_role 만 부를 수 있다 — anon · authenticated(그리고 public)는 실행 권한이 없다'
);
select has_index('public', 'purchases', 'purchases_store_order_id_index', '주문 번호 정확 일치 조회용 인덱스가 있다');

-- 2. 하트 조정 (service_role) ---------------------------------------------------------
-- FastAPI 와 같은 service_role 로 해야 표 권한이 모자란지 드러난다(postgres 는 무엇이든 통과한다).
set local role service_role;

insert into cap select 'adj1', public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03',
  '00000000-0000-0000-0000-0000000000f1', 50, '오류 보상', '203.0.113.9');

select results_eq(
  $$select (r->>'amount')::int, (r->>'heart_balance')::int from cap where k = 'adj1'$$,
  $$values (50, 60)$$,
  'adjust plus adds balance — 잔액 10 에 +50 이면 60 이라고 돌려준다'
);
select results_eq(
  $$select amount, reason::text, ref_id::text from public.heart_transactions
     where profile_id = '00000000-0000-0000-0000-0000000000f1' and reason = 'admin_adjust'$$,
  $$select 50, 'admin_adjust', r->>'action_id' from cap where k = 'adj1'$$,
  'adjust writes one ledger row — 원장 한 줄(admin_adjust)의 ref_id 가 작업 기록 id 와 이어진다'
);
select results_eq(
  $$select admin_user_id, action, target_type, target_id, before, after, reason, ip
      from public.admin_actions where id = (select (r->>'action_id')::uuid from cap where k = 'adj1')$$,
  $$values ('00000000-0000-0000-0000-00000000ad03'::uuid, 'hearts_adjust', 'profile',
            '00000000-0000-0000-0000-0000000000f1', '{"heart_balance": 10}'::jsonb,
            '{"heart_balance": 60, "amount": 50}'::jsonb, '오류 보상', '203.0.113.9'::inet)$$,
  'adjust writes one record — 누가 · 하트 조정 · 대상 · 전후 잔액 · 사유 · ip'
);
select is(
  (public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f2',
     20, '첫 지급', null))->>'heart_balance',
  '20', 'adjust creates the balance row when missing — 잔액 행이 없던 사람에게 +20 이면 20'
);
select is(
  (public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f1',
     -20, '잘못 지급 회수', null))->>'heart_balance',
  '40', 'minus within balance works — 잔액 60 에서 −20 이면 40'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f1',
      -50, '모자람', null)$$,
  'CM409', 'insufficient hearts', 'minus over balance raises CM409'
);
select results_eq(
  $$select (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000f1'),
           (select count(*) from public.heart_transactions where profile_id = '00000000-0000-0000-0000-0000000000f1'),
           (select count(*) from public.admin_actions
             where action = 'hearts_adjust' and target_id = '00000000-0000-0000-0000-0000000000f1')$$,
  $$values (40, 2::bigint, 2::bigint)$$,
  'minus over balance raises CM409 and changes nothing — 잔액 · 원장 · 기록이 그대로'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f1',
      0, '영', null)$$,
  '22023', null, '0 은 조정이 아니다 — 22023(서버 422)'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f1',
      null, '빈 값', null)$$,
  '22023', null, '하트 수가 비면 22023'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f1',
      1001, '상한 넘음', null)$$,
  '22023', null, '한 번 상한(1000)을 넘는 지급은 22023'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f1',
      -1001, '상한 넘음', null)$$,
  '22023', null, '한 번 상한(1000)을 넘는 회수도 22023'
);
select is(
  (public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f2',
     1000, '상한 딱', null))->>'heart_balance',
  '1020', '상한 +1000 은 통과한다(잔액 20 → 1020)'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f2',
      5, '   ', null)$$,
  '22023', null, '공백뿐인 사유는 22023'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f2',
      5, repeat('가', 501), null)$$,
  '23514', null, '사유 501자는 기록 check(23514)에 막힌다'
);
select results_eq(
  $$select (select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000f2'),
           (select count(*) from public.heart_transactions where profile_id = '00000000-0000-0000-0000-0000000000f2')$$,
  $$values (1020, 2::bigint)$$,
  '기록이 실패하면 지급도 없던 일이다 — 잔액 · 원장 그대로'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-00000000eeee',
      5, '없음', null)$$,
  'CM404', null, '없는 사람은 CM404(서버 404)'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-00000000ad03',
      5, '본인', null)$$,
  'CM404', null, 'admin target is CM404 — 관리자 본인'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-00000000ad04',
      5, '다른 관리자', null)$$,
  'CM404', null, 'admin target is CM404 — 다른 관리자'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f3',
      5, '탈퇴', null)$$,
  'CM409', 'profile withdrawn', '탈퇴 계정은 CM409(서버 409 account_withdrawn)'
);
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2',
      5, '비관리자', null)$$,
  '42501', null, '명단에 없는 p_admin 은 42501(서버 403 not_admin)'
);

-- 3. 탈퇴 대행 (service_role) ---------------------------------------------------------
insert into cap select 'close4', public.admin_close_account('00000000-0000-0000-0000-00000000ad03',
  '00000000-0000-0000-0000-0000000000f4', '\xdeadbeef'::bytea, 1::smallint, '본인 탈퇴 요청',
  '가입 메일로 답장 확인', '203.0.113.9');

select results_eq(
  $$select r->>'was_status', r->>'status', r->>'rejoin_blocked' from cap where k = 'close4'$$,
  $$values ('active', 'withdrawn', 'two_months')$$,
  'close active user blocks rejoin for two months — 반환값'
);
select results_eq(
  $$select status::text, withdrawn_at is not null from public.profiles where id = '00000000-0000-0000-0000-0000000000f4'$$,
  $$values ('withdrawn', true)$$,
  '탈퇴 처리됐다(상태 · withdrawn_at, 기존 withdraw_account 재사용)'
);
select ok(
  (select blocked_until between now() + interval '1 month 25 days' and now() + interval '2 months 5 days'
     from public.signup_blocks where email_hmac = '\xdeadbeef'::bytea),
  '재가입 제한이 약 2개월이다'
);
select results_eq(
  $$select action, target_type, before, after->>'rejoin_blocked', after->>'verified_by', reason, ip
      from public.admin_actions where target_id = '00000000-0000-0000-0000-0000000000f4'$$,
  $$values ('account_close', 'profile', '{"status": "active"}'::jsonb, 'two_months', '가입 메일로 답장 확인',
            '본인 탈퇴 요청', '203.0.113.9'::inet)$$,
  '작업 기록 한 줄 — 직전 상태 · 제한 종류 · 본인 확인 방법 · 사유 · ip'
);
select is(
  (public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f5',
     '\xbeef0001'::bytea, 1::smallint, '정지 중 탈퇴 요청', '로그인 방식 · 닉네임 확인', null))->>'rejoin_blocked',
  'forever', 'close suspended user blocks rejoin forever — 반환값'
);
select ok(
  (select blocked_until = 'infinity'::timestamptz from public.signup_blocks where email_hmac = '\xbeef0001'::bytea),
  '정지 중 탈퇴는 재가입 제한이 무기한이다'
);
select is(
  (public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f6',
     null, 1::smallint, '인증 전 계정 탈퇴 요청', '닉네임 확인', null))->>'rejoin_blocked',
  'none', 'close without email hash leaves no block — 반환값'
);
select results_eq(
  $$select status::text from public.profiles where id = '00000000-0000-0000-0000-0000000000f6'$$,
  $$values ('withdrawn')$$,
  '해시가 없어도 탈퇴는 된다(재가입 제한 줄은 만들지 않는다 — 위 두 해시 말고 늘지 않음)'
);
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f4',
      '\xdeadbeef'::bytea, 1::smallint, '다시', '다시 확인', null)$$,
  'CM409', 'profile withdrawn', 'close twice raises CM409 — 이미 탈퇴'
);
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-00000000eeee',
      null, 1::smallint, '없음', '확인', null)$$,
  'CM404', null, '없는 사람은 CM404'
);
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-00000000ad04',
      null, 1::smallint, '다른 관리자', '확인', null)$$,
  'CM404', null, 'admin target is CM404 — 다른 관리자를 탈퇴시키지 못한다'
);
select results_eq(
  $$select status::text from public.profiles where id = '00000000-0000-0000-0000-00000000ad04'$$,
  $$values ('pending')$$,
  '그 관리자 프로필은 그대로다'
);
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f7',
      null, 1::smallint, '   ', '확인', null)$$,
  '22023', null, '공백뿐인 사유는 22023'
);
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f7',
      null, 1::smallint, '사유', '   ', null)$$,
  '22023', null, '공백뿐인 본인 확인 방법은 22023'
);
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f7',
      null, 1::smallint, '사유', repeat('가', 201), null)$$,
  '22023', null, '본인 확인 방법 201자는 22023'
);
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f7',
      null, 1::smallint, '사유', '확인', null)$$,
  '42501', null, '명단에 없는 p_admin 은 42501'
);
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f7',
      '\xfeed0001'::bytea, 1::smallint, repeat('가', 501), '확인', null)$$,
  '23514', null, '사유 501자는 기록 check(23514)에 막힌다'
);
select results_eq(
  $$select (select status::text from public.profiles where id = '00000000-0000-0000-0000-0000000000f7'),
           (select count(*) from public.signup_blocks where email_hmac = '\xfeed0001'::bytea)$$,
  $$values ('active', 0::bigint)$$,
  '기록이 실패하면 탈퇴도 없던 일이다 — 상태 · 재가입 제한 그대로(기록이 마지막이라)'
);

-- 4. 결제 그래프 (service_role) --------------------------------------------------------
select is(
  (select count(*) from public.admin_billing_daily(3)),
  3::bigint, 'billing daily returns exactly p_days rows — 구매 없는 날도 줄이 있다'
);
select results_eq(
  $$select day, revenue_krw, order_count from public.admin_billing_daily(3) order by day$$,
  $$values ((now() at time zone 'Asia/Seoul')::date - 2, 0::bigint, 0),
           ((now() at time zone 'Asia/Seoul')::date - 1, 5700::bigint, 1),
           ((now() at time zone 'Asia/Seoul')::date, 3000::bigint, 1)$$,
  'billing daily buckets by kst midnight — 오늘 0:30(KST)은 오늘, 어제 23:30(KST)은 어제, 시험 결제 · 환불은 매출 아님'
);
select results_eq(
  $$select day, refunded_krw from public.admin_billing_daily(3) order by day$$,
  $$values ((now() at time zone 'Asia/Seoul')::date - 2, 0::bigint),
           ((now() at time zone 'Asia/Seoul')::date - 1, 0::bigint),
           ((now() at time zone 'Asia/Seoul')::date, 10800::bigint)$$,
  'billing daily excludes test and separates refunded — 환불 구매는 refunded_krw 에만(시험 결제 1,000,000 은 없음)'
);
select throws_ok($$select * from public.admin_billing_daily(0)$$, '22023', null, 'billing daily rejects 0');
select throws_ok($$select * from public.admin_billing_daily(91)$$, '22023', null, 'billing daily rejects 91');
select throws_ok($$select * from public.admin_billing_daily(null)$$, '22023', null, 'billing daily rejects null');

-- 5. 못 거둔 하트 (service_role) ---------------------------------------------------------
select results_eq(
  $$select nickname, store::text, product_id, heart_amount, bonus_hearts, clawed_back_hearts, granted_hearts, shortfall_hearts
      from public.admin_billing_shortfall(100)$$,
  $$values ('유저a', 'play_store', 'heart_100', 100, 50, 60, 150, 90),
           ('유저b', 'play_store', 'heart_50', 50, 0, null, 50, 50)$$,
  'shortfall lists only partially clawed back real refunds — 부분 회수(보너스 포함 150 중 60)와 회수 null 만, 최근 환불 순'
);
select is(
  (select count(*) from public.admin_billing_shortfall(1)),
  1::bigint, '한 줄만 달라고 하면 한 줄(p_limit)'
);
select throws_ok($$select * from public.admin_billing_shortfall(0)$$, '22023', null, 'shortfall rejects limit 0');
select throws_ok($$select * from public.admin_billing_shortfall(501)$$, '22023', null, 'shortfall rejects limit 501');

-- 6. 앱 역할은 못 부른다 ------------------------------------------------------------------
reset role;
set local role authenticated;
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f2', 5, '앱', null)$$,
  '42501', null, 'authenticated 는 admin_adjust_hearts 를 부를 수 없다');
select throws_ok(
  $$select public.admin_close_account('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f2',
      null, 1::smallint, '앱', '앱', null)$$,
  '42501', null, 'authenticated 는 admin_close_account 를 부를 수 없다');
select throws_ok($$select * from public.admin_billing_daily(3)$$, '42501', null, 'authenticated 는 admin_billing_daily 를 부를 수 없다');
select throws_ok($$select * from public.admin_billing_shortfall(10)$$, '42501', null, 'authenticated 는 admin_billing_shortfall 을 부를 수 없다');
reset role;
set local role anon;
select throws_ok(
  $$select public.admin_adjust_hearts('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000f2', 5, '앱', null)$$,
  '42501', null, 'anon 은 admin_adjust_hearts 를 부를 수 없다');
reset role;

-- 7. 환불이 잦은 계정 admin_billing_returned_accounts (마이그레이션 20261019220000) ----------------------------
-- 위 시험들이 끝난 뒤에 구매를 더한다(그래프 · 못 거둔 하트 시험의 기대값을 흔들지 않게). 이미 있는 환불: F1 = '5'(150 중 60) · '6'(50 중 50),
-- F2 = 'a'(50, 회수 null), 그리고 빼야 할 것 — '8' 시험 환불 · '4' · '9' 계정이 지워진 환불(profile_id null).
-- 새 사람: G(…f8) = 50 · 100(+보너스 50) · 800하트를 각각 환불(전부 회수 50 / 일부 60 / 하나도 0) + 시험 환불 + 환불 안 된 구매,
-- H(…f9) = 50하트 두 건 환불(하나도 못 거둠) — 건수가 F1 과 같아 못 거둔 하트로 순서가 갈린다.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f8', 'ub-8@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000f9', 'ub-9@testf.ac.kr');
insert into public.profiles (id, university_id)
values ('00000000-0000-0000-0000-0000000000f8', '00000000-0000-0000-0000-00000000000f'),
       ('00000000-0000-0000-0000-0000000000f9', '00000000-0000-0000-0000-00000000000f')
on conflict (id) do nothing;
update public.profiles set nickname = '환불셋' where id = '00000000-0000-0000-0000-0000000000f8';
update public.profiles set nickname = '환불둘' where id = '00000000-0000-0000-0000-0000000000f9';

insert into public.purchases
  (profile_id, store, product_id, store_order_id, token_hash, heart_amount, bonus_hearts, price_krw, status, is_test,
   clawed_back_hearts, purchased_at, refunded_at)
select p, 'play_store', pid, 'GPA.r' || n, repeat('2', 62) || n, h, b, price, st::public.purchase_status, t, c,
       now() - interval '10 days', ref
from (values
  ('00000000-0000-0000-0000-0000000000f8'::uuid, 'heart_50', '01', 50, 0, 3000, 'refunded', false, 50, now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000000f8', 'heart_100', '02', 100, 50, 5700, 'refunded', false, 60, now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000000f8', 'heart_800', '03', 800, 0, 38400, 'refunded', false, 0, now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000f8', 'heart_200', '04', 200, 0, 10800, 'refunded', true, 0, now()),
  ('00000000-0000-0000-0000-0000000000f8', 'heart_400', '05', 400, 0, 20400, 'granted', false, null::integer, null::timestamptz),
  ('00000000-0000-0000-0000-0000000000f9', 'heart_50', '06', 50, 0, 3000, 'refunded', false, 0, now() - interval '5 days'),
  ('00000000-0000-0000-0000-0000000000f9', 'heart_50', '07', 50, 0, 3000, 'refunded', false, 0, now() - interval '5 days')
) as v(p, pid, n, h, b, price, st, t, c, ref);

select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = 'admin_billing_returned_accounts'
      and not p.prosecdef and p.proconfig = array['search_path=""']),
  1::bigint, 'returned accounts 함수가 있고 security invoker · search_path 빈 값이다'
);
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = 'admin_billing_returned_accounts'
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')),
  1::bigint, 'returned accounts 는 service_role 만 부를 수 있다'
);

set local role service_role;
select results_eq(
  $$select nickname, refund_count, refunded_krw, granted_hearts, clawed_back_hearts, shortfall_hearts
      from public.admin_billing_returned_accounts(100)$$,
  $$values ('환불셋', 3, 47100::bigint, 1000, 110, 890),
           ('환불둘', 2, 6000::bigint, 100, 0, 100),
           ('유저a', 2, 8700::bigint, 200, 110, 90),
           ('유저b', 1, 3000::bigint, 50, 0, 50)$$,
  'returned accounts groups real refunds per account — 50 · 100(+50) · 800 환불은 건수 3 · 3000+5700+38400원 · 지급 1000 · 회수 50+60+0 · 못 거둠 890, '
  || '건수 많은 순 → 같으면 못 거둔 하트 많은 순, 회수 null 은 0, 시험 환불 · 환불 안 된 구매는 세지 않는다'
);
select is(
  (select last_refunded_at from public.admin_billing_returned_accounts(100) where nickname = '환불셋'),
  now() - interval '1 day', '마지막 환불 시각은 실제 환불 중 가장 늦은 것(오늘 시험 환불이 아니다)'
);
select is(
  (select count(*) from public.admin_billing_returned_accounts(100) where profile_id is null),
  0::bigint, 'returned accounts excludes deleted accounts — 계정이 지워진 환불(주문 4 · 9)은 줄이 없다'
);
select results_eq(
  $$select nickname from public.admin_billing_returned_accounts(1)$$,
  $$values ('환불셋'::text)$$,
  'returned accounts p_limit 1 이면 맨 앞 한 줄'
);
select is((select count(*) from public.admin_billing_returned_accounts(500)), 4::bigint, 'returned accounts p_limit 500(상한)은 통과');
select throws_ok($$select * from public.admin_billing_returned_accounts(0)$$, '22023', null, 'returned accounts rejects limit 0');
select throws_ok($$select * from public.admin_billing_returned_accounts(501)$$, '22023', null, 'returned accounts rejects limit 501');
select throws_ok($$select * from public.admin_billing_returned_accounts(null)$$, '22023', null, 'returned accounts rejects null limit');
reset role;

-- 7-1. 정렬 키가 서로 반대인 계정 · 3키 · 탈퇴 상태(프로필은 남음). 위 기대값을 흔들지 않게 여기서 더한다.
-- J(…fa) = 1건 환불에 못 거둠 800 → 2건(못 거둠 90 · 100)보다 뒤, 1건 못 거둠 50 보다 앞(건수가 1키, 못 거둔 하트는 2키).
-- K(…fb) · L(…fc) = 유저b 와 똑같이 1건 · 못 거둠 50, 마지막 환불만 다름(유저b 1일 전 → K 7일 전 → L 8일 전, 3키 최근 순).
-- 유저c(…f3, 탈퇴 상태 · 프로필 남음) = 100하트 1건 환불 중 70 회수 → 목록에 나온다(대장 결정 A: 탈퇴 상태도 포함).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000fa', 'ub-10@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000fb', 'ub-11@testf.ac.kr'),
  ('00000000-0000-0000-0000-0000000000fc', 'ub-12@testf.ac.kr');
insert into public.profiles (id, university_id)
values ('00000000-0000-0000-0000-0000000000fa', '00000000-0000-0000-0000-00000000000f'),
       ('00000000-0000-0000-0000-0000000000fb', '00000000-0000-0000-0000-00000000000f'),
       ('00000000-0000-0000-0000-0000000000fc', '00000000-0000-0000-0000-00000000000f')
on conflict (id) do nothing;
update public.profiles set nickname = '환불큼' where id = '00000000-0000-0000-0000-0000000000fa';
update public.profiles set nickname = '최근환불' where id = '00000000-0000-0000-0000-0000000000fb';
update public.profiles set nickname = '예전환불' where id = '00000000-0000-0000-0000-0000000000fc';

insert into public.purchases
  (profile_id, store, product_id, store_order_id, token_hash, heart_amount, bonus_hearts, price_krw, status, is_test,
   clawed_back_hearts, purchased_at, refunded_at)
select p, 'play_store', pid, 'GPA.r' || n, repeat('2', 62) || n, h, 0, price, 'refunded'::public.purchase_status, false, c,
       now() - interval '10 days', ref
from (values
  ('00000000-0000-0000-0000-0000000000fa'::uuid, 'heart_800', '08', 800, 38400, 0, now() - interval '6 days'),
  ('00000000-0000-0000-0000-0000000000fb', 'heart_50', '09', 50, 3000, 0, now() - interval '7 days'),
  ('00000000-0000-0000-0000-0000000000fc', 'heart_50', '0a', 50, 3000, 0, now() - interval '8 days'),
  ('00000000-0000-0000-0000-0000000000f3', 'heart_100', '0b', 100, 5700, 70, now() - interval '2 days')
) as v(p, pid, n, h, price, c, ref);

set local role service_role;
select results_eq(
  $$select nickname, refund_count, refunded_krw, granted_hearts, clawed_back_hearts, shortfall_hearts
      from public.admin_billing_returned_accounts(100)$$,
  $$values ('환불셋', 3, 47100::bigint, 1000, 110, 890),
           ('환불둘', 2, 6000::bigint, 100, 0, 100),
           ('유저a', 2, 8700::bigint, 200, 110, 90),
           ('환불큼', 1, 38400::bigint, 800, 0, 800),
           ('유저b', 1, 3000::bigint, 50, 0, 50),
           ('최근환불', 1, 3000::bigint, 50, 0, 50),
           ('예전환불', 1, 3000::bigint, 50, 0, 50),
           ('유저c', 1, 5700::bigint, 100, 70, 30)$$,
  'returned accounts order — 건수(1키)가 못 거둔 하트(2키)를 이긴다: 1건 · 800 은 2건 · 90 뒤, 1건 · 50 앞. '
  || '건수 · 못 거둔 하트가 같으면 마지막 환불 최근 순(3키)'
);
select results_eq(
  $$select r.refund_count, r.shortfall_hearts, pr.status::text
      from public.admin_billing_returned_accounts(100) r
      join public.profiles pr on pr.id = r.profile_id
     where r.profile_id = '00000000-0000-0000-0000-0000000000f3'$$,
  $$values (1, 30, 'withdrawn')$$,
  'returned accounts includes withdrawn-status profiles — 탈퇴 상태라도 프로필이 남아 있으면 목록에 나온다'
);
reset role;
set local role authenticated;
select throws_ok($$select * from public.admin_billing_returned_accounts(10)$$, '42501', null,
  'authenticated 는 admin_billing_returned_accounts 를 부를 수 없다');
reset role;
set local role anon;
select throws_ok($$select * from public.admin_billing_returned_accounts(10)$$, '42501', null,
  'anon 은 admin_billing_returned_accounts 를 부를 수 없다');
reset role;

select * from finish();
rollback;
