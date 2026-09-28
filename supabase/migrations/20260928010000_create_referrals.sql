-- 추천인 프로그램(spec §2.7, 통합대장 결정 D3~D6 2026-09-28). 기준 문서: docs/ERD.md §3 181줄 · §6
-- 계획서: docs/superpowers/plans/2026-09-28-referral.md

-- 0 · O · 1 · I 를 뺀 32글자(D3). 256 이 32 로 나눠떨어져 get_byte % 32 가 치우치지 않는다.
-- 이미 쓰인 코드면 다시 뽑는다(대장 검토 09-28: 기본값이 unique 와 부딪혀 가입 insert 가 실패하는 길을 막는다).
-- 다섯 번 다 겹칠 확률은 사실상 0 이고, 그래도 겹치면 마지막 후보를 돌려주고 unique 가 23505 로 막는다.
-- 남는 빈틈: 두 사람이 같은 순간 같은 코드를 뽑으면 둘 다 exists 를 통과하고 늦은 쪽 가입이 23505 로 실패한다
-- (≈ 1/10억 × 동시 가입 수). 앱은 가입을 다시 시도하면 된다.
create function public.generate_referral_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_code text;
begin
  for attempt in 1..5 loop
    select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', get_byte(b.bytes, i) % 32 + 1, 1), '' order by i)
    into v_code
    from (select extensions.gen_random_bytes(6) as bytes) as b, generate_series(0, 5) as i;
    exit when not exists (select 1 from public.profiles where referral_code = v_code);
  end loop;
  return v_code;
end;
$$;

-- 기존 행 채우기: 칸을 먼저 비워 둔 채 더하고 update 로 행마다 부른다. add column ... default 로 한 번에 하면
-- 테이블을 다시 쓰는 도중에 함수가 아직 없는 referral_code 칸을 읽어 실패한다.
-- 같은 update 안에서 앞서 채운 행은 exists 가 못 보므로(문장 시작 스냅숏) 기존 행끼리 겹치면 아래 unique 가
-- 마이그레이션을 실패시킨다 — 그때는 그대로 다시 적용하면 된다(수백 명 기준 확률 ≈ 1/1000만).
alter table public.profiles add column referral_code text;
update public.profiles set referral_code = public.generate_referral_code();
alter table public.profiles
  alter column referral_code set default public.generate_referral_code(),
  alter column referral_code set not null,
  add constraint profiles_referral_code_key unique (referral_code),
  add constraint profiles_referral_code_format check (referral_code ~ '^[A-HJ-NP-Z2-9]{6}$');

create table public.referrals (
  referee_id uuid primary key references public.profiles (id) on delete cascade,
  referrer_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  rewarded_at timestamptz,

  constraint referrals_not_self check (referee_id <> referrer_id)
);

comment on table public.referrals is
  '추천 관계. 가입당 1회(PK). 행이 있으면 지인 리뷰를 쓸 수 있는 사이다(채팅탭 friend_reviews). FastAPI 전용';

create index referrals_referrer_id_index on public.referrals (referrer_id);

alter table public.referrals enable row level security;
revoke all on table public.referrals from anon, authenticated, service_role;
grant select, insert, update, delete on table public.referrals to service_role;

-- 검사 · 행 넣기 · 양쪽 50하트를 한 트랜잭션에서(D6). 반환 = 추천인 id(20b 가 상대를 불러온다).
-- security invoker — 부르는 쪽은 FastAPI(service_role) 하나고, service_role 이 표 권한을 다 가진다.
create function public.redeem_referral(p_referee_id uuid, p_code text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_referrer uuid;
  v_referee_hmac bytea;
  v_referrer_hmac bytea;
begin
  -- 탈퇴 · 정지한 사람의 코드는 없는 코드다(ERD 267줄, D5).
  select id into v_referrer
  from public.profiles
  where referral_code = upper(btrim(p_code)) and status not in ('withdrawn', 'suspended');
  if v_referrer is null then
    raise exception 'referral code not found' using errcode = 'CM404';
  end if;
  if v_referrer = p_referee_id then
    raise exception 'referral not allowed' using errcode = 'CM422';
  end if;

  select phone_hmac into v_referee_hmac from public.profile_private where profile_id = p_referee_id;
  select phone_hmac into v_referrer_hmac from public.profile_private where profile_id = v_referrer;

  -- 번호 해시가 빈 옛 계정(백필 전)은 비교하지 않는다(D4).
  if v_referee_hmac is not null then
    -- 같은 번호의 두 계정이 동시에 들어와도 한 번만 통과하게 번호 단위로 줄 세운다. 트랜잭션이 끝나면 풀린다.
    perform pg_advisory_xact_lock(hashtextextended(encode(v_referee_hmac, 'hex'), 0));
    if v_referee_hmac = v_referrer_hmac
       or exists (
         select 1
         from public.referrals r
         join public.profile_private pp on pp.profile_id = r.referee_id
         where pp.phone_hmac = v_referee_hmac and r.referee_id <> p_referee_id
       ) then
      raise exception 'referral not allowed' using errcode = 'CM422';
    end if;
  end if;

  -- 이미 입력한 사람은 PK 가 23505 로 막는다 — 아래 지급까지 가지 않는다.
  insert into public.referrals (referee_id, referrer_id, rewarded_at)
  values (p_referee_id, v_referrer, now());

  perform public.grant_hearts(p_referee_id, 50, 'referral', p_referee_id);
  perform public.grant_hearts(v_referrer, 50, 'referral', p_referee_id);
  return v_referrer;
end;
$$;

revoke execute on function public.generate_referral_code() from public, anon, authenticated;
revoke execute on function public.redeem_referral(uuid, text) from public, anon, authenticated;
grant execute on function public.redeem_referral(uuid, text) to service_role;
