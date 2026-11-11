-- O/X 글 댓글(2026-11-10) 표 · 권한 · DB 함수 검증. 마이그레이션 20261111000000 · 000100 · 000200.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(80);

-- 준비 --------------------------------------------------------------------
-- AU = ...a0(글쓴이) · C1 = ...a1 · C2 = ...a2 · C3 = ...a3(남의 글 글쓴이 · 구경꾼) · LIM = ...a4(하루 50개 확인)
-- OLD = ...a5(어제 이전 댓글만 있는 사람) · SUS = ...a6(정지될 글쓴이) · AD = ...ad02(관리자)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000099', '테스트대학교99', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test99.ac.kr', '00000000-0000-0000-0000-000000000099');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a0', 'pc-au@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000a1', 'pc-c1@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000a2', 'pc-c2@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000a3', 'pc-c3@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000a4', 'pc-lim@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000a5', 'pc-old@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000a6', 'pc-sus@test99.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000099' from auth.users
where id between '00000000-0000-0000-0000-0000000000a0' and '00000000-0000-0000-0000-0000000000a6'
on conflict (id) do nothing;

update public.profiles set
  status = 'active', gender = 'female', birth_year = 2003, height_cm = 165,
  nickname = case id
    when '00000000-0000-0000-0000-0000000000a0' then '글쓴이다'
    when '00000000-0000-0000-0000-0000000000a1' then '댓글하나'
    when '00000000-0000-0000-0000-0000000000a2' then '댓글둘이'
    when '00000000-0000-0000-0000-0000000000a3' then '구경꾼이'
    when '00000000-0000-0000-0000-0000000000a4' then '쉰개쓴이'
    when '00000000-0000-0000-0000-0000000000a5' then '옛날사람'
    when '00000000-0000-0000-0000-0000000000a6' then '정지될이'
  end
where id between '00000000-0000-0000-0000-0000000000a0' and '00000000-0000-0000-0000-0000000000a6';

insert into auth.users (id, email, raw_app_meta_data)
values ('00000000-0000-0000-0000-00000000ad02', 'operator-pc@example.com', '{"provider": "google", "providers": ["google"]}');
insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-00000000ad02');

-- 글: PA(보임) · PB(가려짐) · PC(C3 의 글) · PL(하루 한도 확인) · PS(정지될 글쓴이의 글) · PG(목록 확인)
delete from public.polls;
insert into public.polls (id, author_id, question, status) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', '학식 vs 편의점', 'visible'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '가려진 글', 'blinded'),
  ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a3', '남의 글', 'visible'),
  ('00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a0', '한도 확인 글', 'visible'),
  ('00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a6', '곧 정지될 사람의 글', 'visible'),
  ('00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a0', '목록 확인 글', 'visible'),
  ('00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000a0', '댓글 없는 글', 'visible');
update public.profiles set status = 'suspended' where id = '00000000-0000-0000-0000-0000000000a6';

