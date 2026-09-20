-- 조각 4: 카드 지급과 결정(설계 §2.1·§2.2·§2.4, ERD §4).
create type public.card_source as enum ('daily', 'purchased');
create type public.card_decision as enum ('accept', 'reject');

create table public.daily_cards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  source public.card_source not null default 'daily',
  issued_at timestamptz not null default now(),
  -- daily 는 "다음 지급일 07:00", purchased 는 null(만료 없음, 설계 §2.4).
  expires_at timestamptz,

  constraint daily_cards_not_self check (owner_id <> target_id),
  constraint daily_cards_purchased_never_expires check (
    source <> 'purchased' or expires_at is null
  ),
  constraint daily_cards_daily_has_expiry check (
    source <> 'daily' or expires_at is not null
  )
);

comment on table public.daily_cards is
  '지급된 카드 한 장(설계 §2.1). 무응답 만료는 행을 쓰지 않고 expires_at 으로 판정한다';

-- (owner_id, target_id) 는 unique 가 아니다 — 무응답으로 만료된 상대는 다시 나올 수 있다(ERD §4).
create index daily_cards_owner_target_index on public.daily_cards (owner_id, target_id);
create index daily_cards_owner_issued_index on public.daily_cards (owner_id, issued_at desc);
create index daily_cards_target_index on public.daily_cards (target_id);

create table public.card_decisions (
  card_id uuid primary key references public.daily_cards (id) on delete cascade,
  decision public.card_decision not null,
  decided_at timestamptz not null default now()
);

comment on table public.card_decisions is
  '카드를 받은 사람의 결정(설계 §2.2). 행이 없으면 아직 무응답이다';

-- 받은 수락함 조회가 "최근 7일 안에 수락된 카드"를 시간으로 훑는다(Task B6).
create index card_decisions_decided_at_index on public.card_decisions (decided_at desc)
  where decision = 'accept';

create table public.acceptance_responses (
  card_id uuid primary key references public.daily_cards (id) on delete cascade,
  responder_id uuid not null references public.profiles (id) on delete cascade,
  decision public.card_decision not null,
  decided_at timestamptz not null default now()
);

comment on table public.acceptance_responses is
  '수락을 받은 사람(카드의 target)의 응답(설계 §2.2). 행이 없고 7일이 지나면 만료다';

create index acceptance_responses_responder_index on public.acceptance_responses (responder_id);

-- RLS: 세 테이블 모두 정책을 하나도 만들지 않는다 = authenticated 는 전부 막힌다(ERD §2 "읽기 없음").
-- 오늘의 카드·받은 수락함은 FastAPI 가 service_role 로 읽어 내려준다(설계 §7.1).
alter table public.daily_cards enable row level security;
alter table public.card_decisions enable row level security;
alter table public.acceptance_responses enable row level security;

revoke all on table public.daily_cards, public.card_decisions, public.acceptance_responses
  from anon, authenticated, service_role;
grant select, insert, update, delete
  on table public.daily_cards, public.card_decisions, public.acceptance_responses
  to service_role;
