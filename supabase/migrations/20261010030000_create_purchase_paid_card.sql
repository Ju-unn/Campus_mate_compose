-- 유료 카드 구매(설계 §3-3): 제안 하나를 하트 50개로 사서 구매 카드(daily_cards.source='purchased') 한 장을 만든다.
-- security invoker 다(SUPABASE.md §5) — 부르는 service_role 이 표 권한을 가진다. 그래서 revoke 대상은
-- public · anon · authenticated 이고 service_role 에만 execute 를 준다.
--
-- 돌려주는 값(jsonb):
--   {"result":"ok","card_id":...}                산 카드
--   {"result":"already_purchased","card_id":...} 이미 산 제안을 또 불렀다(하트 · 카드는 그대로)
--   {"result":"not_enough_hearts"}               하트가 모자란다. 아무것도 바뀌지 않는다
--   {"result":"offer_gone"}                      제안이 없거나 · 남의 것이거나 · offered 가 아니거나 · 대상이 이제 고를 수 없다
--                                                대상이 이제 고를 수 없어서 돌려줄 때만, 그 제안(offered)을 replaced 로 바꿔 둔다 —
--                                                서버가 같은 낡은 제안을 계속 보여 주는 것을 막는다. 재선정은 서버가 한다.
--                                                나머지 offer_gone 은 제안 상태를 건드리지 않는다.
--
-- 알고 둔 한계(사소):
--   · 산 뒤 카드가 지워지면 already_purchased 의 card_id 는 null 이다(purchased_card_id 가 set null).
--   · p_owner 본인의 상태(정지 등)는 보지 않는다. 서버가 인증한 사람의 id 를 넘긴다.
--   · 제안이 지금 주기의 것인지(cycle_started_at)는 보지 않는다. 주기 지난 제안의 만료는 서버가 expired 로 돌린다.
--
-- 동시성: 제안 행을 `for update` 로 잠근 채 끝까지 간다. 같은 제안을 두 요청이 동시에 불러도 두 번째는 첫 번째가 끝나길
-- 기다렸다가 purchased 를 보고 already_purchased 를 받는다 — 하트는 한 번만 빠진다.
create function public.purchase_paid_card(p_owner uuid, p_offer uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  -- 하트 가격은 여기 한 곳(설계 §3-3). 바꾸면 이 줄만 마이그레이션으로 바꾼다.
  c_price constant integer := 50;
  v_offer public.paid_card_offers;
  v_card_id uuid;
  v_constraint text;
begin
  -- ① 소유자까지 맞는 제안만 잡는다. 남의 제안 · 없는 제안은 구분 없이 offer_gone(남의 제안 존재를 알리지 않는다).
  select * into v_offer
  from public.paid_card_offers
  where id = p_offer and owner_id = p_owner
  for update;

  if not found then
    return jsonb_build_object('result', 'offer_gone');
  end if;

  -- ② 이미 산 제안
  if v_offer.status = 'purchased' then
    return jsonb_build_object('result', 'already_purchased', 'card_id', v_offer.purchased_card_id);
  end if;

  -- ③ replaced · expired
  if v_offer.status <> 'offered' then
    return jsonb_build_object('result', 'offer_gone');
  end if;

  -- ④ 대상이 아직 고를 수 있는 사람인지. 규칙을 따로 베끼지 않고 match_candidates 의 pickable 을 그대로 쓴다 —
  --    active · 자동 가림 · 일시중지 · 차단 · 지인 차단 · 학교 열림 · 이미 받은 카드(쉼 기간) 등이 한 곳에서 정해진다.
  --    한 번 부를 때 후보 전원을 계산하지만 구매는 드문 일이라 감수한다.
  if not exists (
    select 1
    from jsonb_array_elements(public.match_candidates(p_owner)) e
    where (e ->> 'candidate_id')::uuid = v_offer.target_id
      and (e ->> 'pickable')::boolean
  ) then
    -- 낡은 제안을 replaced 로 돌려 둔다. 그대로 두면 서버가 같은 offered 를 계속 보여 주고 사람은 살 수 없는
    -- 제안에 갇힌다(주기당 offered 하나라 새 제안도 못 들어온다). 예외 없이 돌아가므로 이 update 는 커밋된다.
    -- 하트는 아직 안 건드렸고, 남의 제안 · 없는 제안 · 이미 replaced/expired 인 제안은 위에서 이미 돌아갔다.
    update public.paid_card_offers set status = 'replaced' where id = p_offer;
    return jsonb_build_object('result', 'offer_gone');
  end if;

  -- ⑤ 하트 차감을 카드 만들기보다 먼저 한다. 모자라면 entitlements 의 check(heart_balance >= 0)가 23514 를 던지는데,
  --    이 begin..exception 블록이 하위 트랜잭션이라 그 안의 원장 · 잔액 쓰기가 같이 되돌아가고 바깥은 멀쩡하다.
  --    다른 check 위반을 "하트 부족"으로 잘못 읽지 않게 제약 이름까지 확인하고, 아니면 그대로 다시 던진다.
  begin
    perform public.grant_hearts(p_owner, -c_price, 'extra_card', p_offer);
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint is distinct from 'entitlements_balance_non_negative' then
      raise;
    end if;
    return jsonb_build_object('result', 'not_enough_hearts');
  end;

  -- ⑥ 구매 카드: 만료 없음(daily_cards_purchased_never_expires)
  insert into public.daily_cards (owner_id, target_id, source, expires_at)
  values (p_owner, v_offer.target_id, 'purchased', null)
  returning id into v_card_id;

  -- ⑦
  update public.paid_card_offers
  set status = 'purchased', purchased_card_id = v_card_id
  where id = p_offer;

  return jsonb_build_object('result', 'ok', 'card_id', v_card_id);
end;
$$;

comment on function public.purchase_paid_card(uuid, uuid) is
  '유료 카드 제안 하나를 하트 50개로 산다(설계 §3-3). 결과는 ok · already_purchased · not_enough_hearts · offer_gone';

revoke all on function public.purchase_paid_card(uuid, uuid) from public, anon, authenticated;
grant execute on function public.purchase_paid_card(uuid, uuid) to service_role;