-- 1. 표 · 권한 -----------------------------------------------------------
select has_table('public', 'poll_comments', 'poll_comments 표가 있다');
select has_table('public', 'poll_comment_aliases', 'poll_comment_aliases 표가 있다');
select ok((select relrowsecurity from pg_class where oid = 'public.poll_comments'::regclass), 'poll_comments 는 RLS 가 켜져 있다');
select ok((select relrowsecurity from pg_class where oid = 'public.poll_comment_aliases'::regclass), 'poll_comment_aliases 는 RLS 가 켜져 있다');
select is(
  (select count(*) from pg_policies where tablename in ('poll_comments', 'poll_comment_aliases')),
  0::bigint, '두 표에는 정책이 하나도 없다(FastAPI 전용 — author_id 를 열면 익명이 깨진다)'
);
select table_privs_are('public', 'poll_comments', 'service_role', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'service_role 은 poll_comments 에 네 권한이 다 있다');
select table_privs_are('public', 'poll_comment_aliases', 'service_role', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'service_role 은 poll_comment_aliases 에 네 권한이 다 있다');
select enum_has_labels(
  'public', 'report_target',
  array['profile', 'message', 'friend_review', 'poll', 'poll_comment'],
  'report_target 에 poll_comment 가 더해졌다'
);
select is(
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'notification_settings' and column_name = 'poll_comment'),
  'true', '알림 스위치 poll_comment 는 기본 켜짐이다'
);
select col_not_null('public', 'notification_settings', 'poll_comment', '알림 스위치 poll_comment 는 null 이 될 수 없다');
select lives_ok(
  $$insert into public.notifications (profile_id, kind, title, body, data)
    values ('00000000-0000-0000-0000-0000000000a0', 'poll_comment', '내 질문에 새 댓글이 달렸어요', '학식 vs 편의점',
            '{"route": "poll", "poll_id": "00000000-0000-0000-0000-0000000000e1"}')$$,
  '알림함은 poll_comment 종류를 받는다'
);
select lives_ok(
  $$insert into public.pending_pushes (profile_id, kind, title, body)
    values ('00000000-0000-0000-0000-0000000000a0', 'poll_comment', '내 질문에 새 댓글이 달렸어요', '학식 vs 편의점')$$,
  '밤 보관함은 poll_comment 종류를 받는다'
);
select throws_ok(
  $$insert into public.notifications (profile_id, kind, title, body)
    values ('00000000-0000-0000-0000-0000000000a0', 'poll_commentx', '제목', '본문')$$,
  '23514', null, '모르는 알림 종류는 여전히 막힌다'
);

-- 2. 제약 -----------------------------------------------------------------
select throws_ok(
  $$insert into public.poll_comments (poll_id, author_id, body)
    values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', repeat('가', 201))$$,
  '23514', null, '댓글은 200자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.poll_comments (poll_id, author_id, body)
    values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', '   ')$$,
  '23514', null, '빈칸뿐인 댓글은 들어가지 않는다'
);
select throws_ok(
  $$insert into public.poll_comments (poll_id, author_id, body)
    values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', ' 앞뒤 공백 ')$$,
  '23514', null, '앞뒤 공백이 남은 댓글은 들어가지 않는다(서버가 깎아 넣는다)'
);
select lives_ok(
  $$insert into public.poll_comments (poll_id, author_id, body)
    values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', repeat('가', 200))$$,
  '댓글 200자는 들어간다(경계)'
);
delete from public.poll_comments;
select throws_ok(
  $$insert into public.poll_comment_aliases (poll_id, profile_id, alias_no)
    values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', 0)$$,
  '23514', null, '익명 번호는 1부터다'
);
insert into public.poll_comment_aliases (poll_id, profile_id, alias_no)
values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', 7);
select throws_ok(
  $$insert into public.poll_comment_aliases (poll_id, profile_id, alias_no)
    values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a2', 7)$$,
  '23505', null, '한 글 안에서 같은 번호를 두 사람이 가질 수 없다'
);
delete from public.poll_comment_aliases;

-- 3. add_poll_comment: 번호 부여 ---------------------------------------------
select results_eq(
  $$select alias_no, is_post_author, is_mine, can_delete, poll_question, poll_author_id
      from public.add_poll_comment('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e1', '첫 댓글')$$,
  $$values (1, false, true, true, '학식 vs 편의점', '00000000-0000-0000-0000-0000000000a0'::uuid)$$,
  '첫 댓글은 익명1 이고 내 것이라 지울 수 있다. 글쓴이 id · 질문은 푸시용으로 같이 온다'
);
select is(
  (select alias_no from public.add_poll_comment('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e1', '두 번째')),
  1, '같은 사람은 같은 글에서 같은 번호를 쓴다'
);
select is(
  (select alias_no from public.add_poll_comment('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000e1', '다른 사람')),
  2, '다른 사람의 첫 댓글은 익명2 다'
);
select results_eq(
  $$select alias_no, is_post_author from public.add_poll_comment(
      '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000e1', '글쓴이 댓글')$$,
  $$values (null::integer, true)$$,
  '글쓴이는 번호가 없고 is_post_author 가 참이다'
);
select is(
  (select count(*) from public.poll_comment_aliases where poll_id = '00000000-0000-0000-0000-0000000000e1'),
  2::bigint, '번호 행은 글쓴이를 뺀 두 사람뿐이다'
);
select is(
  (select alias_no from public.add_poll_comment('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e3', '다른 글')),
  1, '번호는 글 단위다 — 다른 글에서는 다시 1부터'
);
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e2', '가려진 글')$$,
  'CM404', null, '가려진 글에는 댓글을 달 수 없다(없는 글과 같게)'
);
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e4', '정지된 사람 글')$$,
  'CM404', null, '글쓴이가 active 가 아닌 글에는 댓글을 달 수 없다'
);
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000ff', '없는 글')$$,
  'CM404', null, '없는 글'
);
select ok(
  -- 줄 머리가 perform 이어야 한다(주석 처리된 잠금 글자로 통과하는 가짜 GREEN 을 막는다).
  pg_get_functiondef('public.add_poll_comment(uuid,uuid,text)'::regprocedure) ~ '\n\s*perform pg_advisory_xact_lock\(hashtext\(''poll_comment_alias''\)',
  'add_poll_comment 는 글 단위 잠금으로 번호를 준다(동시에 첫 댓글이 두 개여도 번호가 겹치지 않는다)'
);

