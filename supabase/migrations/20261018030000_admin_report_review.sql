-- 관리자 웹 대시보드 D2(설계 바탕화면 관리자_대시보드_설계_10-18.md §8 머리 · §8-2): 신고 닫기 · 정지 · 해제 · 자동 가림 해제 ·
-- 투표 글과 지인 리뷰 가림을 작업 기록과 한 번에. 서버는 PostgREST(HTTP)로만 붙어 요청 두 번이 한 트랜잭션이 되지 않는다 —
-- 그래서 바꾸기와 admin_actions insert 를 함수 하나에 둔다. 기록이 실패하면 바꾼 것도 함께 되돌아간다(기록 없는 조치 금지).
-- 모두 대상 행을 select … for update 로 잡는다: 두 관리자가 같은 건을 동시에 누르면 두 번째는 첫 번째 커밋을 기다렸다가
-- 조건을 다시 보고 CM409 가 된다.
-- 오류: 규칙 위반 22023(서버 422) · 없음 CM404(서버 404) · 이미 그 상태 CM409(서버 409).
-- "같은 대상" = 같은 reports.target_profile_id — 자동 가림이 세는 기준(backend/app/safety/repository.py count_open_reporters)과 같다.
-- 시험: supabase/tests/admin_report_review_test.sql

