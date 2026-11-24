-- 할 일 21 커뮤니티 공지사항 검증. 마이그레이션 20261124090000_community_notices.
-- 기대값 기준: docs/superpowers/specs/2026-11-24-community-notices-design.md "시험" 절 · 보안담당 2차 검증 기준 21 의 1~5.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(70);

-- 준비 --------------------------------------------------------------------
-- C0 = ...c0(댓글 첫째) · C1 = ...c1(댓글 둘째) · AU = ...c2(게시물 글쓴이) · LIM = ...c3(댓글 한도)
-- AD = ...ad21(관리자, 학교 메일 없음) · NA = ...ad22(관리자 아님)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000921', '테스트대학교921', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test921.ac.kr', '00000000-0000-0000-0000-000000000921');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c0', 'cn-c0@test921.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c1', 'cn-c1@test921.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c2', 'cn-au@test921.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c3', 'cn-lim@test921.ac.kr'),
  ('00000000-0000-0000-0000-00000000ad21', 'operator21@example.com'),
  ('00000000-0000-0000-0000-00000000ad22', 'someone21@example.com');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000921' from auth.users
where id between '00000000-0000-0000-0000-0000000000c0' and '00000000-0000-0000-0000-0000000000c3'
on conflict (id) do nothing;

update public.profiles set
  status = 'active', gender = 'female', birth_year = 2003, height_cm = 165,
  nickname = case id
    when '00000000-0000-0000-0000-0000000000c0' then '공지하나'
    when '00000000-0000-0000-0000-0000000000c1' then '공지둘'
    when '00000000-0000-0000-0000-0000000000c2' then '글쓴이'
    when '00000000-0000-0000-0000-0000000000c3' then '댓글한도'
  end
where id between '00000000-0000-0000-0000-0000000000c0' and '00000000-0000-0000-0000-0000000000c3';

insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-00000000ad21');

-- 단정이 로컬에서 손으로 만든 글과 섞이지 않게 비운다(끝에 rollback 된다).
delete from public.polls;

-- 1. 칸 · check (보안 기준 21-2: 운영자 글은 작성자가 없다) ----------------------------
select has_column('public', 'polls', 'title', 'polls 에 title 칸이 있다');
select has_column('public', 'polls', 'image_path', 'polls 에 image_path 칸이 있다');
select col_is_null('public', 'polls', 'author_id', '공지를 위해 author_id 는 비울 수 있다');
select has_index('public', 'polls', 'polls_notice_created_id_index', '공지 목록용 부분 인덱스가 있다');

