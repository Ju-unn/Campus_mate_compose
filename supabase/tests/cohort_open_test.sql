-- 코호트(설계 §2.9): universities.card_opens_at 이 아직 오지 않은 학교 사람은
-- 카드를 받지도(card_issue_owners), 후보로 나오지도, 후보를 받지도(match_candidates),
-- 사다리 인원으로 세지지도(region_active_counts) 않는다. null 과 지난 시각은 "열림"이다.
-- 기대값 기준은 docs/superpowers/plans/2026-09-28-cohort-wait.md Task C1.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- 준비 --------------------------------------------------------------------
-- 전용 지역그룹 — region_active_counts 가 다른 데이터와 섞이지 않게 한다.
insert into public.region_group_settings (region_group) values ('cohort_test');

-- 학교 셋: OPEN(null) · PAST(지난 월요일 07:00) · SOON(앞으로 월요일 07:00).
-- 두 시각 모두 서울 월요일 07:00 = UTC 일요일 22:00 이다 — check 가 UTC 로 요일을 보면 여기서 깨진다.
insert into public.universities (id, name, region_group, card_opens_at) values
  ('00000000-0000-0000-0000-000000001901', '코호트열림테스트대학교', 'cohort_test', null),
  ('00000000-0000-0000-0000-000000001902', '코호트지남테스트대학교', 'cohort_test', '2020-01-06 07:00+09'),
  ('00000000-0000-0000-0000-000000001903', '코호트예정테스트대학교', 'cohort_test', '2099-01-05 07:00+09');

-- auth.users 트리거(handle_new_user_profile)가 이 도메인으로 학교를 찾아 pending 프로필을 만든다.
insert into public.university_email_domains (domain, university_id) values
  ('open.cohort-test.ac.kr', '00000000-0000-0000-0000-000000001901'),
  ('past.cohort-test.ac.kr', '00000000-0000-0000-0000-000000001902'),
  ('soon.cohort-test.ac.kr', '00000000-0000-0000-0000-000000001903');

-- 학교마다 남(…x1) · 여(…x2) 한 명씩. 걸러지는 이유가 학교 여는 시각 하나뿐이도록 나머지는 똑같다.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000019a1', 'co-om@open.cohort-test.ac.kr'),
  ('00000000-0000-0000-0000-0000000019a2', 'co-of@open.cohort-test.ac.kr'),
  ('00000000-0000-0000-0000-0000000019b1', 'co-pm@past.cohort-test.ac.kr'),
  ('00000000-0000-0000-0000-0000000019b2', 'co-pf@past.cohort-test.ac.kr'),
  ('00000000-0000-0000-0000-0000000019c1', 'co-sm@soon.cohort-test.ac.kr'),
  ('00000000-0000-0000-0000-0000000019c2', 'co-sf@soon.cohort-test.ac.kr');

update public.profiles set nickname = '열림남자' where id = '00000000-0000-0000-0000-0000000019a1';
update public.profiles set nickname = '열림여자' where id = '00000000-0000-0000-0000-0000000019a2';
update public.profiles set nickname = '지남남자' where id = '00000000-0000-0000-0000-0000000019b1';
update public.profiles set nickname = '지남여자' where id = '00000000-0000-0000-0000-0000000019b2';
update public.profiles set nickname = '예정남자' where id = '00000000-0000-0000-0000-0000000019c1';
update public.profiles set nickname = '예정여자' where id = '00000000-0000-0000-0000-0000000019c2';

update public.profiles set
  gender = (case when right(id::text, 1) = '1' then 'male' else 'female' end)::public.gender,
  status = 'active', birth_year = 2002, height_cm = 170, last_active_at = now(),
  interest_tags = array['카페가기'], my_traits = array['다정한'], ideal_traits = array['다정한']
where university_id in (
  '00000000-0000-0000-0000-000000001901', '00000000-0000-0000-0000-000000001902',
  '00000000-0000-0000-0000-000000001903'
);

insert into public.profile_vectors (profile_id, self_survey, self_embedding, want_embedding)
select id, '[1,0,0,0,0,0,0,0]',
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector
from public.profiles
where university_id in (
  '00000000-0000-0000-0000-000000001901', '00000000-0000-0000-0000-000000001902',
  '00000000-0000-0000-0000-000000001903'
);

set local role service_role;

