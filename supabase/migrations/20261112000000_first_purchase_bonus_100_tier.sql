-- 첫 구매 보너스(+50하트) 자격을 "구매 기록이 하나라도 있으면 끝" 에서 "100하트 이상 상품을 산 적이 없으면 자격 있음" 으로.
-- 사용자 결정 2026-11-12: 50하트는 100하트가 아니다 — 50하트를 먼저 사도 나중에 100하트 이상을 처음 살 때 +50 을 받는다.
-- 보너스 크기(50) · 대상(100하트 이상) · 한 사람 한 번은 그대로다.
--
-- 규칙(원본은 이 함수 ②, 서버 /billing/status 는 같은 조건을 묻는다 — backend/app/billing/router.py · repository.py):
--   이 사람의 purchases 중 heart_amount >= 100 인 줄이 하나라도 있으면(환불된 것도 센다) 자격 없음.
-- 한 사람 한 번 = 보너스를 받은 구매는 그 사람의 첫 100하트 이상 구매이므로, 그 줄이 남아 있는 한 다시 받을 수 없다.
-- 동시성은 그대로: 사람마다 advisory lock 으로 줄을 세워 ②가 앞 사람이 커밋한 행을 본다(read committed).
-- 바뀐 곳은 ② 한 줄뿐이다. 나머지는 20261013010100_billing_purchases.sql 의 정의와 같다.
-- 구글 · 애플이 같은 함수를 쓴다(apple_router.py 도 BillingRepository.grant_store_purchase).
create or replace function public.grant_store_purchase(
  p_profile_id uuid, p_store public.store_platform, p_product_id text, p_token_hash text,
  p_order_id text, p_purchased_at timestamptz, p_is_test boolean
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  -- 상품표와 보너스는 여기 한 곳(보너스안 §1 · §2). 바꾸면 이 함수만 마이그레이션으로 바꾼다.
  -- 서버(billing/router.py)는 화면에 보여 줄 보너스 숫자만 안다(유료 카드 c_price 와 같은 방식).
  c_bonus constant integer := 50;
  c_bonus_min_hearts constant integer := 100;
  v_hearts integer;
  v_price integer;
  v_bonus integer := 0;
  v_existing public.purchases;
  v_id uuid;
begin
  v_hearts := case p_product_id
    when 'heart_50' then 50 when 'heart_100' then 100 when 'heart_200' then 200
    when 'heart_400' then 400 when 'heart_800' then 800 end;
  v_price := case p_product_id
    when 'heart_50' then 3000 when 'heart_100' then 5700 when 'heart_200' then 10800
    when 'heart_400' then 20400 when 'heart_800' then 38400 end;
  if v_hearts is null then
    return jsonb_build_object('result', 'unknown_product');
  end if;

  -- read committed 라 잠근 뒤의 문장은 앞 사람이 커밋한 행을 본다 — 아래 ① · ② 가 줄 선 순서대로 판정된다.
  perform pg_advisory_xact_lock(hashtextextended('purchase:' || p_profile_id::text, 0));

  -- ① 같은 영수증(재전송 · 앱 재시작 · 두 번 누름)
  select * into v_existing from public.purchases where store = p_store and token_hash = p_token_hash;
  if found then
    if v_existing.profile_id is distinct from p_profile_id then
      return jsonb_build_object('result', 'token_used');
    end if;
    return jsonb_build_object(
      'result', 'already_granted', 'hearts', v_existing.heart_amount, 'bonus_hearts', v_existing.bonus_hearts,
      'heart_balance', (select heart_balance from public.entitlements where profile_id = p_profile_id));
  end if;

  -- ② 첫 구매 보너스: 100하트 이상 상품이고, 이 사람이 100하트 이상 상품을 산 적이 없을 때만(환불된 것도 센다).
  --    50하트만 산 기록은 자격을 없애지 않는다(2026-11-12 결정).
  if v_hearts >= c_bonus_min_hearts
     and not exists (select 1 from public.purchases
                      where profile_id = p_profile_id and heart_amount >= c_bonus_min_hearts) then
    v_bonus := c_bonus;
  end if;

  insert into public.purchases
    (profile_id, store, product_id, store_order_id, token_hash, heart_amount, bonus_hearts, price_krw, is_test, purchased_at)
  values
    (p_profile_id, p_store, p_product_id, p_order_id, p_token_hash, v_hearts, v_bonus, v_price, p_is_test, p_purchased_at)
  on conflict on constraint purchases_token_once do nothing
  returning id into v_id;
  if v_id is null then
    -- 잠금이 사람마다라 같은 사람은 ①에서 이미 돌아갔다 — 여기 오는 것은 다른 사람이 먼저 넣은 영수증뿐
    return jsonb_build_object('result', 'token_used');
  end if;

  -- ③ 하트(구매분)와 보너스는 원장을 나눠 적는다(보너스안 §4). 두 줄 모두 ref_id = 구매 행 id
  perform public.grant_hearts(p_profile_id, v_hearts, 'purchase', v_id);
  if v_bonus > 0 then
    perform public.grant_hearts(p_profile_id, v_bonus, 'first_purchase_bonus', v_id);
  end if;

  return jsonb_build_object(
    'result', 'granted', 'hearts', v_hearts, 'bonus_hearts', v_bonus,
    'heart_balance', (select heart_balance from public.entitlements where profile_id = p_profile_id));
end;
$$;

comment on function public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean) is
  '검증된 스토어 구매 한 건을 지급한다. 결과는 granted · already_granted · token_used · unknown_product. 첫 구매 보너스 = 100하트 이상 상품을 산 적이 없는 사람의 100하트 이상 구매(환불된 것도 센다)';

-- create or replace 는 권한을 그대로 두지만, 처음 정의와 같은 권한(service_role 만 부른다)을 다시 적어 둔다.
revoke all on function public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)
  from public, anon, authenticated;
grant execute on function public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)
  to service_role;
