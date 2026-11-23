-- 할 일 19 게시물 + 카테고리 검증. 마이그레이션 20261123155829.
-- 기대값 기준: docs/superpowers/specs/2026-11-24-community-posts-design.md "시험" 절 · 보안담당 2차 검증 기준 19 의 1~5.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
-- 동시 요청 두 개로 11번째가 끼는지는 한 트랜잭션 안의 pgTAP 으로 못 본다 — 사람 단위 잠금이 세기 앞에 있고, 옛 create_poll 이
-- 따로 세지 않고 create_community_item 에 넘기는지(한 곳)만 본다(8 절).
begin;

create extension if not exists pgtap with schema extensions;

select plan(64);

-- 준비 --------------------------------------------------------------------
-- AU = ...b0(글쓴이) · C1 = ...b1 · C2 = ...b2 · LIM = ...b3(합산 한도) · VW = ...b4(구경꾼) · SUS = ...b5(정지될 글쓴이)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000098', '테스트대학교98', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test98.ac.kr', '00000000-0000-0000-0000-000000000098');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b0', 'cp-au@test98.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b1', 'cp-c1@test98.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b2', 'cp-c2@test98.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b3', 'cp-lim@test98.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b4', 'cp-vw@test98.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b5', 'cp-sus@test98.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000098' from auth.users
where id between '00000000-0000-0000-0000-0000000000b0' and '00000000-0000-0000-0000-0000000000b5'
on conflict (id) do nothing;

-- active 전환 check(닉네임 · 성별 · 출생연도 · 키)만 채운다. 나머지 칸은 이 테스트와 상관없다.
update public.profiles set
  status = 'active', gender = 'female', birth_year = 2003, height_cm = 165,
  nickname = case id
    when '00000000-0000-0000-0000-0000000000b0' then '게시글이'
    when '00000000-0000-0000-0000-0000000000b1' then '댓글첫째'
    when '00000000-0000-0000-0000-0000000000b2' then '댓글둘째'
    when '00000000-0000-0000-0000-0000000000b3' then '합산열개'
    when '00000000-0000-0000-0000-0000000000b4' then '구경하기'
    when '00000000-0000-0000-0000-0000000000b5' then '정지될글'
  end
where id between '00000000-0000-0000-0000-0000000000b0' and '00000000-0000-0000-0000-0000000000b5';

-- 1. 칸 · check ------------------------------------------------------------
select has_column('public', 'polls', 'kind', 'polls 에 kind 칸이 있다');
select has_column('public', 'polls', 'category', 'polls 에 category 칸이 있다');
select col_not_null('public', 'polls', 'kind', 'kind 는 비울 수 없다');
select col_not_null('public', 'polls', 'category', 'category 는 비울 수 없다');
select col_is_null('public', 'polls', 'option_a_label', '게시물을 위해 option_a_label 은 비울 수 있다');
select col_is_null('public', 'polls', 'option_b_label', '게시물을 위해 option_b_label 은 비울 수 있다');
select is(
  (select count(*) from public.polls where kind <> 'poll' or category <> 'free'),
  0::bigint, '마이그레이션 전부터 있던 행은 모두 투표 · 자유다'
);

delete from public.polls;

-- 옛 서버(create_poll)로 올린 투표 = 1.0.6 앱이 카테고리 없이 만든 투표.
select public.create_poll('00000000-0000-0000-0000-0000000000b4', '옛 길 투표', '찬성', '반대');
select results_eq(
  $$select kind, category, option_a_label, option_b_label from public.polls
     where author_id = '00000000-0000-0000-0000-0000000000b4'$$,
  $$values ('poll'::text, 'free'::text, '찬성'::text, '반대'::text)$$,
  '옛 create_poll 로 올린 투표는 투표 · 자유다'
);
delete from public.polls;

