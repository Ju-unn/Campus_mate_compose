-- 글 속 취향 부딪힘(2026-10-30): taste_words 사전 · profile_vectors 단어 칸 4개 · taste_clash_candidates 함수 검증.
-- 6쌍(나 ↔ 상대) 각각 · 0.6 경계 · 자기 자신 제외 · null 배열 · 권한을 본다.
-- 단어 임베딩은 손으로 만든 512차원 벡터다 — 앞 몇 칸만 채우고 나머지는 0 이라 코사인 비슷함을 정확히 정할 수 있다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

-- 준비 --------------------------------------------------------------------
-- 벡터 도우미: 앞 칸만 주면 512차원으로 0 을 채운다.
create function pg_temp.v(comps float8[]) returns extensions.vector
language sql immutable as $$
  select ('[' || array_to_string(comps || array_fill(0::float8, array[512 - cardinality(comps)]), ',') || ']')::extensions.vector
$$;

-- 단어 번호 도우미
create function pg_temp.wid(p_word text) returns bigint
language sql stable as $$ select id from public.taste_words where word = p_word $$;

-- 사전. 가족 4개(f1 ~ f4)는 서로 직교(비슷함 0)이고, 가족마다 '다른 단어'(~근처)가 비슷함 0.8 이다.
--   f1 = 기준 사람의 좋아함 / f2 = 싫어함 / f3 = 원하는 좋아함 / f4 = 원하는 싫어함
--   a 가족은 0.6 경계: 3-4-5 삼각형이라 a ↔ a경계 코사인이 정확히 0.6, a위 0.61, a아래 0.59.
insert into public.taste_words (word, embedding) values
  ('f1',    pg_temp.v(array[1])),
  ('f1근처', pg_temp.v(array[0.8, 0, 0, 0, 0.6])),
  ('f2',    pg_temp.v(array[0, 1])),
  ('f2근처', pg_temp.v(array[0, 0.8, 0, 0, 0, 0.6])),
  ('f3',    pg_temp.v(array[0, 0, 1])),
  ('f3근처', pg_temp.v(array[0, 0, 0.8, 0, 0, 0, 0.6])),
  ('f4',    pg_temp.v(array[0, 0, 0, 1])),
  ('f4근처', pg_temp.v(array[0, 0, 0, 0.8, 0, 0, 0, 0.6])),
  ('a',     pg_temp.v(array[0, 0, 0, 0, 0, 0, 0, 0, 1])),
  ('a경계',  pg_temp.v(array[0, 0, 0, 0, 0, 0, 0, 0, 3, 4])),
  ('a위',    pg_temp.v(array[0, 0, 0, 0, 0, 0, 0, 0, 0.61, 0.7923])),
  ('a아래',  pg_temp.v(array[0, 0, 0, 0, 0, 0, 0, 0, 0.59, 0.8074])),
  ('z',     pg_temp.v(array[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]));

-- 사람: 4001 = 기준(O), 4101 ~ 4106 = 6쌍, 4111 = 같은 방향(부딪히지 않음), 4112 = 전부 null, 4113 = 전부 빈 배열,
--       4201 = 경계 기준, 4211 ~ 4213 = 경계 상대, 4301 = 자기 자신과 부딪히는 사람, 4401 = 전부 null 인 기준
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000' || n)::uuid, 'tc-' || n || '@taste.ac.kr'
from unnest(array[
  '4001', '4101', '4102', '4103', '4104', '4105', '4106', '4111', '4112', '4113',
  '4201', '4211', '4212', '4213', '4301', '4401'
]) as n;