select lives_ok(
  $$insert into public.polls (id, kind, title, question, image_path, option_a_label, option_b_label)
    values ('00000000-0000-0000-0000-00000000aa01', 'notice', '서비스 점검 안내', '본문', '00000000-0000-0000-0000-00000000aa01.jpg', null, null)$$,
  '공지는 작성자 없이 제목 · 본문 · 그림 경로로 들어간다'
);
select throws_ok(
  $$insert into public.polls (kind, author_id, title, question, option_a_label, option_b_label)
    values ('notice', '00000000-0000-0000-0000-0000000000c2', '제목', '본문', null, null)$$,
  '23514', null, '작성자가 있는 공지는 들어가지 않는다'
);
select throws_ok(
  $$insert into public.polls (kind, question, option_a_label, option_b_label) values ('post', '주인 없는 글', null, null)$$,
  '23514', null, '작성자 없는 게시물은 들어가지 않는다'
);
select throws_ok(
  $$insert into public.polls (kind, title, question, option_a_label, option_b_label) values ('notice', null, '본문', null, null)$$,
  '23514', null, '제목 없는 공지는 들어가지 않는다'
);
select lives_ok(
  $$insert into public.polls (kind, title, question, option_a_label, option_b_label) values ('notice', repeat('가', 40), '본문', null, null)$$,
  '공지 제목은 40자까지 들어간다'
);
select throws_ok(
  $$insert into public.polls (kind, title, question, option_a_label, option_b_label) values ('notice', repeat('가', 41), '본문', null, null)$$,
  '23514', null, '공지 제목은 40자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (kind, title, question, option_a_label, option_b_label) values ('notice', ' 앞 공백', '본문', null, null)$$,
  '23514', null, '앞뒤 공백을 깎지 않은 제목은 들어가지 않는다'
);
select lives_ok(
  $$insert into public.polls (kind, title, question, option_a_label, option_b_label) values ('notice', '긴 본문', repeat('가', 2000), null, null)$$,
  '공지 본문은 2000자까지 들어간다'
);
select throws_ok(
  $$insert into public.polls (kind, title, question, option_a_label, option_b_label) values ('notice', '넘친 본문', repeat('가', 2001), null, null)$$,
  '23514', null, '공지 본문은 2000자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (kind, author_id, question, option_a_label, option_b_label)
    values ('post', '00000000-0000-0000-0000-0000000000c2', repeat('가', 501), null, null)$$,
  '23514', null, '게시물 본문은 그대로 500자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (kind, author_id, title, question, option_a_label, option_b_label)
    values ('post', '00000000-0000-0000-0000-0000000000c2', '제목', '게시물', null, null)$$,
  '23514', null, '게시물에는 제목을 넣을 수 없다'
);
select throws_ok(
  $$insert into public.polls (kind, author_id, question, image_path, option_a_label, option_b_label)
    values ('post', '00000000-0000-0000-0000-0000000000c2', '게시물', 'x.jpg', null, null)$$,
  '23514', null, '게시물에는 그림 경로를 넣을 수 없다'
);
select throws_ok(
  $$insert into public.polls (kind, author_id, title, question) values ('poll', '00000000-0000-0000-0000-0000000000c2', '제목', '투표')$$,
  '23514', null, '투표에는 제목을 넣을 수 없다'
);
select throws_ok(
  $$insert into public.polls (id, kind, title, question, image_path, option_a_label, option_b_label)
    values ('00000000-0000-0000-0000-00000000aa02', 'notice', '남의 경로', '본문', 'https://evil.example/x.jpg', null, null)$$,
  '23514', null, '공지 그림 경로는 서버가 만든 {공지 id}.jpg 뿐이다(임의 URL 을 넣을 수 없다)'
);
select throws_ok(
  $$insert into public.polls (kind, title, question, option_a_label, option_b_label) values ('notice', '선택지', '본문', '찬성', '반대')$$,
  '23514', null, '공지에는 선택지가 없다'
);

-- 2. create_community_item 은 공지를 만들지 않는다(보안 기준 21-2) ----------------------
select throws_ok(
  $$select public.create_community_item('00000000-0000-0000-0000-0000000000c2', 'notice', 'free', '앱이 만든 공지')$$,
  '22023', null, '앱 글쓰기 함수로는 공지를 만들 수 없다'
);

-- 3. 피드 · 목록 데이터 -------------------------------------------------------------
delete from public.polls;

-- N1(공지 · 3분 전) · N2(공지 · 2분 전) · N3(공지 · 1분 전) · NB(가려진 공지 · 30초 전) · T1(게시물 · 4분 전, AU)
insert into public.polls (id, author_id, kind, category, title, question, image_path, option_a_label, option_b_label, status, created_at) values
  ('00000000-0000-0000-0000-00000000ab01', null, 'notice', 'free', '첫 공지', '첫 본문', '00000000-0000-0000-0000-00000000ab01.jpg', null, null, 'visible', now() - interval '3 minutes'),
  ('00000000-0000-0000-0000-00000000ab02', null, 'notice', 'free', '둘째 공지', '둘째 본문', null, null, null, 'visible', now() - interval '2 minutes'),
  ('00000000-0000-0000-0000-00000000ab03', null, 'notice', 'free', '셋째 공지', '셋째 본문', null, null, null, 'visible', now() - interval '1 minute'),
  ('00000000-0000-0000-0000-00000000abbb', null, 'notice', 'free', '가린 공지', '가린 본문', null, null, null, 'blinded', now() - interval '30 seconds'),
  ('00000000-0000-0000-0000-00000000ab10', '00000000-0000-0000-0000-0000000000c2', 'post', 'free', null, '게시물', null, null, null, 'visible', now() - interval '4 minutes');