select throws_ok(
  $$insert into public.polls (author_id, kind, question) values ('00000000-0000-0000-0000-0000000000b0', 'notice', '공지')$$,
  '23514', null, 'kind 는 poll · post 둘뿐이다'
);
select throws_ok(
  $$insert into public.polls (author_id, category, question) values ('00000000-0000-0000-0000-0000000000b0', 'hot', '질문')$$,
  '23514', null, 'category 는 free · career · love 셋뿐이다'
);
select lives_ok(
  $$insert into public.polls (author_id, kind, question, option_a_label, option_b_label)
    values ('00000000-0000-0000-0000-0000000000b0', 'post', repeat('가', 500), null, null)$$,
  '게시물 본문은 500자까지 들어간다'
);
select throws_ok(
  $$insert into public.polls (author_id, kind, question, option_a_label, option_b_label)
    values ('00000000-0000-0000-0000-0000000000b0', 'post', repeat('가', 501), null, null)$$,
  '23514', null, '게시물 본문은 500자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (author_id, kind, question) values ('00000000-0000-0000-0000-0000000000b0', 'poll', repeat('가', 81))$$,
  '23514', null, '투표 질문은 그대로 80자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (author_id, kind, question, option_a_label, option_b_label)
    values ('00000000-0000-0000-0000-0000000000b0', 'post', '   ', null, null)$$,
  '23514', null, '빈칸뿐인 게시물은 들어가지 않는다'
);
select throws_ok(
  $$insert into public.polls (author_id, kind, question, option_a_label, option_b_label)
    values ('00000000-0000-0000-0000-0000000000b0', 'post', ' 앞 공백', null, null)$$,
  '23514', null, '앞뒤 공백을 깎지 않은 게시물은 들어가지 않는다'
);
select throws_ok(
  $$insert into public.polls (author_id, kind, question) values ('00000000-0000-0000-0000-0000000000b0', 'post', '선택지 기본값')$$,
  '23514', null, '게시물에 선택지(기본값 찬성 · 반대)가 붙으면 들어가지 않는다'
);
select throws_ok(
  $$insert into public.polls (author_id, kind, question, option_b_label)
    values ('00000000-0000-0000-0000-0000000000b0', 'poll', '한쪽 선택지', null)$$,
  '23514', null, '투표는 선택지 둘이 다 있어야 한다'
);

-- 2. 피드 데이터 -------------------------------------------------------------
-- 피드 단정이 앞 절의 글 · 로컬에서 손으로 만든 글과 섞이지 않게 비운다(끝에 rollback 된다).
delete from public.polls;

-- P1(투표 · 자유 · 3분 전, AU) · P2(투표 · 진로 · 10일 전, C1) · T1(게시물 · 연애 · 2분 전, AU) · T2(게시물 · 진로 · 1분 전, C1)
-- T3(게시물 · 자유 · 4분 전, C2) · TB(가려진 게시물 · 30초 전, AU) · TS(정지될 글쓴이의 게시물 · 20초 전)
insert into public.polls (id, author_id, kind, category, question, option_a_label, option_b_label, status, created_at) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b0', 'poll', 'free', '첫 데이트 더치페이', '찬성', '반대', 'visible', now() - interval '3 minutes'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000b1', 'poll', 'career', '대학원 vs 취업', '대학원', '취업', 'visible', now() - interval '10 days'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000b0', 'post', 'love', '오늘 고백했어요', null, null, 'visible', now() - interval '2 minutes'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000b1', 'post', 'career', '자소서 첨삭 받을 곳', null, null, 'visible', now() - interval '1 minute'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000b2', 'post', 'free', '학식 메뉴 추천', null, null, 'visible', now() - interval '4 minutes'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000b0', 'post', 'free', '가려진 게시물', null, null, 'blinded', now() - interval '30 seconds'),
  ('00000000-0000-0000-0000-0000000000f7', '00000000-0000-0000-0000-0000000000b5', 'post', 'free', '정지될 사람의 글', null, null, 'visible', now() - interval '20 seconds');
update public.profiles set status = 'suspended' where id = '00000000-0000-0000-0000-0000000000b5';

