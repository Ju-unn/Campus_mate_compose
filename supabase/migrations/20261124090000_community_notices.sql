-- 할 일 21 커뮤니티 공지사항(2026-11-24 승인, 설계 docs/superpowers/specs/2026-11-24-community-notices-design.md).
-- 19 의 polls 표(kind · category) 위에 kind='notice' 를 얹는다. 공지 = 운영자 글: 작성자 없음(누가 썼는지는 admin_actions) ·
-- 제목 1~40자 · 본문(question 칸) 1~2000자 · 그림 1장(선택, 공개 버킷 community-notices 의 `{공지 id}.jpg`).
-- 댓글 · 익명N · 하루 한도 · 도배 막기 · 신고 · 관리자 가림이 polls.id 를 보므로 공지에도 그대로 돈다.
-- 배포 순서: 이 마이그레이션 → 서버 → 관리자 웹 → 1.0.7 앱. 옛 서버(19 이전 · 19)는 poll_feed · community_feed 만 읽고 둘 다
-- 작성자 active 조인이라 작성자가 없는 공지를 싣지 않는다 — 이 파일 뒤에도 옛 화면에 공지가 섞이지 않는다.
-- 시험: supabase/tests/community_notices_test.sql.

-- 1. 칸 · check · 인덱스 ------------------------------------------------------
-- polls 를 잠그는 문장(alter table 셋 · create index)은 do 블록 하나(= 한 문장 = 한 트랜잭션)에 둔다(#789 20261123170000 과
-- 같은 모양). 실행기가 파일을 트랜잭션으로 감싸든 문장마다 따로 돌리든(로컬 CLI 는 문장마다 따로 돌린다 — 블록 밖
-- `set local` 은 효과가 없다) 잠금 시간 제한이 걸리고, 칸만 생기고 check 는 실패하는 반쪽 적용이 없다.
-- 잠금은 오래 기다리지 않는다(lock_timeout 5초) — 긴 트랜잭션 뒤에 줄 서서 피드 · 댓글 읽기 · 쓰기를 같이 세우지 않게,
-- 못 잡으면 아무것도 안 바뀐 채 실패하니 다시 적용하면 된다. check 를 더하면 기존 줄을 한 번 훑는다(19 글은 새 check 에 맞다).
-- 아래 함수 · 버킷 행 · grant · comment 는 polls 의 읽기 · 쓰기를 막는 잠금을 잡지 않아 블록 밖에 둔다(#789 도 comment 는 밖).
do $$
begin
  perform set_config('lock_timeout', '5s', true);

  alter table public.polls
    add column title text,
    add column image_path text;

  -- 공지는 작성자가 없다. 탈퇴 cascade(on delete cascade)는 그대로 — null 인 공지는 누구의 탈퇴에도 지워지지 않는다.
  alter table public.polls alter column author_id drop not null;

  -- 본문 길이는 kind 별로: 투표 80 · 게시물 500 · 공지 2000. 나머지 19 check(선택지 유무 · 라벨 길이)는 공지(선택지 null)에 그대로 맞다.
  alter table public.polls
    drop constraint polls_kind,
    add constraint polls_kind check (kind in ('poll', 'post', 'notice')),
    drop constraint polls_question_length,
    add constraint polls_question_length check (
      question = btrim(question)
      and char_length(question) between 1 and case kind when 'poll' then 80 when 'post' then 500 else 2000 end),
    -- 공지면 작성자가 없고, 공지가 아니면 작성자가 있다 — 앱 길(create_community_item)로는 작성자 없는 글이 생기지 않는다.
    add constraint polls_notice_author check ((kind = 'notice') = (author_id is null)),
    -- 제목은 공지만, 앞뒤 공백을 깎은 1~40자. 서버가 깎아 넣는다.
    add constraint polls_notice_title check (
      (kind = 'notice') = (title is not null)
      and (title is null or (title = btrim(title) and char_length(title) between 1 and 40))),
    -- 그림은 공지만, 선택. 경로는 서버가 정한 `{공지 id}.jpg` 하나뿐 — 임의 URL · 남의 경로를 넣을 수 없다(보안 기준 21-4).
    add constraint polls_notice_image check (image_path is null or (kind = 'notice' and image_path = id::text || '.jpg'));

  -- 공지 목록(notice_list)은 공지만 최신순 + 커서로 읽는다. 공지는 몇 개뿐이라 부분 인덱스가 작다 — 피드 인덱스를 거슬러 걸러 내지 않는다.
  -- 만드는 동안 polls 쓰기가 잠깐 멈춘다(share 잠금) — 그래서 이것도 잠금 시간 제한 안에 둔다.
  create index polls_notice_created_id_index on public.polls (created_at desc, id desc) where kind = 'notice';
end;
$$;

comment on table public.polls is
  '커뮤니티 글(투표 · 게시물 · 공지). FastAPI 전용. author_id 는 어떤 응답에도 담지 않는다(poll_feed · community_feed · notice_list 가 칸을 주지 않는다)';
comment on column public.polls.kind is 'poll = O/X 투표, post = 글만 있는 게시물(할 일 19), notice = 운영자 공지(할 일 21, 작성자 없음)';
comment on column public.polls.author_id is '글쓴이. 공지면 null(누가 올렸는지는 admin_actions notice_create)';
comment on column public.polls.question is '투표의 질문(1~80자) · 게시물 본문(1~500자) · 공지 본문(1~2000자). 앞뒤 공백을 깎은 모양';
comment on column public.polls.title is '공지 제목(1~40자). 공지가 아니면 null';
comment on column public.polls.image_path is '공지 그림의 community-notices 버킷 경로 `{id}.jpg`(선택). 공지가 아니면 null';

-- 2. 앱 글쓰기 함수가 공지를 만들지 않게 --------------------------------------------
-- create_community_item: 20261123155829 의 정의 그대로 + 맨 앞 kind 검사. 공지는 작성자 check 로도 막히지만(23514)
-- "운영자 글은 관리자 길만" 을 함수 첫 줄로 못박는다(보안 기준 21-2). 서버는 kind 를 앱에서 받지 않는다.
create or replace function public.create_community_item(
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
  if p_kind is null or p_kind not in ('poll', 'post') then
    raise exception 'invalid community item kind' using errcode = '22023';
  end if;

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

-- 3. 댓글 함수 둘이 공지를 받게 -------------------------------------------------------
-- add_poll_comment: 20261112090000(도배 막기 판)의 정의 그대로 + 세 곳.
--   ① 글 확인: 보이는 글이고 "공지이거나 작성자 active". 작성자 조인을 left join 으로.
--   ② 익명N 판단 `p_author <> v_poll_author` → `is distinct from` — 공지는 글쓴이가 null 이라 <> 가 null 이 돼 번호를 못 받는다.
--   ③ is_post_author 도 `is not distinct from` — 공지 댓글은 false(null 이 아니다).
-- 공지면 poll_author_id 가 null 이다 — 서버(comment_push)가 null 이면 푸시를 보내지 않는다.
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
  -- 가려진 글 · 글쓴이가 active 가 아닌 글은 피드에 없다 — 없는 글과 같게 답한다(cast_poll_vote 와 같다). 공지는 글쓴이가 없다.
  select p.author_id, p.question into v_poll_author, v_question
    from public.polls p
    left join public.profiles a on a.id = p.author_id
   where p.id = p_poll_id and p.status = 'visible'
     and (p.kind = 'notice' or a.status = 'active');
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

  -- 글쓴이는 번호가 없다. 나머지는 글 안에서 처음 쓸 때 다음 번호(가장 큰 번호 + 1)를 받는다. 공지는 모두 번호를 받는다.
  if p_author is distinct from v_poll_author then
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

  return query select v_comment_id, p_body, v_created, v_alias, p_author is not distinct from v_poll_author, true, true,
                      v_poll_author, v_question;
end;
$$;

-- poll_comments_page: 20261111000200 의 정의 그대로 + 글 확인(add_poll_comment 와 같은 ①)과 글쓴이 비교 셋을 `is not distinct from` 으로.
-- 공지 댓글은 글쓴이 표시가 없고(false), 지우기는 내 댓글만(공지 글쓴이가 없다).
create or replace function public.poll_comments_page(
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
    left join public.profiles a on a.id = p.author_id
   where p.id = p_poll_id and p.status = 'visible'
     and (p.kind = 'notice' or a.status = 'active');
  if not found then
    raise exception 'poll not found' using errcode = 'CM404';
  end if;

  return query
  select c.id, c.body, c.created_at,
         -- 글쓴이 댓글은 번호 대신 is_post_author 로 알린다.
         case when c.author_id is not distinct from v_poll_author then null else al.alias_no end,
         c.author_id is not distinct from v_poll_author,
         c.author_id = p_viewer,
         -- 내 댓글이거나 내 글에 달린 댓글이면 지울 수 있다.
         c.author_id = p_viewer or v_poll_author is not distinct from p_viewer
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

-- 4. 공지 목록 · 상세 ----------------------------------------------------------------
-- 가리지 않은 공지 최신순 + (created_at, id) 커서. p_notice_id 를 주면 그 공지 하나(상세 · 띠). 작성자 칸은 없다.
-- p_viewer 는 지금 쓰지 않는다 — 다른 피드 함수와 인자 모양을 맞춰 둔다(설계 그대로).
create function public.notice_list(
  p_viewer uuid,
  p_notice_id uuid default null,
  p_before timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  title text,
  text text,
  image_path text,
  created_at timestamptz,
  comment_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.title, p.question, p.image_path, p.created_at,
         -- 보이는 댓글 · active 작성자만(poll_feed · community_feed 와 같다).
         (select count(*) from public.poll_comments pc
            join public.profiles ca on ca.id = pc.author_id and ca.status = 'active'
           where pc.poll_id = p.id and pc.status = 'visible')
    from public.polls p
   where p.kind = 'notice'
     and p.status = 'visible'
     and (p_notice_id is null or p.id = p_notice_id)
     and (p_before is null or (p.created_at, p.id) < (p_before, p_before_id))
   order by p.created_at desc, p.id desc
   limit p_limit;
$$;

-- 5. 관리자 공지 작성 · 삭제 ----------------------------------------------------------
-- admin_set_content_status 와 같은 틀: admin_assert(42501 not admin) → 바꾸기 → admin_actions 한 줄, 한 트랜잭션.
-- 서버가 id 를 먼저 정해 그림을 `{id}.jpg` 로 올린 뒤 부른다(그림 경로 check 가 id 와 묶여 있다). 길이 위반은 23514 → 서버 422.
create function public.admin_create_notice(
  p_admin uuid,
  p_id uuid,
  p_title text,
  p_body text,
  p_image_path text,
  p_ip inet
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform public.admin_assert(p_admin);

  insert into public.polls (id, author_id, kind, title, question, image_path, option_a_label, option_b_label)
  values (p_id, null, 'notice', p_title, p_body, p_image_path, null, null);

  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
  values (p_admin, 'notice_create', 'notice', p_id::text, null,
          jsonb_build_object('title', p_title, 'image_path', p_image_path), null, p_ip);

  return jsonb_build_object('id', p_id);
end;
$$;

-- 지운 공지의 그림 경로를 돌려준다 — 서버가 Storage 에서 지운다. 댓글 · 익명 번호는 cascade 로 같이 지워진다.
-- 공지가 아닌 글(투표 · 게시물)은 이 길로 지우지 않는다(CM404). 사유는 필수(22023).
create function public.admin_delete_notice(p_admin uuid, p_id uuid, p_reason text, p_ip inet)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_title text;
  v_image text;
begin
  perform public.admin_assert(p_admin);
  if nullif(btrim(p_reason), '') is null then
    raise exception 'reason required' using errcode = '22023';
  end if;

  delete from public.polls where id = p_id and kind = 'notice'
  returning title, image_path into v_title, v_image;
  if not found then
    raise exception 'notice not found' using errcode = 'CM404';
  end if;

  insert into public.admin_actions (admin_user_id, action, target_type, target_id, before, after, reason, ip)
  values (p_admin, 'notice_delete', 'notice', p_id::text,
          jsonb_build_object('title', v_title, 'image_path', v_image), null, p_reason, p_ip);

  return jsonb_build_object('id', p_id, 'image_path', v_image);
end;
$$;

-- 6. 그림 버킷 -----------------------------------------------------------------------
-- 공지 그림은 누구나 주소로 보는 안내 그림이라 공개다(home-banners 와 같다). 서버가 다시 저장한 JPEG 만, 장당 2MB.
-- storage.objects 정책은 두지 않는다 — 공개 버킷은 주소로 읽기만 되고, 올리기 · 지우기 · 목록은 서버가 service key 로 한다.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('community-notices', 'community-notices', true, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 7. 권한 -------------------------------------------------------------------------
-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
-- create or replace 한 셋(create_community_item · add_poll_comment · poll_comments_page)은 권한이 남지만 이 파일만 봐도 알 수 있게 다시 적는다.
revoke execute on function public.notice_list(uuid, uuid, timestamptz, uuid, integer) from public, anon, authenticated;
revoke execute on function public.admin_create_notice(uuid, uuid, text, text, text, inet) from public, anon, authenticated;
revoke execute on function public.admin_delete_notice(uuid, uuid, text, inet) from public, anon, authenticated;
revoke execute on function public.create_community_item(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.add_poll_comment(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.poll_comments_page(uuid, uuid, timestamptz, uuid, integer) from public, anon, authenticated;
grant execute on function public.notice_list(uuid, uuid, timestamptz, uuid, integer) to service_role;
grant execute on function public.admin_create_notice(uuid, uuid, text, text, text, inet) to service_role;
grant execute on function public.admin_delete_notice(uuid, uuid, text, inet) to service_role;
grant execute on function public.create_community_item(uuid, text, text, text, text, text) to service_role;
grant execute on function public.add_poll_comment(uuid, uuid, text) to service_role;
grant execute on function public.poll_comments_page(uuid, uuid, timestamptz, uuid, integer) to service_role;
