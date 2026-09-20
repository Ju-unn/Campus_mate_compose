-- 조각 4 RLS · 권한 · 하드 필터 검증. 기대값 기준은 docs/ERD.md §2 와 설계 §2.1·§2.4·§6.7.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- 준비 --------------------------------------------------------------------
-- A = ...aa(남), B = ...bb(여), P = ...fa(여·일시중지), Q = ...fb(여·무응답 만료 3일 전),
-- R = ...fc(여·무응답 만료 20일 전 → 다시 후보), S = ...fd(여·10일 전 거절 → 90일 안이라 제외),
-- T = ...fe(여·100일 전 거절 → 90일이 지나 다시 후보, 2026-09-21 사용자 확정)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test.ac.kr', '00000000-0000-0000-0000-000000000001');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'm4-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000bb', 'm4-b@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000fa', 'm4-p@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000fb', 'm4-q@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000fc', 'm4-r@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000fd', 'm4-s@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000fe', 'm4-t@test.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000001' from auth.users
on conflict (id) do nothing;

update public.profiles set
  nickname = '가나다', gender = 'male', status = 'active',
  interest_tags = array['카페가기'], my_traits = array['다정한'], ideal_traits = array['활발한'],
  height_cm = 180, birth_year = 2002, mbti = 'ENFP', last_active_at = now()
where id = '00000000-0000-0000-0000-0000000000aa';

-- 여자 6명은 닉네임만 다르고 나머지는 똑같다 — 걸러지는 이유가 조각 4 필터 하나임을 분명히 한다.
-- 닉네임은 lower(nickname) 이 unique 라 한꺼번에 같은 값을 넣을 수 없어 따로 준다.
-- profiles_active_requires_onboarding 때문에 active 로 바꾸기 전에 닉네임이 먼저 들어가야 한다.
update public.profiles set nickname = '라마바' where id = '00000000-0000-0000-0000-0000000000bb';
update public.profiles set nickname = '사아자' where id = '00000000-0000-0000-0000-0000000000fa';
update public.profiles set nickname = '차카타' where id = '00000000-0000-0000-0000-0000000000fb';
update public.profiles set nickname = '파하거' where id = '00000000-0000-0000-0000-0000000000fc';
update public.profiles set nickname = '너더러' where id = '00000000-0000-0000-0000-0000000000fd';
update public.profiles set nickname = '머버서' where id = '00000000-0000-0000-0000-0000000000fe';

update public.profiles set
  gender = 'female', status = 'active',
  interest_tags = array['카페가기'], my_traits = array['활발한'], ideal_traits = array['다정한'],
  height_cm = 165, birth_year = 2003, mbti = 'ISFJ', last_active_at = now()
where id <> '00000000-0000-0000-0000-0000000000aa';

-- 일시중지한 사람
update public.profiles set matching_paused = true where id = '00000000-0000-0000-0000-0000000000fa';

insert into public.profile_vectors (profile_id, self_survey, self_embedding, want_embedding)
select id, '[1,0,0,0,0,0,0,0]',
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector
from public.profiles;

-- A 가 받았던 카드들
insert into public.daily_cards (id, owner_id, target_id, source, issued_at, expires_at) values
  -- Q: 3일 전 만료, 무응답 → 재노출 금지 기간(14일) 안이라 아직 후보가 아니다
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000fb', 'daily', now() - interval '6 days', now() - interval '3 days'),
  -- R: 20일 전 만료, 무응답 → 다시 후보가 된다
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000fc', 'daily', now() - interval '23 days', now() - interval '20 days'),
  -- S: 10일 전에 거절한 상대 → 결정 후 90일 안이라 아직 후보가 아니다
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000fd', 'daily', now() - interval '13 days', now() - interval '10 days'),
  -- T: 100일 전에 거절한 상대 → 90일이 지나 다시 후보가 된다(2026-09-21 사용자 확정)
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000fe', 'daily', now() - interval '103 days', now() - interval '100 days');

