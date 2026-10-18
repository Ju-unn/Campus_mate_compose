-- 관리자 웹 대시보드 D2b(설계 바탕화면 관리자_대시보드_설계_10-18.md §8-2 "W2 주의(보안 검토 10-18, 낮음 8)" · "후속(D3 계획 10-18)"):
--  1. 같은 대상 함께 닫기(admin_resolve_report)와 자동 가림 해제(admin_unhide_profile)가 운영자가 상세를 연 **뒤에 들어온 새 신고**까지
--     닫던 것을, 운영자가 **본 신고 id 목록(p_seen)** 에 든 것만 닫게 고친다. 시각(fetched_at) 대신 id 목록을 쓴다 — 시각은
--     신고의 created_at(DB now())과 API 서버 시계를 견주게 되어 시계가 어긋나면 새 신고를 놓치거나 본 신고를 남기고, 긴 트랜잭션이
--     늦게 커밋되면 created_at 이 fetched_at 보다 앞서기도 한다. id 목록은 시계가 없고 "운영자가 본 것" 이 작업 기록에 그대로 남는다.
--  2. 관리자 계정(admin_users)은 정지할 수 없다 — 사용자 기능에서 존재하지 않는 것으로 본다(설계 §6-5, D3 하트 조정 · 탈퇴 대행과 같은 CM404).
-- 오류 약속은 D2 와 같다: 규칙 위반 22023(서버 422) · 없음 CM404(서버 404) · 이미 그 상태 CM409(서버 409) · 관리자 아님 42501(서버 403).
-- p_seen 이 없으면(null) 함께 닫기 · 가림 해제는 22023 이다 — 옛 호출이 "그 사람의 열린 신고 전부" 로 되돌아가지 않게. 빈 배열은
-- "본 신고 없음" 이라 통과한다(가림 해제 = 시각만 비움, 함께 닫기 = 이 신고만 닫음).
-- 인자 수가 바뀌어 옛 시그니처는 drop 한다(create or replace 는 새 오버로드를 만들어 옛 "전부 닫기" 함수가 살아남는다).
-- D2 마이그레이션(20261018030000 · 20261018035204)은 운영 미적용이라 옛 함수를 부르는 곳이 없다.
-- 시험: supabase/tests/admin_report_followups_test.sql (+ 인자를 맞춘 admin_report_review_test.sql)

drop function public.admin_resolve_report(uuid, uuid, public.report_status, text, boolean, inet);
drop function public.admin_unhide_profile(uuid, uuid, text, inet);

-- 1. 신고 닫기(조치 완료 / 기각). p_same_target 이면 같은 사람의 다른 열린 신고 중 p_seen(운영자가 본 신고 id)에 든 것도 같은 결과로 닫는다.
create function public.admin_resolve_report(
  p_admin uuid,
  p_report uuid,
  p_outcome public.report_status,
  p_note text,
  p_same_target boolean,
  p_ip inet,
  p_seen uuid[] default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_target uuid;
  v_closed jsonb;
begin
  perform public.admin_assert(p_admin);
  if p_outcome is null or p_outcome = 'open' then
    raise exception 'invalid report outcome' using errcode = '22023';
  end if;
  if coalesce(p_same_target, false) and p_seen is null then
    raise exception 'seen reports required' using errcode = '22023';
  end if;

  -- 신고당한 사람은 바뀌지 않는다(그 계정이 지워질 때 null 이 될 뿐) — 잠그기 전에 읽어도 된다.
  select target_profile_id into v_target from public.reports where id = p_report;
  if not found then
    raise exception 'report not found' using errcode = 'CM404';
  end if;

  -- 이 신고와(함께 닫기면) 같은 사람의 열린 신고 중 본 것을 **한 문장에서 id 순으로** 잠근다. 이 신고만 먼저 잠그고 나머지를 잠그면
  -- 두 관리자가 같은 사람의 서로 다른 신고를 동시에 함께 닫을 때 서로 반대 순서로 기다려 교착(40P01 → 500)이 난다.
  -- 가림 해제(admin_unhide_profile)도 신고를 같은 순서로 잠근다. 이 함수는 프로필을 잠그지 않는다(프로필 → 신고 순서는 해제 쪽만).
  perform 1 from public.reports
   where id = p_report
      or (coalesce(p_same_target, false) and target_profile_id = v_target and status = 'open' and id = any(p_seen))
   order by id
   for update;

  -- 잠근 뒤 새 문장(새 스냅숏)으로 본다 — 동시에 먼저 닫은 관리자가 있으면 그 커밋을 기다린 뒤 여기서 CM409 가 된다.
  if not exists (select 1 from public.reports where id = p_report and status = 'open') then
    raise exception 'report already resolved' using errcode = 'CM409';
  end if;

  -- 대상 계정이 지워져 target_profile_id 가 null 이면 "= null" 이 참이 되지 않아 그 건만 닫힌다. p_seen 에 남의 신고 id 가
  -- 섞여 와도 target_profile_id = v_target 이 한 번 더 거른다. 운영자가 보지 못한(p_seen 에 없는) 열린 신고는 그대로 열려 있다.
  with closed as (
    update public.reports
       set status = p_outcome, resolved_at = now()
     where status = 'open'
       and (id = p_report
            or (coalesce(p_same_target, false) and target_profile_id = v_target and id = any(p_seen)))
    returning id
  ), logged as (
    -- 닫힌 신고마다 한 줄 — 신고 한 건의 기록을 대상(target_type, target_id) 인덱스로 바로 찾는다. 메모는 reason 칸에.
    insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
    select p_admin, 'report_resolve', 'report', id::text,
           jsonb_build_object('status', 'open'), jsonb_build_object('status', p_outcome), p_note, p_ip
      from closed
    returning target_id
  )
  select jsonb_agg(target_id order by target_id) into v_closed from logged;

  return jsonb_build_object('id', p_report, 'status', p_outcome, 'closed_ids', v_closed);
end;
$$;

-- 2. 정지. 20261018035204 의 것 그대로 + 대상이 관리자 계정이면 "없는 프로필" 과 같은 CM404(D3 admin_adjust_hearts 와 같은 방식).
create or replace function public.admin_suspend_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_before public.profile_status;
begin
  perform public.admin_assert(p_admin);
  if nullif(btrim(p_reason), '') is null then
    raise exception 'reason required' using errcode = '22023';
  end if;

  select status into v_before from public.profiles where id = p_profile for update;
  if not found or exists (select 1 from public.admin_users where user_id = p_profile) then
    raise exception 'profile not found' using errcode = 'CM404';
  end if;
  -- 이미 정지됐거나 탈퇴한 계정은 정지하지 않는다.
  if v_before not in ('pending', 'active') then
    raise exception 'profile cannot be suspended' using errcode = 'CM409';
  end if;

  update public.profiles set status = 'suspended' where id = p_profile;

  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
  values (p_admin, 'profile_suspend', 'profile', p_profile::text,
          jsonb_build_object('status', v_before), jsonb_build_object('status', 'suspended'), p_reason, p_ip);

  return jsonb_build_object('id', p_profile, 'status', 'suspended');
end;
$$;

-- 3. 자동 가림 해제. 시각만 지우면 열린 신고가 그대로라 다음 신고 한 건에 다시 가려진다(safety/router.py ⑦ 이 열린 신고의 서로 다른
-- 신고자 수로 센다) — 그래서 같은 함수에서 운영자가 본 열린 신고(p_seen)를 기각한다. 상세를 연 뒤 들어온 새 신고는 열린 채 남아
-- 가림이 풀린 뒤에도 가림 기준(열린 신고자 수)에 그대로 센다.
create function public.admin_unhide_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet, p_seen uuid[])
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_hidden_at timestamptz;
  v_dismissed jsonb;