-- 4. 하루 50개(한국 시간) ---------------------------------------------------
-- 경계는 한국 시간 0시다(community_polls_test.sql 의 create_poll 경계와 같은 식). 'Asia/Seoul' 이 'UTC' 로 바뀌면 지금이 한국 시간
-- 0~9시일 때는 아래 첫 시험이, 9시 이후일 때는 51번째 시험이 깨진다 — 어느 시각에 돌려도 둘 중 하나가 잡는다.
-- 어제(한국 시간 0시 1분 전) 댓글 60개: 오늘 한도에 들지 않는다.
insert into public.poll_comments (poll_id, author_id, body, created_at)
select '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a4', '어제 ' || g,
       (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') - interval '1 minute'
  from generate_series(1, 60) g;
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000e5', '오늘 첫 댓글')$$,
  '어제(한국 시간) 쓴 댓글 60개는 오늘 한도에 들지 않는다'
);
-- 오늘(한국 시간 0시 이후) 댓글 48개를 더해 방금 단 것까지 49개로 맞춘다.
-- shortcut: 한국 시간 00:00~00:01(UTC 15:00~15:01)에 돌리면 이 48줄이 1분 창(CM42B, 20261112090000)에 들어가 '오십 번째' · '쉰한 번째' 가 CM42B 로 떨어질 수 있다. 하루 약 61초, 자주 떨어지면 pgTAP skip 으로.
insert into public.poll_comments (poll_id, author_id, body, created_at)
select '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a4', '오늘 ' || g,
       (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') + interval '1 second'
  from generate_series(1, 48) g;
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000e5', '오십 번째')$$,
  '오늘 49개 뒤의 50번째 댓글은 달린다'
);
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000e5', '쉰한 번째')$$,
  'CM429', null, '하루 51번째 댓글은 CM429 다'
);
insert into public.poll_comments (poll_id, author_id, body, created_at)
select '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a5', '옛날 ' || g, now() - interval '3 days'
  from generate_series(1, 60) g;
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000e5', '오늘 첫 댓글')$$,
  '며칠 전 댓글은 오늘 한도에 세지 않는다'
);

-- 5. poll_comments_page: 오래된 순 · 커서 · 10개 -------------------------------
-- PG(...e6) 에 댓글 12개. 홀수 g = C1, 짝수 g = C2, 12번만 글쓴이. 3 · 4번은 같은 시각(커서 경계).
-- id 끝 두 자리가 g 다(...0100 + g).
insert into public.poll_comment_aliases (poll_id, profile_id, alias_no) values
  ('00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a1', 1),
  ('00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a2', 2);
insert into public.poll_comments (id, poll_id, author_id, body, created_at)
select ('00000000-0000-0000-0000-0000000001' || lpad(g::text, 2, '0'))::uuid,
       '00000000-0000-0000-0000-0000000000e6',
       case when g = 12 then '00000000-0000-0000-0000-0000000000a0'::uuid
            when g % 2 = 1 then '00000000-0000-0000-0000-0000000000a1'::uuid
            else '00000000-0000-0000-0000-0000000000a2'::uuid end,
       '댓글 ' || g,
       timestamptz '2026-01-01 00:00:00+00' + (case when g = 4 then 3 else g end) * interval '1 minute'
  from generate_series(1, 12) g;

