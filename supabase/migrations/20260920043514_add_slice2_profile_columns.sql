-- 조각 2: 프로필·온보딩 컬럼. ERD.md §3 조각2 태그 컬럼을 전부 담는다.
-- 기준 문서: docs/ERD.md §3·§8, docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md §5·§6

create type public.religion as enum ('none', 'protestant', 'catholic', 'buddhist');

-- 8종 확정(DESIGN.md §5.4 animal-face-*-2d-v1.png 에셋 파일명, 2026-09-20 계획서로 확정).
create type public.animal_type as enum (
  'dog', 'cat', 'fox', 'bear', 'rabbit', 'deer', 'wolf', 'hamster'
);

create type public.impression_type as enum ('arab', 'tofu', 'kind', 'chic', 'innocent');

create type public.acquisition_channel as enum (
  'everytime', 'instagram', 'friend', 'community', 'other'
);

alter table public.profiles
  add column nickname_changed_at timestamptz,
  add column is_smoker boolean,
  add column religion public.religion,
  add column animal_type public.animal_type,
  add column impression_type public.impression_type,
  add column preferred_animal_types public.animal_type[] not null default '{}',
  add column preferred_impression_types public.impression_type[] not null default '{}',
  add column my_traits text[] not null default '{}',
  add column ideal_traits text[] not null default '{}',
  add column preferred_age_min smallint,
  add column preferred_age_max smallint,
  add column acquisition_channel public.acquisition_channel,
  add column acquisition_note text,
  -- 제안(2026-09-20): 2026-09-19 매칭 공식 확정 때 부활한 "이런 사람이 좋아요" 자유 글(spec §6.1 신규).
  -- ERD.md 는 2026-09-13~14 초안이라 이 컬럼이 아직 없다 — erd 세션에 ERD 갱신 요청 필요.
  add column ideal_note text,
  -- 제안(2026-09-20): 06-2b AI 초안은 "최초 1회만" 생성한다(설계 §13-71). 이 시각이 있으면 재호출을 막는다.
  add column bio_draft_generated_at timestamptz;

comment on column public.profiles.ideal_note is '"이런 사람이 좋아요" 자유 글, 선택 입력(2026-09-19 매칭 공식 부활분)';
comment on column public.profiles.bio_draft_generated_at is 'AI 자기소개 초안 생성 시각, 1회 제한용(설계 §13-71)';

alter table public.profiles
  add constraint profiles_preferred_animal_types_max check (cardinality(preferred_animal_types) <= 3),
  add constraint profiles_preferred_impression_types_max check (cardinality(preferred_impression_types) <= 3),
  -- 46개 풀 3~5개, 하한은 FastAPI 온보딩 완료 검사가 본다(조각0 interest_tags 관례와 동일).
  add constraint profiles_my_traits_max check (cardinality(my_traits) <= 5),
  add constraint profiles_ideal_traits_max check (cardinality(ideal_traits) <= 5),
  add constraint profiles_preferred_age_range check (
    preferred_age_min between 19 and 100 and preferred_age_max between 19 and 100
  ),
  add constraint profiles_preferred_age_order check (
    preferred_age_min is null or preferred_age_max is null or preferred_age_min <= preferred_age_max
  );

-- "찾는 성별" 폐지 뒤처리(ERD §12-36, 2026-09-14 사용자 결정 — 반대 성별 자동 매칭).
alter table public.profiles drop constraint profiles_active_requires_onboarding;
alter table public.profiles drop column looking_for;
alter table public.profiles add constraint profiles_active_requires_onboarding check (
  status <> 'active'
  or (
    nickname is not null
    and gender is not null
    and birth_year is not null
    and height_cm is not null
  )
);
