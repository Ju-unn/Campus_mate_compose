-- 관리자 웹 대시보드 D1(설계 바탕화면 관리자_대시보드_설계_10-18.md §8 머리 · §8-1): 인증샷 승인 · 반려와 작업 기록을 한 번에.
-- 서버는 PostgREST(HTTP)로만 붙어 요청 두 번이 한 트랜잭션이 되지 않는다 — 그래서 조건부 update 와 admin_actions insert 를
-- 함수 하나에 둔다. 기록이 실패하면 검수 · 지급도 함께 되돌아간다(기록 없는 조치 금지).
-- 하트 지급은 기존 트리거 heart_task_submissions_grant(20260928030100)가 같은 트랜잭션에서 한다 — 여기서 grant_hearts 를 부르지 않는다.
-- 검수 시각(reviewed_at)도 기존 guard 트리거가 찍는다.
-- 오류: 규칙 위반 22023(서버 422) · 없음 CM404(서버 404) · 이미 검수됨 CM409(서버 409).
-- 시험: supabase/tests/admin_heart_task_review_test.sql

create function public.admin_review_heart_task(
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

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke all on function public.admin_review_heart_task(
  uuid, uuid, public.submission_status, public.heart_task_reject_reason, inet) from public, anon, authenticated;
grant execute on function public.admin_review_heart_task(
  uuid, uuid, public.submission_status, public.heart_task_reject_reason, inet) to service_role;