-- 표: P1 = C1 a · C2 b(2), P2 = C2 a(10일 전이라 인기 밖). T2 = VW a — 게시물에는 투표 길이 없지만 표에 직접 들어간 줄로
-- 옛 피드가 "표가 있는 게시물" 도 거르는지 본다. TB 에도 표 하나.
insert into public.poll_votes (poll_id, voter_id, choice) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b1', 'a'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b2', 'b'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000b2', 'a'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000b4', 'a'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000b4', 'a');

-- 댓글: T1 = 3개, T3 = 1개, TB = 2개(가려진 글이라 어디에도 안 나와야 한다).
insert into public.poll_comments (poll_id, author_id, body) values
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000b1', '축하해요'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000b2', '부러워요'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000b4', '응원해요'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000b0', '돈까스요'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000b1', '숨은 댓글 하나'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000b2', '숨은 댓글 둘');

-- 3. 옛 피드 · 투표가 게시물을 모른다(보안 기준 19-5) ---------------------------------
select is(
  array(select id from public.poll_feed('00000000-0000-0000-0000-0000000000b0')),
  array['00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2']::uuid[],
  'poll_feed 전체 탭은 투표만 최신순으로 준다'
);
select is(
  (select count(*)
     from (values ('00000000-0000-0000-0000-0000000000b0'::uuid), ('00000000-0000-0000-0000-0000000000b4'::uuid)) v(viewer)
     cross join unnest(array['all', 'popular', 'mine', 'voted']) t(tab)
     cross join lateral public.poll_feed(v.viewer, p_tab => t.tab) f
    where f.id in ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f4',
                   '00000000-0000-0000-0000-0000000000f5')),
  0::bigint, 'poll_feed 는 어떤 탭(전체 · 인기 · 내 글 · 내 투표)으로도 게시물을 주지 않는다'
);
select is(
  (select count(*) from public.poll_feed('00000000-0000-0000-0000-0000000000b4', p_poll_id => '00000000-0000-0000-0000-0000000000f4')),
  0::bigint, 'poll_feed 상세(p_poll_id)로 게시물 id 를 넣어도 0행이다'
);
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000b1', 'a')$$,
  'CM404', null, '게시물에 투표하면 없는 글과 같게 CM404 다'
);

-- 4. 새 피드 탭 일곱 ----------------------------------------------------------
select is(
  array(select id from public.community_feed('00000000-0000-0000-0000-0000000000b0')),
  array['00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f1',
        '00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000f2']::uuid[],
  '전체 탭은 투표 + 게시물을 최신순으로 준다(가려진 글 · 정지된 글쓴이의 글은 없다)'
);
select is(
  array(select id from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_tab => 'popular')),
  array['00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f4',
        '00000000-0000-0000-0000-0000000000f5']::uuid[],
  '인기 탭은 최근 7일 · 참여(표 + 댓글) 순, 같으면 최신 — 댓글 3 > 표 2 > 표 1(1분 전) > 댓글 1(4분 전)'
);
select is(
  array(select id from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_tab => 'mine')),
  array['00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f1']::uuid[],
  '내 글 탭은 내 투표 · 게시물(가려진 것 빼고)이다'
);
select is(
  array(select id from public.community_feed('00000000-0000-0000-0000-0000000000b2', p_tab => 'voted')),
  array['00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2']::uuid[],
  '내 투표 탭은 내가 표를 준 글이다'
);
select is(
  array(select id from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_tab => 'free')),
  array['00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f5']::uuid[],
  '자유 탭은 자유 카테고리의 투표 · 게시물이다'
);
select is(
  array(select id from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_tab => 'career')),
  array['00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000f2']::uuid[],
  '진로 탭은 진로 카테고리의 투표 · 게시물이다'
);
select is(
  array(select id from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_tab => 'love')),
  array['00000000-0000-0000-0000-0000000000f3']::uuid[],
  '연애 탭은 연애 카테고리의 글이다'
);
select is(
  (select count(*) from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_tab => 'hot')),
  0::bigint, '모르는 탭은 빈 결과다'
);
select is(
  array(select id from public.community_feed('00000000-0000-0000-0000-0000000000b0',
                                              p_before => (select created_at from public.polls where id = '00000000-0000-0000-0000-0000000000f3'),
                                              p_before_id => '00000000-0000-0000-0000-0000000000f3')),
  array['00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000f2']::uuid[],
  '(시각, id) 커서 뒤의 글만 준다'
);
select is(
  (select count(*) from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_limit => 2)),
  2::bigint, 'p_limit 만큼만 준다'
);

