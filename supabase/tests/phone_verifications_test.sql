-- 휴대폰 문자 인증(phone_verifications) 검증: 권한(default deny) · 보내기 한도 · 최신 번호만 · 5번 잠금 ·
-- 확인된 번호는 활동 계정 하나에만 · 탈퇴 계정은 번호를 놓아준다 · 프로필 삭제 cascade.
-- 마이그레이션 20261111010000_create_phone_verifications. 로컬 스택에서 `supabase test db` 로 돌린다.
-- 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
-- 시각: 함수는 clock_timestamp() 로 센다. 시간이 흐른 것은 행의 시각을 뒤로 옮겨 흉내 낸다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(53);

-- 준비 (postgres) -------------------------------------------------------------
-- A = …d1(인증하는 사람), B = …d2(다른 계정, 인증한 번호 \xb1), W = …d3(탈퇴, 인증한 번호 \xc3), C = …d4(계정 한도 · 삭제),
-- E = …d5(옛 앱이 인증 없이 저장한 번호 \xb5)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-0000000000d0', '문자시험대학교', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('sms.ac.kr', '00000000-0000-0000-0000-0000000000d0');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'pv-a@sms.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d2', 'pv-b@sms.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d3', 'pv-w@sms.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d4', 'pv-c@sms.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d5', 'pv-e@sms.ac.kr');

insert into public.profile_private (profile_id, phone_hmac, phone_verified_at) values
  ('00000000-0000-0000-0000-0000000000d1', '\xa9'::bytea, null),
  ('00000000-0000-0000-0000-0000000000d2', '\xb1'::bytea, now()),
  ('00000000-0000-0000-0000-0000000000d3', '\xc3'::bytea, now()),
  ('00000000-0000-0000-0000-0000000000d4', null, null),
  ('00000000-0000-0000-0000-0000000000d5', '\xb5'::bytea, null);

select public.withdraw_account('00000000-0000-0000-0000-0000000000d3', null, 1::smallint);

-- 짧게 부르는 도우미. 인증번호 해시는 \xc0de 로 고정한다.
create function pg_temp.issue(p_profile uuid, p_hmac bytea, p_limit integer default 300)
returns table (result text, verification_id uuid, retry_after_seconds integer, expires_in_seconds integer,
               global_limit_reached boolean)
language sql as $$
  select * from public.issue_phone_verification(p_profile, p_hmac, 1::smallint, '\xc0de'::bytea, p_limit)
$$;
create function pg_temp.attempt(p_profile uuid, p_hmac bytea)
returns table (result text, verification_id uuid, code_hash bytea, attempts_left integer)
language sql as $$
  select * from public.attempt_phone_verification(p_profile, p_hmac, 1::smallint)
$$;
create function pg_temp.save(p_profile uuid, p_hmac bytea)
returns text
language sql as $$
  select public.save_verified_phone_number(p_profile, '+821055556666', 'phone-key', p_hmac, 1::smallint)
$$;
-- 오늘(한국 시간) 0시.
create function pg_temp.day_start() returns timestamptz
language sql as $$ select date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' $$;
-- 문자를 보낸 줄을 바로 넣는다(한도 채우기). 1분보다 오래된 줄이라 재전송 대기에는 걸리지 않는다.
create function pg_temp.sent(p_profile uuid, p_hmac bytea, p_at timestamptz) returns void
language sql as $$
  insert into public.phone_verifications (profile_id, phone_hmac, phone_hmac_key_version, code_hash, sent_at, expires_at)
  values (p_profile, p_hmac, 1, '\xc0de', p_at, p_at + interval '3 minutes')
$$;

