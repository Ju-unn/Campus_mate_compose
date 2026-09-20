-- Part B 백엔드 헬퍼가 부르는 RPC 함수 2종. Task C2·C5 마이그레이션에 사후 추가하는 대신 별도 파일로
-- 둔다 — C2·C5가 먼저 merge·클라우드 적용된 뒤에 이 파일이 추가돼도, 이미 적용된 파일을 다시 손대지
-- 않아야 나중에 이 함수들이 클라우드에 누락되는 일이 없다(2026-09-20 대장 리뷰).

-- decrypt_phone_number(Task C2)의 짝. PostgREST 는 컬럼 값에 SQL 표현식(pgp_sym_encrypt 호출)을 직접 못
-- 넣으므로 암호화도 RPC 함수로 한다(Part B `encryption.py` 가 이 함수명을 그대로 부른다).
create or replace function public.set_phone_number(p_profile_id uuid, p_phone text, p_key text)
returns void
language sql
as $$
  update public.profile_private
  set phone_number = extensions.pgp_sym_encrypt(p_phone, p_key), updated_at = now()
  where profile_id = p_profile_id;
$$;

revoke all on function public.set_phone_number(uuid, text, text) from public, anon, authenticated;
grant execute on function public.set_phone_number(uuid, text, text) to service_role;

-- 잔액 캐시(entitlements.heart_balance, Task C5)와 원장(heart_transactions)을 한 트랜잭션에서 같이
-- 써야 하므로(ERD §6), PostgREST 두 번 호출 대신 Postgres 함수로 묶는다(Part B `hearts.py` 가 이
-- 함수명을 그대로 부른다).
create or replace function public.grant_hearts(p_profile_id uuid, p_amount integer, p_reason public.heart_reason, p_ref_id uuid default null)
returns void
language plpgsql
as $$
begin
  insert into public.heart_transactions (profile_id, amount, reason, ref_id)
  values (p_profile_id, p_amount, p_reason, p_ref_id);

  insert into public.entitlements (profile_id, heart_balance, updated_at)
  values (p_profile_id, p_amount, now())
  on conflict (profile_id) do update
    set heart_balance = public.entitlements.heart_balance + excluded.heart_balance,
        updated_at = now();
end;
$$;

revoke all on function public.grant_hearts(uuid, integer, public.heart_reason, uuid) from public, anon, authenticated;
grant execute on function public.grant_hearts(uuid, integer, public.heart_reason, uuid) to service_role;
