-- 코호트(설계 §2.9): 학교마다 첫 카드를 여는 시각. null 이면 코호트 없이 이미 열린 학교다(지금 학교 전부).
-- 여는 시각은 월요일 07:00(Asia/Seoul)만 받는다(계획서 결정 2) — 지급 요일이 사다리로 어떻게 바뀌어도
-- 월요일은 늘 지급일이고, 카드 배치는 Cloud Scheduler 가 07:00 에 한 번 부른다(backend/app/cards/issuing.py).
-- 그래서 배치가 따로 갈래를 두지 않는다. 시간대 없이 넣으면 UTC 로 읽혀 서울 16:00 이 되는데,
-- 그러면 07:00 배치 때 아직 안 열려 첫 카드가 다음 지급일로 밀린다 — check 가 막는다.
-- 스케줄 시각을 바꾸면 이 check 도 마이그레이션으로 같이 바꾼다.
-- infinity 는 요일 · 시각이 null 이라 isfinite 없이는 통과하고, 서버가 날짜로 못 읽어 홈이 500 이 된다.
-- 값은 대시보드에서 넣는다(region_group_settings 와 같은 운영 방식). universities 는 anon 까지 읽기라
-- 여는 시각도 공개된다 — 공지하는 날짜라 문제없다.
alter table public.universities
  add column card_opens_at timestamptz,
  add constraint universities_card_opens_monday_0700
    check (
      card_opens_at is null
      or (
        isfinite(card_opens_at)
        and extract(isodow from card_opens_at at time zone 'Asia/Seoul') = 1
        and (card_opens_at at time zone 'Asia/Seoul')::time = time '07:00'
      )
    );

comment on column public.universities.card_opens_at is
  '첫 카드 지급 시각(설계 §2.9). null = 이미 열림. 열리기 전 사람은 카드 · 후보 · 사다리 인원에서 빠진다';

-- 아래 세 함수는 최신 본문을 통째로 옮겨 와 "열린 학교" 조건 한 줄씩만 더했다 —
-- match_candidates · card_issue_owners 는 20260927010500, region_active_counts 는 20260920160540.
-- 옛 파일은 이미 클라우드에 적용돼 있어 고치지 않는다. 시그니처 · 반환 칸은 한 글자도 바꾸지 않는다
-- (운영 서버가 지금 이 함수를 부르고 있어 create or replace 만 쓴다. drop 하지 않는다).
-- "열림" 정의는 셋 모두 같다: card_opens_at is null or card_opens_at <= now().

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
    select p.*, u.region_group, v.self_survey, v.self_embedding, v.want_embedding,
           mp.phone_hmac, mp.phone_hmac_key_version
    from public.profiles p
    join public.universities u on u.id = p.university_id
    left join public.profile_vectors v on v.profile_id = p.id
    left join public.profile_private mp on mp.profile_id = p.id
    where p.id = p_owner
      and (u.card_opens_at is null or u.card_opens_at <= now())  -- 코호트: 열리기 전 사람은 후보를 받지 않는다(구매 카드 포함)
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
  left join public.profile_private cpp on cpp.profile_id = c.id
  where c.gender <> me.gender                                  -- 반대 성별 자동 매칭(DESIGN §13-113)
    and cu.region_group = me.region_group                      -- 지역그룹
    and (cu.card_opens_at is null or cu.card_opens_at <= now())  -- 코호트: 열린 학교 사람만 후보(설계 §2.9)
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
    )
    -- 조각 6 ----------------------------------------------------------------
    and c.auto_hidden_at is null                               -- 결정 3 자동 가림
    -- 차단 양방향(두 개의 not exists — 한 not exists 안의 or 는 PK (blocker_id, blocked_id) 를
    -- 못 타므로 따로 쓴다).
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
    );
$$;

comment on function public.match_candidates(uuid) is
  '하드 필터 + 성향·태그·문장 점수 3종(설계 §6.8). 감점 계수는 FastAPI 가 곱한다';

revoke all on function public.match_candidates(uuid) from public, anon, authenticated;
grant execute on function public.match_candidates(uuid) to service_role;

-- 오늘 카드를 받을 자격이 있는 사람들. 아직 답하지 않은 무료 카드가 살아 있으면 대상이 아니다 —
-- 지급 시각(07:00)에 직전 카드의 expires_at 이 지나므로, 무응답 카드는 이 시점에 자연히 만료다(설계 §2.4).
create or replace function public.card_issue_owners()
returns table (profile_id uuid, region_group text)
language sql
stable
set search_path = ''
as $$
  select p.id, u.region_group
  from public.profiles p
  join public.universities u on u.id = p.university_id
  join public.profile_vectors v on v.profile_id = p.id
  where p.status = 'active'
    and not p.matching_paused
    and p.last_active_at > now() - interval '14 days'
    and v.self_survey is not null
    and v.self_embedding is not null
    and v.want_embedding is not null
    and not exists (
      select 1
      from public.daily_cards dc
      left join public.card_decisions cd on cd.card_id = dc.id
      where dc.owner_id = p.id
        and dc.source = 'daily'
        and cd.card_id is null
        and dc.expires_at > now()
    )
    -- 조각 6: 자동 가림된 본인도 새 카드를 받지 않는다(결정 3 "새 매칭 불가").
    -- 이미 나간 카드의 수락 경로는 서버(PR 2)가 막는다.
    and p.auto_hidden_at is null
    and (u.card_opens_at is null or u.card_opens_at <= now());  -- 코호트: 열린 학교만(설계 §2.9)
$$;

comment on function public.card_issue_owners() is
  '오늘 무료 카드를 받을 자격이 있는 사람과 그 지역그룹(설계 §2.1·§2.6)';

revoke all on function public.card_issue_owners() from public, anon, authenticated;
grant execute on function public.card_issue_owners() to service_role;

-- 사다리 판정 재료: 지역그룹 × 성별 활성 인원(14일 내 접속). 일시중지는 빼고 센다 —
-- 카드를 주고받을 수 없는 사람은 풀의 두께가 아니다.
create or replace function public.region_active_counts()
returns table (region_group text, gender public.gender, active_count bigint)
language sql
stable
set search_path = ''
as $$
  select u.region_group, p.gender, count(*)
  from public.profiles p
  join public.universities u on u.id = p.university_id
  where p.status = 'active'
    and not p.matching_paused
    and p.gender is not null
    and p.last_active_at > now() - interval '14 days'
    and (u.card_opens_at is null or u.card_opens_at <= now())  -- 코호트: 열린 학교만(설계 §2.9)
  group by u.region_group, p.gender;
$$;

comment on function public.region_active_counts() is
  '지역그룹×성별 활성 인원(14일). 지급 주기 사다리 판정용(설계 §2.1)';

revoke all on function public.region_active_counts() from public, anon, authenticated;
grant execute on function public.region_active_counts() to service_role;
