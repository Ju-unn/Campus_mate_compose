-- 관리자 웹 대시보드 D3(설계 바탕화면 관리자_대시보드_설계_10-18.md §8 머리 · §8-3 · §8-4b · §8-5): 하트 조정 · 탈퇴 대행을 작업 기록과
-- 한 번에, 결제 읽기 둘(30일 그래프 · 못 거둔 하트), 주문 번호 인덱스. 서버는 PostgREST(HTTP)로만 붙어 요청 두 번이 한 트랜잭션이 되지 않는다 —
-- 그래서 바꾸기와 admin_actions insert 를 함수 하나에 둔다. 기록이 실패하면 바꾼 것도 함께 되돌아간다(기록 없는 조치 금지).
-- 오류: 규칙 위반 22023(서버 422) · 없음 CM404(서버 404) · 막힌 상태 CM409(서버 409, message 로 이유를 가른다:
-- 'insufficient hearts' · 'profile withdrawn') · 관리자 아님 42501(서버 403 not_admin, admin_assert).
-- 관리자 계정(admin_users)은 사용자 기능에서 존재하지 않는 것으로 본다(설계 §6-5) — 대상이 관리자면 CM404.
-- 시험: supabase/tests/admin_users_billing_test.sql

-- 1. 하트 조정. 잔액 행을 잠근 채 판단해 사용자가 쓰는 도중에도 음수가 되지 않는다. 기존 grant_hearts 는 음수를 받고(20260928020000),
-- 원장 ref_id 에 이 조정의 작업 기록 id 를 실어 둘을 잇는다.
create function public.admin_adjust_hearts(p_admin uuid, p_profile uuid, p_amount integer, p_reason text, p_ip inet)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  -- 한 번 조정 상한(대장 결정 10-18). 바꾸면 이 줄 · pgTAP 경계값 · 서버 backend/app/admin/user_actions.py ADJUST_MAX 를 같이 고친다.
  c_max_adjust constant integer := 1000;
  v_status public.profile_status;
  v_balance integer;
  v_action uuid;
begin
  perform public.admin_assert(p_admin);
  if p_amount is null or p_amount = 0 or p_amount not between -c_max_adjust and c_max_adjust
     or nullif(btrim(p_reason), '') is null then
    raise exception 'invalid heart adjustment' using errcode = '22023';
  end if;

  select status into v_status from public.profiles where id = p_profile for update;
  if not found or exists (select 1 from public.admin_users where user_id = p_profile) then
    raise exception 'profile not found' using errcode = 'CM404';
  end if;
  if v_status = 'withdrawn' then
    raise exception 'profile withdrawn' using errcode = 'CM409';
  end if;

  select heart_balance into v_balance from public.entitlements where profile_id = p_profile for update;
  v_balance := coalesce(v_balance, 0);
  if p_amount < 0 and v_balance + p_amount < 0 then
    raise exception 'insufficient hearts' using errcode = 'CM409';
  end if;

  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
  values (p_admin, 'hearts_adjust', 'profile', p_profile::text,
          jsonb_build_object('heart_balance', v_balance),
          jsonb_build_object('heart_balance', v_balance + p_amount, 'amount', p_amount), p_reason, p_ip)
  returning id into v_action;

  perform public.grant_hearts(p_profile, p_amount, 'admin_adjust', v_action);

  return jsonb_build_object('id', p_profile, 'amount', p_amount, 'heart_balance', v_balance + p_amount,
                            'action_id', v_action);
end;
$$;