-- 1. 신고 닫기(조치 완료 / 기각). p_same_target 이면 같은 사람을 향한 다른 열린 신고도 같은 결과로 닫는다.
create function public.admin_resolve_report(
  p_admin uuid,
  p_report uuid,
  p_outcome public.report_status,
  p_note text,
  p_same_target boolean,
  p_ip inet
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
  if p_outcome is null or p_outcome = 'open' then
    raise exception 'invalid report outcome' using errcode = '22023';
  end if;

  -- 신고당한 사람은 바뀌지 않는다(그 계정이 지워질 때 null 이 될 뿐) — 잠그기 전에 읽어도 된다.
  select target_profile_id into v_target from public.reports where id = p_report;
  if not found then
    raise exception 'report not found' using errcode = 'CM404';
  end if;

  -- 이 신고와(함께 닫기면) 같은 사람의 열린 신고를 **한 문장에서 id 순으로** 잠근다. 이 신고만 먼저 잠그고 나머지를 잠그면
  -- 두 관리자가 같은 사람의 서로 다른 신고를 동시에 함께 닫을 때 서로 반대 순서로 기다려 교착(40P01 → 500)이 난다.
  -- 가림 해제(admin_unhide_profile)도 신고를 같은 순서로 잠근다. 이 함수는 프로필을 잠그지 않는다(프로필 → 신고 순서는 해제 쪽만).
  perform 1 from public.reports
   where id = p_report
      or (coalesce(p_same_target, false) and target_profile_id = v_target and status = 'open')
   order by id
   for update;

  -- 잠근 뒤 새 문장(새 스냅숏)으로 본다 — 동시에 먼저 닫은 관리자가 있으면 그 커밋을 기다린 뒤 여기서 CM409 가 된다.
  if not exists (select 1 from public.reports where id = p_report and status = 'open') then
    raise exception 'report already resolved' using errcode = 'CM409';
  end if;

  -- 대상 계정이 지워져 target_profile_id 가 null 이면 "= null" 이 참이 되지 않아 그 건만 닫힌다.
  with closed as (
    update public.reports
       set status = p_outcome, resolved_at = now()
     where status = 'open'
       and (id = p_report or (coalesce(p_same_target, false) and target_profile_id = v_target))
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

-- 2. 정지. 정지는 profiles.status 뿐이다(기간 · 사유 칸 없음, 설계 §2) — 사유는 기록에, 직전 상태는 기록 before 에.
create function public.admin_suspend_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_before public.profile_status;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'reason required' using errcode = '22023';
  end if;

  select status into v_before from public.profiles where id = p_profile for update;
  if not found then
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

-- 3. 정지 해제. active 고정이 아니라 정지 직전 상태로(설계 §8-2): 온보딩 전 계정을 active 로 올리면
-- profiles_active_requires_onboarding 이 23514 로 막고, pending 이던 계정을 active 로 올리면 가입 단계를 건너뛴다.
create function public.admin_unsuspend_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.profile_status;
  v_onboarded boolean;
  v_after public.profile_status;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'reason required' using errcode = '22023';
  end if;

  select status,
         nickname is not null and gender is not null and birth_year is not null and height_cm is not null
    into v_status, v_onboarded
    from public.profiles where id = p_profile for update;
  if not found then
    raise exception 'profile not found' using errcode = 'CM404';
  end if;
  if v_status <> 'suspended' then
    raise exception 'profile is not suspended' using errcode = 'CM409';
  end if;

  -- 대시보드로 정지했으면 그때 남긴 직전 상태. 대시보드 이전에 SQL 로 정지해 기록이 없으면(select 가 0줄 → null)
  -- 온보딩 체크의 네 칸(20260920043514)을 채웠는지로 active / pending. admin_actions_target_created_at_index 를 탄다.
  select (a.before->>'status')::public.profile_status into v_after
    from public.admin_actions a
   where a.target_type = 'profile' and a.target_id = p_profile::text and a.action = 'profile_suspend'
   order by a.created_at desc
   limit 1;
  v_after := coalesce(v_after,
    case when v_onboarded then 'active'::public.profile_status else 'pending'::public.profile_status end);

  update public.profiles set status = v_after where id = p_profile;

  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
  values (p_admin, 'profile_unsuspend', 'profile', p_profile::text,
          jsonb_build_object('status', 'suspended'), jsonb_build_object('status', v_after), p_reason, p_ip);

  return jsonb_build_object('id', p_profile, 'status', v_after);
end;
$$;

-- 4. 자동 가림 해제. 시각만 지우면 열린 신고가 그대로라 다음 신고 한 건에 다시 가려진다 — 신고 경로(safety/router.py ⑦)가
-- 열린 신고의 서로 다른 신고자 수로 세기 때문이다(safety/repository.py count_open_reporters). 그래서 같은 함수에서 그 사람의
-- 열린 신고를 모두 기각한다.
create function public.admin_unhide_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_hidden_at timestamptz;
  v_dismissed jsonb;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'reason required' using errcode = '22023';
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
  perform 1 from public.reports where target_profile_id = p_profile and status = 'open' order by id for update;

  with closed as (
    update public.reports
       set status = 'dismissed', resolved_at = now()
     where target_profile_id = p_profile and status = 'open'
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

-- 5. 투표 글 · 지인 리뷰 가림 / 해제(content_status). 대상 종류는 신고의 report_target 값을 그대로 받는다.
create function public.admin_set_content_status(
  p_admin uuid,
  p_target public.report_target,
  p_content uuid,
  p_status public.content_status,
  p_reason text,
  p_ip inet
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_before public.content_status;
begin
  if p_status is null or nullif(btrim(p_reason), '') is null
     or p_target is null or p_target not in ('poll', 'friend_review') then
    raise exception 'invalid content status change' using errcode = '22023';
  end if;

  if p_target = 'poll' then
    select status into v_before from public.polls where id = p_content for update;
  else
    select status into v_before from public.friend_reviews where id = p_content for update;
  end if;
  if not found then
    raise exception 'content not found' using errcode = 'CM404';
  end if;
  if v_before = p_status then
    raise exception 'content already in that status' using errcode = 'CM409';
  end if;

  if p_target = 'poll' then
    update public.polls set status = p_status where id = p_content;
  else
    update public.friend_reviews set status = p_status where id = p_content;
  end if;

  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
  values (p_admin, case p_status when 'blinded' then 'content_blind' else 'content_unblind' end,
          p_target::text, p_content::text,
          jsonb_build_object('status', v_before), jsonb_build_object('status', p_status), p_reason, p_ip);

  return jsonb_build_object('id', p_content, 'status', p_status);
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke all on function public.admin_resolve_report(
  uuid, uuid, public.report_status, text, boolean, inet) from public, anon, authenticated;
grant execute on function public.admin_resolve_report(
  uuid, uuid, public.report_status, text, boolean, inet) to service_role;

revoke all on function public.admin_suspend_profile(uuid, uuid, text, inet) from public, anon, authenticated;
grant execute on function public.admin_suspend_profile(uuid, uuid, text, inet) to service_role;

revoke all on function public.admin_unsuspend_profile(uuid, uuid, text, inet) from public, anon, authenticated;
grant execute on function public.admin_unsuspend_profile(uuid, uuid, text, inet) to service_role;

revoke all on function public.admin_unhide_profile(uuid, uuid, text, inet) from public, anon, authenticated;
grant execute on function public.admin_unhide_profile(uuid, uuid, text, inet) to service_role;

revoke all on function public.admin_set_content_status(
  uuid, public.report_target, uuid, public.content_status, text, inet) from public, anon, authenticated;
grant execute on function public.admin_set_content_status(
  uuid, public.report_target, uuid, public.content_status, text, inet) to service_role;