-- 5. 상세 · 칸 ---------------------------------------------------------------
select results_eq(
  $$select f.kind, f.category, f.text, f.option_a_label, f.option_b_label, f.a_count, f.b_count, f.my_choice::text, f.is_mine, f.comment_count
      from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_item_id => '00000000-0000-0000-0000-0000000000f3') f$$,
  $$values ('post'::text, 'love'::text, '오늘 고백했어요'::text, null::text, null::text, 0::bigint, 0::bigint, null::text, true, 3::bigint)$$,
  '게시물 상세: 선택지 null · 표 0 · 내 글 · 보이는 댓글 수'
);
select results_eq(
  $$select f.kind, f.option_a_label, f.option_b_label, f.a_count, f.b_count, f.my_choice::text, f.is_mine
      from public.community_feed('00000000-0000-0000-0000-0000000000b1', p_item_id => '00000000-0000-0000-0000-0000000000f1') f$$,
  $$values ('poll'::text, '찬성'::text, '반대'::text, 1::bigint, 1::bigint, 'a'::text, false)$$,
  '투표 상세: 선택지 · 표 수 · 내가 고른 것, 남의 글은 is_mine 거짓'
);
select ok(
  pg_get_function_result('public.community_feed(uuid,uuid,timestamptz,uuid,integer,text)'::regprocedure) not like '%author%'
  and pg_get_function_result('public.community_feed(uuid,uuid,timestamptz,uuid,integer,text)'::regprocedure) not like '%profile%',
  'community_feed 는 작성자 칸을 돌려주지 않는다(익명, 보안 기준 19-1)'
);

-- 6. 가림 · 정지 글쓴이(보안 기준 19-4) ------------------------------------------
select is(
  (select count(*)
     from unnest(array['all', 'popular', 'mine', 'voted', 'free', 'career', 'love']) t(tab)
     cross join (values ('00000000-0000-0000-0000-0000000000b0'::uuid), ('00000000-0000-0000-0000-0000000000b4'::uuid)) v(viewer)
     cross join lateral public.community_feed(v.viewer, p_tab => t.tab) f
    where f.id in ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000f7')),
  0::bigint, '가려진 글 · 정지된 글쓴이의 글은 일곱 탭 어디에도 없다(쓴 사람 · 표 준 사람이 봐도)'
);
select is(
  (select count(*) from public.community_feed('00000000-0000-0000-0000-0000000000b0', p_item_id => '00000000-0000-0000-0000-0000000000f6')),
  0::bigint, '가려진 글은 상세에서 0행이다(쓴 사람이 봐도)'
);
select is(
  (select count(*) from public.community_feed('00000000-0000-0000-0000-0000000000b4', p_item_id => '00000000-0000-0000-0000-0000000000f7')),
  0::bigint, '정지된 글쓴이의 글은 상세에서 0행이다'
);
select is(
  (select count(*)
     from (values (1), (2)) k(n)
     cross join lateral public.community_feed(
       '00000000-0000-0000-0000-0000000000b0',
       p_before => (select created_at from public.polls where id = '00000000-0000-0000-0000-0000000000f6')
                   + case k.n when 1 then interval '1 second' else interval '0' end,
       p_before_id => case k.n when 1 then '00000000-0000-0000-0000-0000000000f6'::uuid
                               else 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid end) f
    where f.id = '00000000-0000-0000-0000-0000000000f6'),
  0::bigint, '가려진 글의 시각 · id 를 커서에 넣어 경계를 바꿔도 그 글은 나오지 않는다'
);
select throws_ok(
  $$select * from public.poll_comments_page('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f6')$$,
  'CM404', null, '가려진 게시물의 댓글 목록은 CM404 다'
);
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-0000000000f6', '숨은 글에 댓글')$$,
  'CM404', null, '가려진 게시물에는 댓글을 달 수 없다'
);

