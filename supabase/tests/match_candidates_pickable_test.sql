-- match_candidates 가 jsonb 배열 한 덩어리를 돌려주고, 쉼 기간 · 결정 전 카드 · 매칭된 상대를
-- "행은 있되 pickable=false" 로 담는지 본다(유료 카드 설계 §3, §7 / 수익모델 재설계 01).
-- 자격 조건(성별 · 지역 · 상태 · 차단 · 자동 가림 · 일시중지 · 접속 15일)은 그대로라서 행 자체가 없어야 한다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

-- 준비 --------------------------------------------------------------------
-- 전용 지역그룹 둘 — 다른 시험 데이터와 섞이지 않게 한다. PICK = 작은 시험, BULK = 1,500명 시험.
insert into public.region_group_settings (region_group) values ('pickable_test'), ('pickable_bulk'), ('pickable_other');

insert into public.universities (id, name, region_group) values
  ('00000000-0000-0000-0000-000000002001', '픽가능테스트대학교', 'pickable_test'),
  ('00000000-0000-0000-0000-000000002002', '픽가능벌크대학교', 'pickable_bulk'),
  ('00000000-0000-0000-0000-000000002003', '픽가능다른지역대학교', 'pickable_other');

-- 나(OWNER, 남) = ...2101. 나머지는 모두 여자이고 닉네임 말고는 똑같다 — 달라지는 이유가 하나뿐이도록.
--   2102 CTRL    아무 제한 없음            → pickable=true
--   2103 REJ10   10일 전에 내가 거절        → false(결정 후 90일 쉼)
--   2104 EXP3    3일 전 무응답 만료         → false(만료 후 14일 쉼)
--   2105 RESP    내가 수락 응답한 상대(10일 전) → false(90일 쉼)
--   2106 LIVE    살아 있는 무료 카드, 결정 전 → false
--   2107 MATCHED 이미 매칭                → false
--   2108 REJ100  100일 전 거절             → true(쉼이 끝났다)
--   2109 EXP20   20일 전 만료              → true(쉼이 끝났다)
--   2110 PAID    결정 전 유료 카드(만료 없음)  → false
--   아래는 행 자체가 없어야 한다:
--   2111 BLKD 내가 차단 / 2112 BLKA 나를 차단 / 2113 SUSP 정지 / 2114 HID 자동 가림 / 2115 PAUSED 일시중지
--   2116 STALE 20일 미접속 / 2117 SAMEG 같은 성별(남) / 2118 OTHERR 다른 지역그룹
--   2119 BLKD_REJ 내가 차단 + 쉼 기간(차단이 쉼 기간보다 우선해 행이 없다)
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000' || n)::uuid, 'pk-' || n || '@pick.ac.kr'
from unnest(array[
  '2101','2102','2103','2104','2105','2106','2107','2108','2109','2110',
  '2111','2112','2113','2114','2115','2116','2117','2118','2119'
]) as n;

-- 20261008010000(소셜 로그인)부터 트리거가 학교를 비워 둔다 — 시험이 학교를 직접 채운다.
update public.profiles set
  university_id = case
    when id = '00000000-0000-0000-0000-000000002118' then '00000000-0000-0000-0000-000000002003'::uuid
    else '00000000-0000-0000-0000-000000002001'::uuid
  end,
  gender = (case when id in ('00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002117')
                 then 'male' else 'female' end)::public.gender,
  status = (case when id = '00000000-0000-0000-0000-000000002113' then 'suspended' else 'active' end)::public.profile_status,
  birth_year = 2002, height_cm = 170, last_active_at = now(),
  interest_tags = array['카페가기'], my_traits = array['다정한'], ideal_traits = array['다정한'],
  nickname = 'p' || translate(right(id::text, 3), '0123456789', 'abcdefghij')
where id::text like '00000000-0000-0000-0000-0000000021%';

update public.profiles set auto_hidden_at = now() where id = '00000000-0000-0000-0000-000000002114';
update public.profiles set matching_paused = true where id = '00000000-0000-0000-0000-000000002115';
update public.profiles set last_active_at = now() - interval '20 days' where id = '00000000-0000-0000-0000-000000002116';

insert into public.profile_vectors (profile_id, self_survey, self_embedding, want_embedding)
select id, '[1,0,0,0,0,0,0,0]',
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector
from public.profiles where id::text like '00000000-0000-0000-0000-0000000021%';

