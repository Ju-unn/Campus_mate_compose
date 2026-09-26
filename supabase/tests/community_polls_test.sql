-- 커뮤니티 탭(15d · 17b · 17c) 표 · 권한 · DB 함수 검증.
-- 기대값 기준: docs/superpowers/plans/2026-09-27-community-polls.md Task C1 · C2.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(54);

-- 준비 --------------------------------------------------------------------
-- AU = ...80(글쓴이), V1 = ...81 · V2 = ...82(투표자), GONE = ...83(탈퇴할 글쓴이),
-- VOFF = ...84(탈퇴할 투표자), WK = ...85(주간 상한 확인), LIM = ...86(하루 10개 확인)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000007', '테스트대학교7', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test7.ac.kr', '00000000-0000-0000-0000-000000000007');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000080', 'p7-au@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000081', 'p7-v1@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000082', 'p7-v2@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000083', 'p7-gone@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000084', 'p7-voff@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000085', 'p7-wk@test7.ac.kr'),
  ('00000000-0000-0000-0000-000000000086', 'p7-lim@test7.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000007' from auth.users
where id between '00000000-0000-0000-0000-000000000080' and '00000000-0000-0000-0000-000000000086'
on conflict (id) do nothing;

-- active 전환 check(닉네임 · 성별 · 출생연도 · 키)만 채운다. 나머지 칸은 이 테스트와 상관없다.
update public.profiles set
  status = 'active', gender = 'female', birth_year = 2003, height_cm = 165,
  nickname = case id
    when '00000000-0000-0000-0000-000000000080' then '글쓴이가'
    when '00000000-0000-0000-0000-000000000081' then '투표하나'
    when '00000000-0000-0000-0000-000000000082' then '투표둘이'
    when '00000000-0000-0000-0000-000000000083' then '떠난이다'
    when '00000000-0000-0000-0000-000000000084' then '떠난표다'
    when '00000000-0000-0000-0000-000000000085' then '주간이다'
    when '00000000-0000-0000-0000-000000000086' then '열개쓴이'
  end
where id between '00000000-0000-0000-0000-000000000080' and '00000000-0000-0000-0000-000000000086';

-- C1: 표 · enum · 권한 ---------------------------------------------------
select has_table('public', 'polls', 'polls 표가 있다');
select has_table('public', 'poll_votes', 'poll_votes 표가 있다');
select enum_has_labels('public', 'content_status', array['visible', 'blinded'], 'content_status 는 visible · blinded');
select enum_has_labels('public', 'poll_choice', array['a', 'b'], 'poll_choice 는 a · b');
select ok((select relrowsecurity from pg_class where oid = 'public.polls'::regclass), 'polls 는 RLS 가 켜져 있다');
select ok((select relrowsecurity from pg_class where oid = 'public.poll_votes'::regclass), 'poll_votes 는 RLS 가 켜져 있다');
select is(
  (select count(*) from pg_policies where tablename in ('polls', 'poll_votes')),
  0::bigint, 'polls · poll_votes 에는 정책이 하나도 없다(FastAPI 전용, ERD §2 87줄)'
);
select table_privs_are('public', 'polls', 'service_role', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'service_role 은 polls 에 네 권한이 다 있다');
select table_privs_are('public', 'poll_votes', 'service_role', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'service_role 은 poll_votes 에 네 권한이 다 있다');

-- 제약 확인용 글 D1(...d1). C2 절이 시작할 때 polls 를 비우므로 여기서만 쓴다.
insert into public.polls (id, author_id, question)
values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000080', '짜장 짬뽕');
insert into public.poll_votes (poll_id, voter_id, choice)
values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000081', 'a');

select results_eq(
  $$select option_a_label, option_b_label, status::text from public.polls
     where id = '00000000-0000-0000-0000-0000000000d1'$$,
  $$values ('찬성', '반대', 'visible')$$,
  '라벨을 안 주면 찬성 · 반대, 상태는 visible 이다'
);
select throws_ok(
  $$insert into public.polls (author_id, question)
    values ('00000000-0000-0000-0000-000000000080', repeat('가', 81))$$,
  '23514', null, '질문은 80자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (author_id, question) values ('00000000-0000-0000-0000-000000000080', '   ')$$,
  '23514', null, '빈칸뿐인 질문은 들어가지 않는다'
);
select throws_ok(
  $$insert into public.polls (author_id, question, option_a_label)
    values ('00000000-0000-0000-0000-000000000080', '질문', repeat('가', 7))$$,
  '23514', null, '라벨은 6자를 넘을 수 없다'
);
select throws_ok(
  $$insert into public.polls (author_id, question, option_a_label, option_b_label)
    values ('00000000-0000-0000-0000-000000000080', '질문', '좋아', '좋아')$$,
  '23514', null, '두 라벨이 같으면 들어가지 않는다'
);
select throws_ok(
  $$insert into public.poll_votes (poll_id, voter_id, choice)
    values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000081', 'b')$$,
  '23505', null, '같은 사람이 같은 글에 두 번 투표할 수 없다(재투표 불가)'
);
select throws_ok(
  $$insert into public.poll_votes (poll_id, voter_id, choice)
    values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000082', 'c')$$,
  '22P02', null, '선택은 a · b 둘뿐이다'
);

delete from public.polls where id = '00000000-0000-0000-0000-0000000000d1';
select is(
  (select count(*) from public.poll_votes where poll_id = '00000000-0000-0000-0000-0000000000d1'),
  0::bigint, '글을 지우면 그 글의 투표도 지워진다(내 글 삭제 · 탈퇴 cascade)'
);

-- C2 자리 (Task C2 가 여기에 끼워 넣는다) ---------------------------------
-- C2: DB 함수 -------------------------------------------------------------
-- 피드 단정이 앞 절의 글 · 로컬에서 손으로 만든 글과 섞이지 않게 비운다(끝에 rollback 된다).
delete from public.polls;

-- P1(...a1) 3분 전, P2(...a2) · P3(...a3) 2분 전 같은 시각(커서 경계), PB(...b1) 가려짐, PG(...c1) 탈퇴할 글쓴이.
insert into public.polls (id, author_id, question, created_at) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000080', '첫 데이트 더치페이', now() - interval '3 minutes'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000080', '연락 빈도 하루 한 번', now() - interval '2 minutes'),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000080', '카톡 답장 속도', now() - interval '2 minutes'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000083', '떠난 사람의 글', now() - interval '1 minute');
insert into public.polls (id, author_id, question, status)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000080', '가려진 글', 'blinded');

