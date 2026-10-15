-- 15d 탭 줄(전체 · 인기 · 내 질문 · 내 투표): poll_feed 에 p_tab 칸을 더한다. 함수만 바뀐다 — 표 · 인덱스 · 데이터는 그대로다.
-- 인자를 늘리는 건 create or replace 로 안 되고, 새로 만들기만 하면 같은 이름 함수가 둘이 돼
-- PostgREST 가 어느 쪽을 부를지 못 고른다(PGRST203). 옛 함수를 지우고 다시 만든다. 한 트랜잭션이라 사이에 빈틈이 없다.
-- 옛 서버(p_tab 없이 부름)도 기본값 'all' 로 그대로 돈다 — 이 파일을 서버 배포보다 먼저 적용한다.
drop function public.poll_feed(uuid, uuid, timestamptz, uuid, integer);

-- 반환 칸 · 가림 · 집계는 20260927020100 그대로다(author_id 없음 — 익명, 본인에게는 is_mine 만). 탭:
--   all     전체 학교 최신순 + (created_at, id) 커서. 상세 · 투표 뒤 다시 읽기도 이 탭이다
--   popular 최근 7일 글 중 active 표가 1개 이상인 글을 참여 수 많은 순 → 같으면 최신 글 → id. 서버가 한 쪽(20개)만 준다.
--           20개보다 적으면 적은 대로 둔다 — 표 없는 최신 글로 빈자리를 채우지 않는다(2026-10-15 결정)
--   mine    내가 쓴 글, 최신순 + 커서
--   voted   내가 표를 둔 글, 글 올린 시각 순 + 커서
--   그 밖   빈 결과(서버가 먼저 422 로 막는다)
create function public.poll_feed(
  p_viewer uuid,
  p_poll_id uuid default null,
  p_before timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 20,
  p_tab text default 'all'
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
     -- ponytail: 탭 조건을 CASE 한 문장에 건다. 글이 수만 개가 되면 탭별 문장(plpgsql return query)으로 나눠
     -- mine 은 polls_author_id_created_at_index, voted 는 poll_votes_voter_id_index 를 타게 한다.
     and case p_tab
           when 'all' then true
           when 'popular' then p.created_at >= now() - interval '7 days' and c.a_count + c.b_count > 0
           when 'mine' then p.author_id = p_viewer
           when 'voted' then exists (
             select 1 from public.poll_votes tv where tv.poll_id = p.id and tv.voter_id = p_viewer)
           else false
         end
   -- 인기가 아니면 첫 키가 모두 null 이라 최신순만 남는다.
   order by case when p_tab = 'popular' then c.a_count + c.b_count end desc,
            p.created_at desc, p.id desc
   limit p_limit;
$$;

-- 다시 만든 함수는 Supabase 기본 권한(anon · authenticated 실행)을 새로 받는다 — 옛 정의와 같게 다시 뺀다.
revoke execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer, text) from public, anon, authenticated;
grant execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer, text) to service_role;