-- 카드와 결정(가짜 id 는 …c0xx)
insert into public.daily_cards (id, owner_id, target_id, source, issued_at, expires_at) values
  ('00000000-0000-0000-0000-00000000c103', '00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002103', 'daily', now() - interval '13 days', now() - interval '10 days'),
  ('00000000-0000-0000-0000-00000000c104', '00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002104', 'daily', now() - interval '6 days', now() - interval '3 days'),
  ('00000000-0000-0000-0000-00000000c105', '00000000-0000-0000-0000-000000002105', '00000000-0000-0000-0000-000000002101', 'daily', now() - interval '13 days', now() - interval '10 days'),
  ('00000000-0000-0000-0000-00000000c106', '00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002106', 'daily', now() - interval '1 hour', now() + interval '1 day'),
  ('00000000-0000-0000-0000-00000000c108', '00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002108', 'daily', now() - interval '103 days', now() - interval '100 days'),
  ('00000000-0000-0000-0000-00000000c109', '00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002109', 'daily', now() - interval '23 days', now() - interval '20 days'),
  ('00000000-0000-0000-0000-00000000c110', '00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002110', 'purchased', now() - interval '1 day', null),
  ('00000000-0000-0000-0000-00000000c119', '00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002119', 'daily', now() - interval '13 days', now() - interval '10 days');
insert into public.card_decisions (card_id, decision, decided_at) values
  ('00000000-0000-0000-0000-00000000c103', 'reject', now() - interval '10 days'),
  ('00000000-0000-0000-0000-00000000c105', 'accept', now() - interval '11 days'),
  ('00000000-0000-0000-0000-00000000c108', 'reject', now() - interval '100 days'),
  ('00000000-0000-0000-0000-00000000c119', 'reject', now() - interval '10 days');
insert into public.acceptance_responses (card_id, responder_id, decision, decided_at) values
  ('00000000-0000-0000-0000-00000000c105', '00000000-0000-0000-0000-000000002101', 'accept', now() - interval '10 days');
insert into public.matches (profile_a, profile_b) values
  ('00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002107');
insert into public.blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002111'),
  ('00000000-0000-0000-0000-000000002112', '00000000-0000-0000-0000-000000002101'),
  ('00000000-0000-0000-0000-000000002101', '00000000-0000-0000-0000-000000002119');

-- 한 후보의 pickable 을 꺼내는 도우미(시험 안에서만 산다 — rollback 으로 사라진다).
create function pg_temp.pick(p_candidate uuid) returns text
language sql stable as $$
  select e ->> 'pickable'
  from jsonb_array_elements(public.match_candidates('00000000-0000-0000-0000-000000002101')) e
  where (e ->> 'candidate_id')::uuid = p_candidate
$$;

set local role service_role;

-- 1. 모양 --------------------------------------------------------------------
select is(
  jsonb_typeof(public.match_candidates('00000000-0000-0000-0000-000000002101')),
  'array', '반환은 jsonb 배열 한 덩어리다(PostgREST 1,000행 상한에 안 걸린다)'
);

select is(
  (select array_agg(k order by k)
     from jsonb_object_keys((public.match_candidates('00000000-0000-0000-0000-000000002101')) -> 0) k),
  array[
    'birth_year', 'candidate_id', 'height_cm', 'is_smoker', 'last_active_at', 'mbti', 'pickable',
    'preferred_age_max', 'preferred_age_min', 'preferred_height_max', 'preferred_height_min',
    'preferred_mbti_flags', 'religion', 'tag_score', 'text_score', 'trait_score'
  ],
  '옛 15칸 이름이 그대로고 pickable 한 칸이 늘었다(서버 scoring · repository 가 읽는 이름 보존)'
);

select is(
  jsonb_typeof(public.match_candidates('00000000-0000-0000-0000-000000002101') -> 0 -> 'pickable'),
  'boolean', 'pickable 은 참 · 거짓 값이다(문자열이 아니다)'
);

select is(
  jsonb_typeof(public.match_candidates('00000000-0000-0000-0000-000000002101') -> 0 -> 'trait_score'),
  'number', '점수는 숫자로 나온다(PostgREST 가 행으로 줄 때와 같다)'
);

-- 2. pickable ----------------------------------------------------------------
select is(pg_temp.pick('00000000-0000-0000-0000-000000002102'), 'true', '아무 제한 없는 후보는 고를 수 있다');
select is(pg_temp.pick('00000000-0000-0000-0000-000000002103'), 'false', '거절한 지 90일 안 상대는 행은 있고 고를 수 없다');
select is(pg_temp.pick('00000000-0000-0000-0000-000000002104'), 'false', '무응답 만료 뒤 14일 안 상대는 행은 있고 고를 수 없다');
select is(pg_temp.pick('00000000-0000-0000-0000-000000002105'), 'false', '내가 수락 응답한 지 90일 안 상대는 행은 있고 고를 수 없다');
select is(pg_temp.pick('00000000-0000-0000-0000-000000002106'), 'false', '결정 전 살아 있는 카드의 상대는 행은 있고 고를 수 없다');
select is(pg_temp.pick('00000000-0000-0000-0000-000000002107'), 'false', '매칭된 상대는 행은 있고 고를 수 없다');
select is(pg_temp.pick('00000000-0000-0000-0000-000000002108'), 'true', '거절한 지 90일이 지난 상대는 다시 고를 수 있다');
select is(pg_temp.pick('00000000-0000-0000-0000-000000002109'), 'true', '만료 뒤 14일이 지난 상대는 다시 고를 수 있다');
select is(pg_temp.pick('00000000-0000-0000-0000-000000002110'), 'false', '결정 전 유료 카드(만료 없음)의 상대는 고를 수 없다');

