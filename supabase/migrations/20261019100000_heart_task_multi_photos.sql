-- 무료로 하트 모으기: 인증샷 1~3장, 단톡방 공유는 검수 중에도 한도(월 3회) 안에서 이어서 제출.
-- 계획서 docs/superpowers/plans/2026-10-19-heart-task-multiphoto.md Task 1 (D1 · D2 · D5).
--
-- 1. 사진 경로: storage_path text 한 칸 → storage_paths text[](1~3개, 순서 = 보여 줄 순서). 옛 칸은 없앤다.
--    -- shortcut: 사진별 해시 · 크기가 필요해지면(이미 쓴 캡처 자동 판별) heart_task_submission_photos 표로 옮긴다.
-- 2. 부분 unique 인덱스 heart_task_submissions_one_reviewing 삭제 — 남기면 단톡방의 두 번째 검수 중 줄이 23505 로 막힌다.
-- 3. submit_heart_task: 한도(검수 중 + 승인 ≥ 한도)만 본다. 한도에 찼고 검수 중이 있으면 CM409(결과를 기다려 달라),
--    검수 중이 없으면 CM429(이번 달 끝). 두 요청이 동시에 "한도 안"을 보고 넣어 한도를 넘지 않도록
--    사람·항목마다 advisory lock 을 잡는다(READ COMMITTED 라 기다린 쪽은 먼저 온 쪽이 커밋한 뒤의 새 스냅샷으로 센다).
--    함수는 이름은 같고 인자 칸(p_path text → p_paths text[])이 달라 옛 함수를 지우고 새로 만든다.
--
-- heart_task_status · heart_task_monthly_limit · 승인 트리거 · admin_review_heart_task 는 그대로다(사진 경로를 쓰지 않는다).
-- 배포: 이 마이그레이션 직후 서버를 배포한다. 옛 서버는 storage_path 와 p_path 를 쓰므로 그 사이 제출 · 관리자 사진 보기가
-- 오류다(계획서 D5, 대장 결정 10-19). 서버만 이전 리비전으로 되돌리면 깨진다.
-- 시험: supabase/tests/heart_tasks_test.sql

-- 1. 경로 배열 + 백필(옛 줄은 사진 1장). guard 트리거를 바꾸기 전에 해야 한다 — 옛 guard 는 storage_paths 를 보지 않아 통과한다.
alter table public.heart_task_submissions
  add column storage_paths text[] not null default '{}';

update public.heart_task_submissions
   set storage_paths = array[storage_path]
 where storage_path is not null;

alter table public.heart_task_submissions drop constraint heart_task_submissions_proof_while_reviewing;
alter table public.heart_task_submissions drop column storage_path;

alter table public.heart_task_submissions
  add constraint heart_task_submissions_paths_max check (cardinality(storage_paths) <= 3),
  add constraint heart_task_submissions_proof_while_reviewing
    check (status <> 'submitted' or cardinality(storage_paths) between 1 and 3);

comment on column public.heart_task_submissions.storage_paths is
  '인증샷 경로 1~3개(순서 = 보여 줄 순서). 검수 중에는 필수 · 고정, 검수가 끝나고 60일 뒤 정리 배치가 {} 로 비운다';

-- 2. 항목당 검수 중 한 줄 제한 삭제.
drop index public.heart_task_submissions_one_reviewing;

-- 검수 규칙(D1 · 통합대장 2026-09-28)은 그대로다: 승인과 반려는 끝 상태이고, 검수가 끝난 줄에서 바뀔 수 있는 것은
-- 60일 정리의 storage_paths → '{}' 하나뿐이다(일부만 남기기 · 다른 값으로 바꾸기는 막는다).
create or replace function public.heart_task_submissions_guard()
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
    if new.storage_paths is distinct from old.storage_paths then
      raise exception 'heart task proof is fixed while reviewing' using errcode = 'CM409';
    end if;
    -- 검수 시각은 DB 가 찍는다. 대시보드에서 손으로 넣은 값은 덮는다.
    new.reviewed_at := case when new.status = 'submitted' then null else now() end;
    return new;
  end if;

  if new.status is distinct from old.status
     or new.reject_reason is distinct from old.reject_reason
     or new.reviewed_at is distinct from old.reviewed_at
     or (new.storage_paths is distinct from old.storage_paths and new.storage_paths <> '{}') then
    raise exception 'heart task submission already reviewed' using errcode = 'CM409';
  end if;
  return new;
end;
$$;

-- 3. 제출. 오류: 경로가 없거나 4개 이상 22023, 한도에 찼고 검수 중 CM409, 한도에 찼고 검수 중 없음 CM429
-- (서버가 409 · 429 로 바꾼다 — PostgREST 는 모르는 코드를 400 으로 보낸다).
drop function public.submit_heart_task(uuid, uuid, public.heart_task, text, integer, timestamptz);

create function public.submit_heart_task(
  p_id uuid, p_profile uuid, p_task public.heart_task, p_paths text[], p_reward integer,
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
  if p_paths is null or cardinality(p_paths) not between 1 and 3 then
    raise exception 'heart task needs one to three proofs' using errcode = '22023';
  end if;

  -- 같은 사람 · 같은 항목의 제출을 한 줄로 세운다. 에브리타임과 단톡방, 다른 사람끼리는 서로 막지 않고,
  -- 락은 트랜잭션이 끝나면 저절로 풀린다. 이 아래의 한도 판정은 먼저 온 제출이 커밋한 뒤의 값을 본다.
  perform pg_advisory_xact_lock(hashtextextended('heart_task:' || p_profile::text || ':' || p_task::text, 0));

  select s.used, s.task_limit, s.reviewing into v_used, v_limit, v_reviewing
    from public.heart_task_status(p_profile, p_now) s
   where s.task = p_task::text;

  if v_used >= v_limit then
    -- 검수 중이 있으면 반려로 칸이 돌아올 수 있어 "결과를 기다려 달라", 없으면 이번 달은 끝이다.
    raise exception 'heart task limit reached' using errcode = case when v_reviewing then 'CM409' else 'CM429' end;
  end if;

  -- 파일 경로가 제출 id 를 담아서 id 를 서버가 정해 넘긴다. created_at 도 판정에 쓴 시각 그대로 — 달이 어긋나지 않게.
  insert into public.heart_task_submissions (id, profile_id, task, storage_paths, reward_hearts, created_at)
  values (p_id, p_profile, p_task, p_paths, p_reward, p_now);
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke execute on function public.submit_heart_task(uuid, uuid, public.heart_task, text[], integer, timestamptz)
  from public, anon, authenticated;
grant execute on function public.submit_heart_task(uuid, uuid, public.heart_task, text[], integer, timestamptz)
  to service_role;