-- 2. 탈퇴 대행(앱 밖 요청). 기존 withdraw_account(상태 + 재가입 제한, 멱등)를 그대로 쓰고 기록을 **맨 마지막**에 둔다 — 기록이 실패하면
-- 탈퇴도 함께 되돌아간다. 푸시 토큰 · 카카오 연결 같은 바깥 정리는 서버가 이 함수가 끝난 뒤 따로 한다.
-- 본인 확인 방법(p_verified_by)은 작업 기록 after 에 남는다(admin_actions 에 칸이 없다). 서버가 '@' 를 막아 메일 원문이 새지 않게 한다.
create function public.admin_close_account(
  p_admin uuid,
  p_profile uuid,
  p_email_hmac bytea,
  p_key_version smallint,
  p_reason text,
  p_verified_by text,
  p_ip inet
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_before public.profile_status;
  v_block text;
begin
  perform public.admin_assert(p_admin);
  if nullif(btrim(p_reason), '') is null or nullif(btrim(p_verified_by), '') is null
     or char_length(btrim(p_verified_by)) > 200 then
    raise exception 'reason and verified_by required' using errcode = '22023';
  end if;

  select status into v_before from public.profiles where id = p_profile for update;
  if not found or exists (select 1 from public.admin_users where user_id = p_profile) then
    raise exception 'profile not found' using errcode = 'CM404';
  end if;
  if v_before = 'withdrawn' then
    raise exception 'profile withdrawn' using errcode = 'CM409';
  end if;

  perform public.withdraw_account(p_profile, p_email_hmac, p_key_version);

  -- withdraw_account 의 재가입 제한 규칙과 같다(20261008040000): 해시 없으면 제한 없음, 정지 중이면 무기한, 아니면 2개월.
  v_block := case when p_email_hmac is null then 'none'
                  when v_before = 'suspended' then 'forever'
                  else 'two_months' end;

  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
  values (p_admin, 'account_close', 'profile', p_profile::text,
          jsonb_build_object('status', v_before),
          jsonb_build_object('status', 'withdrawn', 'rejoin_blocked', v_block, 'verified_by', btrim(p_verified_by)),
          p_reason, p_ip);

  return jsonb_build_object('id', p_profile, 'was_status', v_before, 'status', 'withdrawn', 'rejoin_blocked', v_block);
end;
$$;

-- 3. 결제 그래프. 날짜는 한국 시간 하루 단위이고 항상 p_days 줄(없는 날 0)이다. 시험 결제(is_test)는 어느 칸에도 넣지 않고,
-- 환불된 구매는 매출 · 건수에서 빼고 refunded_krw 에만 센다. 금액은 서버 상품표의 판매가(price_krw)다. 읽기만 한다.
create function public.admin_billing_daily(p_days integer)
returns table (day date, revenue_krw bigint, order_count integer, refunded_krw bigint)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if p_days is null or p_days < 1 or p_days > 90 then
    raise exception 'p_days must be between 1 and 90' using errcode = '22023';
  end if;

  return query
  with sales as (
    select (p.purchased_at at time zone 'Asia/Seoul')::date as d,
           coalesce(sum(p.price_krw) filter (where p.status = 'granted'), 0)::bigint as rev,
           (count(*) filter (where p.status = 'granted'))::integer as cnt,
           coalesce(sum(p.price_krw) filter (where p.status = 'refunded'), 0)::bigint as ref
      from public.purchases p
     where not p.is_test
       and p.purchased_at >= ((v_today - (p_days - 1))::timestamp at time zone 'Asia/Seoul')
     group by 1
  )
  select v_today - (p_days - 1) + g.i, coalesce(s.rev, 0::bigint), coalesce(s.cnt, 0), coalesce(s.ref, 0::bigint)
    from generate_series(0, p_days - 1) as g(i)
    left join sales s on s.d = v_today - (p_days - 1) + g.i
   order by 1;
end;
$$;

-- 4. 못 거둔 하트: 환불됐는데 이미 써서 다 못 거둔 실제 구매(환불 함수 refund_store_purchase 의 shortfall 과 같은 규칙).
-- 계정이 지워진 구매(회수할 사람이 없다)와 시험 결제는 뺀다. PostgREST 로는 두 열(지급 합 − 회수)을 비교할 수 없어 함수로 둔다.
create function public.admin_billing_shortfall(p_limit integer)
returns table (
  purchase_id uuid, profile_id uuid, nickname text, store public.store_platform, product_id text,
  heart_amount integer, bonus_hearts integer, clawed_back_hearts integer,
  granted_hearts integer, shortfall_hearts integer, purchased_at timestamptz, refunded_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'p_limit must be between 1 and 500' using errcode = '22023';
  end if;

  return query
  select p.id, p.profile_id, pr.nickname, p.store, p.product_id, p.heart_amount, p.bonus_hearts, p.clawed_back_hearts,
         p.heart_amount + p.bonus_hearts, p.heart_amount + p.bonus_hearts - coalesce(p.clawed_back_hearts, 0),
         p.purchased_at, p.refunded_at
    from public.purchases p
    join public.profiles pr on pr.id = p.profile_id
   where p.status = 'refunded'
     and not p.is_test
     and coalesce(p.clawed_back_hearts, 0) < p.heart_amount + p.bonus_hearts
   order by p.refunded_at desc, p.id
   limit p_limit;
end;
$$;

-- 5. 주문 번호 정확 일치 조회(구글 주문 번호 · 애플 거래 번호는 같은 칸). 인덱스가 없으면 표 전체를 훑는다.
create index purchases_store_order_id_index on public.purchases (store_order_id) where store_order_id is not null;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke all on function public.admin_adjust_hearts(uuid, uuid, integer, text, inet) from public, anon, authenticated;
grant execute on function public.admin_adjust_hearts(uuid, uuid, integer, text, inet) to service_role;

revoke all on function public.admin_close_account(uuid, uuid, bytea, smallint, text, text, inet)
  from public, anon, authenticated;
grant execute on function public.admin_close_account(uuid, uuid, bytea, smallint, text, text, inet) to service_role;

revoke all on function public.admin_billing_daily(integer) from public, anon, authenticated;
grant execute on function public.admin_billing_daily(integer) to service_role;

revoke all on function public.admin_billing_shortfall(integer) from public, anon, authenticated;
grant execute on function public.admin_billing_shortfall(integer) to service_role;
