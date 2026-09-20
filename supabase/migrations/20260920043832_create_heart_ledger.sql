-- 조각 7 예정이던 하트 원장을 조각 2로 앞당긴다 — 아바타 생성 5회 연속 실패 보상(10하트)이 조각 2에 필요하기
-- 때문(2026-09-20 사용자 승인). 구매·환불 등 나머지 heart_reason 값은 조각 7이 실제로 쓴다.
-- 기준 문서: docs/ERD.md §6·§8
create type public.heart_reason as enum (
  'purchase', 'referral', 'promo', 'free_task', 'poll_vote',
  'extra_card', 'avatar_regen', 'refund', 'admin_adjust'
);

create table public.entitlements (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  heart_balance integer not null default 0,
  updated_at timestamptz not null default now(),

  constraint entitlements_balance_non_negative check (heart_balance >= 0)
);

comment on table public.entitlements is '하트 잔액 캐시. heart_transactions 합계와 항상 같아야 한다(FastAPI 가 한 트랜잭션에서 둘 다 쓴다)';

create table public.heart_transactions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  amount integer not null,
  reason public.heart_reason not null,
  ref_id uuid,
  created_at timestamptz not null default now(),

  constraint heart_transactions_amount_not_zero check (amount <> 0)
);

comment on table public.heart_transactions is
  '하트 원장. 적립은 양수·사용은 음수(ERD §6). 아바타 생성 5회 연속 실패 보상은 amount=10,
   reason=admin_adjust 로 남긴다(avatar_regen 은 아바타 재생성으로 하트를 "쓸 때" 쓰고, 이 보상은 운영
   보정이라 admin_adjust 가 더 정확하다 — 2026-09-20 계획서 결정)';

create index heart_transactions_profile_id_index on public.heart_transactions (profile_id);

alter table public.entitlements enable row level security;
alter table public.heart_transactions enable row level security;

create policy "entitlements are readable by owner"
  on public.entitlements for select to authenticated
  using ((select auth.uid()) = profile_id);

create policy "heart transactions are readable by owner"
  on public.heart_transactions for select to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.entitlements from anon, authenticated, service_role;
grant select on table public.entitlements to authenticated;
grant select, insert, update, delete on table public.entitlements to service_role;

revoke all on table public.heart_transactions from anon, authenticated, service_role;
grant select on table public.heart_transactions to authenticated;
grant select, insert, update, delete on table public.heart_transactions to service_role;

-- 잔액 캐시(entitlements.heart_balance)와 원장(heart_transactions)을 한 트랜잭션에서 같이 쓴다(ERD §6) —
-- PostgREST 두 번 호출로는 원자성이 안 나오므로 Postgres 함수로 묶는다(Part B Task B4 `hearts.py` 가
-- 이 함수명을 그대로 부른다, 2026-09-20 사후 추가).
create or replace function public.grant_hearts(p_profile_id uuid, p_amount integer, p_reason public.heart_reason, p_ref_id uuid default null)
returns void
language plpgsql
as $$
begin
  insert into public.heart_transactions (profile_id, amount, reason, ref_id)
  values (p_profile_id, p_amount, p_reason, p_ref_id);

  insert into public.entitlements (profile_id, heart_balance, updated_at)
  values (p_profile_id, p_amount, now())
  on conflict (profile_id) do update
    set heart_balance = public.entitlements.heart_balance + excluded.heart_balance,
        updated_at = now();
end;
$$;

revoke all on function public.grant_hearts(uuid, integer, public.heart_reason, uuid) from public, anon, authenticated;
grant execute on function public.grant_hearts(uuid, integer, public.heart_reason, uuid) to service_role;
