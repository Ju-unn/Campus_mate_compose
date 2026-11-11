-- 휴대폰 문자 인증(바탕화면 기획·설계/문자인증_솔라피_계획_11-10 §1 · §4-2 · §4-2-1, 사용자 「현업처럼 구성해줘」).
-- 가입 기본 정보 화면에서 010 번호로 6자리 인증번호를 보내고 3분 안에 맞히면 그 번호를 "확인된 번호"로 저장한다.
-- 클라이언트는 존재 자체를 몰라도 된다(default deny) — FastAPI(phone_verification/)만 다룬다. inquiries 와 같은 틀.
--
-- 한도는 서버 메모리가 아니라 이 표의 줄로 센다 — Cloud Run 이 여러 대로 늘어도 느슨해지지 않는다.
--   같은 번호: 1분에 1번 · 하루 5번 / 한 계정: 하루 10번 / 전체: 하루 p_daily_global_limit 번(서버 환경값, 처음 300)
--   "하루" 는 한국 시간 0시부터다(문의 · 신고 하루 한도와 같다).
--
-- 확인된 번호는 활동 계정 하나에만(§4-2-1): "다른 계정이 쓰는 번호" = 탈퇴하지 않은 다른 계정이 **문자로 인증해 저장한**
-- profile_private.phone_hmac(phone_verified_at 이 있는 행). 인증 없이 저장된 번호(옛 앱 · 남의 오타)는 막지 않는다 —
-- 그 번호의 진짜 주인이 인증하지 못하게 되기 때문이다(11-10 검토 권고 1, A).
-- 유일 인덱스를 걸지 않는 이유:
--   ① 탈퇴(withdraw_account)는 줄을 지우지 않고 status 만 바꾼다. 탈퇴 계정의 phone_hmac 은 30일 뒤 정리 배치가 지울 때까지
--      남아야 한다 — 추천 보상 남용 검사(redeem_referral)가 탈퇴한 계정의 번호까지 대조한다.
--      profile_private 에는 status 가 없어 "활동 계정만" 부분 유일 인덱스를 만들 수 없다.
--   ② 운영 DB 에는 이미 같은 번호를 가진 옛 계정들이 있을 수 있다 — 제약을 걸면 이 파일이 적용되지 않는다(옛 계정은 그대로 둔다).
-- 그래서 보내기(issue)와 저장(save_verified_phone_number) 두 함수가 줄 세우기(advisory lock) 안에서 검사한다.
-- 탈퇴 · 재가입 제한(signup_blocks) · 지인 차단(contact_blocks) · 추천(redeem_referral)은 건드리지 않는다.

create table public.phone_verifications (
  id uuid primary key default gen_random_uuid(),
  -- 계정을 지우면(탈퇴 30일 뒤 정리 배치 · 미인증 정리) 같이 지운다.
  profile_id uuid not null references public.profiles (id) on delete cascade,
  -- 번호 원문은 두지 않는다 — signup_policy.hash_phone(E.164) 값과 그 키 버전.
  phone_hmac bytea not null,
  phone_hmac_key_version smallint not null,
  -- 인증번호의 HMAC(FastAPI 가 신원 키로 뜬다). 원문은 어디에도 저장하지 않는다.
  -- null = 다른 계정이 쓰는 번호라 문자를 보내지 않은 시도. 계정 하루 한도에만 센다(번호 떠보기를 막는다).
  code_hash bytea,
  sent_at timestamptz not null default now(),
  expires_at timestamptz not null,
  -- 확인 시도 수(맞힌 시도 포함). 5 가 되면 잠긴다 — 새로 받아야 한다.
  attempts smallint not null default 0,
  verified_at timestamptz,
  -- 기본 정보 저장이 이 인증을 쓴 시각. 한 인증으로 한 번만 저장한다.
  used_at timestamptz,
  constraint phone_verifications_attempts_range check (attempts between 0 and 5),
  constraint phone_verifications_verified_needs_code check (verified_at is null or code_hash is not null),
  constraint phone_verifications_used_needs_verified check (used_at is null or verified_at is not null)
);

comment on table public.phone_verifications is
  '휴대폰 문자 인증. FastAPI 전용, 클라이언트 접근 없음. 인증번호는 HMAC 으로만. 계정을 지우면 cascade';

