-- 태그점수(설계 §6.6b)용 자카드. 한쪽이라도 비면 0 이다(합집합이 0 일 때 0/0 을 피한다).
create or replace function public.jaccard(a text[], b text[])
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case when u = 0 then 0 else i::numeric / u end
  from (
    select
      cardinality(array(select unnest(a) intersect select unnest(b))) as i,
      cardinality(array(select unnest(a) union select unnest(b))) as u
  ) counts;
$$;

comment on function public.jaccard(text[], text[]) is
  '태그 자카드 유사도(설계 §6.6b). 합집합이 0 이면 0';

-- 설계 §6.8: 하드 필터와 벡터 연산을 한 SQL 안에서 끝낸다. 감점 계수(MBTI·키·나이·흡연·종교·활동성)는
-- 분기가 많아 FastAPI scoring.py 가 곱한다 — 그래서 여기서는 계수의 재료 컬럼을 같이 돌려준다.
--
-- 최대가능거리 5.657 = 2 × sqrt(8) (8축이 단위 가중치로 정반대인 경우, 설계 §6.2).
--   축별 가중치를 균등 1.0 이 아닌 값으로 바꾸면 이 상수도 같이 바꾼다(FastAPI AXIS_WEIGHTS 와 짝).
-- pgvector `<=>` 는 코사인 "거리"라 유사도는 1 - 거리다.
-- 연산자는 extensions 스키마에 있고 search_path 가 비어 있어서 operator(extensions.<->) 로 수식해야 한다.
--
-- 조각 4에서 추가할 조건(테이블이 생기면 아래 두 줄을 where 에 넣는다):
--   and not c.matching_paused                                   -- 일시중지(조각 4 컬럼)
--   and not exists (select 1 from public.card_decisions ...)    -- 이미 카드로 받은 사람(조각 4)
-- 조각 6에서 추가할 조건:
--   and not exists (select 1 from public.blocks b
--                    where (b.blocker_id = p_owner and b.blocked_id = c.id)
--                       or (b.blocker_id = c.id and b.blocked_id = p_owner))
create or replace function public.match_candidates(p_owner uuid)
returns table (
  candidate_id uuid,
  trait_score numeric,
  tag_score numeric,
  text_score numeric,
  mbti text,
  preferred_mbti_flags jsonb,
  height_cm smallint,
  preferred_height_min smallint,
  preferred_height_max smallint,
  birth_year smallint,
  preferred_age_min smallint,
  preferred_age_max smallint,
  is_smoker boolean,
  religion public.religion,
  last_active_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  with me as (
    select p.*, u.region_group, v.self_survey, v.self_embedding, v.want_embedding
    from public.profiles p
    join public.universities u on u.id = p.university_id
    left join public.profile_vectors v on v.profile_id = p.id
    where p.id = p_owner
  )
  select
    c.id,
    greatest(0, 1 - (me.self_survey operator(extensions.<->) cv.self_survey) / 5.657),
    (
      public.jaccard(me.interest_tags, c.interest_tags)
      + (public.jaccard(me.my_traits, c.ideal_traits) + public.jaccard(c.my_traits, me.ideal_traits)) / 2
    ) / 2,
    greatest(0, (
      (1 - (me.want_embedding operator(extensions.<=>) cv.self_embedding))
      + (1 - (cv.want_embedding operator(extensions.<=>) me.self_embedding))
    ) / 2),
    c.mbti,
    c.preferred_mbti_flags,
    c.height_cm,
    c.preferred_height_min,
    c.preferred_height_max,
    c.birth_year,
    c.preferred_age_min,
    c.preferred_age_max,
    c.is_smoker,
    c.religion,
    c.last_active_at
  from me
  join public.profiles c on c.id <> me.id
  join public.universities cu on cu.id = c.university_id
  join public.profile_vectors cv on cv.profile_id = c.id
  where c.gender <> me.gender                                  -- 반대 성별 자동 매칭(DESIGN §13-113)
    and cu.region_group = me.region_group                      -- 지역그룹
    and c.status = 'active'
    and c.last_active_at > now() - interval '15 days'          -- 15일 이상 미접속 제외(설계 §6.7)
    and cv.self_survey is not null
    and cv.self_embedding is not null
    and cv.want_embedding is not null;
$$;

comment on function public.match_candidates(uuid) is
  '하드 필터 + 성향·태그·문장 점수 3종(설계 §6.8). 감점 계수는 FastAPI 가 곱한다';

revoke all on function public.match_candidates(uuid) from public, anon, authenticated;
grant execute on function public.match_candidates(uuid) to service_role;
revoke all on function public.jaccard(text[], text[]) from public, anon, authenticated;
grant execute on function public.jaccard(text[], text[]) to service_role;