-- P1: V1 a · AU a(작성자 자기 투표 허용) · V2 b · VOFF a(탈퇴 → 집계에서 빠진다)
insert into public.poll_votes (poll_id, voter_id, choice) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000081', 'a'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000080', 'a'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000082', 'b'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000084', 'a');

update public.profiles set status = 'withdrawn', withdrawn_at = now()
where id in ('00000000-0000-0000-0000-000000000083', '00000000-0000-0000-0000-000000000084');

-- 피드 --
select ok(
  pg_get_function_result('public.poll_feed(uuid,uuid,timestamptz,uuid,integer)'::regprocedure) not like '%author%',
  'poll_feed 는 작성자 칸을 돌려주지 않는다(익명)'
);
select results_eq(
  $$select id from public.poll_feed('00000000-0000-0000-0000-000000000081')$$,
  $$values ('00000000-0000-0000-0000-0000000000a3'::uuid), ('00000000-0000-0000-0000-0000000000a2'::uuid),
           ('00000000-0000-0000-0000-0000000000a1'::uuid)$$,
  '피드는 최신순 · 같은 시각이면 id 큰 것부터, 가려진 글 · 탈퇴한 사람의 글은 없다'
);
select results_eq(
  $$select id from public.poll_feed('00000000-0000-0000-0000-000000000081',
      p_before => (select created_at from public.polls where id = '00000000-0000-0000-0000-0000000000a3'),
      p_before_id => '00000000-0000-0000-0000-0000000000a3')$$,
  $$values ('00000000-0000-0000-0000-0000000000a2'::uuid), ('00000000-0000-0000-0000-0000000000a1'::uuid)$$,
  '커서는 같은 시각의 글을 빠뜨리지 않는다'
);
select results_eq(
  $$select id from public.poll_feed('00000000-0000-0000-0000-000000000081', p_limit => 1)$$,
  $$values ('00000000-0000-0000-0000-0000000000a3'::uuid)$$,
  'p_limit 만큼만 준다'
);
select results_eq(
  $$select a_count, b_count, my_choice, is_mine
      from public.poll_feed('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-0000000000a1')$$,
  $$values (2::bigint, 1::bigint, 'a'::public.poll_choice, false)$$,
  '집계는 active 투표자만(탈퇴한 VOFF 제외), my_choice 는 보는 사람의 표'
);
select is(
  (select is_mine from public.poll_feed('00000000-0000-0000-0000-000000000080', '00000000-0000-0000-0000-0000000000a1')),
  true, '글쓴이 본인에게만 is_mine 이 참이다'
);
select is_empty(
  $$select * from public.poll_feed('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-0000000000b1')$$,
  '가려진 글은 id 로 불러도 없다'
);
select is_empty(
  $$select * from public.poll_feed('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-0000000000c1')$$,
  '탈퇴한 사람의 글은 id 로 불러도 없다'
);