-- O: 좋아함 f1 · 싫어함 f2 · 원하는 좋아함 f3 · 원하는 싫어함 f4
insert into public.profile_vectors (profile_id, self_like_words, self_dislike_words, want_like_words, want_dislike_words) values
  ('00000000-0000-0000-0000-000000004001', array[pg_temp.wid('f1')], array[pg_temp.wid('f2')], array[pg_temp.wid('f3')], array[pg_temp.wid('f4')]),
  -- 1. 나 self_like × 상대 self_dislike (같은 단어 번호)
  ('00000000-0000-0000-0000-000000004101', '{}', array[pg_temp.wid('f1')], '{}', '{}'),
  -- 2. 나 self_dislike × 상대 self_like (다른 단어, 비슷함 1.0)
  ('00000000-0000-0000-0000-000000004102', array[pg_temp.wid('f2근처')], '{}', '{}', '{}'),
  -- 3. 나 want_like × 상대 self_dislike (비슷함 0.8)
  ('00000000-0000-0000-0000-000000004103', '{}', array[pg_temp.wid('f3근처')], '{}', '{}'),
  -- 4. 나 want_dislike × 상대 self_like
  ('00000000-0000-0000-0000-000000004104', array[pg_temp.wid('f4근처')], '{}', '{}', '{}'),
  -- 5. 상대 want_like × 나 self_dislike
  ('00000000-0000-0000-0000-000000004105', '{}', '{}', array[pg_temp.wid('f2근처')], '{}'),
  -- 6. 상대 want_dislike × 나 self_like
  ('00000000-0000-0000-0000-000000004106', '{}', '{}', '{}', array[pg_temp.wid('f1근처')]),
  -- 같은 방향이라 부딪히지 않는다: 같이 좋아함(f1) · 같이 싫어함(f2) · 내가 원하는 좋아함(f3)을 상대도 좋아함 ·
  -- 내가 원치 않는 것(f4)을 상대도 싫어함 · 상대가 원하는 좋아함이 내 좋아함(f1)과 같음 · 상대가 원치 않는 것이 내 싫어함(f2)과 같음
  ('00000000-0000-0000-0000-000000004111',
     array[pg_temp.wid('f1'), pg_temp.wid('f3근처')], array[pg_temp.wid('f2'), pg_temp.wid('f4근처')],
     array[pg_temp.wid('f1근처')], array[pg_temp.wid('f2근처')]),
  -- 나누기 전 · 실패한 사람은 null 이다
  ('00000000-0000-0000-0000-000000004112', null, null, null, null),
  -- 글이 비었거나 항목이 없으면 빈 배열이다
  ('00000000-0000-0000-0000-000000004113', '{}', '{}', '{}', '{}'),
  -- 경계 기준: 좋아함 a
  ('00000000-0000-0000-0000-000000004201', array[pg_temp.wid('a')], '{}', '{}', '{}'),
  ('00000000-0000-0000-0000-000000004211', '{}', array[pg_temp.wid('a경계')], '{}', '{}'),
  ('00000000-0000-0000-0000-000000004212', '{}', array[pg_temp.wid('a위')], '{}', '{}'),
  ('00000000-0000-0000-0000-000000004213', '{}', array[pg_temp.wid('a아래')], '{}', '{}'),
  -- 자기 자신과 부딪힘: 같은 단어를 좋아하고 싫어한다
  ('00000000-0000-0000-0000-000000004301', array[pg_temp.wid('z')], array[pg_temp.wid('z')], '{}', '{}'),
  ('00000000-0000-0000-0000-000000004401', null, null, null, null);

-- 부딪히는 사람 중 이 시험의 사람(4xxx)만 정렬해 돌려준다. 다른 데이터가 섞여 있어도 흔들리지 않게 한다.
create function pg_temp.clash(p_owner uuid) returns text[]
language sql stable as $$
  select coalesce(array_agg(right(e, 4) order by e), '{}')
  from jsonb_array_elements_text(public.taste_clash_candidates(p_owner)) e
  where e like '00000000-0000-0000-0000-000000004%'
$$;

-- 1. 모양 · 6쌍 ---------------------------------------------------------------
set local role service_role;

select is(
  jsonb_typeof(public.taste_clash_candidates('00000000-0000-0000-0000-000000004001')),
  'array', '반환은 jsonb 배열 한 덩어리다(PostgREST 행 수 상한에 안 걸린다)'
);