select results_eq(
  $$select right(id::text, 2) from public.poll_comments_page(
      '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6')$$,
  $$select lpad(g::text, 2, '0') from generate_series(1, 10) g$$,
  '첫 쪽은 오래된 순 10개다'
);
select results_eq(
  $$select right(id::text, 2) from public.poll_comments_page(
      '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6',
      timestamptz '2026-01-01 00:00:00+00' + interval '10 minutes', '00000000-0000-0000-0000-000000000110')$$,
  $$values ('11'), ('12')$$,
  '커서 뒤로 남은 두 개가 온다'
);
select results_eq(
  $$select right(id::text, 2) from public.poll_comments_page(
      '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6',
      timestamptz '2026-01-01 00:00:00+00' + interval '3 minutes', '00000000-0000-0000-0000-000000000103', 2)$$,
  $$values ('04'), ('05')$$,
  '같은 시각의 두 댓글(3 · 4번)이 경계에서 빠지지 않는다'
);
select is(
  (select count(*) from public.poll_comments_page(
     '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6', null, null, 11)),
  11::bigint, 'limit + 1 줄을 달라고 하면 11줄이 온다(has_more 판정용)'
);
select results_eq(
  $$select alias_no, is_post_author, is_mine, can_delete from public.poll_comments_page(
      '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6', null, null, 2)$$,
  $$values (1, false, true, true), (2, false, false, false)$$,
  '내 댓글은 is_mine · can_delete 가 참, 남의 댓글은 둘 다 거짓이다'
);
select results_eq(
  $$select alias_no, is_post_author, is_mine, can_delete from public.poll_comments_page(
      '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e6', null, null, 20)
     where right(id::text, 2) = '12'$$,
  $$values (null::integer, true, false, false)$$,
  '글쓴이 댓글은 번호가 null 이고 is_post_author 가 참이다(구경꾼 눈)'
);
select is(
  (select bool_and(can_delete) from public.poll_comments_page(
     '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000e6', null, null, 20)),
  true, '글쓴이는 자기 글의 모든 댓글을 지울 수 있다'
);
select is(
  (select count(*) filter (where is_mine) from public.poll_comments_page(
     '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000e6', null, null, 20)),
  1::bigint, '글쓴이 눈에도 is_mine 은 자기 댓글 하나뿐이다'
);
select is(
  (select bool_or(can_delete) from public.poll_comments_page(
     '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e6', null, null, 20)),
  false, '구경꾼은 아무 댓글도 지울 수 없다'
);
select ok(
  pg_get_function_result('public.poll_comments_page(uuid,uuid,timestamptz,uuid,integer)'::regprocedure) not like '%author_id%',
  'poll_comments_page 는 작성자 칸을 돌려주지 않는다(익명)'
);
select throws_ok(
  $$select * from public.poll_comments_page('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e2')$$,
  'CM404', null, '가려진 글의 댓글은 읽을 수 없다'
);
select throws_ok(
  $$select * from public.poll_comments_page('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e4')$$,
  'CM404', null, '글쓴이가 active 가 아닌 글의 댓글은 읽을 수 없다'
);