-- 7. 게시물 댓글 · 익명N --------------------------------------------------------
-- T2(C1 의 게시물)에 AU → C2 → 글쓴이 C1 순으로 단다. 번호는 글마다 따로라 T1 에서 쓴 번호와 상관없이 1 부터다.
select results_eq(
  $$select alias_no, is_post_author, is_mine from public.add_poll_comment(
      '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000f4', '저도 궁금해요')$$,
  $$values (1, false, true)$$,
  '게시물의 첫 댓글 작성자는 익명1 이다'
);
select results_eq(
  $$select alias_no, is_post_author from public.add_poll_comment(
      '00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000f4', '학교 센터요')$$,
  $$values (2, false)$$,
  '다른 사람은 익명2 다'
);
select results_eq(
  $$select alias_no, is_post_author from public.add_poll_comment(
      '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f4', '고마워요')$$,
  $$values (null::integer, true)$$,
  '게시물 글쓴이의 댓글은 번호 없이 글쓴이로 표시된다'
);
select is(
  array(select coalesce(alias_no::text, '글쓴이') from public.poll_comments_page(
          '00000000-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-0000000000f4')),
  array['1', '2', '글쓴이'],
  '게시물 댓글 목록은 오래된 순 · 익명 번호 · 글쓴이 표시를 준다'
);
select is(
  (select f.comment_count from public.community_feed('00000000-0000-0000-0000-0000000000b4', p_item_id => '00000000-0000-0000-0000-0000000000f4') f),
  3::bigint, '게시물의 comment_count 가 새 댓글을 센다'
);

-- 8. 올리기 · 하루 합산 한도(보안 기준 19-3) ------------------------------------------
select throws_ok(
  $$select public.create_community_item('00000000-0000-0000-0000-0000000000b3', 'post', 'free', '선택지 붙은 글', '찬성', '반대')$$,
  '23514', null, 'create_community_item: 게시물에 선택지를 넣으면 막힌다'
);
select throws_ok(
  $$select public.create_community_item('00000000-0000-0000-0000-0000000000b3', 'poll', 'free', '선택지 없는 투표')$$,
  '23514', null, 'create_community_item: 투표에 선택지가 없으면 막힌다'
);
select throws_ok(
  $$select public.create_community_item('00000000-0000-0000-0000-0000000000b3', 'post', 'hot', '모르는 카테고리')$$,
  '23514', null, 'create_community_item: 카테고리는 세 값뿐이다'
);
select lives_ok(
  $$select public.create_community_item('00000000-0000-0000-0000-0000000000b3', 'poll', 'career', '투표 ' || g, '찬성', '반대')
      from generate_series(1, 5) g$$,
  '투표 5개를 올린다'
);
select lives_ok(
  $$select public.create_community_item('00000000-0000-0000-0000-0000000000b3', 'post', 'love', '게시물 ' || g)
      from generate_series(1, 5) g$$,
  '게시물 5개를 올린다'
);
select results_eq(
  $$select kind, category, option_a_label, option_b_label from public.polls
     where author_id = '00000000-0000-0000-0000-0000000000b3' and question = '게시물 1'$$,
  $$values ('post'::text, 'love'::text, null::text, null::text)$$,
  'create_community_item 으로 올린 게시물은 kind · category 그대로, 선택지 null 이다'
);
select throws_ok(
  $$select public.create_community_item('00000000-0000-0000-0000-0000000000b3', 'post', 'free', '열한 번째 게시물')$$,
  'CM429', null, '투표 5 + 게시물 5 뒤 11번째 게시물은 CM429 다'
);
select throws_ok(
  $$select public.create_community_item('00000000-0000-0000-0000-0000000000b3', 'poll', 'free', '열한 번째 투표', '찬성', '반대')$$,
  'CM429', null, '투표 5 + 게시물 5 뒤 11번째 투표도 CM429 다'
);
select throws_ok(
  $$select public.create_poll('00000000-0000-0000-0000-0000000000b3', '옛 길 열한 번째', '찬성', '반대')$$,
  'CM429', null, '옛 create_poll 도 게시물을 합쳐 센다'
);
select ok(
  pg_get_functiondef('public.create_community_item(uuid,text,text,text,text,text)'::regprocedure)
    like '%pg_advisory_xact_lock(hashtext(''create_poll''), hashtext(p_author::text))%',
  'create_community_item 은 사람 단위 잠금(옛 create_poll 의 키 그대로) 뒤에서 센다(동시 요청 11번째 막기)'
);
select ok(
  pg_get_functiondef('public.create_poll(uuid,text,text,text)'::regprocedure)
    like '%public.create_community_item(p_author, ''poll'', ''free'', p_question, p_option_a, p_option_b)%'
  and pg_get_functiondef('public.create_poll(uuid,text,text,text)'::regprocedure) not like '%pg_advisory_xact_lock%'
  and pg_get_functiondef('public.create_poll(uuid,text,text,text)'::regprocedure) not like '%count(*)%',
  '옛 create_poll 은 잠금 · 세기를 따로 두지 않고 create_community_item(투표 · 자유)에 넘긴다 — 하루 한도가 한 곳에만 있다'
);