-- 번호별 하루 수 · 1분 재전송 · 최신 번호 찾기.
create index phone_verifications_phone_hmac_sent_at_index on public.phone_verifications (phone_hmac, sent_at);
-- 계정별 하루 수(FK 인덱스도 겸한다).
create index phone_verifications_profile_id_sent_at_index on public.phone_verifications (profile_id, sent_at);
-- 전체 하루 수 — 실제로 보낸 줄만 센다.
create index phone_verifications_sent_at_index on public.phone_verifications (sent_at) where code_hash is not null;

alter table public.phone_verifications enable row level security;

revoke all on table public.phone_verifications from anon, authenticated, service_role;
grant select, insert, update, delete on table public.phone_verifications to service_role;


-- 이 번호를 문자로 인증해 저장한 시각. save_verified_phone_number 만 채우고, 인증 없이 번호를 바꾸는 set_phone_number 는 지운다.
-- 옛 행은 null 이라 아무 번호도 막지 않는다(기존 가입자는 그대로 — 사용자 결정, 출시 전 DB 를 비운다).
alter table public.profile_private add column phone_verified_at timestamptz;

comment on column public.profile_private.phone_verified_at is
  '문자 인증으로 저장한 번호면 그 시각. 인증 없이 번호를 바꾸면 null. "다른 활동 계정이 쓰는 번호" 판정은 이 값이 있는 행만 본다';

-- "다른 계정이 인증한 번호인가" 를 찾는 인덱스. 유일 제약이 아니다(위 이유 ① ②).
create index profile_private_verified_phone_hmac_index on public.profile_private (phone_hmac)
  where phone_verified_at is not null;

-- 번호 저장(20260927030000)과 같고, 번호가 바뀔 때 인증 표시(phone_verified_at)를 지우는 것만 더했다. 옛 앱의 기본 정보 저장
-- (PHONE_VERIFICATION_REQUIRED=false)이 이 함수로 번호를 바꾸므로, 바뀐 번호가 "인증한 번호" 로 남지 않게 한다.
-- 같은 번호(해시 · 키 버전이 같음)를 다시 저장하면 표시를 그대로 둔다 — 04-1 을 다시 내도 인증이 풀리지 않게.
-- 서명 · 기본값 · search_path 가 같은 create or replace 라 권한은 남지만 같은 줄을 다시 적어 둔다.
create or replace function public.set_phone_number(
  p_profile_id uuid,
  p_phone text,
  p_key text,
  p_phone_hmac bytea default null,
  p_phone_hmac_key_version smallint default 1
)
returns void
language sql
set search_path = ''
as $$
  update public.profile_private
  set phone_number = extensions.pgp_sym_encrypt(p_phone, p_key),
      phone_hmac = p_phone_hmac,
      phone_hmac_key_version = p_phone_hmac_key_version,
      -- set 의 오른쪽은 고치기 전 값을 본다: 번호가 그대로면 표시를 두고, 바뀌면 null.
      phone_verified_at = case
        when phone_hmac is not distinct from p_phone_hmac and phone_hmac_key_version = p_phone_hmac_key_version
        then phone_verified_at
      end,
      updated_at = now()
  where profile_id = p_profile_id;
$$;

comment on function public.set_phone_number(uuid, text, text, bytea, smallint) is
  '번호를 pgp_sym_encrypt 로 암호화해 저장하고, FastAPI 가 계산한 신원 HMAC 과 키 버전을 같이 쓴다. '
  '번호(해시 · 키 버전)가 바뀌면 인증한 번호 표시(phone_verified_at)를 지운다 — 같은 번호면 그대로 둔다. FastAPI 전용';

revoke all on function public.set_phone_number(uuid, text, text, bytea, smallint) from public, anon, authenticated;
grant execute on function public.set_phone_number(uuid, text, text, bytea, smallint) to service_role;


