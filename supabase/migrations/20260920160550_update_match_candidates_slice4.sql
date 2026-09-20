-- 조각 4: match_candidates 에 하드 필터 3종을 더한다(일시중지 · 이미 받은 카드 · 이미 매칭된 상대).
-- 20260920101730_create_match_candidates.sql 의 함수를 통째로 옮겨 와 where 절만 늘렸다 —
-- 그 파일은 이미 클라우드에 적용돼 있어 고치지 않는다. jaccard 함수도 건드리지 않는다.

-- 설계 §6.8: 하드 필터와 벡터 연산을 한 SQL 안에서 끝낸다. 감점 계수(MBTI·키·나이·흡연·종교·활동성)는
-- 분기가 많아 FastAPI scoring.py 가 곱한다 — 그래서 여기서는 계수의 재료 컬럼을 같이 돌려준다.
--
-- 최대가능거리 5.657 = 2 × sqrt(8) (8축이 단위 가중치로 정반대인 경우, 설계 §6.2).
--   축별 가중치를 균등 1.0 이 아닌 값으로 바꾸면 이 상수도 같이 바꾼다(FastAPI AXIS_WEIGHTS 와 짝).
-- pgvector `<=>` 는 코사인 "거리"라 유사도는 1 - 거리다.
-- 연산자는 extensions 스키마에 있고 search_path 가 비어 있어서 operator(extensions.<->) 로 수식해야 한다.
--
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
    and cv.want_embedding is not null
    -- 조각 4 ---------------------------------------------------------------
    and not c.matching_paused                                  -- 일시중지(설계 §2.6)
    -- 이미 카드로 받은 사람(설계 §6.7 · 2026-09-21 사용자 확정). 세 가지를 한 번에 본다:
    --   ① 아직 결정하지 않았고 만료도 안 된 카드 → 중복 지급 방지
    --      (구매 카드는 expires_at is null 이라 결정하기 전까지 항상 여기 걸린다)
    --   ② 수락·거절로 결정한 카드 → 결정 시각 + 90일은 쉬어 간다(영구 제외가 아니다)
    --   ③ 무응답으로 만료된 카드 → 만료 시각 + 14일은 쉬어 간다
    and not exists (
      select 1
      from public.daily_cards dc
      left join public.card_decisions cd on cd.card_id = dc.id
      where dc.owner_id = me.id
        and dc.target_id = c.id
        and (
          (cd.card_id is null and (dc.expires_at is null or dc.expires_at > now()))
          or (cd.card_id is not null and cd.decided_at > now() - interval '90 days')
          or (cd.card_id is null and dc.expires_at is not null
              and dc.expires_at > now() - interval '14 days')
        )
    )
    -- 내가 수락 응답을 한 상대(= 내가 수락을 받았던 상대)도 같은 90일을 쉰다(설계 §6.7).
    -- 쌍방 수락이었다면 아래 matches 조건이 영구히 막으므로 여기서 기간을 따질 일이 없다.
    and not exists (
      select 1
      from public.acceptance_responses ar
      join public.daily_cards dc2 on dc2.id = ar.card_id
      where ar.responder_id = me.id
        and dc2.owner_id = c.id
        and ar.decided_at > now() - interval '90 days'
    )
    -- 이미 매칭된 상대(설계 §6.7)
    and not exists (
      select 1
      from public.matches m
      where m.profile_a = least(me.id, c.id)
        and m.profile_b = greatest(me.id, c.id)
    );
$$;

comment on function public.match_candidates(uuid) is
  '하드 필터 + 성향·태그·문장 점수 3종(설계 §6.8). 감점 계수는 FastAPI 가 곱한다';

revoke all on function public.match_candidates(uuid) from public, anon, authenticated;
grant execute on function public.match_candidates(uuid) to service_role;