-- 6. 가려진 댓글 · 떠난 작성자의 댓글은 목록과 댓글 수에서 빠진다 ------------------------
select is(
  (select comment_count from public.poll_feed('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6')),
  12::bigint, 'poll_feed 의 comment_count 는 보이는 댓글 수다'
);
select is(
  (select comment_count from public.poll_feed('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e3')),
  1::bigint, '댓글 수는 글마다 따로 센다'
);
select is(
  (select comment_count from public.poll_feed('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e7')),
  0::bigint, '댓글이 없는 글은 0 이다(null 이 아니다)'
);
update public.poll_comments set status = 'blinded' where id = '00000000-0000-0000-0000-000000000101';
select is(
  (select count(*) from public.poll_comments_page(
     '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6', null, null, 20)),
  11::bigint, '가려진 댓글은 목록에서 빠진다'
);
select is(
  (select comment_count from public.poll_feed('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6')),
  11::bigint, '가려진 댓글은 댓글 수에서도 빠진다'
);
update public.profiles set status = 'suspended' where id = '00000000-0000-0000-0000-0000000000a2';
select is(
  (select count(*) from public.poll_comments_page(
     '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6', null, null, 20)),
  6::bigint, 'active 가 아닌 사람(C2)의 댓글은 목록에서 빠진다 — 남는 것: C1 의 3 · 5 · 7 · 9 · 11번(1번은 가려짐)과 글쓴이의 12번'
);
select is(
  (select comment_count from public.poll_feed('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e6')),
  6::bigint, 'active 가 아닌 사람의 댓글은 댓글 수에서도 빠진다'
);
update public.profiles set status = 'active' where id = '00000000-0000-0000-0000-0000000000a2';
update public.poll_comments set status = 'visible' where id = '00000000-0000-0000-0000-000000000101';

-- 7. delete_poll_comment -----------------------------------------------------
select is(
  (select count(*) from public.delete_poll_comment('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000101')),
  0::bigint, '구경꾼은 남의 댓글을 지울 수 없다(0행)'
);
select is(
  (select count(*) from public.delete_poll_comment('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000101')),
  0::bigint, '다른 댓글 작성자도 남의 댓글을 지울 수 없다(0행)'
);
select is(
  (select count(*) from public.poll_comments where id = '00000000-0000-0000-0000-000000000101'),
  1::bigint, '막힌 삭제는 아무것도 지우지 않는다'
);
select is(
  (select count(*) from public.delete_poll_comment('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000101')),
  1::bigint, '내 댓글은 지울 수 있다'
);
select is(
  (select count(*) from public.poll_comments where id = '00000000-0000-0000-0000-000000000101'),
  0::bigint, '지운 댓글은 행이 사라진다'
);
select is(
  (select count(*) from public.delete_poll_comment('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-000000000102')),
  1::bigint, '글쓴이는 자기 글에 달린 남의 댓글을 지울 수 있다'
);
select is(
  (select count(*) from public.delete_poll_comment('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000ff')),
  0::bigint, '없는 댓글은 0행이다(남의 것과 구별되지 않는다)'
);
select is(
  (select count(*) from public.delete_poll_comment('00000000-0000-0000-0000-0000000000a0',
     (select id from public.poll_comments where poll_id = '00000000-0000-0000-0000-0000000000e3' limit 1))),
  0::bigint, '남의 글(PC)에 달린 댓글은 내 글이 아니라 지울 수 없다'
);

-- 8. cascade(글 삭제 · 탈퇴) ---------------------------------------------------
delete from public.polls where id = '00000000-0000-0000-0000-0000000000e3';
select is(
  (select count(*) from public.poll_comments where poll_id = '00000000-0000-0000-0000-0000000000e3')
  + (select count(*) from public.poll_comment_aliases where poll_id = '00000000-0000-0000-0000-0000000000e3'),
  0::bigint, '글을 지우면 댓글과 익명 번호도 같이 지워진다'
);
delete from auth.users where id = '00000000-0000-0000-0000-0000000000a2';
select is(
  (select count(*) from public.poll_comments where author_id = '00000000-0000-0000-0000-0000000000a2')
  + (select count(*) from public.poll_comment_aliases where profile_id = '00000000-0000-0000-0000-0000000000a2'),
  0::bigint, '계정이 지워지면 그 사람의 댓글과 익명 번호도 지워진다'
);