select is(
  (select count(*) from unnest(array['all', 'popular', 'mine', 'voted', 'free', 'career', 'love']) tab,
          lateral public.community_feed('00000000-0000-0000-0000-0000000000c0', null, null, null, 100, tab) f
    where f.kind = 'notice'),
  0::bigint, 'community_feed 는 어느 탭에도 공지를 싣지 않는다'
);
select is(
  (select count(*) from public.community_feed('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ab01')),
  0::bigint, 'community_feed 상세(p_item_id)로도 공지를 받지 않는다'
);
select is(
  (select count(*) from unnest(array['all', 'popular', 'mine', 'voted']) tab,
          lateral public.poll_feed('00000000-0000-0000-0000-0000000000c0', null, null, null, 100, tab) f
    where f.id::text like '00000000-0000-0000-0000-00000000ab0%'),
  0::bigint, '옛 poll_feed 는 어느 탭에도 공지를 싣지 않는다(1.0.6)'
);
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-0000000000c0', 'a')$$,
  'CM404', null, '공지에는 투표할 수 없다'
);

-- notice_list: 가리지 않은 공지만 최신순, 작성자 칸 없음.
select results_eq(
  $$select id, title, text, image_path from public.notice_list('00000000-0000-0000-0000-0000000000c0')$$,
  $$values ('00000000-0000-0000-0000-00000000ab03'::uuid, '셋째 공지'::text, '셋째 본문'::text, null::text),
           ('00000000-0000-0000-0000-00000000ab02'::uuid, '둘째 공지'::text, '둘째 본문'::text, null::text),
           ('00000000-0000-0000-0000-00000000ab01'::uuid, '첫 공지'::text, '첫 본문'::text, '00000000-0000-0000-0000-00000000ab01.jpg'::text)$$,
  'notice_list 는 가리지 않은 공지만 최신순으로 준다(게시물 · 가린 공지 없음)'
);
select ok(
  not exists (
    select 1 from pg_proc p, unnest(p.proargnames) arg
     where p.oid = 'public.notice_list(uuid,uuid,timestamptz,uuid,integer)'::regprocedure and arg ilike '%author%'),
  'notice_list 반환 칸에 작성자가 없다'
);
select results_eq(
  $$select id from public.notice_list('00000000-0000-0000-0000-0000000000c0', null, null, null, 1)$$,
  $$values ('00000000-0000-0000-0000-00000000ab03'::uuid)$$,
  '쪽 크기만큼만 준다'
);
select results_eq(
  $$select id from public.notice_list('00000000-0000-0000-0000-0000000000c0', null,
      (select created_at from public.polls where id = '00000000-0000-0000-0000-00000000ab03'),
      '00000000-0000-0000-0000-00000000ab03', 20)$$,
  $$values ('00000000-0000-0000-0000-00000000ab02'::uuid), ('00000000-0000-0000-0000-00000000ab01'::uuid)$$,
  '(created_at, id) 커서 뒤의 공지만 준다'
);
select is(
  (select count(*) from public.notice_list('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000abbb')),
  0::bigint, '가린 공지는 하나 읽기(p_notice_id)로도 없다'
);
select is(
  (select count(*) from public.notice_list('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ab10')),
  0::bigint, '게시물 id 로 notice_list 를 불러도 없다'
);

