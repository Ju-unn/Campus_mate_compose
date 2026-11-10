-- O/X 글 댓글(2026-11-10) 3/3: DB 함수 셋 + poll_feed 의 comment_count + 관리자 가림이 댓글도 받게.
-- 부르는 쪽은 FastAPI(service_role) 하나다. 전부 security invoker — service_role 이 표 권한을 다 가지고 RLS 를 우회하므로
-- definer 로 권한을 빌릴 이유가 없다(20260927020100 과 같은 틀). 앱 역할이 부르는 길은 파일 끝 revoke 로 막는다.
-- 서버 배포보다 먼저 적용한다(새 서버는 poll_feed 의 comment_count 칸을 읽는다).

-- 댓글 쓰기. 보이는 글이고 글쓴이가 active 일 때만(아니면 CM404). 한국 시간 하루 50개를 넘으면 CM429.
-- 처음 쓰는 사람은 글 안의 다음 익명 번호를 받는다. 돌려주는 줄 = 새 댓글 한 줄 + 푸시에 쓸 글쓴이 id · 질문.
-- poll_author_id · poll_question 은 서버가 푸시를 보내는 데만 쓰고 앱 응답에는 싣지 않는다(익명).
create function public.add_poll_comment(p_author uuid, p_poll_id uuid, p_body text)
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
begin
  -- 가려진 글 · 글쓴이가 active 가 아닌 글은 피드에 없다 — 없는 글과 같게 답한다(cast_poll_vote 와 같다).
  select p.author_id, p.question into v_poll_author, v_question
    from public.polls p
    join public.profiles a on a.id = p.author_id and a.status = 'active'
   where p.id = p_poll_id and p.status = 'visible';
  if not found then
    raise exception 'poll not found' using errcode = 'CM404';
  end if;

  -- 같은 사람이 동시에 51번째를 끼우지 못하게 사람 단위로 줄 세운다(create_poll 과 같다). 트랜잭션이 끝나면 풀린다.
  perform pg_advisory_xact_lock(hashtext('add_poll_comment'), hashtext(p_author::text));

  -- 지운 댓글은 세지 않는다(행이 없다). 가려진 댓글은 센다 — 가려져도 쓴 사실은 남는다.
  if (select count(*) from public.poll_comments c
       where c.author_id = p_author
         and c.created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') >= 50 then
    -- 서버가 이 코드를 보고 429 로 바꾼다(PostgREST 는 모르는 코드를 400 으로 보낸다).
    raise exception 'poll comment daily limit' using errcode = 'CM429';
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

  insert into public.poll_comments (poll_id, author_id, body)
  values (p_poll_id, p_author, p_body)
  returning poll_comments.id, poll_comments.created_at into v_comment_id, v_created;

  return query select v_comment_id, p_body, v_created, v_alias, p_author = v_poll_author, true, true,
                      v_poll_author, v_question;
end;
$$;

-- 댓글 목록. 오래된 순 + (created_at, id) 커서(채팅 메시지 · 피드와 같은 모양, 같은 시각 두 댓글이 경계에서 빠지지 않는다).
-- 서버는 limit + 1 줄을 달라고 해서 has_more 를 정확히 안다. 반환 칸에 author_id 가 없다 — 익명은 여기서 끝난다.
-- 가려진 글 · 글쓴이가 active 가 아닌 글은 CM404, 가려진 댓글 · active 가 아닌 작성자의 댓글은 줄에 없다.
create function public.poll_comments_page(
  p_viewer uuid,
  p_poll_id uuid,
  p_after timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 10
)
returns table (
  id uuid,
  body text,
  created_at timestamptz,
  alias_no integer,
  is_post_author boolean,
  is_mine boolean,
  can_delete boolean
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_poll_author uuid;
begin
  select p.author_id into v_poll_author
    from public.polls p
    join public.profiles a on a.id = p.author_id and a.status = 'active'
   where p.id = p_poll_id and p.status = 'visible';
  if not found then
    raise exception 'poll not found' using errcode = 'CM404';
  end if;

  return query
  select c.id, c.body, c.created_at,
         -- 글쓴이 댓글은 번호 대신 is_post_author 로 알린다.
         case when c.author_id = v_poll_author then null else al.alias_no end,
         c.author_id = v_poll_author,
         c.author_id = p_viewer,
         -- 내 댓글이거나 내 글에 달린 댓글이면 지울 수 있다.
         c.author_id = p_viewer or v_poll_author = p_viewer
    from public.poll_comments c
    join public.profiles ca on ca.id = c.author_id and ca.status = 'active'
    left join public.poll_comment_aliases al on al.poll_id = c.poll_id and al.profile_id = c.author_id
   where c.poll_id = p_poll_id
     and c.status = 'visible'
     and (p_after is null or (c.created_at, c.id) > (p_after, p_after_id))
   order by c.created_at, c.id
   limit p_limit;
end;
$$;

-- 댓글 지우기(행 삭제). 내 댓글이거나 내 글에 달린 댓글이면 지우고 그 id 를 돌려준다. 아니면 0행 → 서버가 404
-- (남의 댓글이든 없는 댓글이든 똑같이 답해야 그 id 가 남의 것이라는 게 새지 않는다).
create function public.delete_poll_comment(p_viewer uuid, p_comment_id uuid)
returns setof uuid
language sql
security invoker
set search_path = ''
as $$
  delete from public.poll_comments c
   using public.polls p
   where c.id = p_comment_id
     and p.id = c.poll_id
     and (c.author_id = p_viewer or p.author_id = p_viewer)
  returning c.id;
$$;

-- poll_feed 에 comment_count(보이는 댓글 · active 작성자) 한 칸을 더한다. 반환형이 바뀌면 create or replace 가 안 돼 지우고 다시 만든다
-- (인자는 그대로라 함수는 하나뿐이다). 한 트랜잭션이라 사이에 빈틈이 없다. 나머지(탭 · 커서 · 가림 · 집계)는 20261015120000 그대로다.
-- 옛 서버(comment_count 를 모름)는 칸을 골라 쓰므로 이 마이그레이션 뒤에도 그대로 돈다.
drop function public.poll_feed(uuid, uuid, timestamptz, uuid, integer, text);

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

-- 관리자 가림 / 해제가 댓글(poll_comment)도 받는다. 20261018035204 의 정의 그대로 + 허용 목록과 표 고르기에 poll_comment.
-- 'poll_comment' 는 앞 파일(20261111000000)에서 이미 커밋된 enum 값이라 여기서 쓸 수 있다.
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
     or p_target is null or p_target not in ('poll', 'friend_review', 'poll_comment') then
    raise exception 'invalid content status change' using errcode = '22023';
  end if;

  if p_target = 'poll' then
    select status into v_before from public.polls where id = p_content for update;
  elsif p_target = 'poll_comment' then
    select status into v_before from public.poll_comments where id = p_content for update;
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
  elsif p_target = 'poll_comment' then
    update public.poll_comments set status = p_status where id = p_content;
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

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
-- poll_feed 는 다시 만든 함수라 새 기본 권한을 받는다 — 옛 정의와 같게 다시 뺀다. admin_set_content_status 는 or replace 라 권한이 그대로다.
revoke execute on function public.add_poll_comment(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.poll_comments_page(uuid, uuid, timestamptz, uuid, integer) from public, anon, authenticated;
revoke execute on function public.delete_poll_comment(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer, text) from public, anon, authenticated;
grant execute on function public.add_poll_comment(uuid, uuid, text) to service_role;
grant execute on function public.poll_comments_page(uuid, uuid, timestamptz, uuid, integer) to service_role;
grant execute on function public.delete_poll_comment(uuid, uuid) to service_role;
grant execute on function public.poll_feed(uuid, uuid, timestamptz, uuid, integer, text) to service_role;