-- 9. 함수 모양 · 권한 -----------------------------------------------------------
select is(
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('add_poll_comment', 'poll_comments_page', 'delete_poll_comment', 'poll_feed')),
  4::bigint, '네 함수는 하나씩뿐이다(poll_feed 는 지우고 다시 만들었다)'
);
select results_eq(
  $$select count(*), count(*) filter (where not prosecdef and proconfig = array['search_path=""'])
      from pg_proc where pronamespace = 'public'::regnamespace
       and proname in ('add_poll_comment', 'poll_comments_page', 'delete_poll_comment', 'poll_feed')$$,
  $$values (4::bigint, 4::bigint)$$,
  '네 함수 모두 security invoker · search_path 고정이다'
);
select ok(
  has_function_privilege('service_role', 'public.add_poll_comment(uuid,uuid,text)', 'execute')
  and has_function_privilege('service_role', 'public.poll_comments_page(uuid,uuid,timestamptz,uuid,integer)', 'execute')
  and has_function_privilege('service_role', 'public.delete_poll_comment(uuid,uuid)', 'execute')
  and has_function_privilege('service_role', 'public.poll_feed(uuid,uuid,timestamptz,uuid,integer,text)', 'execute'),
  'service_role 은 네 함수를 부를 수 있다'
);
select ok(
  not has_function_privilege('anon', 'public.add_poll_comment(uuid,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.add_poll_comment(uuid,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.poll_comments_page(uuid,uuid,timestamptz,uuid,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.delete_poll_comment(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.poll_feed(uuid,uuid,timestamptz,uuid,integer,text)', 'execute'),
  '앱 역할은 네 함수를 부를 수 없다'
);

-- 10. 관리자 가림 ------------------------------------------------------------------
select is(
  public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll_comment',
    '00000000-0000-0000-0000-000000000103', 'blinded', '욕설 댓글', '203.0.113.9'),
  '{"id": "00000000-0000-0000-0000-000000000103", "status": "blinded"}'::jsonb,
  '댓글을 가리면 처리 뒤 모양을 돌려준다'
);
select results_eq(
  $$select action, target_type, before, after, reason from public.admin_actions
     where target_id = '00000000-0000-0000-0000-000000000103'$$,
  $$values ('content_blind', 'poll_comment', '{"status": "visible"}'::jsonb, '{"status": "blinded"}'::jsonb, '욕설 댓글')$$,
  '작업 기록에 댓글 가림이 남는다'
);
select is(
  (select status::text from public.poll_comments where id = '00000000-0000-0000-0000-000000000103'),
  'blinded', '표의 댓글 상태가 가려짐으로 바뀐다'
);
select throws_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll_comment',
      '00000000-0000-0000-0000-000000000103', 'blinded', '또', null)$$,
  'CM409', null, '이미 가려진 댓글을 또 가리면 CM409'
);
select is(
  public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll_comment',
    '00000000-0000-0000-0000-000000000103', 'visible', '오해였다', null)->>'status',
  'visible', '가림을 풀 수 있다'
);
select throws_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'poll_comment',
      '00000000-0000-0000-0000-0000000000ff', 'blinded', '없는 댓글', null)$$,
  'CM404', null, '없는 댓글은 CM404'
);
select throws_ok(
  $$select public.admin_set_content_status('00000000-0000-0000-0000-00000000ad02', 'profile',
      '00000000-0000-0000-0000-000000000103', 'blinded', '엉뚱한 종류', null)$$,
  '22023', null, '그 밖의 종류는 여전히 22023'
);

-- 11. 클라이언트 권한 ------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000a0", "role": "authenticated"}';

select throws_ok($$select id from public.poll_comments$$, '42501', null, 'authenticated 는 poll_comments 를 읽을 수 없다');
select throws_ok($$select poll_id from public.poll_comment_aliases$$, '42501', null, 'authenticated 는 poll_comment_aliases 를 읽을 수 없다');
select throws_ok(
  $$insert into public.poll_comments (poll_id, author_id, body)
    values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', '댓글')$$,
  '42501', null, 'authenticated 는 poll_comments 에 쓸 수 없다'
);
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000e1', '댓글')$$,
  '42501', null, 'authenticated 는 add_poll_comment 를 부를 수 없다'
);
select throws_ok(
  $$select * from public.poll_comments_page('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000e1')$$,
  '42501', null, 'authenticated 는 poll_comments_page 를 부를 수 없다'
);
select throws_ok(
  $$select * from public.delete_poll_comment('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-000000000101')$$,
  '42501', null, 'authenticated 는 delete_poll_comment 를 부를 수 없다'
);

set local role anon;
select throws_ok($$select id from public.poll_comments$$, '42501', null, 'anon 은 poll_comments 를 읽을 수 없다');

select * from finish();
rollback;
