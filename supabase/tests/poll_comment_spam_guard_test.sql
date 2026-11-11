-- 댓글 도배 막기(2026-11-12) 검증. 마이그레이션 20261112090000. 로컬 스택에서 `supabase test db` 로 돌린다.
-- 사용자 결정 원문: 「1번에 1번 2번 만」(③ 한 글 하루 20개는 넣지 않는다).
--   ① 같은 사람이 (어느 글이든) 최근 1분 안에 단 댓글이 이미 5개면 6번째는 CM42B (서버가 429 로 바꾼다)
--   ② 같은 글에서 내 바로 전 댓글과 본문이 똑같으면 CM409 (서버가 409 로 바꾼다)
-- 하루 50개(CM429)는 그대로이고 둘보다 먼저 본다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- 준비 --------------------------------------------------------------------
-- AU = ...b0(글쓴이) · RT = ...b1(1분 5개) · OT = ...b2(구경꾼) · D1 = ...b3(같은 내용) · D3 = ...b5(지우고 다시)
-- D4 = ...b6(오래전 댓글과 같은 내용) · LIM = ...b7(하루 한도)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000099', '테스트대학교99', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test99.ac.kr', '00000000-0000-0000-0000-000000000099');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b0', 'sg-au@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b1', 'sg-rt@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b2', 'sg-ot@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b3', 'sg-d1@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b5', 'sg-d3@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b6', 'sg-d4@test99.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b7', 'sg-lim@test99.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000099' from auth.users
where id between '00000000-0000-0000-0000-0000000000b0' and '00000000-0000-0000-0000-0000000000b7'
on conflict (id) do nothing;

update public.profiles set
  status = 'active', gender = 'female', birth_year = 2003, height_cm = 165,
  nickname = case id
    when '00000000-0000-0000-0000-0000000000b0' then '글쓴이공'
    when '00000000-0000-0000-0000-0000000000b1' then '속도시험'
    when '00000000-0000-0000-0000-0000000000b2' then '다른사람'
    when '00000000-0000-0000-0000-0000000000b3' then '같은말하나'
    when '00000000-0000-0000-0000-0000000000b5' then '지우고쓰기'
    when '00000000-0000-0000-0000-0000000000b6' then '옛날같은말'
    when '00000000-0000-0000-0000-0000000000b7' then '한도시험'
  end
where id between '00000000-0000-0000-0000-0000000000b0' and '00000000-0000-0000-0000-0000000000b7';

-- 글 네 개: P1 · P2 · P3 · P4(전부 글쓴이 AU 의 보이는 글)
delete from public.polls;
insert into public.polls (id, author_id, question, status) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b0', '첫째 글', 'visible'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000b0', '둘째 글', 'visible'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000b0', '셋째 글', 'visible'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000b0', '넷째 글', 'visible');

-- 1. 인덱스 · 잠금 순서 ----------------------------------------------------------
select has_index('public', 'poll_comments', 'poll_comments_poll_author_created_index',
  '내 바로 전 댓글을 (poll_id, author_id, created_at) 인덱스로 바로 찾는다');
select ok(
  -- 두 판단 모두 사람 단위 잠금을 잡은 뒤에 한다 — 동시에 보낸 요청이 한도와 중복 검사를 같이 빠져나가지 못한다.
  pg_get_functiondef('public.add_poll_comment(uuid,uuid,text)'::regprocedure)
    ~ '(?s)\n\s*perform pg_advisory_xact_lock\(hashtext\(''add_poll_comment''\).*CM42B.*CM409',
  '사람 단위 잠금을 잡은 뒤에 1분 5개(CM42B)와 같은 내용(CM409)을 본다'
);

select ok(
  -- clock_timestamp() 는 volatile 이라 where 절에 그대로 쓰면 (author_id, created_at) 인덱스를 범위 조건으로 못 탄다 —
  -- 그 사람의 댓글 이력 전체를 훑는다(로컬 EXPLAIN 으로 확인). 변수에 담아 넘겨야 1분 구간만 읽는다.
  pg_get_functiondef('public.add_poll_comment(uuid,uuid,text)'::regprocedure)
    ~ 'v_burst_since := clock_timestamp\(\) - interval ''1 minute''.*created_at > v_burst_since',
  '1분 창의 시작 시각을 변수에 담아 인덱스 범위 조건으로 쓴다(volatile 함수를 where 에 직접 쓰지 않는다)'
);

-- 2. ① 1분 안에 5개 -----------------------------------------------------------
-- 어느 글이든 센다: P1 에 셋, P2 에 둘 → 다섯.
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f1', '하나')$$,
  '1분 안 첫 번째는 달린다');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f1', '둘')$$,
  '두 번째');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f1', '셋')$$,
  '세 번째');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f2', '넷')$$,
  '네 번째(다른 글)');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f2', '다섯')$$,
  '다섯 번째는 1분 안 마지막으로 달린다');
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f3', '여섯')$$,
  'CM42B', null, '1분 안 여섯 번째는 CM42B 다 — 앞의 다섯은 다른 글(P1 · P2)에 단 것이어도 센다');
select is(
  (select count(*) from public.poll_comments where author_id = '00000000-0000-0000-0000-0000000000b1'),
  5::bigint, '막힌 여섯 번째는 저장되지 않는다');
