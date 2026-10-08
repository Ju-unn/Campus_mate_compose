-- 소셜 로그인 뒤 탈퇴(사용자 승인 10-08, 서버 #426 검토): 이메일 해시가 없는 계정도 탈퇴할 수 있게 한다.
-- 카카오는 계정 메일이 없고, 학교 메일 인증 전에 나가는 계정은 school_email_claims 해시도 없다. 서버는 앞으로 claims 의
-- 해시를 넘기고 없으면 null 을 넘긴다 — 지금 본문은 signup_blocks(email_hmac PK)에 null 을 넣으려다 23502 로 실패해
-- 탈퇴가 500 이 된다. null 이면 재가입 제한만 건너뛰고 상태 · withdrawn_at 은 그대로 바꾼다.
-- 인증 전 계정은 학교 메일을 쓴 적이 없으니 막을 메일도 없다(소셜 계정 자체로 다시 가입하는 것은 막지 않는다).
-- 바뀐 곳은 insert 를 if 로 감싼 것뿐이다. 서명 · security invoker · search_path · 권한은 20260927030100 과 같다
-- (create or replace 라 권한이 남지만 같은 줄을 다시 적어 둔다). 시험: supabase/tests/slice6_account_test.sql
create or replace function public.withdraw_account(p_profile_id uuid, p_email_hmac bytea, p_key_version smallint)
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

  if p_email_hmac is null then
    return;
  end if;

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
  '탈퇴: status=withdrawn · withdrawn_at 과 재가입 제한(정지 중이면 무기한, 아니면 2개월)을 한 트랜잭션에서. 멱등. FastAPI 전용. '
  '이메일 해시가 없는 계정(학교 메일 인증 전, 이메일 없는 소셜)은 재가입 제한을 남기지 않는다(p_email_hmac null)';

revoke all on function public.withdraw_account(uuid, bytea, smallint) from public, anon, authenticated;
grant execute on function public.withdraw_account(uuid, bytea, smallint) to service_role;
