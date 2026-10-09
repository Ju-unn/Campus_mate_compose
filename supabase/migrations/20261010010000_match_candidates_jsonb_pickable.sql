-- 유료 카드 설계 §3 · §7: 후보 함수가 "쉬는 중인 사람"도 같이 돌려주고, 고를 수 있는지는 pickable 한 칸으로 알린다.
-- 서버가 쉬는 중인 사람의 수까지 알아야 후보 폭(band_count)과 안내 문구를 만들 수 있다.
--
-- 바뀌는 것 둘:
--  ① 반환이 `table(...)` 에서 `jsonb`(배열 한 덩어리)로 바뀐다. PostgREST 는 행 집합을 1,000행에서 자르지만
--     jsonb 는 한 행이라 후보가 1,500명이어도 전부 온다. 후보가 없으면 null 이 아니라 `[]` 다.
--  ② 쉼 기간 안(결정 후 90일 · 무응답 만료 후 14일 · 내가 수락 응답한 상대 90일), 결정 전 카드(구매 카드 포함),
--     매칭된 상대는 행에서 빠지지 않고 `pickable = false` 로 나온다.
-- 그 밖의 자격 조건(이성 · 같은 지역그룹 · 열린 학교 · active · 접속 15일 · 일시중지 · 자동 가림 · 차단 · 지인 차단 ·
-- 벡터 있음)은 20260928050000 본문 그대로라서 걸리면 행 자체가 없다. 옛 15칸 이름도 그대로다
-- (backend/app/matching/scoring.py · repository.py 가 읽는 이름).
--
-- 반환 타입이 바뀌어 create or replace 가 안 되므로 drop 한 뒤 만든다. 같은 이름 · 같은 인자의 RPC 라 서버 호출 주소는
-- 그대로고, 응답 본문은 여전히 "객체의 배열"이라 서버 코드가 그대로 읽는다.
drop function public.match_candidates(uuid);