select is(
  (select count(*) from public.poll_comment_aliases
    where profile_id = '00000000-0000-0000-0000-0000000000b1' and poll_id = '00000000-0000-0000-0000-0000000000f3'),
  0::bigint, '막힌 요청은 그 글의 익명 번호도 남기지 않는다(막는 판단이 번호 부여보다 앞이다)');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000f3', '구경꾼 댓글')$$,
  '한도는 사람마다다 — 다른 사람은 영향이 없다');
-- 아직 1분이 안 지났다(30초 전)면 계속 막힌다.
update public.poll_comments set created_at = clock_timestamp() - interval '30 seconds'
 where author_id = '00000000-0000-0000-0000-0000000000b1';
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f3', '여섯')$$,
  'CM42B', null, '30초 전에 단 다섯 개도 아직 1분 안이라 센다');
-- 2분이 지나면(1분 밖) 다시 된다.
update public.poll_comments set created_at = clock_timestamp() - interval '2 minutes'
 where author_id = '00000000-0000-0000-0000-0000000000b1';
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f3', '여섯')$$,
  '1분이 지나면 다시 달린다');

-- 3. ② 같은 글에서 바로 전 댓글과 같은 내용 --------------------------------------
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000f1', '같은 말')$$,
  '첫 댓글은 달린다');
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000f1', '같은 말')$$,
  'CM409', null, '같은 글에서 바로 전과 같은 본문이면 CM409 다');
select is(
  (select count(*) from public.poll_comments
    where author_id = '00000000-0000-0000-0000-0000000000b3' and poll_id = '00000000-0000-0000-0000-0000000000f1'),
  1::bigint, '막힌 같은 내용은 저장되지 않는다');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000f1', '다른 말')$$,
  '같은 글이어도 본문이 다르면 달린다');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000f2', '같은 말')$$,
  '다른 글에는 같은 본문을 달 수 있다');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000f1', '같은 말')$$,
  '그 사이 다른 내용을 달았으면 같은 본문도 달린다(바로 전 것만 비교한다)');
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000f1', '같은 말')$$,
  'CM409', null, '방금 단 것과 다시 같아지면 또 막힌다');

-- 4. 내 댓글이 지워진 뒤에는 비교 대상이 아니다(행 삭제) --------------------------------
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000f1', '지울 말')$$,
  '지울 댓글을 단다');
select is(
  (select count(*) from public.delete_poll_comment('00000000-0000-0000-0000-0000000000b5',
     (select id from public.poll_comments where author_id = '00000000-0000-0000-0000-0000000000b5' limit 1))),
  1::bigint, '내 댓글을 지운다');
select lives_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000f1', '지울 말')$$,
  '지운 댓글은 비교 대상이 아니라 같은 본문을 다시 달 수 있다');

-- 5. 바로 전 댓글이 아주 오래전 것이어도 같으면 막는다(시간 제한이 없다) ------------------------
insert into public.poll_comments (poll_id, author_id, body, created_at)
values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b6', '옛날 말', now() - interval '3 days');
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000f1', '옛날 말')$$,
  'CM409', null, '사흘 전 댓글이라도 그 글의 내 마지막 댓글이면 같은 본문은 막힌다');

-- 6. 하루 50개(CM429)가 먼저다 -----------------------------------------------------
-- 오늘 50개: 45개는 한국 시간 0시 1초(1분보다 오래 전), 5개는 방금(1분 안) — 같은 본문 '한도 말'. 51번째가 하루 한도 · 1분 5개 ·
-- 같은 내용 셋 다에 걸리지만 사용자에게는 가장 큰 이유인 하루 한도(CM429)로 답한다. 하루 한도를 먼저 보므로 0시 근처에도 CM429 다.
-- 0시 근처에 흔들릴 수 있는 쪽은 poll_comments_test 의 하루 50개 시험이다.
insert into public.poll_comments (poll_id, author_id, body, created_at)
select '00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000b7', '한도 말',
       (date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') + interval '1 second'
  from generate_series(1, 45) g;
insert into public.poll_comments (poll_id, author_id, body, created_at)
select '00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000b7', '한도 말', clock_timestamp()
  from generate_series(1, 5) g;
select throws_ok(
  $$select * from public.add_poll_comment('00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-0000000000f4', '한도 말')$$,
  'CM429', null, '하루 한도 · 1분 5개 · 같은 내용이 한꺼번에 걸려도 하루 한도(CM429)로 답한다');

-- 7. 권한은 그대로(or replace 가 지우지 않았다) ---------------------------------------
select ok(
  has_function_privilege('service_role', 'public.add_poll_comment(uuid,uuid,text)', 'execute'),
  'service_role 은 add_poll_comment 를 실행할 수 있다');
select ok(
  not has_function_privilege('anon', 'public.add_poll_comment(uuid,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.add_poll_comment(uuid,uuid,text)', 'execute'),
  '앱 역할(anon · authenticated)은 add_poll_comment 를 실행할 수 없다');
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.add_poll_comment(uuid,uuid,text)'::regprocedure),
  'add_poll_comment 는 여전히 security invoker · search_path 고정이다');

select * from finish();
rollback;