-- 1. 모양 · RLS · 권한 ------------------------------------------------------------
select is(
  (select relrowsecurity from pg_class where oid = 'public.phone_verifications'::regclass),
  true, 'phone_verifications 는 RLS 가 켜져 있다'
);                                                                                                   -- 1
select is(
  (select count(*) from pg_policies where tablename = 'phone_verifications'),
  0::bigint, 'phone_verifications 에는 정책이 하나도 없다(FastAPI 전용)'
);                                                                                                   -- 2
select is(
  (select confdeltype::text from pg_constraint
    where conrelid = 'public.phone_verifications'::regclass and contype = 'f'),
  'c', 'profile_id FK 는 on delete cascade 다'
);                                                                                                   -- 3
select is(
  (select count(*) from pg_indexes
    where tablename = 'phone_verifications'
      and indexname in ('phone_verifications_phone_hmac_sent_at_index',
                        'phone_verifications_profile_id_sent_at_index',
                        'phone_verifications_sent_at_index')),
  3::bigint, '번호별 · 계정별 · 전체 하루 수를 세는 인덱스 세 개가 있다'
);                                                                                                   -- 4
select is(
  (select indexdef ~ 'WHERE \(phone_verified_at IS NOT NULL\)' from pg_indexes
    where indexname = 'profile_private_verified_phone_hmac_index'),
  true, '인증한 번호만 담는 profile_private(phone_hmac) 부분 인덱스가 있다(유일 제약은 아니다)'
);                                                                                                   -- 4-1

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000d1", "role": "authenticated"}';
select throws_ok(
  $$select id from public.phone_verifications$$,
  '42501', null, 'authenticated 는 phone_verifications 를 select 할 수 없다(42501)'
);                                                                                                   -- 5
set local role anon;
select throws_ok(
  $$select id from public.phone_verifications$$,
  '42501', null, 'anon 은 phone_verifications 를 select 할 수 없다(42501)'
);                                                                                                   -- 6
reset role;

select ok(
  has_table_privilege('service_role', 'public.phone_verifications', 'select, insert, update, delete')
  and not has_table_privilege('authenticated', 'public.phone_verifications', 'select, insert, update, delete')
  and not has_table_privilege('anon', 'public.phone_verifications', 'select, insert, update, delete'),
  'service_role 만 phone_verifications 를 읽고 쓴다'
);                                                                                                   -- 7
select ok(
  (select bool_and(has_function_privilege('service_role', f, 'execute')
                   and not has_function_privilege('authenticated', f, 'execute')
                   and not has_function_privilege('anon', f, 'execute'))
     from unnest(array[
       'public.issue_phone_verification(uuid, bytea, smallint, bytea, integer)',
       'public.attempt_phone_verification(uuid, bytea, smallint)',
       'public.save_verified_phone_number(uuid, text, text, bytea, smallint)',
       'public.check_verified_phone_number(uuid, bytea, smallint)']) f),
  '네 함수는 service_role 만 부른다'
);                                                                                                   -- 8

-- 2. 보내기 --------------------------------------------------------------------
select results_eq(
  $$select result, retry_after_seconds, expires_in_seconds, global_limit_reached
      from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xa1')$$,
  $$values ('issued'::text, 60, 180, false)$$,
  '처음 보내면 issued · 다시 받기 60초 · 유효 180초'
);                                                                                                   -- 9
select results_eq(
  $$select result, verification_id, retry_after_seconds between 1 and 60
      from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xa1')$$,
  $$select 'already_sent'::text, id, true from public.phone_verifications where phone_hmac = '\xa1'$$,
  '같은 계정 · 같은 번호를 1분 안에 또 보내면 already_sent + 남은 초, 처음 줄을 가리킨다'
);                                                                                                   -- 10
select is(
  (select count(*) from public.phone_verifications where phone_hmac = '\xa1'),
  1::bigint, 'already_sent 는 줄을 만들지 않는다(문자 없음)'
);                                                                                                   -- 11
select results_eq(
  $$select result, verification_id is null, retry_after_seconds between 1 and 60
      from pg_temp.issue('00000000-0000-0000-0000-0000000000d2', '\xa1')$$,
  $$values ('number_cooldown'::text, true, true)$$,
  '다른 계정이라도 같은 번호는 1분에 한 번이다(number_cooldown)'
);                                                                                                   -- 12