-- 1. 카드 받을 사람 -------------------------------------------------------------
select results_eq(
  $$select profile_id from public.card_issue_owners()
    where region_group = 'cohort_test' order by profile_id$$,
  $$values ('00000000-0000-0000-0000-0000000019a1'::uuid), ('00000000-0000-0000-0000-0000000019a2'::uuid),
           ('00000000-0000-0000-0000-0000000019b1'::uuid), ('00000000-0000-0000-0000-0000000019b2'::uuid)$$,
  'card_issue_owners: null · 지난 학교 사람은 받고, 앞으로 열 학교 사람은 받지 않는다'
);

-- 2. 후보 -------------------------------------------------------------------
select results_eq(
  $$select candidate_id from public.match_candidates('00000000-0000-0000-0000-0000000019a1')
    order by candidate_id$$,
  $$values ('00000000-0000-0000-0000-0000000019a2'::uuid), ('00000000-0000-0000-0000-0000000019b2'::uuid)$$,
  'match_candidates: null 학교 사람의 후보에 지난 학교 사람은 나오고 앞으로 열 학교 사람은 없다'
);

select results_eq(
  $$select candidate_id from public.match_candidates('00000000-0000-0000-0000-0000000019b1')
    order by candidate_id$$,
  $$values ('00000000-0000-0000-0000-0000000019a2'::uuid), ('00000000-0000-0000-0000-0000000019b2'::uuid)$$,
  'match_candidates: 지난 학교 사람도 후보를 받는다(앞으로 열 학교 사람은 없다)'
);

select is_empty(
  $$select candidate_id from public.match_candidates('00000000-0000-0000-0000-0000000019c1')$$,
  'match_candidates: 앞으로 열 학교 사람은 후보를 한 명도 받지 않는다(구매 카드도 열리기 전엔 못 받는다)'
);

-- 3. 사다리 인원 --------------------------------------------------------------
select results_eq(
  $$select gender::text, active_count from public.region_active_counts()
    where region_group = 'cohort_test' order by 1$$,
  $$values ('female', 2::bigint), ('male', 2::bigint)$$,
  'region_active_counts: 앞으로 열 학교 사람은 세지 않는다(여 2 · 남 2)'
);

reset role;

-- 4. 월요일 check --------------------------------------------------------------
-- 2099-01-06 07:00 서울은 화요일, UTC 로는 월요일 22:00 이다 — 요일을 서울 기준으로 봐야 막힌다.
select throws_ok(
  $$update public.universities set card_opens_at = '2099-01-06 07:00+09'
    where id = '00000000-0000-0000-0000-000000001903'$$,
  '23514', null,
  '서울 기준 월요일이 아닌 여는 시각은 check 위반이다'
);

-- 시간대 없이 넣으면 UTC 로 읽혀 서울 월요일 16:00 이 된다 — 07:00 배치가 못 여는 시각이라 막는다.
select throws_ok(
  $$update public.universities set card_opens_at = '2099-01-05 16:00+09'
    where id = '00000000-0000-0000-0000-000000001903'$$,
  '23514', null,
  '서울 월요일이어도 07:00 이 아니면 check 위반이다(배치는 07:00 한 번뿐)'
);

-- infinity 는 요일 · 시각이 null 이라 isfinite 없이는 check 를 통과하고, 서버가 날짜로 못 읽어 홈이 500 이 된다.
select throws_ok(
  $$update public.universities set card_opens_at = 'infinity'
    where id = '00000000-0000-0000-0000-000000001903'$$,
  '23514', null,
  'infinity 는 check 위반이다'
);

select lives_ok(
  $$update public.universities set card_opens_at = '2099-01-12 07:00+09'
    where id = '00000000-0000-0000-0000-000000001903'$$,
  '서울 기준 월요일 07:00(UTC 로는 일요일)은 넣을 수 있다'
);

select lives_ok(
  $$update public.universities set card_opens_at = null
    where id = '00000000-0000-0000-0000-000000001903'$$,
  '여는 시각을 null 로 돌려놓을 수 있다(이미 열린 학교)'
);

-- 5. 앞으로 열 학교를 null 로 되돌리면 바로 카드 대상이 된다 --------------------------------
set local role service_role;

select ok(
  exists(select 1 from public.card_issue_owners() where profile_id = '00000000-0000-0000-0000-0000000019c1'),
  'card_issue_owners: 여는 시각을 null 로 바꾼 학교 사람은 곧바로 받는다'
);

reset role;

select * from finish();
rollback;