-- 글쓰기: 하루 10개 --
select isnt(
  public.create_poll('00000000-0000-0000-0000-000000000086', '오늘 첫 글', '찬성', '반대'), null,
  'create_poll 은 새 글 id 를 돌려준다'
);
insert into public.polls (author_id, question)
select '00000000-0000-0000-0000-000000000086', '오늘 ' || n || '번째' from generate_series(2, 10) n;
select throws_ok(
  $$select public.create_poll('00000000-0000-0000-0000-000000000086', '열한 번째', '찬성', '반대')$$,
  'CM429', null, '한국 시간 오늘 10개를 올렸으면 11번째는 막힌다'
);
insert into public.polls (author_id, question, created_at)
select '00000000-0000-0000-0000-000000000080', '어제 ' || n,
       (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') - interval '1 minute'
from generate_series(1, 10) n;
select lives_ok(
  $$select public.create_poll('00000000-0000-0000-0000-000000000080', '오늘 글', '찬성', '반대')$$,
  '어제(한국 시간) 올린 10개는 오늘 한도에 들지 않는다'
);

-- 보상 판정: 고정 시각(2026-09-28 월 ~ 10-04 일 한 주) --
insert into public.heart_transactions (profile_id, amount, reason, created_at) values
  ('00000000-0000-0000-0000-000000000085', 10, 'poll_vote', '2026-09-28 10:00+09'),
  ('00000000-0000-0000-0000-000000000085', 10, 'poll_vote', '2026-09-29 10:00+09');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-09-29 12:00+09'),
  false, '오늘 이미 받았으면 다시 주지 않는다');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-09-30 12:00+09'),
  true, '이번 주 20하트면 새 날에 또 준다');
insert into public.heart_transactions (profile_id, amount, reason, created_at)
values ('00000000-0000-0000-0000-000000000085', 10, 'poll_vote', '2026-09-30 10:00+09');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-10-04 23:59+09'),
  false, '이번 주 30하트를 채웠으면 일요일 밤까지 주지 않는다');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-10-05 00:00+09'),
  true, '월요일 0시(한국 시간)에 새 주가 시작된다');
insert into public.heart_transactions (profile_id, amount, reason, created_at)
values ('00000000-0000-0000-0000-000000000085', 10, 'admin_adjust', '2026-10-06 09:00+09');
select is(public.poll_vote_reward_due('00000000-0000-0000-0000-000000000085', '2026-10-06 12:00+09'),
  true, 'poll_vote 가 아닌 적립은 셈하지 않는다');

-- 투표 (진짜 now()) --
select is(public.cast_poll_vote('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000082', 'a'),
  true, '오늘 첫 투표면 하트를 준다');
