-- 조각 4: 지역그룹별 카드 지급 주기(설계 §2.1). 주기를 바꾸는 손잡이는 전부 이 테이블 행에 있다 —
-- 배포 없이 대시보드에서 값만 고치면 다음 배치부터 적용된다.
create table public.region_group_settings (
  region_group text primary key,
  -- ISO 요일(1=월 … 7=일). 기본은 사다리 아래칸(주 2회 · 월 · 목)이다.
  -- 이 값은 배치가 사다리로 계산해 갱신하는 결과값이다 — 앱이 "다음 지급은 O요일" 문구를
  -- 그리는 재료이기도 하다. 요일을 바꾸고 싶으면 아래 임계값을 조정한다(손으로 고친 요일은 다음 배치가 덮는다).
  issue_weekdays smallint[] not null default array[1, 4]::smallint[],
  issue_time time not null default '07:00',            -- Asia/Seoul 기준
  -- 사다리 임계값(2026-09-19 사용자 확정 값이 기본). 남녀 중 적은 쪽 활성 인원과 비교한다.
  ladder_three_per_week_min integer not null default 200,
  ladder_daily_min integer not null default 500,
  updated_at timestamptz not null default now(),

  constraint region_group_settings_weekdays_valid check (
    issue_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]
    and cardinality(issue_weekdays) between 1 and 7
  ),
  constraint region_group_settings_ladder_order check (
    ladder_daily_min >= ladder_three_per_week_min
  )
);

comment on table public.region_group_settings is
  '지역그룹별 카드 지급 요일·시각·사다리 임계값(설계 §2.1). 값만 바꿔 주기를 조정한다';

-- 설계 §2.6 매칭 일시중지 토글: 새 카드 배치 대상에서 빠지고, 남의 후보에서도 빠진다(20260920160550).
alter table public.profiles
  add column matching_paused boolean not null default false;

comment on column public.profiles.matching_paused is
  '매칭 일시중지(설계 §2.6). true 면 카드를 받지도, 남의 후보로 나오지도 않는다';

-- FK 를 걸기 전에 지금 존재하는 지역그룹의 행을 먼저 만든다(ERD §3 주석).
-- 첫 출시는 'seoul' 뿐이지만, 시드에 다른 값이 있어도 빠짐없이 들어가게 distinct 로 넣는다.
insert into public.region_group_settings (region_group)
values ('seoul')
on conflict (region_group) do nothing;

insert into public.region_group_settings (region_group)
select distinct u.region_group from public.universities u
on conflict (region_group) do nothing;

alter table public.universities
  add constraint universities_region_group_fkey
  foreign key (region_group) references public.region_group_settings (region_group);

-- FK 컬럼 인덱스(advisor WARN 방지 — 20260920061752 에서 지적받은 항목).
create index universities_region_group_index on public.universities (region_group);

alter table public.region_group_settings enable row level security;

-- ERD §2: authenticated 전체 읽기 — "다음 지급은 O요일 오전 7시" 문구(DESIGN §8.1 Badge Row)를 그리려면
-- 앱이 요일·시각을 알아야 한다. 개인정보가 아니라 지역 단위 설정값이라 소유자 조건이 없다.
create policy "region group settings are readable by signed in users"
  on public.region_group_settings
  for select
  to authenticated
  using (true);

revoke all on table public.region_group_settings from anon, authenticated, service_role;
grant select on table public.region_group_settings to authenticated;
grant select, insert, update, delete on table public.region_group_settings to service_role;

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
  group by u.region_group, p.gender;
$$;

comment on function public.region_active_counts() is
  '지역그룹×성별 활성 인원(14일). 지급 주기 사다리 판정용(설계 §2.1)';

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
    );
$$;

comment on function public.card_issue_owners() is
  '오늘 무료 카드를 받을 자격이 있는 사람과 그 지역그룹(설계 §2.1·§2.6)';

revoke all on function public.region_active_counts() from public, anon, authenticated;
grant execute on function public.region_active_counts() to service_role;
revoke all on function public.card_issue_owners() from public, anon, authenticated;
grant execute on function public.card_issue_owners() to service_role;