create function public.match_candidates(p_owner uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with me as (
    select p.*, u.region_group, v.self_survey, v.self_embedding, v.want_embedding,
           mp.phone_hmac, mp.phone_hmac_key_version
    from public.profiles p
    join public.universities u on u.id = p.university_id
    left join public.profile_vectors v on v.profile_id = p.id
    left join public.profile_private mp on mp.profile_id = p.id
    where p.id = p_owner
      and (u.card_opens_at is null or u.card_opens_at <= now())  -- 코호트: 열리기 전 사람은 후보를 받지 않는다(구매 카드 포함)
  ),
  cand as (
    select
      c.id as candidate_id,
      greatest(0, 1 - (me.self_survey operator(extensions.<->) cv.self_survey) / 5.657) as trait_score,
      (
        public.jaccard(me.interest_tags, c.interest_tags)
        + (public.jaccard(me.my_traits, c.ideal_traits) + public.jaccard(c.my_traits, me.ideal_traits)) / 2
      ) / 2 as tag_score,
      greatest(0, (
        (1 - (me.want_embedding operator(extensions.<=>) cv.self_embedding))
        + (1 - (cv.want_embedding operator(extensions.<=>) me.self_embedding))
      ) / 2) as text_score,
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
      c.last_active_at,
      -- 쉬는 중이면 후보에는 남되 고를 수 없다. 이 식이 예전 `not exists` 세 개를 그대로 뒤집은 것이다(설계 §6.7).
      --   ① 이미 카드로 받은 사람. 세 가지를 한 번에 본다:
      --      · 아직 결정하지 않았고 만료도 안 된 카드 → 중복 지급 방지(구매 카드는 expires_at is null 이라 결정 전까지 늘 여기 걸린다)
      --      · 수락 · 거절로 결정한 카드 → 결정 시각 + 90일은 쉬어 간다(영구 제외가 아니다)
      --      · 무응답으로 만료된 카드 → 만료 시각 + 14일은 쉬어 간다
      --   ② 내가 수락 응답을 한 상대(= 내가 수락을 받았던 상대)도 같은 90일을 쉰다.
      --   ③ 이미 매칭된 상대는 영구히 고를 수 없다.
      (
        exists (
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
        or exists (
          select 1
          from public.acceptance_responses ar
          join public.daily_cards dc2 on dc2.id = ar.card_id
          where ar.responder_id = me.id
            and dc2.owner_id = c.id
            and ar.decided_at > now() - interval '90 days'
        )
        or exists (
          select 1
          from public.matches m
          where m.profile_a = least(me.id, c.id)
            and m.profile_b = greatest(me.id, c.id)
        )
      ) as resting
    from me
    join public.profiles c on c.id <> me.id
    join public.universities cu on cu.id = c.university_id
    join public.profile_vectors cv on cv.profile_id = c.id
    left join public.profile_private cpp on cpp.profile_id = c.id
    where c.gender <> me.gender                                  -- 반대 성별 자동 매칭(DESIGN §13-113)
      and cu.region_group = me.region_group                      -- 지역그룹
      and (cu.card_opens_at is null or cu.card_opens_at <= now())  -- 코호트: 열린 학교 사람만 후보(설계 §2.9)
      and c.status = 'active'
      and c.last_active_at > now() - interval '15 days'          -- 15일 이상 미접속 제외(설계 §6.7)
      and cv.self_survey is not null
      and cv.self_embedding is not null
      and cv.want_embedding is not null
      and not c.matching_paused                                  -- 일시중지(설계 §2.6)
      and c.auto_hidden_at is null                               -- 결정 3 자동 가림
      -- 차단 양방향(두 개의 not exists — 한 not exists 안의 or 는 PK (blocker_id, blocked_id) 를
      -- 못 타므로 따로 쓴다). 쉼 기간과 달리 차단은 행 자체를 뺀다.
      and not exists (
        select 1 from public.blocks b
        where b.blocker_id = me.id and b.blocked_id = c.id
      )
      and not exists (
        select 1 from public.blocks b
        where b.blocker_id = c.id and b.blocked_id = me.id
      )
      -- 지인 차단 양방향. phone_hmac 이 null 이면 `=` 가 참이 아니라 제외되지 않는다 —
      -- 지금 운영 사용자 전원이 null 이므로 이 성질이 필수다(조각 6 백필 전에는 아무도 걸러지지 않는다).
      and not exists (
        select 1 from public.contact_blocks cb
        where cb.owner_id = me.id
          and cb.contact_hmac = cpp.phone_hmac
          and cb.key_version = cpp.phone_hmac_key_version
      )
      and not exists (
        select 1 from public.contact_blocks cb
        where cb.owner_id = c.id
          and cb.contact_hmac = me.phone_hmac
          and cb.key_version = me.phone_hmac_key_version
      )
  )
  select coalesce(
    jsonb_agg(jsonb_build_object(
      'candidate_id', candidate_id,
      'trait_score', trait_score,
      'tag_score', tag_score,
      'text_score', text_score,
      'mbti', mbti,
      'preferred_mbti_flags', preferred_mbti_flags,
      'height_cm', height_cm,
      'preferred_height_min', preferred_height_min,
      'preferred_height_max', preferred_height_max,
      'birth_year', birth_year,
      'preferred_age_min', preferred_age_min,
      'preferred_age_max', preferred_age_max,
      'is_smoker', is_smoker,
      'religion', religion,
      'last_active_at', last_active_at,
      'pickable', not resting
    )),
    '[]'::jsonb
  )
  from cand;
$$;

comment on function public.match_candidates(uuid) is
  '하드 필터 통과 후보 전원을 jsonb 배열로(설계 §6.8). 쉼 기간 · 결정 전 카드 · 매칭된 상대는 pickable=false 로 포함. 감점 계수는 FastAPI 가 곱한다';

-- security invoker + service_role 만 부른다(이 저장소 관례). 서버가 service_role 로 RPC 를 부른다.
revoke all on function public.match_candidates(uuid) from public, anon, authenticated;
grant execute on function public.match_candidates(uuid) to service_role;
