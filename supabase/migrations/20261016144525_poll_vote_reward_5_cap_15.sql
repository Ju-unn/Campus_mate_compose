-- 커뮤니티 투표 보상: 하루 첫 투표 10 → 5하트, 주 상한 30 → 15하트(2026-10-16 사용자 확정 "무료하트조정 확정").
-- 서버 상수 POLL_VOTE_REWARD(backend/app/heart_tasks/router.py, 18a 표시용)와 같이 간다.
-- **초안 — 아직 어디에도 적용하지 않았다.** 운영 적용은 사용자 원문 승인 뒤 대장이 한다(frontend/CLAUDE.md §10.1).
-- 시험: supabase/tests/community_polls_test.sql(보상 판정 · 전환 주 · 투표) · heart_tasks_test.sql 56.
--
-- 바꾸는 것은 20260927020100_create_poll_functions.sql 의 두 함수 안 숫자뿐이다. 이름 · 인자 · 반환형(boolean) ·
-- language · volatile(기본) · security invoker · search_path '' 는 그대로 — create or replace 라 권한(ACL)도 남는다.
-- 18a 투표 줄(heart_task_status, 20260928030100)은 "이번 주 적립 횟수 / 한도 3" 이라 값이 그대로(5 × 3 = 15)여서 다시 만들지 않는다.
--
-- 전환 주(적용한 날이 든 월요일 0시 ~ 일요일 끝, 한국 시간): 상한은 원장 합(poll_vote)으로 본다.
--   - 그 주에 옛 10하트를 한 번 받았으면 5하트를 한 번 더 받아 15 에서 멈춘다(10 + 5 = 15 ≤ 15).
--   - 옛 10하트를 두 번(20) 이상 받았으면 그 주는 더 받지 못한다(20 + 5 > 15).
--   - 다음 월요일 0시(한국 시간)부터는 하루 5 · 주 15 그대로다. 이미 받은 하트는 회수하지 않는다.
--   - 그 주 18a 투표 줄은 횟수로 세서 2/3("참여")로 보일 수 있다 — 눌러 투표해도 하트는 없다(전환 주에만).

-- 투표 보상을 줄 차례인가: 한국 시간 오늘 poll_vote 적립이 없고, 이번 주(월 0시 시작) 합에 5 를 더해도 15 를 넘지 않을 때.
-- 원장(heart_transactions)으로 센다(ERD 508줄). p_now 를 받는 이유는 pgTAP 이 고정 시각으로 경계를 확인하려고.
-- volatile(기본값)로 둔다. 지금은 잠금이 별도 문장이라 stable 이어도 맞게 돌지만, 나중에 잠금과 한 문장 안에서
-- 불리게 바뀌면 stable 은 문장 시작 스냅샷을 써서 앞 트랜잭션이 막 커밋한 원장 행을 못 본다.
create or replace function public.poll_vote_reward_due(p_voter uuid, p_now timestamptz)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with bounds as (
    select date_trunc('day', p_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as day_start,
           date_trunc('week', p_now at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as week_start
  )
  select not exists (
           select 1 from public.heart_transactions t
            where t.profile_id = p_voter and t.reason = 'poll_vote'
              and t.created_at >= b.day_start and t.created_at < b.day_start + interval '1 day')
         -- 5하트를 더해도 주간 상한 15 안이어야 한다(DESIGN §8.10 무료 획득 표, 2026-10-16 개정).
         and (select coalesce(sum(t.amount), 0) from public.heart_transactions t
               where t.profile_id = p_voter and t.reason = 'poll_vote'
                 and t.created_at >= b.week_start and t.created_at < b.week_start + interval '7 days') + 5 <= 15
    from bounds b;
$$;

-- 투표 + 보상을 한 트랜잭션에서. 돌려주는 값 = 이번 투표로 하트를 줬는가.
create or replace function public.cast_poll_vote(p_poll_id uuid, p_voter uuid, p_choice public.poll_choice)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_due boolean;
begin
  -- 가려진 글 · 글쓴이가 active 가 아닌 글은 피드에 없다 — 없는 글과 같게 답한다.
  if not exists (
    select 1 from public.polls p
      join public.profiles a on a.id = p.author_id and a.status = 'active'
     where p.id = p_poll_id and p.status = 'visible'
  ) then
    raise exception 'poll not found' using errcode = 'CM404';
  end if;

  -- 한 사람의 투표를 줄 세운다. 서로 다른 글 두 개에 동시에 투표하면 둘 다 "오늘 아직 안 받았다" 를 보고
  -- 하루에 10하트가 나간다 — 뒤에 온 쪽이 앞 트랜잭션이 끝날 때까지 여기서 기다린다. 트랜잭션이 끝나면 풀린다.
  perform pg_advisory_xact_lock(hashtext('cast_poll_vote'), hashtext(p_voter::text));

  -- 재투표는 PK(poll_id, voter_id) 가 23505 로 막는다 → 서버 409.
  insert into public.poll_votes (poll_id, voter_id, choice) values (p_poll_id, p_voter, p_choice);

  v_due := public.poll_vote_reward_due(p_voter, now());
  if v_due then
    -- 조각 2 의 원장 + 잔액 캐시 함수를 그대로 쓴다. 같은 트랜잭션이라 투표가 실패하면 하트도 없다.
    perform public.grant_hearts(p_voter, 5, 'poll_vote', p_poll_id);
  end if;
  return v_due;
end;
$$;

comment on function public.poll_vote_reward_due(uuid, timestamptz) is
  '투표 보상 차례인가 — 한국 시간 오늘 poll_vote 적립이 없고 이번 주(월 0시~) 합 + 5 ≤ 15. 2026-10-16 개정(종전 10 · 30)';
comment on function public.cast_poll_vote(uuid, uuid, public.poll_choice) is
  '투표 + 하루 첫 투표 보상 5하트(주 15 상한은 poll_vote_reward_due). 반환 = 하트를 줬는가. 2026-10-16 개정(종전 10)';

-- create or replace 는 권한을 그대로 두지만, 처음 파일과 같은 결과를 이 파일만 봐도 알 수 있게 다시 적는다(두 번 돌려도 같다).
revoke execute on function public.poll_vote_reward_due(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.cast_poll_vote(uuid, uuid, public.poll_choice) from public, anon, authenticated;
grant execute on function public.poll_vote_reward_due(uuid, timestamptz) to service_role;
grant execute on function public.cast_poll_vote(uuid, uuid, public.poll_choice) to service_role;