-- 4. 공지 댓글: 익명N · 한도 · 가림 (보안 기준 21-5) ------------------------------------
select results_eq(
  $$select alias_no, is_post_author, is_mine, can_delete, poll_author_id, poll_question
      from public.add_poll_comment('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ab01', '첫 댓글')$$,
  $$values (1, false, true, true, null::uuid, '첫 본문'::text)$$,
  '공지 첫 댓글은 익명1, 글쓴이 표시 없음, 푸시 받을 글쓴이 null'
);
select results_eq(
  $$select alias_no, is_post_author from public.add_poll_comment('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000ab01', '둘째 댓글')$$,
  $$values (2, false)$$,
  '공지 둘째 사람은 익명2'
);
select results_eq(
  $$select alias_no from public.add_poll_comment('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ab01', '다시 첫째')$$,
  $$values (1)$$,
  '같은 사람은 같은 번호를 다시 받는다'
);
select results_eq(
  $$select alias_no, is_post_author, is_mine, can_delete
      from public.poll_comments_page('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ab01')$$,
  $$values (1, false, true, true), (2, false, false, false), (1, false, true, true)$$,
  '공지 댓글 목록: 글쓴이 표시 없음, 지우기는 내 댓글만'
);
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ab01', '다시 첫째')$$,
  'CM409', null, '공지 댓글도 바로 전 댓글과 같은 본문은 막힌다'
);
insert into public.poll_comments (poll_id, author_id, body)
select '00000000-0000-0000-0000-00000000ab10', '00000000-0000-0000-0000-0000000000c3', '한도 채우기 ' || g
  from generate_series(1, 50) g;
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-00000000ab01', '51번째')$$,
  'CM429', null, '공지 댓글도 하루 50개 한도를 같이 센다'
);
select is(
  (select count(*) from public.delete_poll_comment('00000000-0000-0000-0000-0000000000c0',
     (select id from public.poll_comments where poll_id = '00000000-0000-0000-0000-00000000ab01'
         and author_id = '00000000-0000-0000-0000-0000000000c1'))),
  0::bigint, '공지 댓글은 남의 것을 지울 수 없다(공지 글쓴이가 없다)'
);
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000abbb', '가린 공지에')$$,
  'CM404', null, '가린 공지에는 댓글을 쓸 수 없다'
);
select throws_ok(
  $$select * from public.poll_comments_page('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000abbb')$$,
  'CM404', null, '가린 공지의 댓글은 읽을 수 없다'
);
select is(
  (select comment_count from public.notice_list('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ab01')),
  3::bigint, 'notice_list 의 comment_count 는 보이는 댓글 수다'
);
select lives_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad21', 'poll_comment',
      (select id from public.poll_comments where poll_id = '00000000-0000-0000-0000-00000000ab01'
          and author_id = '00000000-0000-0000-0000-0000000000c1'), 'blinded', '욕설', null)$$,
  '관리자는 공지 댓글을 가릴 수 있다'
);
select is(
  (select count(*) from public.poll_comments_page('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ab01')),
  2::bigint, '가린 공지 댓글은 목록에 없다'
);
select lives_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad21', 'poll',
      '00000000-0000-0000-0000-00000000ab02', 'blinded', '잘못 올림', null)$$,
  '관리자는 공지를 기존 가림 길로 가릴 수 있다'
);
select is(
  (select count(*) from public.notice_list('00000000-0000-0000-0000-0000000000c0') where id = '00000000-0000-0000-0000-00000000ab02'),
  0::bigint, '가린 공지는 목록에서 빠진다'
);
-- 게시물 댓글은 그대로 — 글쓴이는 번호 없이 is_post_author.
select results_eq(
  $$select alias_no, is_post_author, poll_author_id
      from public.add_poll_comment('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-00000000ab10', '내 글 댓글')$$,
  $$values (null::integer, true, '00000000-0000-0000-0000-0000000000c2'::uuid)$$,
  '게시물 글쓴이 댓글은 그대로 번호 없음 · 글쓴이 표시 · 푸시 받을 글쓴이 있음'
);