update public.phone_verifications set sent_at = sent_at - interval '61 seconds' where phone_hmac = '\xa1';
select is(
  (select result from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xa1')),
  'issued', '1분이 지나면 다시 보낸다(줄 수는 19번에서 본다)'
);                                                                                                   -- 13

select pg_temp.sent('00000000-0000-0000-0000-0000000000d2', '\xa2', pg_temp.day_start() + make_interval(secs => n))
  from generate_series(1, 5) n;
select results_eq(
  $$select result, retry_after_seconds = ceil(extract(epoch from pg_temp.day_start() + interval '1 day' - clock_timestamp()))::int
               or retry_after_seconds = ceil(extract(epoch from pg_temp.day_start() + interval '1 day' - clock_timestamp()))::int + 1
      from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xa2')$$,
  $$values ('number_daily_limit'::text, true)$$,
  '같은 번호는 하루(한국 시간) 5번까지 — 남은 초는 자정까지다'
);                                                                                                   -- 14

select pg_temp.sent('00000000-0000-0000-0000-0000000000d2', '\xa3', pg_temp.day_start() - make_interval(mins => n))
  from generate_series(1, 5) n;
select is(
  (select result from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xa3')),
  'issued', '어제(한국 시간) 보낸 줄은 오늘 한도에 세지 않는다'
);                                                                                                   -- 15

select pg_temp.sent('00000000-0000-0000-0000-0000000000d4', decode(lpad(to_hex(n), 2, '0'), 'hex'),
                    pg_temp.day_start() + make_interval(secs => n))
  from generate_series(16, 25) n;
select results_eq(
  $$select result, retry_after_seconds > 0
      from pg_temp.issue('00000000-0000-0000-0000-0000000000d4', '\xa4')$$,
  $$values ('account_daily_limit'::text, true)$$,
  '한 계정은 하루 10번까지(번호가 달라도)'
);                                                                                                   -- 16

select results_eq(
  $$select result, retry_after_seconds > 0
      from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xa5',
                         (select count(*)::int from public.phone_verifications
                           where code_hash is not null and sent_at >= pg_temp.day_start()))$$,
  $$values ('global_daily_limit'::text, true)$$,
  '하루 전체 한도에 닿으면 global_daily_limit'
);                                                                                                   -- 17
select results_eq(
  $$select result, global_limit_reached
      from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xa5',
                         (select count(*)::int + 1 from public.phone_verifications
                           where code_hash is not null and sent_at >= pg_temp.day_start()))$$,
  $$values ('issued'::text, true)$$,
  '마지막 한 통을 쓴 보내기는 global_limit_reached = true(디스코드 알림 한 번)'
);                                                                                                   -- 18
select is(
  (select count(*) from public.phone_verifications where phone_hmac = '\xa1'),
  2::bigint, '1분 뒤 다시 보낸 줄이 새로 생겼다'
);                                                                                                   -- 19

