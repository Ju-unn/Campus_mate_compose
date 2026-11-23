-- 할 일 19 커뮤니티 게시물 + 카테고리(2026-11-24 승인, 설계 docs/superpowers/specs/2026-11-24-community-posts-design.md A안).
-- polls 한 표에 투표(kind='poll')와 게시물(kind='post', 글만 · 익명 · 500자 · 제목 없음)을 담는다. 댓글 · 익명N · 하루 한도 · 신고 ·
-- 관리자 가림 · 삭제 · 탈퇴 cascade · 댓글 푸시가 모두 polls.id 를 보므로 게시물에 그대로 돈다. 게시물 본문은 question 칸이다.
-- 배포 순서: 이 마이그레이션 → 서버 → 1.0.7 앱. 옛 서버는 poll_feed · create_poll · cast_poll_vote 만 부르고 셋 다 인자 · 반환이
-- 그대로라 이 파일 뒤에도 그대로 돌고,
-- 서버를 되돌려도 poll_feed 가 게시물을 걸러 1.0.6 화면에 게시물이 섞이지 않는다.
-- 시험: supabase/tests/community_posts_test.sql.

-- 1. 칸 -------------------------------------------------------------------
-- 기존 행 · 옛 앱(1.0.6)이 올리는 투표는 기본값으로 투표 · 자유 게시판이다. 상수 기본값이라 표를 다시 쓰지 않는다.
alter table public.polls
  add column kind text not null default 'poll' constraint polls_kind check (kind in ('poll', 'post')),
  add column category text not null default 'free' constraint polls_category check (category in ('free', 'career', 'love'));

-- 게시물은 선택지가 없다. 기본값(찬성 · 반대)은 옛 create_poll 이 그대로 쓰게 남기고, 게시물은 null 을 명시해 넣는다.
-- 두 라벨 check(1~6자 · 서로 다름)는 null 이면 통과하므로 그대로 둔다.
alter table public.polls
  alter column option_a_label drop not null,
  alter column option_b_label drop not null;

-- 투표 질문 1~80자, 게시물 본문 1~500자. 서버가 앞뒤 공백을 깎아 넣는다 — 깎인 모양이 아니면 빈칸뿐인 글이 들어온 것이다.
-- 투표면 선택지 둘이 다 있고 게시물이면 둘 다 없다 — 한쪽만 있는 줄은 화면이 그릴 수 없다.
alter table public.polls
  drop constraint polls_question_length,
  add constraint polls_question_length check (
    question = btrim(question)
    and char_length(question) between 1 and case kind when 'poll' then 80 else 500 end),
  add constraint polls_kind_options check ((kind = 'poll') = (option_a_label is not null and option_b_label is not null));

comment on table public.polls is
  '커뮤니티 익명 글(투표 · 게시물). FastAPI 전용. author_id 는 어떤 응답에도 담지 않는다(poll_feed · community_feed 가 칸을 주지 않는다)';
comment on column public.polls.kind is 'poll = O/X 투표, post = 글만 있는 게시물(할 일 19). 게시물이면 두 선택지가 null';
comment on column public.polls.category is '카테고리: free(자유) · career(진로) · love(연애). 옛 앱 투표는 기본값 free';
comment on column public.polls.question is '투표의 질문(1~80자) 또는 게시물 본문(1~500자). 앞뒤 공백을 깎은 모양';
-- ponytail: 카테고리 탭도 피드처럼 polls_created_at_id_index 를 거슬러 걸러 낸다. 글이 수만 개가 되면
-- (category, created_at desc, id desc) 인덱스를 두고 community_feed 를 탭별 문장으로 나눈다.