-- 9. 함수 속성 · 권한(보안 기준 19-2) ----------------------------------------------
select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('create_community_item', 'community_feed')
      and not prosecdef
      and proconfig @> array['search_path=""']),
  2::bigint, '새 함수 둘은 security invoker 이고 search_path 가 빈 값이다'
);
select is(
  (select count(*) from pg_policies where tablename = 'polls'),
  0::bigint, 'polls 에는 여전히 정책이 없다(FastAPI 전용)'
);
select ok(
  has_function_privilege('service_role', 'public.create_community_item(uuid,text,text,text,text,text)', 'execute')
  and has_function_privilege('service_role', 'public.community_feed(uuid,uuid,timestamptz,uuid,integer,text)', 'execute'),
  'service_role 은 새 함수 둘을 부를 수 있다'
);
select ok(
  not has_function_privilege('anon', 'public.create_community_item(uuid,text,text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.community_feed(uuid,uuid,timestamptz,uuid,integer,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.create_community_item(uuid,text,text,text,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.community_feed(uuid,uuid,timestamptz,uuid,integer,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.poll_feed(uuid,uuid,timestamptz,uuid,integer,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.cast_poll_vote(uuid,uuid,public.poll_choice)', 'execute'),
  'anon · authenticated 는 새 함수 · 다시 만든 함수를 부를 수 없다'
);

-- 클라이언트 역할로 직접 불러 본다. grant 가 없어 0행이 아니라 42501 이다.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000b0", "role": "authenticated"}';

select throws_ok($$select * from public.community_feed('00000000-0000-0000-0000-0000000000b0')$$,
  '42501', null, 'authenticated 는 community_feed 를 부를 수 없다');
select throws_ok($$select public.create_community_item('00000000-0000-0000-0000-0000000000b0', 'post', 'free', '글')$$,
  '42501', null, 'authenticated 는 create_community_item 을 부를 수 없다');

set local role anon;
select throws_ok($$select * from public.community_feed('00000000-0000-0000-0000-0000000000b0')$$,
  '42501', null, 'anon 은 community_feed 를 부를 수 없다');
select throws_ok($$select public.create_community_item('00000000-0000-0000-0000-0000000000b0', 'post', 'free', '글')$$,
  '42501', null, 'anon 은 create_community_item 을 부를 수 없다');

select * from finish();
rollback;
