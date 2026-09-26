-- 홈 09b 서비스 전체 집계 home_stats() 검증. 기대값은 아래 준비 데이터에서 손으로 센 값이다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
-- seed.sql 은 학교·도메인만 넣고 프로필·카드·매칭은 넣지 않는다 — 그래서 전체 집계가 이 파일의 데이터와 같다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- 준비 --------------------------------------------------------------------
-- 학교 셋. '나다' 를 '가나' 보다 먼저 넣는다 — 이름순 정렬을 빼면 5번이 깨진다.
-- '마바' 에는 pending 한 명만 있다 — active 조건을 빼면 5번이 깨진다.
insert into public.universities (id, name, region_group) values
  ('00000000-0000-0000-0000-00000000e001', '나다테스트대학교', 'seoul'),
  ('00000000-0000-0000-0000-00000000e002', '가나테스트대학교', 'seoul'),
  ('00000000-0000-0000-0000-00000000e003', '마바테스트대학교', 'seoul');

-- auth.users 트리거(handle_new_user_profile)가 이 도메인으로 학교를 찾아 pending 프로필을 만든다.
insert into public.university_email_domains (domain, university_id) values
  ('nd.home-test.ac.kr', '00000000-0000-0000-0000-00000000e001'),
  ('gn.home-test.ac.kr', '00000000-0000-0000-0000-00000000e002'),
  ('mb.home-test.ac.kr', '00000000-0000-0000-0000-00000000e003');

-- A(나다, active) · B(가나, active) · C(가나, active) · D(마바, pending)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a0', 'hs-a@nd.home-test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b0', 'hs-b@gn.home-test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c0', 'hs-c@gn.home-test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d0', 'hs-d@mb.home-test.ac.kr');

-- profiles_active_requires_onboarding: 닉네임·성별·출생연도·키가 있어야 active 가 된다.
update public.profiles set nickname = '가나다', gender = 'male', birth_year = 2002, height_cm = 178, status = 'active'
where id = '00000000-0000-0000-0000-0000000000a0';
update public.profiles set nickname = '라마바', gender = 'female', birth_year = 2003, height_cm = 165, status = 'active'
where id = '00000000-0000-0000-0000-0000000000b0';
update public.profiles set nickname = '사아자', gender = 'female', birth_year = 2003, height_cm = 160, status = 'active'
where id = '00000000-0000-0000-0000-0000000000c0';

-- 카드 3장. 결정·만료와 상관없이 "나간 카드" 전부를 센다.
insert into public.daily_cards (owner_id, target_id, source, expires_at) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000b0', 'daily', now() + interval '1 day'),
  ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000a0', 'daily', now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-0000000000a0', 'purchased', null);

-- 매칭 셋. profile_a < profile_b 라 uuid 가 작은 쪽이 앞이다.
insert into public.matches (id, profile_a, profile_b) values
  ('00000000-0000-0000-0000-00000000e501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000b0'),
  ('00000000-0000-0000-0000-00000000e502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000c0'),
  ('00000000-0000-0000-0000-00000000e503', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000c0');

-- A↔B 는 말풍선 2건(매칭 하나로 세야 한다 — 메시지 수로 세면 3번이 3 이 된다).
-- A↔C 는 시스템 줄만 있다(kind 조건을 빼면 3번이 3 이 된다). B↔C 는 말풍선 1건.
insert into public.messages (match_id, sender_id, kind, body) values
  ('00000000-0000-0000-0000-00000000e501', '00000000-0000-0000-0000-0000000000a0', 'text', '안녕하세요'),
  ('00000000-0000-0000-0000-00000000e501', '00000000-0000-0000-0000-0000000000b0', 'text', '반가워요'),
  ('00000000-0000-0000-0000-00000000e502', '00000000-0000-0000-0000-0000000000a0', 'trust_accept', '카톡 공유를 수락했어요'),
  ('00000000-0000-0000-0000-00000000e502', '00000000-0000-0000-0000-0000000000c0', 'left', '사아자님이 채팅방을 나갔어요'),
  ('00000000-0000-0000-0000-00000000e503', '00000000-0000-0000-0000-0000000000c0', 'text', '처음 뵙겠습니다');

-- 1. 값 (service_role 로 부른다 — FastAPI 가 쓰는 역할) -------------------------
set local role service_role;

select is((select delivered_cards from public.home_stats()), 3::bigint,
  '누적 카드 수는 daily_cards 전체 행 수다');

select is((select signups from public.home_stats()), 3::bigint,
  '가입자 수는 active 프로필만 센다(pending 제외)');

select is((select conversations_started from public.home_stats()), 2::bigint,
  '대화 시작 수는 말풍선(text)이 한 건이라도 있는 매칭 수다');

select is((select cardinality(campuses) from public.home_stats()), 2,
  '캠퍼스는 active 프로필이 있는 학교만 나온다');

select is((select campuses from public.home_stats()), array['가나테스트대학교', '나다테스트대학교'],
  '캠퍼스 이름은 이름순이다');

select ok(has_function_privilege('service_role', 'public.home_stats()', 'execute'),
  'service_role 은 home_stats 를 부를 수 있다');

reset role;

-- 2. 앱 역할은 못 부른다 --------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000a0", "role": "authenticated"}';

select throws_ok($$select * from public.home_stats()$$, '42501', null,
  'authenticated 는 home_stats 를 부르지 못한다');

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok($$select * from public.home_stats()$$, '42501', null,
  'anon 은 home_stats 를 부르지 못한다');

reset role;

select ok(not has_function_privilege('public', 'public.home_stats()', 'execute'),
  'PUBLIC 에도 실행 권한이 없다');

select * from finish();
rollback;