-- 2. 옛 피드 · 투표가 게시물을 모르게 ---------------------------------------
-- poll_feed: 20261111000200 의 정의 그대로 + `p.kind = 'poll'` 한 줄. 인자 · 반환 칸이 같아 create or replace 로 바꾸고 권한도 남는다.
-- 1.0.6 이 부르는 /community/polls 는 어떤 탭 · p_poll_id 로도 게시물을 받지 않는다.
create or replace function public.poll_feed(
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
  is_mine boolean,
  comment_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.question, p.option_a_label, p.option_b_label, p.created_at,
         c.a_count, c.b_count,
         (select mv.choice from public.poll_votes mv where mv.poll_id = p.id and mv.voter_id = p_viewer),
         p.author_id = p_viewer,
         -- EXPLAIN 관점: 글마다 poll_comments_poll_created_id_index(poll_id 앞머리)로 센다 — 피드 한 쪽(20글)이면 인덱스 탐색 20번.
         -- ponytail: 글 하나에 댓글이 수천이 되면 polls 에 집계 칸을 두고 댓글 쓰기 · 지우기 때 올린다.
         (select count(*) from public.poll_comments pc
            join public.profiles ca on ca.id = pc.author_id and ca.status = 'active'
           where pc.poll_id = p.id and pc.status = 'visible')
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
     -- 게시물(할 일 19)은 옛 피드 · 옛 상세에 없다 — 1.0.6 은 선택지가 null 인 글을 그릴 수 없다.
     -- compat(1.0.6): poll_feed 의 kind='poll' — MIN_APP_VERSION 1.0.7 뒤 삭제(투표 뒤 다시 읽기는 투표만 부르므로 빼도 같다)
     and p.kind = 'poll'
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

-- cast_poll_vote: 20261016144525 의 정의 그대로 + 있는지 확인에 `p.kind = 'poll'`. 게시물에 투표하면 없는 글과 같게 CM404(서버 404).
create or replace function public.cast_poll_vote(p_poll_id uuid, p_voter uuid, p_choice public.poll_choice)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_due boolean;
begin
  -- 가려진 글 · 글쓴이가 active 가 아닌 글은 피드에 없다 — 없는 글과 같게 답한다. 게시물은 투표할 선택지가 없다.
  if not exists (
    select 1 from public.polls p
      join public.profiles a on a.id = p.author_id and a.status = 'active'
     where p.id = p_poll_id and p.status = 'visible' and p.kind = 'poll'
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

-- 3. 새 함수 둘 -------------------------------------------------------------
-- 투표 · 게시물 올리기의 한 곳. 한국 시간 하루 10개는 둘을 합쳐 센다(지운 글은 행이 없어 세지 않는다). 하트는 없다.
-- kind · category 값, 길이, 선택지 유무는 표 check 가 막는다(23514) — 서버가 먼저 거르므로 정상 요청은 닿지 않는다.
create function public.create_community_item(
  p_author uuid,
  p_kind text,
  p_category text,
  p_text text,
  p_option_a text default null,
  p_option_b text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- 사람 단위로 줄 세운다(옛 create_poll 의 키 그대로). 옛 create_poll 도 이 함수를 거치므로 배포 사이에 옛 서버 · 새 서버로
  -- 같은 사람이 동시에 올려도 한 줄로 서서 11번째가 끼지 않는다. 트랜잭션이 끝나면 풀린다.
  perform pg_advisory_xact_lock(hashtext('create_poll'), hashtext(p_author::text));

  if (select count(*) from public.polls
       where author_id = p_author
         and created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') >= 10 then
    -- 서버가 이 코드를 보고 429 로 바꾼다(PostgREST 는 모르는 코드를 400 으로 보낸다).
    raise exception 'community daily limit' using errcode = 'CM429';
  end if;

  insert into public.polls (author_id, kind, category, question, option_a_label, option_b_label)
  values (p_author, p_kind, p_category, p_text, p_option_a, p_option_b)
  returning id into v_id;
  return v_id;
end;
$$;

-- compat(1.0.6): 옛 create_poll 껍데기 — MIN_APP_VERSION 1.0.7 뒤 삭제(옛 서버로 되돌릴 일이 없어진 뒤 drop)
-- create_poll: 옛 서버(배포 사이 · 되돌린 서버)가 부른다. 인자 · 반환 · security invoker · search_path 는 그대로 두고 몸통만
-- create_community_item(투표 · 자유)에 넘긴다 — 하루 합산 10개의 잠금 · 세는 식이 한 곳에만 있게(설계에서 바꿈, 코더 보고 참고).
-- or replace 라 권한(service_role 만)이 남는다. 한도를 넘으면 같은 CM429 라 옛 서버도 429 로 답한다.
create or replace function public.create_poll(p_author uuid, p_question text, p_option_a text, p_option_b text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return public.create_community_item(p_author, 'poll', 'free', p_question, p_option_a, p_option_b);
end;
$$;

-- 새 피드 · 상세(/community/feed · /community/items/{id}). 반환 칸에 author_id 가 없다 — 익명은 여기서 끝난다. 본인에게는 is_mine 만.
-- 가림 · 비활성 작성자 · 비활성 투표자 · 보이는 댓글 규칙은 poll_feed 와 같다. 게시물이면 두 선택지가 null, 표 수는 0 이다.
-- 탭: all · popular · mine · voted · free · career · love(그 밖은 빈 결과). popular 는 최근 7일 + 참여 수(활성 표 + 보이는 댓글) > 0,
-- 참여 수 → 최신 → id 순 한 쪽뿐이라 서버가 커서를 받지 않는다.
create function public.community_feed(
  p_viewer uuid,
  p_item_id uuid default null,
  p_before timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 20,
  p_tab text default 'all'
)
returns table (
  id uuid,
  kind text,
  category text,
  text text,
  option_a_label text,
  option_b_label text,
  created_at timestamptz,
  a_count bigint,
  b_count bigint,
  my_choice public.poll_choice,
  is_mine boolean,
  comment_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.kind, p.category, p.question, p.option_a_label, p.option_b_label, p.created_at,
         c.a_count, c.b_count,
         (select mv.choice from public.poll_votes mv where mv.poll_id = p.id and mv.voter_id = p_viewer),
         p.author_id = p_viewer,
         cc.comment_count
    from public.polls p
    join public.profiles author on author.id = p.author_id and author.status = 'active'
   -- ponytail: 요청마다 표 · 댓글을 센다(poll_feed 와 같다). 글 하나에 수천이 되면 polls 에 집계 칸을 둔다.
   cross join lateral (
     select count(*) filter (where v.choice = 'a') as a_count,
            count(*) filter (where v.choice = 'b') as b_count
       from public.poll_votes v
       join public.profiles voter on voter.id = v.voter_id and voter.status = 'active'
      where v.poll_id = p.id
   ) c
   -- 인기 순서도 같은 수를 쓰도록 lateral 로 한 번만 센다.
   cross join lateral (
     select count(*) as comment_count
       from public.poll_comments pc
       join public.profiles ca on ca.id = pc.author_id and ca.status = 'active'
      where pc.poll_id = p.id and pc.status = 'visible'
   ) cc
   where p.status = 'visible'
     and (p_item_id is null or p.id = p_item_id)
     -- 채팅 메시지와 같은 (시각, id) 커서. 커서 값은 경계일 뿐 — 가려진 글의 시각 · id 를 넣어도 위 status 조건이 막는다.
     and (p_before is null or (p.created_at, p.id) < (p_before, p_before_id))
     and case p_tab
           when 'all' then true
           when 'popular' then p.created_at >= now() - interval '7 days' and c.a_count + c.b_count + cc.comment_count > 0
           when 'mine' then p.author_id = p_viewer
           when 'voted' then exists (
             select 1 from public.poll_votes tv where tv.poll_id = p.id and tv.voter_id = p_viewer)
           when 'free' then p.category = 'free'
           when 'career' then p.category = 'career'
           when 'love' then p.category = 'love'
           else false
         end
   -- 인기가 아니면 첫 키가 모두 null 이라 최신순만 남는다.
   order by case when p_tab = 'popular' then c.a_count + c.b_count + cc.comment_count end desc,
            p.created_at desc, p.id desc
   limit p_limit;
$$;

-- 4. 권한 -------------------------------------------------------------------
-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
-- poll_feed · cast_poll_vote · create_poll 은 or replace 라 권한이 남지만 이 파일만 봐도 알 수 있게 다시 적는다(두 번 돌려도 같다).
revoke execute on function public.create_community_item(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.community_feed(uuid, uuid, timestamptz, uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.cast_poll_vote(uuid, uuid, public.poll_choice) from public, anon, authenticated;
revoke execute on function public.create_poll(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.create_community_item(uuid, text, text, text, text, text) to service_role;
grant execute on function public.community_feed(uuid, uuid, timestamptz, uuid, integer, text) to service_role;
grant execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer, text) to service_role;
grant execute on function public.cast_poll_vote(uuid, uuid, public.poll_choice) to service_role;
grant execute on function public.create_poll(uuid, text, text, text) to service_role;
