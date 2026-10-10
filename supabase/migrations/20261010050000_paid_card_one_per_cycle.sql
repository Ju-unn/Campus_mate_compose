-- 유료 카드는 주기(cycle)당 한 장만: offered(제안 중) 와 purchased(산 것) 를 합쳐 하나만 둘 수 있게 한다.
-- 이유: 설계 §6 성공 기준 "같은 주기에 두 장이 생기는 경우를 막는다". 돈(하트)이 걸린 규칙이라 서버 코드만 믿지 않고 DB 가 막는다.
-- 이전 인덱스(paid_card_offers_one_offered_per_cycle)는 offered 만 막아서, 구매 뒤 같은 주기에 새 offered 가 들어갈 수 있었다.
-- replaced · expired 는 계속 몇 개든 쌓인다(재선정 · 만료 이력). 구매는 같은 행을 offered -> purchased 로 바꾸므로 충돌하지 않는다.
--
-- 적용 전 중복 확인(결과가 0 줄이어야 한다. 한 줄이라도 있으면 새 인덱스 생성이 실패하니 먼저 정리한다):
--   select owner_id, cycle_started_at, count(*)
--     from public.paid_card_offers
--    where status in ('offered', 'purchased')
--    group by owner_id, cycle_started_at
--   having count(*) > 1;

drop index if exists public.paid_card_offers_one_offered_per_cycle;

create unique index paid_card_offers_one_live_per_cycle
  on public.paid_card_offers (owner_id, cycle_started_at)
  where status in ('offered', 'purchased');

comment on table public.paid_card_offers is
  '유료 카드 제안(설계 §3). 주기마다 offered · purchased 합쳐 하나(주기당 한 장). 대상이 자격을 잃으면 서버가 replaced 로 돌리고 다시 고른다';