-- 3. 자격 조건은 그대로 — 행이 없다 -------------------------------------------
select is(
  (select count(*) from jsonb_array_elements(public.match_candidates('00000000-0000-0000-0000-000000002101')) e
    where (e ->> 'candidate_id')::uuid in (
      '00000000-0000-0000-0000-000000002111', '00000000-0000-0000-0000-000000002112',
      '00000000-0000-0000-0000-000000002113', '00000000-0000-0000-0000-000000002114',
      '00000000-0000-0000-0000-000000002115', '00000000-0000-0000-0000-000000002116',
      '00000000-0000-0000-0000-000000002117', '00000000-0000-0000-0000-000000002118',
      '00000000-0000-0000-0000-000000002119')),
  0::bigint, '차단 · 정지 · 자동 가림 · 일시중지 · 미접속 · 같은 성별 · 다른 지역은 행 자체가 없다(쉼 기간과 겹쳐도 같다)'
);

select is(
  (select count(*) from jsonb_array_elements(public.match_candidates('00000000-0000-0000-0000-000000002101'))),
  9::bigint, '후보 행은 정확히 9명이다(2102~2110)'
);

select is(
  (select count(*) from jsonb_array_elements(public.match_candidates('00000000-0000-0000-0000-000000002101')) e
    where (e ->> 'pickable')::boolean),
  3::bigint, '고를 수 있는 사람은 대조군 · 쉼이 끝난 2명, 세 명이다'
);

-- 4. 빈 결과 -------------------------------------------------------------------
-- 후보가 한 명도 없는 사람(2118 은 혼자 다른 지역그룹)과 없는 사람 id 모두 빈 배열이어야 한다(null 이 아니다).
select is(
  public.match_candidates('00000000-0000-0000-0000-000000002118'),
  '[]'::jsonb, '후보가 없으면 빈 배열이다'
);

select is(
  public.match_candidates('00000000-0000-0000-0000-00000000ffff'),
  '[]'::jsonb, '없는 사람이어도 null 이 아니라 빈 배열이다'
);

-- 5. 권한 ---------------------------------------------------------------------
reset role;
select ok(
  not has_function_privilege('authenticated', 'public.match_candidates(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.match_candidates(uuid)', 'execute')
  and has_function_privilege('service_role', 'public.match_candidates(uuid)', 'execute'),
  '새 정의도 service_role 만 부른다'
);

-- 6. 1,500명 --------------------------------------------------------------------
-- PostgREST 는 행 집합을 1,000행에서 자른다. jsonb 한 덩어리는 한 행이라 1,500명이 다 와야 한다.
-- 기준 사람(남 1명) + 여자 1,500명이 한 지역그룹에 있다.
insert into auth.users (id, email)
select ('00000000-0000-0000-0001-' || lpad(to_hex(i), 12, '0'))::uuid, 'bulk' || i || '@bulk.ac.kr'
from generate_series(0, 1500) i;

-- 닉네임은 영문 2~5자 · 대소문자 무시 unique 라서 순번을 알파벳 세 자리로 바꾼다(26^3 = 17,576가지).
with numbered as (
  select id, row_number() over (order by id) - 1 as n
  from public.profiles where id::text like '00000000-0000-0000-0001-%'
)
update public.profiles p set
  university_id = '00000000-0000-0000-0000-000000002002',
  gender = (case when nu.n = 0 then 'male' else 'female' end)::public.gender,
  status = 'active', birth_year = 2002, height_cm = 170, last_active_at = now(),
  interest_tags = array['카페가기'], my_traits = array['다정한'], ideal_traits = array['다정한'],
  nickname = 'q' || chr(97 + (nu.n / 676)::int % 26) || chr(97 + (nu.n / 26)::int % 26) || chr(97 + (nu.n % 26)::int)
from numbered nu where nu.id = p.id;

insert into public.profile_vectors (profile_id, self_survey, self_embedding, want_embedding)
select id, '[1,0,0,0,0,0,0,0]',
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector
from public.profiles where id::text like '00000000-0000-0000-0001-%';

set local role service_role;

select is(
  jsonb_array_length(public.match_candidates('00000000-0000-0000-0001-000000000000')),
  1500, '후보 1,500명이면 1,500개가 다 온다(1,000 상한에 안 걸린다)'
);

select is(
  (select count(distinct e ->> 'candidate_id')
     from jsonb_array_elements(public.match_candidates('00000000-0000-0000-0001-000000000000')) e),
  1500::bigint, '1,500개가 서로 다른 사람이다'
);

select is(
  (select count(*) from jsonb_array_elements(public.match_candidates('00000000-0000-0000-0001-000000000000')) e
    where (e ->> 'pickable')::boolean),
  1500::bigint, '이력이 없는 1,500명은 전부 고를 수 있다'
);

select * from finish();
rollback;
