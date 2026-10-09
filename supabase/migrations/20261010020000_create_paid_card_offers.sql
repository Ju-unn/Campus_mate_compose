-- 유료 카드 제안(설계 §3 · §8): 서버가 "이번 주기에 살 수 있는 한 사람"을 골라 적어 두는 표.
-- 사는 쪽은 제안 id 로 purchase_paid_card 를 부른다(다음 마이그레이션). 제안을 고르는 일(후보 폭 · 이유 문구)은 서버 몫이다.
create type public.paid_card_offer_status as enum ('offered', 'purchased', 'replaced', 'expired');

create table public.paid_card_offers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  -- 이 제안이 속한 카드 주기의 시작 시각. 주기마다 살아 있는 제안은 하나다(아래 부분 유일 인덱스).
  cycle_started_at timestamptz not null,
  target_id uuid not null references public.profiles (id) on delete cascade,
  reasons jsonb not null default '[]',
  -- 제안을 고를 때 후보 폭(상위 몇 명 중에서 뽑았는가). 뽑을 사람이 없으면 제안이 생기지 않으므로 1 이상이다.
  band_count integer not null check (band_count >= 1),
  status public.paid_card_offer_status not null default 'offered',
  -- 산 카드. 카드가 지워지면 칸만 비고(set null) 제안 행은 남는다 — 그래서 purchased 이면서 null 인 행도 정상이다.
  purchased_card_id uuid references public.daily_cards (id) on delete set null,
  created_at timestamptz not null default now(),

  constraint paid_card_offers_card_only_if_purchased check (
    purchased_card_id is null or status = 'purchased'
  )
);

comment on table public.paid_card_offers is
  '유료 카드 제안(설계 §3). 주기마다 offered 는 하나. 대상이 자격을 잃으면 서버가 replaced 로 돌리고 다시 고른다';

-- 같은 주기에 offered 두 개 금지. replaced · purchased · expired 는 몇 개든 쌓인다(재선정 이력).
create unique index paid_card_offers_one_offered_per_cycle
  on public.paid_card_offers (owner_id, cycle_started_at)
  where status = 'offered';

create index paid_card_offers_owner_created_index on public.paid_card_offers (owner_id, created_at desc);
-- FK 칸 인덱스 관례(daily_cards_target_index 와 같다): 프로필 · 카드를 지울 때 이 표를 통째로 훑지 않게 한다.
create index paid_card_offers_target_index on public.paid_card_offers (target_id);
create index paid_card_offers_purchased_card_index on public.paid_card_offers (purchased_card_id)
  where purchased_card_id is not null;

-- RLS: 정책 없음 = 클라이언트는 자기 행도 못 읽는다. FastAPI 가 service_role 로 읽고 내려준다.
alter table public.paid_card_offers enable row level security;

revoke all on table public.paid_card_offers from anon, authenticated, service_role;
grant select, insert, update, delete on table public.paid_card_offers to service_role;
