-- 졸업생 인증(졸업증명서) 2/2: 관리자 승인 · 반려 함수와 14일 정리 제외.
-- 앞 파일(20261019200000_graduate_verification_tables)이 먼저 적용돼 있어야 한다. DB 먼저, 서버는 그 뒤에 배포한다 —
-- 서버가 먼저 나가면 프로필 칸 읽기 · 신청 표 쓰기가 칸 없음으로 실패한다.
-- 시험: supabase/tests/graduate_verification_test.sql
--
-- 모든 함수는 security invoker 다(SUPABASE.md §5 — definer 금지). 그래도 Supabase 기본 권한이 새 함수에 anon · authenticated
-- 실행을 주므로 처음부터 public · anon · authenticated 를 모두 걷고 service_role 만 준다.

-- 1. 승인 · 반려 + 작업 기록을 한 트랜잭션에.
--    서버는 PostgREST(HTTP)로만 붙어 요청 두 번이 한 트랜잭션이 되지 않는다 — 신청 줄 · 프로필 · admin_actions 를 함수 하나에 둔다.
--    기록이 실패하면 조치도 함께 되돌아간다(기록 없는 조치 금지).
--    승인: 신청 줄 → approved(학교 · 관리자가 확인한 번호 해시 · 학번 해시, 평문 칸 비움) + 프로필에 학교 메일 인증과 같은 두 칸
--      (university_id · school_email_verified_at) + graduate_verified_at · verification_method. school_email_claims 는 쓰지 않는다.
--    반려: 신청 줄만 rejected(사유 코드)로. 프로필은 그대로(사진 · 평문은 같은 update 에서 비운다).
--    사진 파일은 서버가 이 함수가 성공한 뒤에 지운다(photo_path 는 서버가 비운다 — 못 지우면 매시 배치가 다시 지운다).
--    오류: 규칙 위반 22023(서버 422) · 관리자 아님 42501(403) · 없음 CM404(404) · 충돌 CM409(409, message 가 이유 코드):
--      already_reviewed | already_verified | account_withdrawn | document_reused | student_reused | rejoin_blocked
--    없는 학교는 FK 위반 23503(서버 422).
create function public.admin_review_graduate_request(
  p_admin uuid,
  p_request uuid,
  p_status text,
  p_reason text,
  p_university uuid,
  p_document_hmac bytea,
  p_student_hmac bytea,
  p_key_version smallint,
  p_ip inet
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.graduate_verification_requests;
  v_profile_status public.profile_status;
  v_verified_at timestamptz;
  v_constraint text;
begin
  perform public.admin_assert(p_admin);

  -- 승인에는 사유가 없고 학교 · 문서 해시가 있다(D9: 번호는 승인 때 필수). 반려에는 사유 코드만 있다. 그 밖의 상태는 검수가 아니다.
  if p_status is null or p_status not in ('approved', 'rejected') then
    raise exception 'invalid graduate review' using errcode = '22023';
  end if;
  if p_status = 'approved' and (p_reason is not null or p_university is null or p_document_hmac is null) then
    raise exception 'invalid graduate review' using errcode = '22023';
  end if;
  if p_status = 'rejected' and (
       p_reason is null
       or p_reason not in ('unreadable', 'not_certificate', 'unverifiable', 'school_unsupported')
       or p_university is not null or p_document_hmac is not null or p_student_hmac is not null) then
    raise exception 'invalid graduate review' using errcode = '22023';
  end if;

  -- 같은 건을 두 관리자가 동시에 누르면 두 번째는 첫 번째 커밋을 기다렸다가 상태를 다시 보고 CM409 가 된다.
  select * into v_row
  from public.graduate_verification_requests
  where id = p_request
  for update;
  if not found then
    raise exception 'graduate request not found' using errcode = 'CM404';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'already_reviewed' using errcode = 'CM409';
  end if;

  -- 프로필도 잠근다 — 같은 순간 학교 메일 인증(complete_school_email_verification)이나 탈퇴가 끼어드는 경쟁을 줄 세운다.
  select status, school_email_verified_at into v_profile_status, v_verified_at
  from public.profiles
  where id = v_row.profile_id
  for update;
  if v_profile_status = 'withdrawn' then
    raise exception 'account_withdrawn' using errcode = 'CM409';
  end if;
  if v_verified_at is not null then
    raise exception 'already_verified' using errcode = 'CM409';
  end if;

  -- 학번 해시가 재가입 제한(탈퇴한 졸업생)에 걸려 있으면 승인하지 않는다. 지난 제한은 통과.
  if p_status = 'approved' and p_student_hmac is not null and exists (
       select 1 from public.signup_blocks where email_hmac = p_student_hmac and blocked_until > now()) then
    raise exception 'rejoin_blocked' using errcode = 'CM409';
  end if;

  -- 평문 칸은 같은 update 에서 비운다(표의 check 도 막는다). 예외 블록은 부분 롤백이라 이 update 만 되돌린다 —
  -- 작업 기록 insert 는 성공 경로(블록 밖)에서만 한다.
  begin
    update public.graduate_verification_requests
       set status = p_status,
           reason = p_reason,
           university_id = p_university,
           document_hmac = case when p_status = 'approved' then p_document_hmac else document_hmac end,
           student_hmac = case when p_status = 'approved' then p_student_hmac else null end,
           key_version = case when p_status = 'approved' then p_key_version else key_version end,
           ocr_document_number = null,
           ocr_school_text = null,
           previous_school_email = null,
           decided_by = p_admin,
           decided_at = now()
     where id = p_request
    returning * into v_row;
  exception when unique_violation then
    get stacked diagnostics v_constraint = constraint_name;
    raise exception '%', case v_constraint
        when 'graduate_requests_document_approved_key' then 'document_reused'
        when 'graduate_requests_student_approved_key' then 'student_reused'
        else 'already_reviewed' end
      using errcode = 'CM409';
  end;

  if p_status = 'approved' then
    update public.profiles
       set university_id = p_university,
           school_email_verified_at = now(),
           graduate_verified_at = now(),
           verification_method = 'graduate_certificate'
     where id = v_row.profile_id;
  end if;

  -- 번호 · 학번 · 해시 · 이메일 · 사진 경로는 싣지 않는다. 학번을 넣었는지만 true/false 로 남긴다.
  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, ip)
  values (
    p_admin,
    case p_status when 'approved' then 'graduate_approve' else 'graduate_reject' end,
    'graduate_request',
    p_request::text,
    jsonb_build_object('status', 'pending'),
    jsonb_strip_nulls(jsonb_build_object(
      'status', v_row.status,
      'university_id', v_row.university_id,
      'reason', v_row.reason,
      'has_student_hmac', case when p_status = 'approved' then p_student_hmac is not null end)),
    p_ip
  );

  return jsonb_build_object(
    'id', v_row.id, 'profile_id', v_row.profile_id, 'status', v_row.status, 'reason', v_row.reason,
    'university_id', v_row.university_id, 'decided_at', v_row.decided_at);