-- 5. 관리자 공지 작성 · 삭제 (보안 기준 21-1) -------------------------------------------
select throws_ok(
  $$select public.admin_create_notice('00000000-0000-0000-0000-00000000ad22', '00000000-0000-0000-0000-00000000ac01',
      '관리자 아님', '본문', null, null)$$,
  '42501', 'not admin', '관리자가 아니면 공지를 만들 수 없다'
);
select throws_ok(
  $$select public.admin_create_notice(null, '00000000-0000-0000-0000-00000000ac01', '관리자 없음', '본문', null, null)$$,
  '42501', 'not admin', '관리자 id 가 비면 공지를 만들 수 없다'
);
select is(
  public.admin_create_notice('00000000-0000-0000-0000-00000000ad21', '00000000-0000-0000-0000-00000000ac01',
    '새 공지', '새 본문', '00000000-0000-0000-0000-00000000ac01.jpg', '203.0.113.7'),
  jsonb_build_object('id', '00000000-0000-0000-0000-00000000ac01'),
  '관리자는 공지를 만들고 id 를 받는다'
);
select results_eq(
  $$select kind, author_id, title, question, image_path, option_a_label, status::text
      from public.polls where id = '00000000-0000-0000-0000-00000000ac01'$$,
  $$values ('notice'::text, null::uuid, '새 공지'::text, '새 본문'::text, '00000000-0000-0000-0000-00000000ac01.jpg'::text, null::text, 'visible'::text)$$,
  '만든 공지는 작성자 없는 보이는 공지다'
);
select results_eq(
  $$select admin_user_id, target_type, target_id, after ->> 'title', after ->> 'image_path', host(ip)
      from public.admin_actions where action = 'notice_create'$$,
  $$values ('00000000-0000-0000-0000-00000000ad21'::uuid, 'notice'::text, '00000000-0000-0000-0000-00000000ac01'::text,
            '새 공지'::text, '00000000-0000-0000-0000-00000000ac01.jpg'::text, '203.0.113.7'::text)$$,
  '공지 작성은 admin_actions 에 notice_create 로 남는다'
);
select throws_ok(
  $$select public.admin_create_notice('00000000-0000-0000-0000-00000000ad21', '00000000-0000-0000-0000-00000000ac02',
      repeat('가', 41), '본문', null, null)$$,
  '23514', null, '관리자 길도 제목 40자를 넘을 수 없다'
);
select throws_ok(
  $$select public.admin_delete_notice('00000000-0000-0000-0000-00000000ad22', '00000000-0000-0000-0000-00000000ac01', '사유', null)$$,
  '42501', 'not admin', '관리자가 아니면 공지를 지울 수 없다'
);
select throws_ok(
  $$select public.admin_delete_notice('00000000-0000-0000-0000-00000000ad21', '00000000-0000-0000-0000-00000000ac01', '  ', null)$$,
  '22023', null, '공지 삭제는 사유가 필요하다'
);
select throws_ok(
  $$select public.admin_delete_notice('00000000-0000-0000-0000-00000000ad21', '00000000-0000-0000-0000-00000000ab10', '사유', null)$$,
  'CM404', null, '공지 삭제 길로 게시물은 지울 수 없다'
);
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-00000000ac01', '지워질 댓글')$$,
  '새 공지에 댓글을 단다'
);
select is(
  public.admin_delete_notice('00000000-0000-0000-0000-00000000ad21', '00000000-0000-0000-0000-00000000ac01', '기간 끝', null),
  jsonb_build_object('id', '00000000-0000-0000-0000-00000000ac01', 'image_path', '00000000-0000-0000-0000-00000000ac01.jpg'),
  '공지를 지우면 지운 그림 경로를 돌려준다(서버가 그림을 지운다)'
);
select is(
  (select count(*) from public.poll_comments where poll_id = '00000000-0000-0000-0000-00000000ac01')
  + (select count(*) from public.polls where id = '00000000-0000-0000-0000-00000000ac01'),
  0::bigint, '지운 공지와 그 댓글이 사라진다'
);
select results_eq(
  $$select target_type, target_id, reason, before ->> 'title' from public.admin_actions where action = 'notice_delete'$$,
  $$values ('notice'::text, '00000000-0000-0000-0000-00000000ac01'::text, '기간 끝'::text, '새 공지'::text)$$,
  '공지 삭제는 admin_actions 에 notice_delete 로 남는다'
);
select throws_ok(
  $$select public.admin_delete_notice('00000000-0000-0000-0000-00000000ad21', '00000000-0000-0000-0000-00000000ac01', '다시', null)$$,
  'CM404', null, '이미 지운 공지는 없다'
);