-- 저장 미리 보기(아무것도 바꾸지 않는다): in_use(다른 활동 계정이 인증한 번호) · ok(30분 안에 인증하고 아직 안 쓴 인증이 있거나,
-- 내 번호가 이미 인증해 저장한 바로 그 번호) · not_verified. 기본 정보 저장이 프로필을 고치기 전에 부르고(422 면 아무것도 저장하지 않게), 보내기 · 저장 함수도 같은 판정을 쓴다.
create function public.check_verified_phone_number(
  p_profile_id uuid,
  p_phone_hmac bytea,
  p_phone_hmac_key_version smallint
)
returns text
language sql
set search_path = ''
as $$
  select case
    when exists (
      select 1
      from public.profile_private pp
      join public.profiles p on p.id = pp.profile_id
      where pp.phone_hmac = p_phone_hmac
        and pp.phone_hmac_key_version = p_phone_hmac_key_version
        and pp.phone_verified_at is not null
        and pp.profile_id <> p_profile_id
        and p.status <> 'withdrawn'
    ) then 'in_use'
    when exists (
      select 1
      from public.phone_verifications pv
      where pv.profile_id = p_profile_id
        and pv.phone_hmac = p_phone_hmac
        and pv.phone_hmac_key_version = p_phone_hmac_key_version
        and pv.verified_at >= clock_timestamp() - interval '30 minutes'
        and pv.used_at is null
    ) or exists (
      -- 04-1 을 같은 번호로 다시 낸다(뒤로 갔다 다시 저장) — 새 문자 없이 통과시킨다.
      select 1
      from public.profile_private pp
      where pp.profile_id = p_profile_id
        and pp.phone_hmac = p_phone_hmac
        and pp.phone_hmac_key_version = p_phone_hmac_key_version
        and pp.phone_verified_at is not null
    ) then 'ok'
    else 'not_verified'
  end
$$;

comment on function public.check_verified_phone_number(uuid, bytea, smallint) is
  '번호 저장 미리 보기(in_use · ok · not_verified). 아무것도 바꾸지 않는다. FastAPI 전용';

revoke all on function public.check_verified_phone_number(uuid, bytea, smallint) from public, anon, authenticated;
grant execute on function public.check_verified_phone_number(uuid, bytea, smallint) to service_role;


