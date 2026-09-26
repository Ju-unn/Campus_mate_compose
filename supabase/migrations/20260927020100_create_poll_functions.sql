-- 커뮤니티 탭 DB 함수 네 개. 부르는 쪽은 FastAPI(service_role) 하나다.
-- 전부 security invoker — service_role 이 표 권한을 다 가지고 RLS 를 우회하므로 definer 로 권한을 빌릴 이유가 없다.
-- 앱 역할이 부르는 길은 파일 끝 revoke 로 막는다(home_stats 와 같은 모양).

-- 15d 피드 · 17c 상세. 반환 칸에 author_id 가 없다 — 익명은 여기서 끝난다. 본인에게는 is_mine 만 준다.
-- 가려진 글 · 글쓴이가 active 가 아닌 글은 없고, active 가 아닌 투표자의 표는 세지 않는다(ERD 264줄).
-- 피드 범위는 전체 학교다(2026-09-27 사용자 결정 1).
create function public.poll_feed(
  p_viewer uuid,
  p_poll_id uuid default null,
  p_before timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  question text,
  option_a_label text,
  option_b_label text,
  created_at timestamptz,
  a_count bigint,
  b_count bigint,
  my_choice public.poll_choice,
  is_mine boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.question, p.option_a_label, p.option_b_label, p.created_at,
         c.a_count, c.b_count,
         (select mv.choice from public.poll_votes mv where mv.poll_id = p.id and mv.voter_id = p_viewer),
         p.author_id = p_viewer
    from public.polls p
    join public.profiles author on author.id = p.author_id and author.status = 'active'
   -- ponytail: 요청마다 표를 센다. 글 하나에 표가 수천이 되면 polls 에 집계 칸을 두고 투표 때 올린다.
   cross join lateral (
     select count(*) filter (where v.choice = 'a') as a_count,
            count(*) filter (where v.choice = 'b') as b_count
       from public.poll_votes v
       join public.profiles voter on voter.id = v.voter_id and voter.status = 'active'
      where v.poll_id = p.id
   ) c
   where p.status = 'visible'
     and (p_poll_id is null or p.id = p_poll_id)
     -- 채팅 메시지와 같은 (시각, id) 커서. 같은 시각의 두 글이 경계에서 빠지지 않는다.
     and (p_before is null or (p.created_at, p.id) < (p_before, p_before_id))
   order by p.created_at desc, p.id desc
   limit p_limit;
$$;

-- 17b 질문 올리기. 한국 시간 하루 10개(2026-09-27 사용자 결정 3). 지운 글은 세지 않는다.
create function public.create_poll(p_author uuid, p_question text, p_option_a text, p_option_b text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- 같은 사람이 두 번 동시에 올려도 11번째가 끼지 않게 사람 단위로 줄 세운다. 트랜잭션이 끝나면 풀린다.
  perform pg_advisory_xact_lock(hashtext('create_poll'), hashtext(p_author::text));

  if (select count(*) from public.polls
       where author_id = p_author
         and created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') >= 10 then
    -- 서버가 이 코드를 보고 429 로 바꾼다(PostgREST 는 모르는 코드를 400 으로 보낸다).
    raise exception 'poll daily limit' using errcode = 'CM429';
  end if;

  insert into public.polls (author_id, question, option_a_label, option_b_label)
  values (p_author, p_question, p_option_a, p_option_b)
  returning id into v_id;
  return v_id;
end;
$$;

-- 투표 보상을 줄 차례인가: 한국 시간 오늘 poll_vote 적립이 없고, 이번 주(월 0시 시작) 합이 30 을 넘지 않을 때.
-- 원장(heart_transactions)으로 센다(ERD 508줄). p_now 를 받는 이유는 pgTAP 이 고정 시각으로 경계를 확인하려고.
-- volatile(기본값)로 둔다. 지금은 잠금이 별도 문장이라 stable 이어도 맞게 돌지만, 나중에 잠금과 한 문장 안에서
-- 불리게 바뀌면 stable 은 문장 시작 스냅샷을 써서 앞 트랜잭션이 막 커밋한 원장 행을 못 본다.
create function public.poll_vote_reward_due(p_voter uuid, p_now timestamptz)
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
         -- 10하트를 더해도 주간 상한 30 안이어야 한다(DESIGN §8.10 무료 획득 표).
         and (select coalesce(sum(t.amount), 0) from public.heart_transactions t
               where t.profile_id = p_voter and t.reason = 'poll_vote'
                 and t.created_at >= b.week_start and t.created_at < b.week_start + interval '7 days') + 10 <= 30
    from bounds b;
$$;

-- 투표 + 보상을 한 트랜잭션에서. 돌려주는 값 = 이번 투표로 하트를 줬는가.
create function public.cast_poll_vote(p_poll_id uuid, p_voter uuid, p_choice public.poll_choice)
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
  -- 20하트가 나간다 — 뒤에 온 쪽이 앞 트랜잭션이 끝날 때까지 여기서 기다린다. 트랜잭션이 끝나면 풀린다.
  perform pg_advisory_xact_lock(hashtext('cast_poll_vote'), hashtext(p_voter::text));

  -- 재투표는 PK(poll_id, voter_id) 가 23505 로 막는다 → 서버 409.
  insert into public.poll_votes (poll_id, voter_id, choice) values (p_poll_id, p_voter, p_choice);

  v_due := public.poll_vote_reward_due(p_voter, now());
  if v_due then
    -- 조각 2 의 원장 + 잔액 캐시 함수를 그대로 쓴다. 같은 트랜잭션이라 투표가 실패하면 하트도 없다.
    perform public.grant_hearts(p_voter, 10, 'poll_vote', p_poll_id);
  end if;
  return v_due;
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer) from public, anon, authenticated;
revoke execute on function public.create_poll(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.poll_vote_reward_due(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.cast_poll_vote(uuid, uuid, public.poll_choice) from public, anon, authenticated;
grant execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer) to service_role;
grant execute on function public.create_poll(uuid, text, text, text) to service_role;
grant execute on function public.poll_vote_reward_due(uuid, timestamptz) to service_role;
grant execute on function public.cast_poll_vote(uuid, uuid, public.poll_choice) to service_role;