-- 다른 활동 계정(B)이 저장한 번호 \xb1
select results_eq(
  $$select result, verification_id is null from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xb1')$$,
  $$values ('in_use'::text, true)$$,
  '다른 활동 계정이 쓰는 번호면 in_use — 문자를 보내지 않는다'
);                                                                                                   -- 20
select results_eq(
  $$select code_hash is null, profile_id from public.phone_verifications where phone_hmac = '\xb1'$$,
  $$values (true, '00000000-0000-0000-0000-0000000000d1'::uuid)$$,
  'in_use 시도는 인증번호 없는 줄로 남아 계정 하루 한도에만 센다(번호 떠보기 막기)'
);                                                                                                   -- 21
select is(
  (select result from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xc3')),
  'issued', '탈퇴한 계정이 쓰던 번호는 다시 인증할 수 있다'
);                                                                                                   -- 22
select is(
  (select result from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xa9')),
  'issued', '내가 이미 저장한 번호는 in_use 가 아니다'
);                                                                                                   -- 23
select is(
  (select result from pg_temp.issue('00000000-0000-0000-0000-0000000000d1', '\xb5')),
  'issued', '다른 계정이 인증 없이 저장한 번호(옛 앱 · 오타)는 막지 않는다 — 진짜 주인이 인증할 수 있다'
);                                                                                                   -- 23-1

-- 3. 확인 -----------------------------------------------------------------------
select results_eq(
  $$select result, verification_id is null from pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xee')$$,
  $$values ('expired'::text, true)$$,
  '보낸 적 없는 번호는 expired(인증번호를 다시 받는다)'
);                                                                                                   -- 24
select results_eq(
  $$select result, code_hash, attempts_left from pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xa1')$$,
  $$values ('check'::text, '\xc0de'::bytea, 4)$$,
  '확인 한 번은 시도 한 칸을 먼저 쓰고 해시를 준다(비교는 FastAPI 가 compare_digest 로)'
);                                                                                                   -- 25
select is(
  (select verification_id from pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xa1')),
  (select id from public.phone_verifications where phone_hmac = '\xa1' order by sent_at desc limit 1),
  '가장 최근에 보낸 번호만 확인한다(새로 보내면 옛 번호는 못 쓴다)'
);                                                                                                   -- 26
select pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xa1') from generate_series(1, 3);
select results_eq(
  $$select result, attempts_left from pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xa1')$$,
  $$values ('locked'::text, 0)$$,
  '5번 쓰면 잠긴다 — 인증번호를 새로 받아야 한다'
);                                                                                                   -- 27
select is(
  (select attempts from public.phone_verifications where phone_hmac = '\xa1' order by sent_at desc limit 1),
  5::smallint, '잠긴 뒤의 시도는 더 세지 않는다'
);                                                                                                   -- 28

update public.phone_verifications set expires_at = clock_timestamp() - interval '1 second' where phone_hmac = '\xc3';
select is(
  (select result from pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xc3')),
  'expired', '3분이 지나면 expired'
);                                                                                                   -- 29

update public.phone_verifications set verified_at = clock_timestamp() where phone_hmac = '\xa3';
select is(
  (select result from pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xa3')),
  'verified', '이미 맞힌 번호를 다시 확인하면 verified(두 번 눌러도 같다)'
);                                                                                                   -- 30

-- 4. 기본 정보 저장 ----------------------------------------------------------------
-- 미리 보기(check): 저장 전에 FastAPI 가 부른다. 아무것도 바꾸지 않는다.
select is(
  public.check_verified_phone_number('00000000-0000-0000-0000-0000000000d1', '\xa5', 1::smallint),
  'not_verified', 'check: 인증하지 않은 번호는 not_verified'
);                                                                                                   -- 30-1
select results_eq(
  $$select public.check_verified_phone_number('00000000-0000-0000-0000-0000000000d1', '\xa3', 1::smallint),
           (select used_at is null from public.phone_verifications
             where profile_id = '00000000-0000-0000-0000-0000000000d1' and phone_hmac = '\xa3')$$,
  $$values ('ok'::text, true)$$,
  'check: 30분 안에 인증한 번호는 ok — 인증을 쓰지는 않는다'
);                                                                                                   -- 30-2
select is(
  public.check_verified_phone_number('00000000-0000-0000-0000-0000000000d1', '\xb1', 1::smallint),
  'in_use', 'check: 다른 활동 계정이 인증한 번호는 in_use'
);                                                                                                   -- 30-3

select is(
  pg_temp.save('00000000-0000-0000-0000-0000000000d1', '\xa5'),
  'not_verified', '인증하지 않은 번호는 저장하지 않는다'
);                                                                                                   -- 31
select is(
  (select phone_hmac from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000d1'),
  '\xa9'::bytea, 'not_verified 면 저장된 번호가 그대로다'
);                                                                                                   -- 32
select is(
  pg_temp.save('00000000-0000-0000-0000-0000000000d1', '\xa3'),
  'saved', '30분 안에 인증한 번호는 저장한다'
);                                                                                                   -- 33
select results_eq(
  $$select pp.phone_hmac, extensions.pgp_sym_decrypt(pp.phone_number, 'phone-key'), pp.phone_verified_at is not null,
           (select used_at is not null from public.phone_verifications
             where profile_id = pp.profile_id and phone_hmac = '\xa3' and verified_at is not null)
      from public.profile_private pp where pp.profile_id = '00000000-0000-0000-0000-0000000000d1'$$,
  $$values ('\xa3'::bytea, '+821055556666'::text, true, true)$$,
  '저장하면 번호 · 해시가 바뀌고 인증한 번호(phone_verified_at)로 표시되며 그 인증은 쓴 것(used_at)이 된다'
);                                                                                                   -- 34
-- 04-1 을 같은 번호로 다시 낸다(뒤로 갔다 다시 저장). 인증은 이미 썼지만 내 번호가 인증한 그 번호라 새 문자 없이 된다.
select is(
  public.check_verified_phone_number('00000000-0000-0000-0000-0000000000d1', '\xa3', 1::smallint),
  'ok', '내가 인증해 저장한 번호를 다시 내면 check 는 ok — 새 문자를 받지 않아도 된다'
);                                                                                                   -- 35
select is(
  pg_temp.save('00000000-0000-0000-0000-0000000000d1', '\xa3'),
  'saved', '내가 인증해 저장한 번호를 다시 저장하면 saved'
);                                                                                                   -- 35-a
select results_eq(
  $$select phone_hmac, phone_verified_at is not null from public.profile_private
     where profile_id = '00000000-0000-0000-0000-0000000000d1'$$,
  $$values ('\xa3'::bytea, true)$$,
  '같은 번호를 다시 저장해도 인증한 번호 표시가 남는다'
);                                                                                                   -- 35-b
select is(
  (select result from pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xa3')),
  'expired', '저장에 쓴 인증을 다시 확인하면 expired — 새로 받는다'
);                                                                                                   -- 35-1

-- 인증 없이 번호를 저장하는 길(옛 앱 · set_phone_number): 같은 번호면 표시를 그대로 두고, 다른 번호면 지운다.
select public.set_phone_number('00000000-0000-0000-0000-0000000000d1', '+821055556666', 'phone-key', '\xa3'::bytea, 1::smallint);
select is(
  (select phone_verified_at is not null from public.profile_private where profile_id = '00000000-0000-0000-0000-0000000000d1'),
  true, '인증 없이 같은 번호를 다시 저장하면 인증한 번호 표시가 남는다'
);                                                                                                   -- 35-c
select public.set_phone_number('00000000-0000-0000-0000-0000000000d1', '+821077778888', 'phone-key', '\xaa'::bytea, 1::smallint);
select results_eq(
  $$select phone_hmac, phone_verified_at is null from public.profile_private
     where profile_id = '00000000-0000-0000-0000-0000000000d1'$$,
  $$values ('\xaa'::bytea, true)$$,
  '인증 없이 다른 번호로 바꾸면 인증한 번호 표시(phone_verified_at)가 지워진다'
);                                                                                                   -- 35-d
select is(
  public.check_verified_phone_number('00000000-0000-0000-0000-0000000000d1', '\xa3', 1::smallint),
  'not_verified', 'check: 이미 쓴 인증(used_at)은 ok 가 아니다 — 내 번호가 그 번호가 아니면 다시 인증한다'
);                                                                                                   -- 35-e

select pg_temp.sent('00000000-0000-0000-0000-0000000000d1', '\xa6', clock_timestamp() - interval '40 minutes');
update public.phone_verifications set verified_at = clock_timestamp() - interval '31 minutes' where phone_hmac = '\xa6';
select is(
  pg_temp.save('00000000-0000-0000-0000-0000000000d1', '\xa6'),
  'not_verified', '인증한 지 30분이 지나면 다시 인증한다'
);                                                                                                   -- 36
select is(
  public.check_verified_phone_number('00000000-0000-0000-0000-0000000000d1', '\xa6', 1::smallint),
  'not_verified', 'check: 인증한 지 30분이 지나면 ok 가 아니다'
);                                                                                                   -- 36-a
select is(
  (select result from pg_temp.attempt('00000000-0000-0000-0000-0000000000d1', '\xa6')),
  'expired', '인증한 지 30분이 지난 줄을 다시 확인하면 expired'
);                                                                                                   -- 36-1

-- E 가 인증 없이 저장한 번호 \xb5 를 A 가 인증해 저장한다(23-1 에서 보낸 줄).
update public.phone_verifications set verified_at = clock_timestamp()
 where phone_hmac = '\xb5' and profile_id = '00000000-0000-0000-0000-0000000000d1';
select is(
  pg_temp.save('00000000-0000-0000-0000-0000000000d1', '\xb5'),
  'saved', '다른 계정이 인증 없이 저장한 번호는 저장도 막지 않는다'
);                                                                                                   -- 36-2

-- A 가 \xa7 을 인증해 두었는데 그사이 B 가 같은 번호를 인증해 저장했다(동시에 인증한 두 계정).
select pg_temp.sent('00000000-0000-0000-0000-0000000000d1', '\xa7', clock_timestamp() - interval '2 minutes');
update public.phone_verifications set verified_at = clock_timestamp() where phone_hmac = '\xa7';
update public.profile_private set phone_hmac = '\xa7', phone_verified_at = clock_timestamp()
 where profile_id = '00000000-0000-0000-0000-0000000000d2';
select results_eq(
  $$select pg_temp.save('00000000-0000-0000-0000-0000000000d1', '\xa7'),
           (select used_at is null from public.phone_verifications where phone_hmac = '\xa7')$$,
  $$values ('in_use'::text, true)$$,
  '저장할 때 한 번 더 본다 — 다른 활동 계정이 먼저 저장했으면 in_use, 인증은 쓰지 않는다'
);                                                                                                   -- 37

-- 5. 기존 중복 · 삭제 ----------------------------------------------------------------
select lives_ok(
  $$update public.profile_private set phone_hmac = '\xa3'
     where profile_id = '00000000-0000-0000-0000-0000000000d2'$$,
  '이미 같은 번호를 가진 옛 계정들은 그대로 둔다(유일 제약을 걸지 않는다)'
);                                                                                                   -- 38

delete from auth.users where id = '00000000-0000-0000-0000-0000000000d4';
select is(
  (select count(*) from public.phone_verifications where profile_id = '00000000-0000-0000-0000-0000000000d4'),
  0::bigint, '계정을 지우면 인증 줄도 같이 지워진다(cascade)'
);                                                                                                   -- 39

select * from finish();
rollback;
