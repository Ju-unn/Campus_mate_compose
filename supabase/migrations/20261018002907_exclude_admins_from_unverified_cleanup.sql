-- 관리자 웹 대시보드 D0(설계 바탕화면 관리자_대시보드_설계_10-18.md §6-5): 관리자 계정을 14일 정리 배치에서 뺀다.
-- 관리자는 운영자 전용 구글 계정이라 가입 훅을 통과해 학교 없는 pending 프로필이 생기고, 학교 메일 인증을 하지 않는다 —
-- 그대로 두면 14일 뒤 정리 배치(backend/app/account/batch_router.py run_cleanup ①-b)가 이 함수로 골라 계정을 지운다.
--
-- 20261008030000_create_school_email_claims.sql 의 정의를 그대로 옮기고 admin_users 제외 조건 한 줄만 더했다.
-- 이름 · 인자 · 반환형 · plpgsql · stable · security invoker · search_path '' 는 그대로 — create or replace 라 권한(ACL)도 남는다.
-- 부르는 service_role 은 admin_users select 권한이 있다(20261018002858_create_admin_users).
-- 시험: supabase/tests/admin_foundation_test.sql · social_login_test.sql 5절
create or replace function public.list_unverified_accounts(p_older_than_days integer, p_limit integer default 100)
returns table (id uuid)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_older_than_days is null or p_older_than_days < 1 or p_limit is null or p_limit < 1 then
    raise exception 'list_unverified_accounts: p_older_than_days 와 p_limit 은 1 이상이어야 한다'
      using errcode = '22023';
  end if;

  return query
    select p.id
    from public.profiles p
    where p.school_email_verified_at is null
      and p.created_at < now() - make_interval(days => p_older_than_days)
      and not exists (select 1 from public.admin_users a where a.user_id = p.id)
    order by p.created_at
    limit p_limit;
end;
$$;

comment on function public.list_unverified_accounts(integer, integer) is
  '학교 메일 인증 전 + p_older_than_days 일 지난 프로필 id, 오래된 순 p_limit 개(기본 100). 관리자(admin_users)는 뺀다. '
  '정리 배치(FastAPI) 전용';
