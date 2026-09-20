-- 조각 3 RLS · 권한 · 점수 함수 검증. 기대값 기준은 docs/ERD.md §2 "사이클 B pgTAP 기대값의 기준".
-- 전 테이블 권한(ACL) 표 · 모든 테이블 RLS 는 rls_slice0_test.sql 이 누적으로 본다.
-- 로컬 스택에서 `supabase test db` 로 돌린다.
-- 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

-- 준비 (postgres) -------------------------------------------------------------
-- 사용자 A = ...aa(남), 사용자 B = ...bb(여), 테스트 대학 = ...01
-- 하드 필터에 걸려야 하는 사람들: C = ...cc(A 와 같은 성별), D = ...dd(다른 지역그룹), E = ...ee(16일 미접속)
-- on_auth_user_created 트리거가 auth.users insert 직후 도메인으로 대학을 찾으므로 도메인 행이 먼저다.
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000002', '부산테스트대학교', 'busan');

insert into public.university_email_domains (domain, university_id) values
  ('test.ac.kr', '00000000-0000-0000-0000-000000000001'),
  ('test2.ac.kr', '00000000-0000-0000-0000-000000000002');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'm3-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000bb', 'm3-b@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000cc', 'm3-c@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000dd', 'm3-d@test2.ac.kr'),
  ('00000000-0000-0000-0000-0000000000ee', 'm3-e@test.ac.kr');

insert into public.profiles (id, university_id) values
  ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000cc', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000dd', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-0000000000ee', '00000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

update public.profiles set
  nickname = '가나다', gender = 'male', status = 'active',
  interest_tags = array['카페가기','등산','영화'],
  my_traits = array['유머러스한','다정한','계획적인'],
  ideal_traits = array['다정한','활발한','솔직한'],
  height_cm = 180, birth_year = 2002, mbti = 'ENFP', last_active_at = now()
where id = '00000000-0000-0000-0000-0000000000aa';

update public.profiles set
  nickname = '라마바', gender = 'female', status = 'active',
  interest_tags = array['카페가기','등산','전시회'],
  my_traits = array['다정한','활발한','차분한'],
  ideal_traits = array['유머러스한','성실한','솔직한'],
  height_cm = 165, birth_year = 2003, mbti = 'ISFJ', last_active_at = now()
where id = '00000000-0000-0000-0000-0000000000bb';

-- C·D·E 는 하드 필터 한 가지씩만 어기고 나머지는 B 와 같다 — 걸러지는 이유가 그 한 가지임을 분명히 한다.
update public.profiles set
  nickname = '사아자', gender = 'male', status = 'active',
  interest_tags = array['카페가기','등산','전시회'],
  my_traits = array['다정한','활발한','차분한'],
  ideal_traits = array['유머러스한','성실한','솔직한'],
  height_cm = 175, birth_year = 2003, mbti = 'ISFJ', last_active_at = now()
where id = '00000000-0000-0000-0000-0000000000cc';

update public.profiles set
  nickname = '차카타', gender = 'female', status = 'active',
  interest_tags = array['카페가기','등산','전시회'],
  my_traits = array['다정한','활발한','차분한'],
  ideal_traits = array['유머러스한','성실한','솔직한'],
  height_cm = 165, birth_year = 2003, mbti = 'ISFJ', last_active_at = now()
where id = '00000000-0000-0000-0000-0000000000dd';

update public.profiles set
  nickname = '파하가', gender = 'female', status = 'active',
  interest_tags = array['카페가기','등산','전시회'],
  my_traits = array['다정한','활발한','차분한'],
  ideal_traits = array['유머러스한','성실한','솔직한'],
  height_cm = 165, birth_year = 2003, mbti = 'ISFJ', last_active_at = now() - interval '16 days'
where id = '00000000-0000-0000-0000-0000000000ee';

insert into public.profile_vectors (profile_id, self_survey, shyness_score, self_embedding, want_embedding)
values
  ('00000000-0000-0000-0000-0000000000aa',
   '[1,0,0,0,0,0,0,0]', 0.5,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector),
  ('00000000-0000-0000-0000-0000000000bb',
   '[1,0,0,0,0,0,0,0]', -0.5,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector),
  ('00000000-0000-0000-0000-0000000000cc',
   '[1,0,0,0,0,0,0,0]', -0.5,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector),
  ('00000000-0000-0000-0000-0000000000dd',
   '[1,0,0,0,0,0,0,0]', -0.5,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector),
  ('00000000-0000-0000-0000-0000000000ee',
   '[1,0,0,0,0,0,0,0]', -0.5,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector);

-- 1. 구조 · 제약 ------------------------------------------------------------
select has_table('public', 'profile_vectors', 'profile_vectors 테이블이 있다');

select col_type_is('public', 'profile_vectors', 'self_survey', 'extensions.vector(8)',
  'self_survey 는 8차원 벡터다');

select col_type_is('public', 'profile_vectors', 'self_embedding', 'extensions.vector(512)',
  '"나는" 임베딩은 512차원이다');

select col_type_is('public', 'profile_vectors', 'want_embedding', 'extensions.vector(512)',
  '"원해" 임베딩은 512차원이다');

select throws_ok(
  $$update public.profile_vectors set shyness_score = 0.3
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23514', null, 'shyness_score 는 5점 척도 값만 받는다'
);

-- 2. RLS · 권한 -------------------------------------------------------------
select is(
  (select relrowsecurity from pg_class where oid = 'public.profile_vectors'::regclass),
  true, 'profile_vectors 는 RLS 가 켜져 있다'
);

select is(
  (select count(*) from pg_policies where tablename = 'profile_vectors'),
  0::bigint, 'profile_vectors 에는 정책이 하나도 없다(FastAPI 전용)'
);

select ok(
  not has_table_privilege('authenticated', 'public.profile_vectors', 'select'),
  'authenticated 는 profile_vectors 를 읽지 못한다'
);

select ok(
  has_table_privilege('service_role', 'public.profile_vectors', 'select, insert, update, delete'),
  'service_role 만 profile_vectors 를 읽고 쓴다'
);

select ok(
  not has_function_privilege('authenticated', 'public.match_candidates(uuid)', 'execute'),
  'authenticated 는 match_candidates 를 부르지 못한다'
);

-- 3. 점수 계산 ---------------------------------------------------------------
select is(public.jaccard(array['a','b','c'], array['b','c','d']), 0.5::numeric,
  '자카드는 교집합 ÷ 합집합이다');

-- 관심사 2/4, 내 특징↔상대 이상형 1/5, 상대 특징↔내 이상형 2/4 → (0.5 + 0.35) / 2 = 0.425
select is(
  (select round(tag_score, 4) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')),
  round(((2::numeric/4) + ((1::numeric/5) + (2::numeric/4)) / 2) / 2, 4),
  '태그점수 = 평균[관심사 자카드, 양방향 특징 자카드의 평균]'
);

-- 4. 하드 필터 — 걸려야 하는 사람은 안 나온다(설계 §6.7) ------------------------
select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000cc'),
  0::bigint, '같은 성별은 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000dd'),
  0::bigint, '다른 지역그룹은 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')
    where candidate_id = '00000000-0000-0000-0000-0000000000ee'),
  0::bigint, '15일을 넘게 접속하지 않은 사람은 후보가 아니다'
);

select * from finish();
rollback;
