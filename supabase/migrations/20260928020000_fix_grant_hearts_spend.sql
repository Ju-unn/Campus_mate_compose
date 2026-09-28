-- 하트 쓰기(음수)가 잔액과 상관없이 늘 막히던 것 고침(계획서 2026-09-27-me-edit.md 3절 · D9, 2026-09-28).
-- insert ... on conflict do update 는 entitlements check(heart_balance >= 0)를 충돌 처리 전에 **제안 행**
-- (heart_balance = p_amount)에 건다 — 음수면 잔액 320 에서 10 을 써도 23514. 행을 0 으로 보장한 뒤 update 로 더한다.
-- 이름 · 인자 · 반환 · 권한은 그대로다(create or replace 는 grant 를 지키고, search_path 는 다시 적어야 한다 —
-- 20260920061752_fix_slice2_advisor_warnings.sql). 적립(양수)은 동작이 같다. 모자라면 23514 가 원장까지 함수째 되돌린다.
create or replace function public.grant_hearts(p_profile_id uuid, p_amount integer, p_reason public.heart_reason, p_ref_id uuid default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into public.heart_transactions (profile_id, amount, reason, ref_id)
  values (p_profile_id, p_amount, p_reason, p_ref_id);

  insert into public.entitlements (profile_id) values (p_profile_id)
  on conflict (profile_id) do nothing;

  update public.entitlements
    set heart_balance = heart_balance + p_amount, updated_at = now()
    where profile_id = p_profile_id;
end;
$$;
