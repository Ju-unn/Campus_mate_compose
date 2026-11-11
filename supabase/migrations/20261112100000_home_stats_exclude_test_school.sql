-- 홈 09b 메인 숫자 · 참여 중인 대학에서 시험 학교(region_group = 'e2e', 심사 · 시험 계정 소속)를 뺀다.
-- 사용자 결정(2026-11-12): 「목록과 숫자 둘 다 빼기」. 학교 이름이 아니라 region_group 으로 가른다(다른 학교는 전부 'seoul').
-- 20260926150000 의 home_stats 를 같은 시그니처로 다시 정의한다(create or replace — 호출 쪽 · 권한 그대로).
--
-- 규칙: e2e 학교 소속 프로필을 "시험 사람" 으로 묶고 네 값 모두에서 뺀다.
--   - delivered_cards        : 받은 사람(owner_id)이 시험 사람인 카드를 뺀다.
--   - signups                : 시험 사람인 active 프로필을 뺀다.
--   - conversations_started  : 두 사람 중 한 명이라도 시험 사람인 매칭을 뺀다. 매칭은 같은 region_group 끼리만 이어져
--                              실제로는 e2e 끼리만 있지만, 한쪽만 시험 사람이어도 시험 흐름이라 뺀다(안전한 쪽).
--   - campuses               : e2e 학교 이름을 뺀다.
-- 학교가 아직 없는 프로필(소셜 로그인 직후)은 시험 사람이 아니므로 종전처럼 센다 — 양성(join)이 아니라 음성(not exists)으로 걸렀다.
-- 성능: 시험 사람은 수십 명뿐이라 CTE 한 번(universities_region_group_index → profiles_university_id_index)으로 모으고,
-- 큰 표(daily_cards · profiles · matches)는 종전처럼 한 번씩 훑되 작은 집합에 대한 anti join 만 더한다. 쿼리 모양은 그대로다.
create or replace function public.home_stats()
returns table (
  delivered_cards bigint,
  signups bigint,
  conversations_started bigint,
  campuses text[]
)
language sql
stable
security invoker
set search_path = ''
as $$
  with test_people as materialized (
    select p.id
      from public.universities u
      join public.profiles p on p.university_id = u.id
     where u.region_group = 'e2e'
  )
  select
    (select count(*)
       from public.daily_cards c
      where not exists (select 1 from test_people t where t.id = c.owner_id)),
    (select count(*)
       from public.profiles p
      where p.status = 'active'
        and not exists (select 1 from test_people t where t.id = p.id)),
    -- 카톡 공유 완료(trust_passed_at)가 아니라 "사람이 쓴 말풍선이 한 건이라도 오간 매칭"이다.
    -- exists 가 messages_match_created_index 의 match_id 앞머리를 탄다.
    (select count(*)
       from public.matches m
      where not exists (select 1 from test_people t where t.id = m.profile_a)
        and not exists (select 1 from test_people t where t.id = m.profile_b)
        and exists (
          select 1 from public.messages msg
           where msg.match_id = m.id and msg.kind = 'text'
        )),
    (select coalesce(array_agg(u.name order by u.name), '{}')
       from public.universities u
      where u.region_group <> 'e2e'
        and exists (
          select 1 from public.profiles p
           where p.university_id = u.id and p.status = 'active'
        ));
$$;

comment on function public.home_stats() is
  '홈 09b 서비스 전체 집계: 누적 카드·active 가입자·말풍선이 오간 매칭·active 학교 이름(이름순). 시험 학교(region_group e2e) 제외. FastAPI 전용';

-- create or replace 는 권한을 그대로 두지만, 처음 정의와 같은 모양으로 다시 못 박아 둔다(멱등).
revoke execute on function public.home_stats() from public, anon, authenticated;
grant execute on function public.home_stats() to service_role;
