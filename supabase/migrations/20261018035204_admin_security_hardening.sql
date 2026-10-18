-- 관리자 대시보드 보안 보강(10-18 보안 검토 낮음 13 · 낮음 8).
-- 1. admin_users: 서버(service_role)는 명단을 읽기만 한다(backend/app/admin/repository.py is_admin) — 넣기 · 고치기 · 지우기를 뺀다.
--    서버에 버그가 나도 스스로를 관리자로 넣거나 명단을 지우지 못한다. 등록은 대장이 사용자 승인 뒤 postgres(대시보드 SQL 창)로 한다.
--    auth 계정 삭제의 on delete cascade 는 표 주인 권한으로 돌아 이 권한과 무관하다.
-- 2. admin_assert: 조치 DB 함수 여섯이 p_admin 이 명단에 있는지 스스로 본다 — 서버 버그로 관리자 아닌 id 가 넘어와도
--    조치 · 기록이 남지 않는다. 오류 42501(서버 403 not_admin). security invoker 라 service_role 의 select 권한만으로 읽는다.
-- 3~8. 각 함수는 원본(20261018011200 · 20261018030000)과 서명 · 속성 · 본문이 글자까지 같고 begin 바로 뒤 perform 한 줄만 더했다.
--    create or replace 는 주인과 실행 권한(service_role 만)을 그대로 둔다.
-- 시험: supabase/tests/admin_foundation_test.sql · admin_heart_task_review_test.sql · admin_report_review_test.sql · rls_slice0_test.sql

-- 1. admin_users 는 service_role 에게 읽기만.
revoke insert, update, delete on table public.admin_users from service_role;

-- 2. 명단 확인. 기본 키(user_id) 한 번 찾기다. p_admin 이 null 이어도 "= null" 은 참이 아니라 막는다.
create function public.admin_assert(p_admin uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (select 1 from public.admin_users where user_id = p_admin) then
    raise exception 'not admin' using errcode = '42501';
  end if;
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke all on function public.admin_assert(uuid) from public, anon, authenticated;
grant execute on function public.admin_assert(uuid) to service_role;

-- 3. admin_review_heart_task (원본 20261018011200_admin_review_heart_task.sql 그대로 + 맨 앞 한 줄)
create or replace function public.admin_review_heart_task(
  p_admin uuid,
  p_submission uuid,
  p_status public.submission_status,
  p_reject_reason public.heart_task_reject_reason,
  p_ip inet
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.heart_task_submissions;
begin
  perform public.admin_assert(p_admin);
  -- 승인이면 사유가 없고, 반려면 사유가 있다. 'submitted' 나 null 은 검수가 아니다.
  if p_status is null or p_status = 'submitted' or (p_status = 'approved') = (p_reject_reason is not null) then
    raise exception 'invalid heart task review' using errcode = '22023';
  end if;

  -- 두 탭이 같은 건을 동시에 누르면 두 번째 update 는 첫 번째 커밋을 기다렸다가 status 조건을 다시 보고 0줄이 된다.
  update public.heart_task_submissions
     set status = p_status, reject_reason = p_reject_reason
   where id = p_submission and status = 'submitted'
  returning * into v_row;

  if not found then
    if exists (select 1 from public.heart_task_submissions where id = p_submission) then
      raise exception 'heart task submission already reviewed' using errcode = 'CM409';
    end if;
    raise exception 'heart task submission not found' using errcode = 'CM404';
  end if;

  -- 사진 경로 · 이름은 싣지 않는다. 사유는 고르는 값(enum)이라 after 에 둔다(reason 칸은 관리자가 적는 글자 몫).
  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, ip)
  values (
    p_admin,
    case p_status when 'approved' then 'heart_task_approve' else 'heart_task_reject' end,
    'heart_task_submission',
    p_submission::text,
    jsonb_build_object('status', 'submitted'),
    jsonb_strip_nulls(jsonb_build_object(
      'status', v_row.status, 'reward_hearts', v_row.reward_hearts, 'reject_reason', v_row.reject_reason)),
    p_ip
  );

  return jsonb_build_object(
    'id', v_row.id, 'status', v_row.status, 'reject_reason', v_row.reject_reason,
    'reward_hearts', v_row.reward_hearts, 'reviewed_at', v_row.reviewed_at);
end;
$$;

-- 4. admin_resolve_report (원본 20261018030000_admin_report_review.sql 그대로 + 맨 앞 한 줄)
create or replace function public.admin_resolve_report(
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
  perform public.admin_assert(p_admin);
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

-- 5. admin_suspend_profile (원본 20261018030000_admin_report_review.sql 그대로 + 맨 앞 한 줄)
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

-- 6. admin_unsuspend_profile (원본 20261018030000_admin_report_review.sql 그대로 + 맨 앞 한 줄)
create or replace function public.admin_unsuspend_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)
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
  perform public.admin_assert(p_admin);
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

-- 7. admin_unhide_profile (원본 20261018030000_admin_report_review.sql 그대로 + 맨 앞 한 줄)
create or replace function public.admin_unhide_profile(p_admin uuid, p_profile uuid, p_reason text, p_ip inet)
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

-- 8. admin_set_content_status (원본 20261018030000_admin_report_review.sql 그대로 + 맨 앞 한 줄)
create or replace function public.admin_set_content_status(
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
  perform public.admin_assert(p_admin);
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
