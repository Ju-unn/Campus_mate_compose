-- 인앱결제(하트 구매, 안드로이드 먼저). 계획서 바탕화면 출시준비/인앱결제_구현계획_초안.md §4. 기준: docs/ERD.md §6 purchases 제안 · §11-14.
-- 쓰는 곳은 서버(service_role)의 DB 함수 둘뿐이다(backend/app/billing/repository.py). 앱은 본인 행을 읽기만 한다.
-- 두 함수는 security invoker 다(SUPABASE.md §5) — 부르는 service_role 이 표 권한을 가진다. 그래서 revoke 대상은
-- public · anon · authenticated 이고 service_role 에만 execute 를 준다(purchase_paid_card 와 같다).
create type public.store_platform as enum ('play_store', 'app_store');
-- 대기(pending) 결제는 행을 만들지 않는다 — 지급 전이라 기록할 것이 없고, 앱이 결제됨이 되면 다시 보낸다.
create type public.purchase_status as enum ('granted', 'refunded');

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  -- 탈퇴 30일 뒤 계정이 지워지면 null(구매자 식별 없이 5년 보관, ERD §11-14 · 결정 I-2)
  profile_id uuid references public.profiles (id) on delete set null,
  store public.store_platform not null,
  product_id text not null,
  -- 구글 주문 번호(GPA.…). 문의 대응용. 없을 수 있다
  store_order_id text,
  -- 구매 토큰 원문은 두지 않는다(서비스 계정과 함께면 조회 · 소비가 되는 값). sha256 16진수
  token_hash text not null,
  heart_amount integer not null,
  bonus_hearts integer not null default 0,
  -- 서버 상품표의 판매가(원). 실제 청구액은 스토어 통화 · 세금에 따라 다를 수 있다
  price_krw integer not null,
  status public.purchase_status not null default 'granted',
  -- 라이선스 테스터 결제(purchaseType 0). 매출에서 빼고, 계정이 지워지면 서버가 지운다(결정 I-9)
  is_test boolean not null default false,
  -- 환불 때 실제로 회수한 하트(이미 쓴 하트는 회수하지 못한다, 결정 I-1)
  clawed_back_hearts integer,
  purchased_at timestamptz not null,
  granted_at timestamptz not null default now(),
  refunded_at timestamptz,

  constraint purchases_token_once unique (store, token_hash),
  constraint purchases_token_hash_shape check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint purchases_amounts_valid check (heart_amount > 0 and bonus_hearts >= 0 and price_krw > 0),
  constraint purchases_refund_consistent check ((status = 'refunded') = (refunded_at is not null))
);

comment on table public.purchases is
  '인앱결제 기록. 탈퇴해도 지우지 않는다(profile_id 만 null, 5년 뒤 서버가 지움 — ERD §11-14). 쓰기는 grant_store_purchase · refund_store_purchase 뿐';

-- 상점 첫 구매 자격(GET /billing/status) · RLS 소유자 조건 · 탈퇴 set null 이 모두 이 칸으로 찾는다.
create index purchases_profile_id_index on public.purchases (profile_id);

alter table public.purchases enable row level security;

create policy "purchases are readable by owner"
  on public.purchases for select to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.purchases from anon, authenticated, service_role;
grant select on table public.purchases to authenticated;
grant select, insert, update, delete on table public.purchases to service_role;

-- 지급: 구매 행 + 하트 + 첫 구매 판정 + 보너스 + 원장을 한 트랜잭션에(유료약관 3-2 원자성).
-- 돌려주는 값(jsonb):
--   {"result":"granted","hearts":h,"bonus_hearts":b,"heart_balance":n}
--   {"result":"already_granted",…같은 칸}   같은 사람이 같은 영수증을 또 보냈다(하트는 그대로)
--   {"result":"token_used"}                  다른 사람이 이미 쓴 영수증
--   {"result":"unknown_product"}
-- 동시성: 사람마다 advisory lock 으로 줄을 세운다 — 두 기기에서 동시에 첫 구매를 해도 보너스는 한 번.
-- 다른 사람끼리 같은 토큰은 unique + on conflict 가 막는다(먼저 넣은 쪽이 끝나길 기다렸다가 do nothing).
create function public.grant_store_purchase(
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

  -- ② 첫 구매: 이 사람의 구매 기록이 하나도 없고(환불된 것도 센다) 100하트 이상일 때만(결정 I-6)
  if v_hearts >= c_bonus_min_hearts
     and not exists (select 1 from public.purchases where profile_id = p_profile_id) then
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
  '검증된 스토어 구매 한 건을 지급한다. 결과는 granted · already_granted · token_used · unknown_product';

-- 환불 회수: 구매분 + 보너스를 min(잔액, 합계)만 회수(결정 I-1 · 보너스안 §4). 잔액은 음수가 되지 않는다.
-- 원장은 기존 사유 'refund' 음수 한 줄(ref_id = 구매 행 id) — 회수가 0 이면 줄을 만들지 않는다(amount <> 0 제약).
-- 돌려주는 값: {"result":"refunded","profile_id":…,"clawed_back":n,"shortfall":m} · {"result":"already_refunded"} · {"result":"unknown"}
-- unknown = 우리가 지급한 적 없는 영수증(확인 전에 자동 환불된 것 등). 할 일이 없다.
create function public.refund_store_purchase(p_store public.store_platform, p_token_hash text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_purchase public.purchases;
  v_balance integer;
  v_owed integer;
  v_take integer := 0;
begin
  select * into v_purchase from public.purchases
  where store = p_store and token_hash = p_token_hash
  for update;
  if not found then
    return jsonb_build_object('result', 'unknown');
  end if;
  if v_purchase.status = 'refunded' then
    return jsonb_build_object('result', 'already_refunded');
  end if;

  v_owed := v_purchase.heart_amount + v_purchase.bonus_hearts;
  if v_purchase.profile_id is not null then
    -- 잔액 행을 잠근 채 읽는다 — 읽고 빼는 사이에 다른 차감이 끼면 음수 금지(23514)에 걸린다
    select heart_balance into v_balance from public.entitlements
    where profile_id = v_purchase.profile_id
    for update;
    v_take := least(coalesce(v_balance, 0), v_owed);
    if v_take > 0 then
      perform public.grant_hearts(v_purchase.profile_id, -v_take, 'refund', v_purchase.id);
    end if;
  end if;

  update public.purchases
  set status = 'refunded', refunded_at = now(), clawed_back_hearts = v_take
  where id = v_purchase.id;

  return jsonb_build_object(
    'result', 'refunded', 'profile_id', v_purchase.profile_id, 'clawed_back', v_take,
    -- 계정이 지워진 구매는 회수할 사람이 없다 — 모자람으로 세지 않는다
    'shortfall', case when v_purchase.profile_id is null then 0 else v_owed - v_take end);
end;
$$;

comment on function public.refund_store_purchase(public.store_platform, text) is
  '스토어 환불 한 건의 하트를 회수한다. 결과는 refunded · already_refunded · unknown';

revoke all on function public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)
  from public, anon, authenticated;
grant execute on function public.grant_store_purchase(uuid, public.store_platform, text, text, text, timestamptz, boolean)
  to service_role;
revoke all on function public.refund_store_purchase(public.store_platform, text) from public, anon, authenticated;
grant execute on function public.refund_store_purchase(public.store_platform, text) to service_role;