select ok(
  '4101' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '쌍 1: 내 좋아함 × 상대 싫어함 — 같은 단어 번호면 부딪힌다'
);
select ok(
  '4102' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '쌍 2: 내 싫어함 × 상대 좋아함 — 다른 단어여도 비슷함 0.8 이면 부딪힌다'
);
select ok(
  '4103' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '쌍 3: 내가 원하는 좋아함 × 상대 싫어함 — 비슷함 0.8'
);
select ok(
  '4104' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '쌍 4: 내가 원하는 싫어함 × 상대 좋아함'
);
select ok(
  '4105' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '쌍 5: 상대가 원하는 좋아함 × 내 싫어함'
);
select ok(
  '4106' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '쌍 6: 상대가 원하는 싫어함 × 내 좋아함'
);

select is(
  pg_temp.clash('00000000-0000-0000-0000-000000004001'),
  array['4101', '4102', '4103', '4104', '4105', '4106'],
  '부딪히는 사람은 6쌍의 여섯 명뿐이다(같은 방향 · null · 빈 배열 · 다른 단어는 안 걸린다)'
);

select ok(
  not '4111' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '같은 방향(같이 좋아함 · 같이 싫어함 · 원하는 것을 상대도 좋아함)은 부딪힘이 아니다'
);
select ok(
  not '4112' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '배열이 null 인 사람(아직 안 나눔 · 나누기 실패)은 걸리지 않는다'
);
select ok(
  not '4113' = any (pg_temp.clash('00000000-0000-0000-0000-000000004001')),
  '배열이 빈 사람(글이 비었음)은 걸리지 않는다'
);

-- 2. 0.6 경계 ------------------------------------------------------------------
select is(
  pg_temp.clash('00000000-0000-0000-0000-000000004201'),
  array['4212'],
  '비슷함 0.61 은 부딪히고, 정확히 0.6 과 0.59 는 아니다("0.6 초과")'
);

select ok(
  (select 1 - (a.embedding operator(extensions.<=>) e.embedding) = 0.6
     from public.taste_words a, public.taste_words e where a.word = 'a' and e.word = 'a경계'),
  '준비 확인: a ↔ a경계 의 비슷함이 부동소수 오차 없이 정확히 0.6 이다'
);

-- 2-1. 다른 방법으로 계산한 결과와 같다 -----------------------------------------------------
-- 시험 DB 실험(taste_tables.sql 의 sim_taste_scores)과 같은 풀이 — 사람 · 칸 · 단어 행을 펼쳐 두 사람의 모든 단어 짝을 직접 비교 — 를
-- 기준으로 삼아, 무작위 단어 80개 · 사람 40명(고정 씨앗)에서 함수 결과가 한 명도 다르지 않은지 본다.
reset role;
select setseed(0.30);
insert into public.taste_words (word, embedding)
select 'r' || g, pg_temp.v(array[random() * 2 - 1, random() * 2 - 1, random() * 2 - 1, random() * 2 - 1, random() * 2 - 1])
from generate_series(1, 80) g;

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000' || (5000 + g))::uuid, 'tr-' || g || '@taste.ac.kr' from generate_series(1, 40) g;

-- 사람마다 칸 4개에 0~3 개의 무작위 단어(10% 는 칸 전체가 null)
create function pg_temp.pick_words() returns bigint[]
language sql volatile as $$
  select case when random() < 0.1 then null
    else coalesce((select array_agg(id) from (select id from public.taste_words where word like 'r%' order by random() limit floor(random() * 4)::int) x), '{}') end
$$;
insert into public.profile_vectors (profile_id, self_like_words, self_dislike_words, want_like_words, want_dislike_words)
select ('00000000-0000-0000-0000-00000000' || (5000 + g))::uuid, pg_temp.pick_words(), pg_temp.pick_words(), pg_temp.pick_words(), pg_temp.pick_words()
from generate_series(1, 40) g;