-- 보내기: 한도 · "이미 보냈어요" · 다른 계정 번호를 한 트랜잭션 안에서 판정하고, 보내도 되면 줄을 넣는다.
-- 문자는 FastAPI 가 이 함수가 issued 를 돌려준 뒤에만 보낸다(실패하면 그 줄을 지운다).
-- 모든 보내기를 하나의 잠금으로 줄 세운다 — 같은 계정 · 같은 번호로 동시에 두 번 와도 두 번째는 첫 줄을 보고
-- already_sent 를 받는다. 전체 · 계정 한도도 정확해진다. 보내기는 하루 수백 건이라 한 줄 세우기로 충분하다.
-- 결과(result): issued · already_sent · in_use · number_cooldown · number_daily_limit · account_daily_limit · global_daily_limit
create function public.issue_phone_verification(
  p_profile_id uuid,
  p_phone_hmac bytea,
  p_phone_hmac_key_version smallint,
  p_code_hash bytea,
  p_daily_global_limit integer
)
returns table (
  result text,
  verification_id uuid,
  retry_after_seconds integer,
  expires_in_seconds integer,
  global_limit_reached boolean
)
language plpgsql
set search_path = ''
as $$
declare
  v_now timestamptz;
  v_day_start timestamptz;
  v_until_tomorrow integer;
  v_last record;
  v_sent_today integer;
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('phone_verifications.issue', 0));
  -- 잠금을 기다린 뒤의 시각이다(now() 는 트랜잭션 시작 시각이라 기다린 만큼 어긋난다).
  v_now := clock_timestamp();
  v_day_start := date_trunc('day', v_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  v_until_tomorrow := ceil(extract(epoch from v_day_start + interval '1 day' - v_now))::integer;

  -- 계정 하루 10번 — in_use 시도까지 센다.
  if (select count(*) from public.phone_verifications
       where profile_id = p_profile_id and sent_at >= v_day_start) >= 10 then
    return query select 'account_daily_limit'::text, null::uuid, v_until_tomorrow, null::integer, false;
    return;
  end if;

  -- 다른 활동 계정(탈퇴 말고 전부 — 가입 중 · 정지 포함)이 인증해 저장한 번호. 문자는 보내지 않고 시도만 남긴다.
  if public.check_verified_phone_number(p_profile_id, p_phone_hmac, p_phone_hmac_key_version) = 'in_use' then
    insert into public.phone_verifications (profile_id, phone_hmac, phone_hmac_key_version, code_hash, sent_at, expires_at)
    values (p_profile_id, p_phone_hmac, p_phone_hmac_key_version, null, v_now, v_now);
    return query select 'in_use'::text, null::uuid, null::integer, null::integer, false;
    return;
  end if;

  -- 같은 번호 1분에 1번(계정이 달라도). 같은 계정이면 문자 없이 "이미 보냈어요 + 남은 초".
  select pv.id, pv.profile_id, pv.sent_at, pv.expires_at into v_last
  from public.phone_verifications pv
  where pv.phone_hmac = p_phone_hmac and pv.code_hash is not null
  order by pv.sent_at desc
  limit 1;
  if found and v_last.sent_at > v_now - interval '60 seconds' then
    if v_last.profile_id = p_profile_id then
      return query select 'already_sent'::text, v_last.id,
        ceil(extract(epoch from v_last.sent_at + interval '60 seconds' - v_now))::integer,
        greatest(ceil(extract(epoch from v_last.expires_at - v_now))::integer, 0), false;
    else
      return query select 'number_cooldown'::text, null::uuid,
        ceil(extract(epoch from v_last.sent_at + interval '60 seconds' - v_now))::integer, null::integer, false;
    end if;
    return;
  end if;

  -- 같은 번호 하루 5번(보낸 것만).
  if (select count(*) from public.phone_verifications
       where phone_hmac = p_phone_hmac and code_hash is not null and sent_at >= v_day_start) >= 5 then
    return query select 'number_daily_limit'::text, null::uuid, v_until_tomorrow, null::integer, false;
    return;
  end if;

  -- 전체 하루 한도 — 요금 폭탄의 마지막 방어선.
  select count(*) into v_sent_today
  from public.phone_verifications
  where code_hash is not null and sent_at >= v_day_start;
  if v_sent_today >= p_daily_global_limit then
    return query select 'global_daily_limit'::text, null::uuid, v_until_tomorrow, null::integer, false;
    return;
  end if;

  insert into public.phone_verifications (profile_id, phone_hmac, phone_hmac_key_version, code_hash, sent_at, expires_at)
  values (p_profile_id, p_phone_hmac, p_phone_hmac_key_version, p_code_hash, v_now, v_now + interval '3 minutes')
  returning id into v_id;
  -- 이 보내기가 오늘 마지막 한 통이면 true — FastAPI 가 문자를 보낸 뒤 디스코드로 한 번 알린다.
  return query select 'issued'::text, v_id, 60, 180, v_sent_today + 1 >= p_daily_global_limit;
end;
$$;

comment on function public.issue_phone_verification(uuid, bytea, smallint, bytea, integer) is
  '휴대폰 인증번호 보내기 판정 + 줄 넣기(한도 · 이미 보냄 · 다른 계정 번호). 모든 보내기를 한 잠금으로 줄 세운다. FastAPI 전용';

revoke all on function public.issue_phone_verification(uuid, bytea, smallint, bytea, integer) from public, anon, authenticated;
grant execute on function public.issue_phone_verification(uuid, bytea, smallint, bytea, integer) to service_role;


-- 확인 한 번: 이 계정 · 이 번호의 가장 최근 줄만 본다(새로 보내면 옛 번호는 못 쓴다). 시도 한 칸을 먼저 쓰고 해시를 준다 —
-- 비교는 FastAPI 가 hmac.compare_digest 로 한다. 줄 잠금(for update)이라 동시에 틀려도 5번을 넘지 못한다.
-- 결과: check(해시와 남은 횟수) · verified(이미 맞혔고 30분 안 · 아직 저장에 안 씀) · expired(없음 · 3분 지남 ·
-- 맞힌 지 30분 지남 · 저장에 이미 씀) · locked(5번 씀)
create function public.attempt_phone_verification(
  p_profile_id uuid,
  p_phone_hmac bytea,
  p_phone_hmac_key_version smallint
)
returns table (result text, verification_id uuid, code_hash bytea, attempts_left integer)
language plpgsql
set search_path = ''
as $$
declare
  v public.phone_verifications%rowtype;
begin
  select * into v
  from public.phone_verifications pv
  where pv.profile_id = p_profile_id
    and pv.phone_hmac = p_phone_hmac
    and pv.phone_hmac_key_version = p_phone_hmac_key_version
  order by pv.sent_at desc, pv.id desc
  limit 1
  for update;

  if not found or v.code_hash is null then
    return query select 'expired'::text, null::uuid, null::bytea, 0;
  elsif v.verified_at is not null then
    -- 저장이 받지 않을 인증(30분 지남 · 이미 씀)을 "인증됐어요" 라고 하지 않는다.
    if v.used_at is null and v.verified_at >= clock_timestamp() - interval '30 minutes' then
      return query select 'verified'::text, v.id, null::bytea, 5 - v.attempts;
    else
      return query select 'expired'::text, v.id, null::bytea, 5 - v.attempts;
    end if;
  elsif v.expires_at <= clock_timestamp() then
    return query select 'expired'::text, v.id, null::bytea, 5 - v.attempts;
  elsif v.attempts >= 5 then
    return query select 'locked'::text, v.id, null::bytea, 0;
  else
    update public.phone_verifications set attempts = attempts + 1 where id = v.id;
    return query select 'check'::text, v.id, v.code_hash, 5 - (v.attempts + 1);
  end if;
end;
$$;

comment on function public.attempt_phone_verification(uuid, bytea, smallint) is
  '휴대폰 인증번호 확인 한 번(최신 줄만, 시도 한 칸 먼저 쓰기). 해시 비교는 FastAPI. FastAPI 전용';

revoke all on function public.attempt_phone_verification(uuid, bytea, smallint) from public, anon, authenticated;
grant execute on function public.attempt_phone_verification(uuid, bytea, smallint) to service_role;


-- 기본 정보 저장(PHONE_VERIFICATION_REQUIRED 일 때): 30분 안에 인증하고 아직 쓰지 않은 인증이 있어야 번호를 저장한다.
-- 저장하면서 "다른 활동 계정이 인증한 번호" 를 한 번 더 본다 — 두 계정이 같은 번호를 동시에 인증해도 먼저 저장한 쪽만 된다.
-- 같은 번호의 저장을 번호 단위 잠금으로 줄 세운다. 번호 저장 본문은 set_phone_number 그대로이고(행은 부르는 쪽이 먼저 보장),
-- 그 뒤 인증한 번호 표시(phone_verified_at)를 단다.
-- 결과: saved · not_verified · in_use
create function public.save_verified_phone_number(
  p_profile_id uuid,
  p_phone text,
  p_key text,
  p_phone_hmac bytea,
  p_phone_hmac_key_version smallint
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_check text;
  v_verification_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('phone_verifications.save:' || encode(p_phone_hmac, 'hex'), 0));

  v_check := public.check_verified_phone_number(p_profile_id, p_phone_hmac, p_phone_hmac_key_version);
  if v_check <> 'ok' then
    return v_check;
  end if;

  select pv.id into v_verification_id
  from public.phone_verifications pv
  where pv.profile_id = p_profile_id
    and pv.phone_hmac = p_phone_hmac
    and pv.phone_hmac_key_version = p_phone_hmac_key_version
    and pv.verified_at >= clock_timestamp() - interval '30 minutes'
    and pv.used_at is null
  order by pv.verified_at desc
  limit 1
  for update;
  if v_verification_id is null then
    -- 쓸 인증이 없으면 내 번호가 이미 인증한 바로 그 번호일 때만 다시 저장한다(표시는 set_phone_number 가 그대로 둔다).
    -- check 와 이 select 사이에 30분이 막 지난 경우도 여기서 걸러진다.
    if not exists (
      select 1 from public.profile_private pp
      where pp.profile_id = p_profile_id and pp.phone_hmac = p_phone_hmac
        and pp.phone_hmac_key_version = p_phone_hmac_key_version and pp.phone_verified_at is not null
    ) then
      return 'not_verified';
    end if;
    perform public.set_phone_number(p_profile_id, p_phone, p_key, p_phone_hmac, p_phone_hmac_key_version);
    return 'saved';
  end if;

  update public.phone_verifications set used_at = clock_timestamp() where id = v_verification_id;
  perform public.set_phone_number(p_profile_id, p_phone, p_key, p_phone_hmac, p_phone_hmac_key_version);
  -- 인증한 이 저장에서 표시를 단다(다른 번호에서 바꿨으면 set_phone_number 가 지운 뒤다).
  update public.profile_private set phone_verified_at = clock_timestamp() where profile_id = p_profile_id;
  return 'saved';
end;
$$;

comment on function public.save_verified_phone_number(uuid, text, text, bytea, smallint) is
  '인증한 번호만 저장(30분 · 한 번, 또는 이미 인증해 저장한 같은 번호) + 다른 활동 계정 번호면 in_use. 번호 단위 잠금. FastAPI 전용';

revoke all on function public.save_verified_phone_number(uuid, text, text, bytea, smallint) from public, anon, authenticated;
grant execute on function public.save_verified_phone_number(uuid, text, text, bytea, smallint) to service_role;