-- 6. 버킷 (보안 기준 21-4) ----------------------------------------------------------
select is((select public from storage.buckets where id = 'community-notices'), true, 'community-notices 는 공개 버킷이다');
select is((select file_size_limit from storage.buckets where id = 'community-notices'), 2097152::bigint, '장당 2MB 까지');
select is((select allowed_mime_types from storage.buckets where id = 'community-notices'), array['image/jpeg'],
  '서버가 다시 저장한 JPEG 만 받는다');
select is(
  (select count(*) from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (coalesce(qual, '') || coalesce(with_check, '')) like '%community-notices%'),
  0::bigint, 'storage.objects 에 이 버킷의 정책이 없다(쓰기 · 목록은 서버 열쇠만)'
);

-- 7. 함수 속성 · 권한 ----------------------------------------------------------------
select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('notice_list', 'admin_create_notice', 'admin_delete_notice')
      and not prosecdef
      and proconfig @> array['search_path=""']),
  3::bigint, '새 함수 셋은 security invoker 이고 search_path 가 빈 값이다'
);
select ok(
  has_function_privilege('service_role', 'public.notice_list(uuid,uuid,timestamptz,uuid,integer)', 'execute')
  and has_function_privilege('service_role', 'public.admin_create_notice(uuid,uuid,text,text,text,inet)', 'execute')
  and has_function_privilege('service_role', 'public.admin_delete_notice(uuid,uuid,text,inet)', 'execute'),
  'service_role 은 새 함수 셋을 부를 수 있다'
);
select ok(
  not has_function_privilege('anon', 'public.notice_list(uuid,uuid,timestamptz,uuid,integer)', 'execute')
  and not has_function_privilege('anon', 'public.admin_create_notice(uuid,uuid,text,text,text,inet)', 'execute')
  and not has_function_privilege('anon', 'public.admin_delete_notice(uuid,uuid,text,inet)', 'execute')
  and not has_function_privilege('authenticated', 'public.notice_list(uuid,uuid,timestamptz,uuid,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.admin_create_notice(uuid,uuid,text,text,text,inet)', 'execute')
  and not has_function_privilege('authenticated', 'public.admin_delete_notice(uuid,uuid,text,inet)', 'execute')
  and not has_function_privilege('authenticated', 'public.add_poll_comment(uuid,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.poll_comments_page(uuid,uuid,timestamptz,uuid,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.create_community_item(uuid,text,text,text,text,text)', 'execute'),
  'anon · authenticated 는 새 함수 · 다시 만든 함수를 부를 수 없다'
);

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000ad21", "role": "authenticated"}';
select throws_ok($$select public.admin_create_notice('00000000-0000-0000-0000-00000000ad21', gen_random_uuid(), '직접', '본문', null, null)$$,
  '42501', null, 'authenticated 는 관리자 토큰이어도 admin_create_notice 를 직접 부를 수 없다');
select throws_ok($$select * from public.notice_list('00000000-0000-0000-0000-00000000ad21')$$,
  '42501', null, 'authenticated 는 notice_list 를 부를 수 없다');

set local role anon;
select throws_ok($$select public.admin_delete_notice('00000000-0000-0000-0000-00000000ad21', gen_random_uuid(), '직접', null)$$,
  '42501', null, 'anon 은 admin_delete_notice 를 부를 수 없다');
select throws_ok($$select * from public.notice_list('00000000-0000-0000-0000-00000000ad21')$$,
  '42501', null, 'anon 은 notice_list 를 부를 수 없다');

select * from finish();
rollback;