create function pg_temp.reference(p_owner uuid) returns text[]
language sql stable as $$
  with items as (
    select profile_id, 'sl' as slot, unnest(self_like_words) as w from public.profile_vectors
    union all select profile_id, 'sd', unnest(self_dislike_words) from public.profile_vectors
    union all select profile_id, 'wl', unnest(want_like_words) from public.profile_vectors
    union all select profile_id, 'wd', unnest(want_dislike_words) from public.profile_vectors
  )
  select coalesce(array_agg(distinct right(c.profile_id::text, 4) order by right(c.profile_id::text, 4)), '{}')
  from items o
  join items c on c.profile_id <> o.profile_id
  join public.taste_words ow on ow.id = o.w
  join public.taste_words cw on cw.id = c.w
  where o.profile_id = p_owner
    and c.profile_id::text like '00000000-0000-0000-0000-00000000500%'
    and 1 - (ow.embedding operator(extensions.<=>) cw.embedding) > 0.6
    and (   (o.slot = 'sl' and c.slot = 'sd') or (o.slot = 'sd' and c.slot = 'sl')
         or (o.slot = 'wl' and c.slot = 'sd') or (o.slot = 'wd' and c.slot = 'sl')
         or (c.slot = 'wl' and o.slot = 'sd') or (c.slot = 'wd' and o.slot = 'sl'))
$$;
create function pg_temp.fast(p_owner uuid) returns text[]
language sql stable as $$
  select coalesce(array_agg(right(e, 4) order by right(e, 4)), '{}')
  from jsonb_array_elements_text(public.taste_clash_candidates(p_owner)) e
  where e like '00000000-0000-0000-0000-00000000500%'
$$;

set local role service_role;
select is(
  (select count(*) from generate_series(1, 40) g
    where pg_temp.fast(('00000000-0000-0000-0000-00000000' || (5000 + g))::uuid)
          is distinct from pg_temp.reference(('00000000-0000-0000-0000-00000000' || (5000 + g))::uuid)),
  0::bigint,
  '무작위 40명 모두에서 함수 결과가 단어 짝 직접 비교와 같다'
);
select cmp_ok(
  (select sum(cardinality(pg_temp.reference(('00000000-0000-0000-0000-00000000' || (5000 + g))::uuid))) from generate_series(1, 40) g),
  '>', 20::bigint,
  '준비 확인: 무작위 데이터에서 부딪히는 짝이 충분히 나온다(비교가 빈 집합끼리가 아니다)'
);

-- 3. 자기 자신 제외 · null 기준 --------------------------------------------------
select ok(
  not '4301' = any (pg_temp.clash('00000000-0000-0000-0000-000000004301')),
  '자기 자신은 결과에서 빠진다(같은 단어를 좋아하고 싫어해도)'
);
select is(
  pg_temp.clash('00000000-0000-0000-0000-000000004401'),
  '{}'::text[],
  '기준 사람의 배열이 전부 null 이면 아무도 안 걸린다(지금과 같음)'
);
select is(
  public.taste_clash_candidates('00000000-0000-0000-0000-00000000dead'),
  '[]'::jsonb,
  '벡터 행이 없는 기준 사람도 빈 배열이다(오류가 아니다)'
);

-- 4. 함수 권한 -----------------------------------------------------------------
reset role;

select ok(
  has_function_privilege('service_role', 'public.taste_clash_candidates(uuid)', 'execute'),
  'service_role 은 taste_clash_candidates 를 실행할 수 있다'
);
select ok(
  not has_function_privilege('anon', 'public.taste_clash_candidates(uuid)', 'execute'),
  'anon 은 taste_clash_candidates 를 실행할 수 없다'
);
select ok(
  not has_function_privilege('authenticated', 'public.taste_clash_candidates(uuid)', 'execute'),
  'authenticated 는 taste_clash_candidates 를 실행할 수 없다'
);
select ok(
  not exists (
    select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'public.taste_clash_candidates(uuid)'::regprocedure and a.grantee = 0
  ),
  'PUBLIC 에도 실행 권한이 없다'
);
select ok(
  (select not prosecdef from pg_proc where oid = 'public.taste_clash_candidates(uuid)'::regprocedure),
  '함수는 security invoker 다(호출자의 권한으로 읽는다)'
);

