-- 조각 4~5: 쌍방 수락으로 성립한 매칭(설계 §2.2, ERD §4). 신뢰 게이트·채팅은 조각 5 가 이어서 쓴다.
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  profile_a uuid not null references public.profiles (id) on delete cascade,
  profile_b uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  trust_passed_at timestamptz,   -- 조각 5: 쌍방 카톡 아이디 공유가 끝난 시각
  chat_closed_at timestamptz,    -- 조각 5: 대화가 닫힌 시각

  -- 같은 두 사람의 매칭이 두 행이 되지 않게 순서를 고정한다(ERD §4).
  constraint matches_pair_order check (profile_a < profile_b),
  constraint matches_pair_unique unique (profile_a, profile_b)
);

comment on table public.matches is
  '쌍방 수락으로 성립한 매칭(설계 §2.2). 항상 profile_a < profile_b 로 저장한다';

create index matches_profile_b_index on public.matches (profile_b);

create table public.match_participants (
  match_id uuid not null references public.matches (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  trust_response public.card_decision,   -- 조각 5: 카톡 아이디 공유 수락/거절
  responded_at timestamptz,
  left_at timestamptz,
  last_read_at timestamptz,

  primary key (match_id, profile_id)
);

comment on table public.match_participants is
  '매칭 당사자 두 행(ERD §4). 신뢰 게이트 응답·읽음 시각은 조각 5 가 채운다';

create index match_participants_profile_index on public.match_participants (profile_id);

alter table public.matches enable row level security;
alter table public.match_participants enable row level security;

-- ERD §2: matches 는 당사자만, match_participants 는 본인 행만 읽는다.
-- 쓰기는 FastAPI(service_role) 전용이라 insert·update 정책은 두지 않는다.
create policy "matches are readable by participants"
  on public.matches
  for select
  to authenticated
  using ((select auth.uid()) in (profile_a, profile_b));

create policy "match participants rows are readable by owner"
  on public.match_participants
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.matches, public.match_participants
  from anon, authenticated, service_role;
grant select on table public.matches, public.match_participants to authenticated;
grant select, insert, update, delete on table public.matches, public.match_participants to service_role;
