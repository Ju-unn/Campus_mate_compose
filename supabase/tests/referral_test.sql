-- 추천 코드(화면 20): profiles.referral_code · referrals 표 · redeem_referral 함수 검증.
-- 기대값 기준: docs/superpowers/plans/2026-09-28-referral.md Task C1 · 통합대장 결정 D3~D6.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

-- 준비 --------------------------------------------------------------------
-- A = ...c1(추천인), B = ...c2(입력하는 사람), C = ...c3(A 와 같은 번호), D = ...c4(B 와 같은 번호, 다른 계정),
-- W = ...c5(탈퇴), S = ...c6(정지)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-0000000000c0', '테스트대학교C', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('testc.ac.kr', '00000000-0000-0000-0000-0000000000c0');

-- on_auth_user_created 트리거가 pending 행을 만든다 — referral_code 는 이때 기본값으로 붙는다.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'rc-a@testc.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c2', 'rc-b@testc.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c3', 'rc-c@testc.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c4', 'rc-d@testc.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c5', 'rc-w@testc.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c6', 'rc-s@testc.ac.kr');

-- A · C 는 같은 번호(\x01), B · D 도 같은 번호(\x02), W · S 는 서로 다른 번호.
insert into public.profile_private (profile_id, phone_hmac) values
  ('00000000-0000-0000-0000-0000000000c1', '\x01'::bytea),
  ('00000000-0000-0000-0000-0000000000c2', '\x02'::bytea),
  ('00000000-0000-0000-0000-0000000000c3', '\x01'::bytea),
  ('00000000-0000-0000-0000-0000000000c4', '\x02'::bytea),
  ('00000000-0000-0000-0000-0000000000c5', '\x05'::bytea),
  ('00000000-0000-0000-0000-0000000000c6', '\x06'::bytea);

-- 1. 코드 칸 ------------------------------------------------------------------
-- 고정하기 전에 본다: 가입 트리거가 넣은 행에 기본값이 붙었는가.
select matches(
  (select referral_code from public.profiles where id = '00000000-0000-0000-0000-0000000000c2'),
  '^[A-HJ-NP-Z2-9]{6}$',
  '가입하면 코드가 기본값으로 생긴다'
);
select is(
  (select count(distinct referral_code)::int from public.profiles where id::text like '%0000000000c_'),
  6,
  '행마다 다른 코드가 붙는다(기본값이 행마다 돈다)'
);
select is_empty($$ select 1 from public.profiles where referral_code is null $$, '빈 코드가 없다');

update public.profiles set referral_code = 'AAAAAA' where id = '00000000-0000-0000-0000-0000000000c1';
update public.profiles set referral_code = 'WWWWWW', status = 'withdrawn', withdrawn_at = now()
where id = '00000000-0000-0000-0000-0000000000c5';
update public.profiles set referral_code = 'SSSSSS', status = 'suspended'
where id = '00000000-0000-0000-0000-0000000000c6';

select throws_ok(
  $$ update public.profiles set referral_code = 'AAAA0A' where id = '00000000-0000-0000-0000-0000000000c2' $$,
  '23514', null, '0 이 든 코드는 check 에 걸린다'
);
select throws_ok(
  $$ update public.profiles set referral_code = 'AAAAAA' where id = '00000000-0000-0000-0000-0000000000c2' $$,
  '23505', null, '코드는 유니크다'
);

-- 2. 거절 --------------------------------------------------------------------
select throws_ok($$ select public.redeem_referral('00000000-0000-0000-0000-0000000000c2', 'ZZZZZZ') $$,
  'CM404', null, '없는 코드');
select throws_ok($$ select public.redeem_referral('00000000-0000-0000-0000-0000000000c2', 'WWWWWW') $$,
  'CM404', null, '탈퇴자 코드는 없는 코드');
select throws_ok($$ select public.redeem_referral('00000000-0000-0000-0000-0000000000c2', 'SSSSSS') $$,
  'CM404', null, '정지된 사람 코드는 없는 코드');
select throws_ok($$ select public.redeem_referral('00000000-0000-0000-0000-0000000000c1', 'AAAAAA') $$,
  'CM422', null, '자기 코드');
select throws_ok($$ select public.redeem_referral('00000000-0000-0000-0000-0000000000c3', 'AAAAAA') $$,
  'CM422', null, '추천인과 같은 번호');

-- 3. 성공 · 지급 --------------------------------------------------------------
select is(
  public.redeem_referral('00000000-0000-0000-0000-0000000000c2', '  aaaaaa '),
  '00000000-0000-0000-0000-0000000000c1'::uuid,
  '공백 · 소문자도 받고 추천인 id 를 돌려준다'
);
select is(
  (select count(*)::int from public.heart_transactions
    where reason = 'referral' and amount = 50 and ref_id = '00000000-0000-0000-0000-0000000000c2'),
  2, '양쪽 한 줄씩(50, ref_id = 입력한 사람)'
);
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000c1'),
  50, '추천인 50');
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-0000000000c2'),
  50, '입력한 사람 50');
select isnt((select rewarded_at from public.referrals where referee_id = '00000000-0000-0000-0000-0000000000c2'),
  null, '보상 시각이 찍힌다');

-- 4. 두 번째 입력 · 같은 번호 --------------------------------------------------
select throws_ok($$ select public.redeem_referral('00000000-0000-0000-0000-0000000000c2', 'AAAAAA') $$,
  '23505', null, '두 번째 입력은 PK 충돌');
select is(
  (select count(*)::int from public.heart_transactions
    where reason = 'referral' and ref_id::text like '%0000000000c_'),
  2, '하트는 그대로'
);
select throws_ok($$ select public.redeem_referral('00000000-0000-0000-0000-0000000000c4', 'AAAAAA') $$,
  'CM422', null, '이 번호로 이미 다른 계정이 보상을 받았다');

-- phone_hmac 이 빈 옛 계정은 비교하지 않고 통과(D4)
update public.profile_private set phone_hmac = null where profile_id = '00000000-0000-0000-0000-0000000000c3';
select is(
  public.redeem_referral('00000000-0000-0000-0000-0000000000c3', 'AAAAAA'),
  '00000000-0000-0000-0000-0000000000c1'::uuid,
  '번호 해시가 빈 계정은 통과'
);

-- 5. 권한 · 잠금 ---------------------------------------------------------------
select is_empty(
  $$ select 1 from information_schema.role_table_grants
      where table_schema = 'public' and table_name = 'referrals' and grantee in ('anon', 'authenticated') $$,
  'referrals 는 클라이언트 권한 0'
);
select policies_are('public', 'referrals', array[]::name[], 'referrals 에는 정책이 없다');
select ok(not has_function_privilege('authenticated', 'public.redeem_referral(uuid, text)', 'execute'),
  'redeem 은 service_role 만');
select ok(not has_function_privilege('authenticated', 'public.generate_referral_code()', 'execute'),
  '코드 생성 함수는 앱 역할이 부르지 못한다');
select ok(pg_get_functiondef('public.redeem_referral(uuid, text)'::regprocedure) ~ 'pg_advisory_xact_lock',
  '같은 번호 동시 입력을 막는 잠금 줄이 있다');

select * from finish();
rollback;