end;
$$;

comment on function public.admin_review_graduate_request(uuid, uuid, text, text, uuid, bytea, bytea, smallint, inet) is
  '졸업생 신청 승인 · 반려 + 작업 기록을 한 트랜잭션에(FastAPI 전용). 승인은 학교 메일 인증과 같은 두 칸을 채운다. '
  '오류: 22023 규칙 위반 · 42501 관리자 아님 · CM404 없음 · CM409(message = already_reviewed | already_verified | account_withdrawn | '
  'document_reused | student_reused | rejoin_blocked) · 23503 없는 학교';

revoke all on function public.admin_review_graduate_request(
  uuid, uuid, text, text, uuid, bytea, bytea, smallint, inet) from public, anon, authenticated;
grant execute on function public.admin_review_graduate_request(
  uuid, uuid, text, text, uuid, bytea, bytea, smallint, inet) to service_role;

-- 2. 14일 정리 배치에서 신청 중 · 최근에 결정된 졸업생을 뺀다.
--    20261018002907_exclude_admins_from_unverified_cleanup.sql 의 정의 그대로 + 졸업생 신청 조건 한 줄만 더했다.
--    이름 · 인자 · 반환형 · plpgsql · stable · security invoker · search_path '' 는 그대로 — create or replace 라 권한(ACL)도 남는다.
--    졸업생은 학교 메일이 없어 승인 전까지 school_email_verified_at 이 비어 있다 — 그대로 두면 심사를 기다리다 14일 뒤 계정이 지워진다.
--    반려 직후에도 같은 기간(p_older_than_days 일)을 더 준다: 반려 사유를 보고 다시 신청할 시간이다.
--    부르는 service_role 은 graduate_verification_requests select 권한이 있다(앞 파일).
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
      and not exists (
        select 1 from public.graduate_verification_requests g
        where g.profile_id = p.id
          and (g.status = 'pending' or g.decided_at > now() - make_interval(days => p_older_than_days)))
    order by p.created_at
    limit p_limit;
end;
$$;

comment on function public.list_unverified_accounts(integer, integer) is
  '학교 메일 인증 전 + p_older_than_days 일 지난 프로필 id, 오래된 순 p_limit 개(기본 100). 관리자(admin_users)와 '
  '졸업생 신청이 대기 중이거나 최근 p_older_than_days 일 안에 결정된 계정은 뺀다. 정리 배치(FastAPI) 전용';
