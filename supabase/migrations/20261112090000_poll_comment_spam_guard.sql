-- O/X 글 댓글 도배 막기(2026-11-12). 사용자 결정 원문: 「1번에 1번 2번 만」(③ 한 글 하루 20개는 넣지 않는다).
--   ① 같은 사람이 (어느 글이든) 최근 1분 안에 단 댓글이 이미 5개면 6번째를 막는다 → CM42B (서버가 429 로 바꾼다)
--   ② 같은 글에서 내 바로 전 댓글(그 글의 내 마지막 댓글)과 본문이 똑같으면 막는다 → CM409 (서버가 409 로 바꾼다)
-- 기존 하루 50개(CM429)는 그대로이고 둘보다 먼저 본다. 코드 이름: 하루 한도가 이미 CM429 라 ① 은 같은 429 계열의 다른 이유로
-- CM42B(B = burst)를 쓴다. ② 는 20261019100000 의 heart_task 와 같은 CM409. PostgREST 는 모르는 코드를 400 으로 보내므로
-- 서버(community/repository.py add_comment)가 코드를 보고 상태 · 문구를 정한다.
-- 운영 적용은 서버 배포 먼저 → 이 마이그레이션(반대면 막힌 요청 하나가 옛 서버에서 500). 되돌리기는 DB 먼저 → 서버.
-- 새 서버가 먼저면 새 코드가 아직 안 와서 옛 동작 그대로이고, 이 파일이 먼저면 막힌 요청 하나가 새 서버가 올라올 때까지 500 이다.
-- 되돌리기: 20261111000200 의 add_poll_comment 정의를 다시 create or replace 하고 아래 인덱스를 drop 한다.

-- ② 가 "그 글의 내 마지막 댓글" 한 줄을 (poll_id, author_id) 로 바로 찾게 한다. 기존 인덱스는 둘 다 못 맞는다 —
-- (poll_id, created_at, id) 는 글 전체 댓글을 거슬러 올라가며 내 것을 찾아야 하고(인기 글이면 길다),
-- (author_id, created_at) 는 이 글에 처음 쓰는 사람의 전체 댓글 이력을 훑어야 한다.
create index poll_comments_poll_author_created_index on public.poll_comments (poll_id, author_id, created_at);

-- 20261111000200 의 정의 그대로 + ① ② 두 줄과 created_at 을 clock_timestamp() 로 넣는 것.
-- created_at: 기본값 now() 는 트랜잭션이 시작한 시각이라 같은 사람의 두 요청이 잠금을 기다리다 순서가 뒤집히면 "마지막 댓글"이 뒤바뀐다.
-- 잠금 안에서 찍는 clock_timestamp() 는 쓴 순서와 시각이 늘 같아 ① 의 1분 창과 ② 의 마지막 댓글이 쓴 순서를 따른다.
create or replace function public.add_poll_comment(p_author uuid, p_poll_id uuid, p_body text)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  alias_no integer,
  is_post_author boolean,
  is_mine boolean,
  can_delete boolean,
  poll_author_id uuid,
  poll_question text
)
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_poll_author uuid;
  v_question text;
  v_alias integer;
  v_comment_id uuid;
  v_created timestamptz;
  v_burst_since timestamptz;
begin
  -- 가려진 글 · 글쓴이가 active 가 아닌 글은 피드에 없다 — 없는 글과 같게 답한다(cast_poll_vote 와 같다).
  select p.author_id, p.question into v_poll_author, v_question
    from public.polls p
    join public.profiles a on a.id = p.author_id and a.status = 'active'
   where p.id = p_poll_id and p.status = 'visible';
  if not found then
    raise exception 'poll not found' using errcode = 'CM404';
  end if;

  -- 같은 사람이 동시에 51번째 · 6번째를 끼우거나 같은 내용을 두 번 넣지 못하게 사람 단위로 줄 세운다(create_poll 과 같다).
  -- 아래 세 판단이 모두 이 잠금 뒤에 있다. 트랜잭션이 끝나면 풀린다.
  perform pg_advisory_xact_lock(hashtext('add_poll_comment'), hashtext(p_author::text));

  -- 지운 댓글은 세지 않는다(행이 없다). 가려진 댓글은 센다 — 가려져도 쓴 사실은 남는다.
  if (select count(*) from public.poll_comments c
       where c.author_id = p_author
         and c.created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') >= 50 then
    -- 서버가 이 코드를 보고 429 로 바꾼다(PostgREST 는 모르는 코드를 400 으로 보낸다).
    raise exception 'poll comment daily limit' using errcode = 'CM429';
  end if;

  -- ① 도배: 어느 글이든 최근 1분 안에 이미 5개면 6번째를 막는다. 서버가 429 로 바꾼다. 하루 한도와 같은 인덱스(author_id, created_at)다.
  -- 1분 창의 시작을 변수에 담아 쓴다 — clock_timestamp() 는 volatile 이라 where 에 직접 쓰면 인덱스 범위 조건이 안 돼
  -- 그 사람의 댓글 이력 전체를 훑는다(로컬 EXPLAIN 으로 확인).
  v_burst_since := clock_timestamp() - interval '1 minute';
  if (select count(*) from public.poll_comments c
       where c.author_id = p_author
         and c.created_at > v_burst_since) >= 5 then
    raise exception 'poll comment too fast' using errcode = 'CM42B';
  end if;

  -- ② 같은 글에서 내 바로 전 댓글과 본문이 같으면 막는다(시간 제한 없음, 서버가 이미 앞뒤 공백을 깎았다). 서버가 409 로 바꾼다.
  -- 지운 댓글은 행이 없어 비교 대상이 아니다. 가려진 댓글은 남아 있어 비교 대상이다(하루 한도와 같다).
  if exists (
    select 1
      from (select c.body from public.poll_comments c
             where c.poll_id = p_poll_id and c.author_id = p_author
             order by c.created_at desc
             limit 1) last_comment
     where last_comment.body = p_body) then
    raise exception 'poll comment same as last' using errcode = 'CM409';
  end if;

  -- 글쓴이는 번호가 없다. 나머지는 글 안에서 처음 쓸 때 다음 번호(가장 큰 번호 + 1)를 받는다.
  if p_author <> v_poll_author then
    select al.alias_no into v_alias
      from public.poll_comment_aliases al
     where al.poll_id = p_poll_id and al.profile_id = p_author;
    if not found then
      -- 서로 다른 두 사람이 동시에 첫 댓글을 써도 같은 번호를 받지 않게 글 단위로 줄 세운다(잠금 순서는 늘 사람 → 글).
      perform pg_advisory_xact_lock(hashtext('poll_comment_alias'), hashtext(p_poll_id::text));
      insert into public.poll_comment_aliases (poll_id, profile_id, alias_no)
      select p_poll_id, p_author, coalesce(max(al.alias_no), 0) + 1
        from public.poll_comment_aliases al
       where al.poll_id = p_poll_id
      returning poll_comment_aliases.alias_no into v_alias;
    end if;
  end if;

  insert into public.poll_comments (poll_id, author_id, body, created_at)
  values (p_poll_id, p_author, p_body, clock_timestamp())
  returning poll_comments.id, poll_comments.created_at into v_comment_id, v_created;

  return query select v_comment_id, p_body, v_created, v_alias, p_author = v_poll_author, true, true,
                      v_poll_author, v_question;
end;
$$;

-- create or replace 는 권한을 그대로 둔다(service_role 만). 같은 모양으로 다시 못 박는 줄은 두지 않는다.