-- decided_at 을 직접 넣는다 — 90일 경계를 보는 테스트라 기본값 now() 로는 T 를 만들 수 없다.
insert into public.card_decisions (card_id, decision, decided_at) values
  ('00000000-0000-0000-0000-00000000c003', 'reject', now() - interval '10 days'),
  ('00000000-0000-0000-0000-00000000c004', 'reject', now() - interval '100 days');

-- 1. 구조 · 제약 -------------------------------------------------------------
select has_table('public', 'daily_cards', 'daily_cards 테이블이 있다');
select has_table('public', 'region_group_settings', 'region_group_settings 테이블이 있다');
select has_column('public', 'profiles', 'matching_paused', 'profiles 에 일시중지 컬럼이 있다');

select is(
  (select count(*) from public.region_group_settings where region_group = 'seoul'),
  1::bigint, 'seoul 설정 행이 시드로 들어 있다'
);

select throws_ok(
  $$insert into public.daily_cards (owner_id, target_id, source, expires_at)
    values ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000aa',
            'daily', now() + interval '1 day')$$,
  '23514', null, '자기 자신은 카드가 되지 않는다'
);

select throws_ok(
  $$insert into public.daily_cards (owner_id, target_id, source, expires_at)
    values ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000bb',
            'purchased', now() + interval '1 day')$$,
  '23514', null, '구매 카드는 만료 시각을 가질 수 없다'
);

select throws_ok(
  $$insert into public.matches (profile_a, profile_b)
    values ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000000aa')$$,
  '23514', null, '매칭은 항상 작은 uuid 가 profile_a 다'
);

-- 2. RLS · 권한 --------------------------------------------------------------
select is(
  (select count(*) from pg_policies where tablename = 'daily_cards'),
  0::bigint, 'daily_cards 에는 정책이 하나도 없다(FastAPI 전용)'
);

select ok(
  not has_table_privilege('authenticated', 'public.daily_cards', 'select'),
  'authenticated 는 daily_cards 를 읽지 못한다'
);

select ok(
  not has_table_privilege('authenticated', 'public.push_tokens', 'select'),
  'authenticated 는 push_tokens 를 읽지 못한다'
);

select ok(
  has_table_privilege('authenticated', 'public.region_group_settings', 'select'),
  'authenticated 는 지급 주기 설정을 읽는다(다음 지급 시각 표시)'
);

select ok(
  has_table_privilege('authenticated', 'public.matches', 'select'),
  'authenticated 는 matches 를 읽는다(정책이 당사자로 좁힌다)'
);

select is(
  (select count(*) from pg_policies where tablename = 'matches'),
  1::bigint, 'matches 에는 당사자 읽기 정책 하나만 있다'
);

select ok(
  not has_function_privilege('authenticated', 'public.card_issue_owners()', 'execute'),
  'authenticated 는 지급 대상 목록 함수를 부르지 못한다'
);

-- 3. 하드 필터(설계 §6.7 · §2.4) ---------------------------------------------
select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000fa'),
  0::bigint, '매칭을 일시중지한 사람은 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000fd'),
  0::bigint, '거절한 지 90일이 지나지 않은 상대는 아직 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000fe'),
  1::bigint, '거절한 지 90일이 지난 상대는 다시 후보가 된다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000fb'),
  0::bigint, '무응답 만료 뒤 14일이 지나지 않은 상대는 아직 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000fc'),
  1::bigint, '무응답 만료 뒤 14일이 지난 상대는 다시 후보가 된다'
);

-- 4. 지급 대상 함수 -----------------------------------------------------------
select is(
  (select count(*) from public.card_issue_owners()
    where profile_id = '00000000-0000-0000-0000-0000000000fa'),
  0::bigint, '일시중지한 사람은 카드를 받지 않는다'
);

select * from finish();
rollback;
