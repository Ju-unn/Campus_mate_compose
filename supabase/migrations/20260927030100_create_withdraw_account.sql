-- 조각 6 탈퇴(계획서 Task B3): 상태를 withdrawn 으로 바꾸고 재가입 제한(signup_blocks)을 넣는다.
-- 부르는 쪽은 FastAPI(service_role) 하나다. 이메일 HMAC 은 FastAPI 가 계산해 넘긴다(키는 DB 에 들이지 않는다).
--
-- 왜 PostgREST 호출 둘이 아니라 함수 하나로 묶는가:
-- ① 상태를 먼저 바꾸고 재가입 제한 삽입이 실패하면, 다시 시도하려 해도 탈퇴 계정은 로그인 관문에서 401 이라
--    영영 제한이 안 들어간다. 한 트랜잭션이면 둘 다 되거나 둘 다 안 된다.
-- ② "정지 중이면 무기한"은 상태를 읽고 쓰는 사이에 운영자가 정지를 걸 수 있어서, 같은 트랜잭션에서
--    for update 로 읽어야 한다.
--
-- 멱등: 프로필이 없거나 이미 withdrawn 이면 아무것도 하지 않는다(재시도해도 제한 기간이 늘거나 줄지 않는다).
-- 예전에 탈퇴했다 재가입한 사람의 만료된 행이 남아 있을 수 있어 on conflict 로 올리되, greatest 로
-- infinity 를 줄이지 않는다.
--
-- security invoker 다 — service_role 이 profiles · signup_blocks 권한을 다 가지고 RLS 를 우회한다.
create function public.withdraw_account(p_profile_id uuid, p_email_hmac bytea, p_key_version smallint)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_status public.profile_status;
begin
  select status into v_status
  from public.profiles
  where id = p_profile_id
  for update;

  if not found or v_status = 'withdrawn' then
    return;
  end if;

  update public.profiles
  set status = 'withdrawn', withdrawn_at = now()
  where id = p_profile_id;

  insert into public.signup_blocks (email_hmac, blocked_until, key_version)
  values (
    p_email_hmac,
    case when v_status = 'suspended' then 'infinity'::timestamptz else now() + interval '2 months' end,
    p_key_version
  )
  on conflict (email_hmac) do update
    set blocked_until = greatest(public.signup_blocks.blocked_until, excluded.blocked_until),
        key_version = excluded.key_version;
end;
$$;

comment on function public.withdraw_account(uuid, bytea, smallint) is
  '탈퇴: status=withdrawn · withdrawn_at 과 재가입 제한(정지 중이면 무기한, 아니면 2개월)을 한 트랜잭션에서. 멱등. FastAPI 전용';

revoke all on function public.withdraw_account(uuid, bytea, smallint) from public, anon, authenticated;
grant execute on function public.withdraw_account(uuid, bytea, smallint) to service_role;