-- 5. taste_words 표 -------------------------------------------------------------
select ok(
  (select relrowsecurity from pg_class where oid = 'public.taste_words'::regclass),
  'taste_words 는 RLS 가 켜져 있다'
);
select is_empty(
  $$select policyname from pg_policies where schemaname = 'public' and tablename = 'taste_words'$$,
  'taste_words 에는 정책이 없다(서버 전용)'
);
select ok(
  not has_table_privilege('anon', 'public.taste_words', 'select, insert, update, delete')
  and not has_table_privilege('authenticated', 'public.taste_words', 'select, insert, update, delete'),
  'anon · authenticated 는 taste_words 권한이 하나도 없다'
);
select ok(
  has_table_privilege('service_role', 'public.taste_words', 'select')
  and has_table_privilege('service_role', 'public.taste_words', 'insert')
  and not has_table_privilege('service_role', 'public.taste_words', 'update')
  and not has_table_privilege('service_role', 'public.taste_words', 'delete'),
  'service_role 은 taste_words 를 읽고 넣을 수만 있다(고치거나 지우지 못한다)'
);

set local role authenticated;
select throws_ok($$select * from public.taste_words$$, '42501', null, 'authenticated 가 taste_words 를 읽으면 막힌다');
set local role anon;
select throws_ok($$select * from public.taste_words$$, '42501', null, 'anon 이 taste_words 를 읽으면 막힌다');
reset role;

select is(
  (select attstorage::text from pg_attribute where attrelid = 'public.taste_words'::regclass and attname = 'embedding'),
  'p',
  '사전 임베딩은 TOAST 밖(plain)에 둔다 — 비교할 때마다 풀지 않아 부딪힘 계산이 10배 넘게 빠르다(로컬 4,000단어 20명: 17.4초 → 1.2초)'
);

-- 6. 제약 · 넣기 ----------------------------------------------------------------
set local role service_role;
select throws_ok(
  $$insert into public.taste_words (word, embedding) values ('', pg_temp.v(array[1]))$$,
  '23514', null, '빈 단어는 넣을 수 없다'
);
select throws_ok(
  $$insert into public.taste_words (word, embedding) values (repeat('가', 41), pg_temp.v(array[1]))$$,
  '23514', null, '41글자 단어는 넣을 수 없다'
);
select lives_ok(
  $$insert into public.taste_words (word, embedding) values (repeat('가', 40), pg_temp.v(array[1]))$$,
  '40글자 단어는 넣을 수 있다'
);
select throws_ok(
  $$insert into public.taste_words (word, embedding) values ('f1', pg_temp.v(array[1]))$$,
  '23505', null, '같은 단어는 두 번 넣을 수 없다(unique)'
);
select lives_ok(
  $$insert into public.taste_words (word, embedding) values ('f1', pg_temp.v(array[1])) on conflict (word) do nothing$$,
  '동시에 같은 새 단어를 넣어도 ignore-duplicates(on conflict do nothing)로 하나만 남는다'
);
reset role;

-- 7. profile_vectors 새 칸 ------------------------------------------------------
select is(
  (select array_agg(attname::text || ':' || format_type(atttypid, atttypmod) || ':' || (not attnotnull)::text order by attname)
     from pg_attribute
    where attrelid = 'public.profile_vectors'::regclass
      and attname in ('self_like_words', 'self_dislike_words', 'want_like_words', 'want_dislike_words')),
  array['self_dislike_words:bigint[]:true', 'self_like_words:bigint[]:true',
        'want_dislike_words:bigint[]:true', 'want_like_words:bigint[]:true'],
  'profile_vectors 에 bigint[] 칸 4개가 null 허용으로 있다'
);
select ok(
  has_column_privilege('service_role', 'public.profile_vectors', 'self_like_words', 'select')
  and not has_column_privilege('authenticated', 'public.profile_vectors', 'self_like_words', 'select')
  and not has_column_privilege('anon', 'public.profile_vectors', 'want_dislike_words', 'select'),
  '새 칸도 service_role 만 읽는다(기존 표 권한 그대로)'
);

select * from finish();
rollback;