begin
  perform public.admin_assert(p_admin);
  if nullif(btrim(p_reason), '') is null or p_seen is null then
    raise exception 'reason and seen reports required' using errcode = '22023';
  end if;

  select auto_hidden_at into v_hidden_at from public.profiles where id = p_profile for update;
  if not found then
    raise exception 'profile not found' using errcode = 'CM404';
  end if;
  if v_hidden_at is null then
    raise exception 'profile is not hidden' using errcode = 'CM409';
  end if;

  update public.profiles set auto_hidden_at = null where id = p_profile;

  -- 잠금 순서: 프로필(위) → 신고(id 순, admin_resolve_report 와 같은 순서) — 함께 닫기와 동시에 눌려도 교착이 나지 않게.
  perform 1 from public.reports
   where target_profile_id = p_profile and status = 'open' and id = any(p_seen)
   order by id
   for update;

  with closed as (
    update public.reports
       set status = 'dismissed', resolved_at = now()
     where target_profile_id = p_profile and status = 'open' and id = any(p_seen)
    returning id
  ), logged as (
    insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
    select p_admin, 'report_resolve', 'report', id::text, jsonb_build_object('status', 'open'),
           jsonb_build_object('status', 'dismissed', 'via', 'profile_unhide'), p_reason, p_ip
      from closed
    returning target_id
  )
  select coalesce(jsonb_agg(target_id order by target_id), '[]'::jsonb) into v_dismissed from logged;

  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
  values (p_admin, 'profile_unhide', 'profile', p_profile::text,
          jsonb_build_object('auto_hidden_at', v_hidden_at), jsonb_build_object('auto_hidden_at', null), p_reason, p_ip);

  return jsonb_build_object('id', p_profile, 'auto_hidden_at', null, 'dismissed_ids', v_dismissed);
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
-- (create or replace 한 admin_suspend_profile 은 20261018030000 의 revoke / grant 가 그대로 이어지지만 한 번 더 못박는다.)
revoke all on function public.admin_resolve_report(
  uuid, uuid, public.report_status, text, boolean, inet, uuid[]) from public, anon, authenticated;
grant execute on function public.admin_resolve_report(
  uuid, uuid, public.report_status, text, boolean, inet, uuid[]) to service_role;

revoke all on function public.admin_suspend_profile(uuid, uuid, text, inet) from public, anon, authenticated;
grant execute on function public.admin_suspend_profile(uuid, uuid, text, inet) to service_role;

revoke all on function public.admin_unhide_profile(uuid, uuid, text, inet, uuid[]) from public, anon, authenticated;
grant execute on function public.admin_unhide_profile(uuid, uuid, text, inet, uuid[]) to service_role;