select results_eq(
  $$select amount, reason::text, ref_id from public.heart_transactions
     where profile_id = '00000000-0000-0000-0000-000000000082'$$,
  $$values (10, 'poll_vote', '00000000-0000-0000-0000-0000000000a2'::uuid)$$,
  '원장에 10 · poll_vote · ref_id = 글 id 로 남는다'
);
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000082'),
  10, '잔액 캐시도 같은 트랜잭션에서 오른다');
select is(public.cast_poll_vote('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000082', 'b'),
  false, '같은 날 두 번째 투표는 하트가 없다(투표 자체는 된다)');
select is((select heart_balance from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000082'),
  10, '두 번째 투표 뒤에도 잔액은 그대로');
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000082', 'b')$$,
  '23505', null, '같은 글에 다시 투표할 수 없다'
);
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000081', 'a')$$,
  'CM404', null, '가려진 글에는 투표할 수 없다(없는 글과 같게)'
);
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000081', 'a')$$,
  'CM404', null, '탈퇴한 사람의 글에는 투표할 수 없다'
);
select throws_ok(
  $$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000ff', '00000000-0000-0000-0000-000000000081', 'a')$$,
  'CM404', null, '없는 글'
);
select is(public.cast_poll_vote('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000080', 'a'),
  true, '글쓴이도 자기 글에 투표할 수 있다(사용자 결정 4-2)');
select ok(
  -- 줄 머리가 perform 이어야 한다. like '%…%' 는 잠금 줄을 -- 로 주석 처리해도 글자가 남아 통과했다(가짜 GREEN).
  pg_get_functiondef('public.cast_poll_vote(uuid,uuid,public.poll_choice)'::regprocedure) ~ '\n\s*perform pg_advisory_xact_lock',
  'cast_poll_vote 는 사람 단위 잠금을 건다(동시 투표 두 개에 하트 한 번) — 경합 스크립트는 계획서 C2 Step 5'
);

-- 탈퇴 cascade --
delete from auth.users where id = '00000000-0000-0000-0000-000000000082';
select is((select count(*) from public.poll_votes where voter_id = '00000000-0000-0000-0000-000000000082'),
  0::bigint, '계정이 지워지면 그 사람의 투표도 지워진다');
delete from auth.users where id = '00000000-0000-0000-0000-000000000083';
select is((select count(*) from public.polls where author_id = '00000000-0000-0000-0000-000000000083'),
  0::bigint, '계정이 지워지면 그 사람의 글도 지워진다');

-- 클라이언트 권한 --------------------------------------------------------
-- grant 가 없어 0행이 아니라 42501 이다(ERD §2 95줄 "읽기가 없는 테이블은 본인 행이라도 42501").
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000080", "role": "authenticated"}';

select throws_ok($$select id from public.polls$$, '42501', null, 'authenticated 는 polls 를 읽을 수 없다');
select throws_ok($$select poll_id from public.poll_votes$$, '42501', null, 'authenticated 는 poll_votes 를 읽을 수 없다');
select throws_ok(
  $$insert into public.polls (author_id, question) values ('00000000-0000-0000-0000-000000000080', '질문')$$,
  '42501', null, 'authenticated 는 polls 에 쓸 수 없다'
);

select throws_ok($$select * from public.poll_feed('00000000-0000-0000-0000-000000000080')$$,
  '42501', null, 'authenticated 는 poll_feed 를 부를 수 없다');
select throws_ok($$select public.create_poll('00000000-0000-0000-0000-000000000080', '질문', '찬성', '반대')$$,
  '42501', null, 'authenticated 는 create_poll 을 부를 수 없다');
select throws_ok($$select public.poll_vote_reward_due('00000000-0000-0000-0000-000000000080', now())$$,
  '42501', null, 'authenticated 는 poll_vote_reward_due 를 부를 수 없다');
select throws_ok($$select public.cast_poll_vote('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000080', 'a')$$,
  '42501', null, 'authenticated 는 cast_poll_vote 를 부를 수 없다');

set local role anon;
select throws_ok($$select id from public.polls$$, '42501', null, 'anon 은 polls 를 읽을 수 없다');

select * from finish();
rollback;
