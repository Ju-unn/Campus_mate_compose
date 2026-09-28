-- 무료로 하트 모으기 DB 함수 셋과 검수 트리거 둘. 함수를 부르는 쪽은 FastAPI(service_role) 하나다.
-- 트리거는 누가 status 를 바꾸든(FastAPI · 대시보드) 같은 규칙을 지킨다 — 승인 한 번에 하트 한 번.
-- 함수는 security invoker — service_role 이 표 권한을 다 가지고 RLS 를 우회한다(poll_feed 와 같은 모양).

-- 항목별 한 달 한도(DESIGN §8.10 표). 한도는 여기 한 곳에만 둔다 — 제출 판정과 18a 표시가 같이 본다.
create function public.heart_task_monthly_limit(p_task public.heart_task)
returns integer
language sql
immutable
set search_path = ''
as $$
  -- 모르는 항목은 0 — enum 에 항목을 더하고 여기를 잊으면 한도가 풀리지 않고 닫힌다(검토 09-28).
  select case p_task when 'everytime_post' then 1 when 'kakao_share' then 3 else 0 end;
$$;

-- 18a 세 줄. 항목마다 이번 달(한국 시간 1일 0시 시작, D4) 쓴 횟수 = 검수 중 + 승인(반려는 빠진다), 검수 중인가,
-- 이번 달 마지막 제출의 상태 · 반려 사유. 투표 줄은 이번 주(월요일 0시 시작) poll_vote 적립 횟수와 한도 3
-- (10하트 × 3 = 주 30, poll_vote_reward_due 와 같은 상한).
-- 검수 중은 달과 상관없이 본다 — 지난달 말에 낸 것이 아직 검수 중이면 부분 unique 인덱스가 새 제출을 막는다.
-- p_now 를 받는 이유는 pgTAP 이 고정 시각으로 달 경계를 확인하려고.
create function public.heart_task_status(p_profile uuid, p_now timestamptz default now())
returns table (
  task text,
  used integer,
  task_limit integer,
  reviewing boolean,
  last_status public.submission_status,
  last_reject_reason public.heart_task_reject_reason
)
language sql
stable
security invoker
set search_path = ''
as $$
  with bounds as (
    select date_trunc('month', p_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as month_start,
           (date_trunc('month', p_now at time zone 'Asia/Seoul') + interval '1 month') at time zone 'Asia/Seoul'
             as month_end,
           date_trunc('week', p_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as week_start
  )
  select t.task::text,
         (select count(*) from public.heart_task_submissions s
           where s.profile_id = p_profile and s.task = t.task and s.status in ('submitted', 'approved')
             and s.created_at >= b.month_start and s.created_at < b.month_end)::integer,
         public.heart_task_monthly_limit(t.task),
         exists (select 1 from public.heart_task_submissions s
                  where s.profile_id = p_profile and s.task = t.task and s.status = 'submitted'),
         last.status,
         last.reject_reason
    from bounds b
   cross join unnest(enum_range(null::public.heart_task)) as t (task)
    left join lateral (
      select s.status, s.reject_reason from public.heart_task_submissions s
       where s.profile_id = p_profile and s.task = t.task
         and s.created_at >= b.month_start and s.created_at < b.month_end
       order by s.created_at desc
       limit 1
    ) last on true
  union all
  select 'poll_vote',
         (select count(*) from public.heart_transactions h
           where h.profile_id = p_profile and h.reason = 'poll_vote'
             and h.created_at >= b.week_start and h.created_at < b.week_start + interval '7 days')::integer,
         3, false, null, null
    from bounds b;
$$;

-- 18b 제출. 검수 중이면 CM409, 이번 달 한도면 CM429 — 서버가 409 · 429 로 바꾼다(PostgREST 는 모르는 코드를 400 으로 보낸다).
-- 잠금을 두지 않는다: 같은 항목에 검수 중인 줄은 부분 unique 인덱스로 하나뿐이라, 두 요청이 동시에 "한도 안" 을 보고
-- 넣어도 두 번째는 23505 로 막힌다(서버 409).
create function public.submit_heart_task(
  p_id uuid, p_profile uuid, p_task public.heart_task, p_path text, p_reward integer,
  p_now timestamptz default now()
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_used integer;
  v_limit integer;
  v_reviewing boolean;
begin
  select s.used, s.task_limit, s.reviewing into v_used, v_limit, v_reviewing
    from public.heart_task_status(p_profile, p_now) s
   where s.task = p_task::text;

  if v_reviewing then
    raise exception 'heart task in review' using errcode = 'CM409';
  end if;
  if v_used >= v_limit then
    raise exception 'heart task monthly limit' using errcode = 'CM429';
  end if;

  -- 파일 경로가 제출 id 를 담아서 id 를 서버가 정해 넘긴다. created_at 도 판정에 쓴 시각 그대로 — 달이 어긋나지 않게.
  insert into public.heart_task_submissions (id, profile_id, task, storage_path, reward_hearts, created_at)
  values (p_id, p_profile, p_task, p_path, p_reward, p_now);
end;
$$;

-- 검수 규칙(D1 · 통합대장 2026-09-28): 승인과 반려는 끝 상태다. 되돌리지 않는다 — 운영자 실수는 사용자가 다시 내거나
-- admin_adjust 로 보정한다. 검수가 끝난 줄에서 바뀔 수 있는 것은 60일 정리의 storage_path → null 하나뿐이다.
-- 같은 값으로 다시 저장(대시보드 재저장)은 아무것도 바꾸지 않아 통과한다.
create function public.heart_task_submissions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.id, new.profile_id, new.task, new.reward_hearts, new.created_at)
     is distinct from (old.id, old.profile_id, old.task, old.reward_hearts, old.created_at) then
    raise exception 'heart task submission fields are fixed' using errcode = 'CM409';
  end if;

  if old.status = 'submitted' then
    if new.storage_path is distinct from old.storage_path then
      raise exception 'heart task proof is fixed while reviewing' using errcode = 'CM409';
    end if;
    -- 검수 시각은 DB 가 찍는다. 대시보드에서 손으로 넣은 값은 덮는다.
    new.reviewed_at := case when new.status = 'submitted' then null else now() end;
    return new;
  end if;

  if new.status is distinct from old.status
     or new.reject_reason is distinct from old.reject_reason
     or new.reviewed_at is distinct from old.reviewed_at
     or (new.storage_path is distinct from old.storage_path and new.storage_path is not null) then
    raise exception 'heart task submission already reviewed' using errcode = 'CM409';
  end if;
  return new;
end;
$$;

create trigger heart_task_submissions_guard
  before update on public.heart_task_submissions
  for each row execute function public.heart_task_submissions_guard();

-- 승인 = 원장 + 잔액(조각 2 grant_hearts). 같은 트랜잭션이라 지급이 실패하면 승인도 되돌아간다.
-- 승인은 끝 상태라(위 guard) 한 줄에서 이 트리거는 많아야 한 번 돈다.
create function public.heart_task_submissions_grant()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform public.grant_hearts(new.profile_id, new.reward_hearts, 'free_task', new.id);
  return null;
end;
$$;

create trigger heart_task_submissions_grant
  after update of status on public.heart_task_submissions
  for each row
  when (old.status = 'submitted' and new.status = 'approved')
  execute function public.heart_task_submissions_grant();

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke execute on function public.heart_task_monthly_limit(public.heart_task) from public, anon, authenticated;
revoke execute on function public.heart_task_status(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.heart_task_submissions_guard() from public, anon, authenticated;
revoke execute on function public.heart_task_submissions_grant() from public, anon, authenticated;
grant execute on function public.heart_task_monthly_limit(public.heart_task) to service_role;
grant execute on function public.heart_task_status(uuid, timestamptz) to service_role;
grant execute on function public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz)
  to service_role;
