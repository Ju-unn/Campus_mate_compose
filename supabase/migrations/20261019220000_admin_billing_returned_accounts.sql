-- 관리자 결제 화면 "환불이 잦은 계정"(서버 GET /admin/billing/frequent-returns — 경로는 e2e 금지어 'refund' 를 피했다).
-- 환불된 실제 구매를 계정별로 묶는다. 규칙은 admin_billing_shortfall(20261018120000)과 같다: 시험 결제(is_test) 제외,
-- 계정이 지워진 구매(profile_id null — 회수할 사람이 없다) 제외, 회수 null 은 0, 금액은 구매 행의 판매가(price_krw, admin_billing_daily 와 같음).
-- 정렬: 환불 건수 많은 순 → 못 거둔 하트 많은 순 → 마지막 환불 최근 순. 읽기만 한다.
-- 시험: supabase/tests/admin_users_billing_test.sql 7절
create function public.admin_billing_returned_accounts(p_limit integer)
returns table (
  profile_id uuid, nickname text, refund_count integer, refunded_krw bigint, granted_hearts integer,
  clawed_back_hearts integer, shortfall_hearts integer, last_refunded_at timestamptz
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
  select p.profile_id, pr.nickname, count(*)::integer, sum(p.price_krw)::bigint,
         sum(p.heart_amount + p.bonus_hearts)::integer, sum(coalesce(p.clawed_back_hearts, 0))::integer,
         sum(p.heart_amount + p.bonus_hearts - coalesce(p.clawed_back_hearts, 0))::integer, max(p.refunded_at)
    from public.purchases p
    join public.profiles pr on pr.id = p.profile_id
   where p.status = 'refunded'
     and not p.is_test
   group by p.profile_id, pr.nickname
   order by 3 desc, 7 desc, 8 desc, 1
   limit p_limit;
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke all on function public.admin_billing_returned_accounts(integer) from public, anon, authenticated;
grant execute on function public.admin_billing_returned_accounts(integer) to service_role;
