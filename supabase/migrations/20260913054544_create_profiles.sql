-- 조각 0 스키마 2/4: 프로필. 조각 0 컬럼만 담고 나머지는 그 조각에서 추가한다(설계 §5.4).
-- 기준 문서: docs/ERD.md §2 · §3 · §10
-- 계획서 Task 7 초안과 다른 점: hide_same_major 없음, admission_year 추가,
-- 온보딩 컬럼은 null 허용 + active 전환 check, 클라이언트 쓰기 정책 없음.

create type public.gender as enum ('male', 'female');

-- pending 은 이메일 인증 직후 FastAPI 가 만든, 온보딩을 끝내지 않은 상태다.
create type public.profile_status as enum ('pending', 'active', 'suspended');

-- 학과 계열. 표시만 하고 매칭 점수에는 넣지 않는다.
create type public.major_field as enum (
  'humanities', 'social', 'business', 'engineering',
  'natural_science', 'medical', 'arts_sports', 'education'
);

create table public.profiles (
  -- auth.users 의 id 를 그대로 쓴다. 계정을 지우면 cascade 로 함께 지워진다.
  id uuid primary key references auth.users (id) on delete cascade,
  -- 메일 도메인으로 서버가 정한다. 행을 만들 때 이미 정해져 있어 not null 이다.
  -- 프로필이 남아 있는 대학은 지울 수 없다.
  university_id uuid not null references public.universities (id) on delete restrict,

  -- 여기부터는 온보딩(DESIGN 04-1 이후)에서 받는 값이다. FastAPI 가 행을 만들 때는 비어 있으므로
  -- null 을 허용하고, 필수값은 아래 profiles_active_requires_onboarding 이 active 전환 때 막는다.
  -- 닉네임은 전체 서비스에서 유니크하다(대소문자 무시, 아래 인덱스).
  nickname text,
  gender public.gender,
  looking_for public.gender,
  -- 연 나이 19세 이상인지는 Asia/Seoul 기준 "올해"로 FastAPI 가 검사한다. DB 는 now() 없는 범위만 본다.
  birth_year smallint,
  -- 필수 입력이며 프로필에 공개된다.
  height_cm smallint,
  -- 선호 키 범위는 선택. null 이면 상관없음.
  preferred_height_min smallint,
  preferred_height_max smallint,
  bio text,
  -- null 이면 모름.
  mbti text,
  -- 8개 극의 켜짐/꺼짐. 한 축에서 켜진 극이 1개면 그 극을 선호하고, 0개나 2개면 상관없음이다.
  preferred_mbti_flags jsonb not null default '{}'::jsonb,
  major text,
  major_field public.major_field,
  -- 입학년도. 앱에서 받은 "21" 을 2021 로 바꿔 저장한다.
  admission_year smallint,
  interest_tags text[] not null default '{}',

  status public.profile_status not null default 'pending',
  -- 활동성 계수에 쓴다.
  last_active_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  constraint profiles_active_requires_onboarding check (
    status <> 'active'
    or (
      nickname is not null
      and gender is not null
      and looking_for is not null
      and birth_year is not null
      and height_cm is not null
    )
  ),
  -- 한글 완성형(가-힣)과 영문만, 2~5자.
  constraint profiles_nickname_format check (nickname ~ '^[가-힣a-zA-Z]{2,5}$'),
  constraint profiles_birth_year_range check (birth_year between 1950 and 2020),
  constraint profiles_height_range check (height_cm between 120 and 230),
  constraint profiles_preferred_height_order check (
    preferred_height_min is null
    or preferred_height_max is null
    or preferred_height_min <= preferred_height_max
  ),
  constraint profiles_preferred_height_range check (
    preferred_height_min between 120 and 230
    and preferred_height_max between 120 and 230
  ),
  constraint profiles_mbti_format check (mbti ~ '^[EI][NS][TF][JP]$'),
  -- 키는 E I N S T F J P, 값은 boolean(true 가 ok, 설계 §6.4). 키 모양은 FastAPI 가 검사한다.
  constraint profiles_preferred_mbti_flags_object check (jsonb_typeof(preferred_mbti_flags) = 'object'),
  -- 45개 풀에서 3~5개. 하한은 FastAPI 온보딩 완료 검사가 본다.
  constraint profiles_interest_tags_max check (cardinality(interest_tags) <= 5),
  -- 두 자리 입력을 네 자리로 바꾸지 않고 저장하는 실수를 막는다.
  constraint profiles_admission_year_range check (admission_year between 1950 and 2100)
);

comment on table public.profiles is '사용자 프로필. 클라이언트는 본인 행만 읽고, 남의 프로필은 FastAPI 가 필요한 컬럼만 준다';

create index profiles_university_id_index
  on public.profiles (university_id);

create unique index profiles_nickname_unique
  on public.profiles (lower(nickname));

-- RLS: 본인 행 읽기만. 행 생성과 수정은 FastAPI 가 한다(ERD §2 · §11-8).
-- 클라이언트가 자기 status · university_id 를 직접 바꾸는 우회가 여기서 막힌다.
alter table public.profiles enable row level security;

create policy "profiles are readable by owner"
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = id);

-- 권한(ERD §2): anon 은 없음, authenticated 는 select, service_role 은 select·insert·update·delete.
revoke all on table public.profiles from anon, authenticated, service_role;
grant select on table public.profiles to authenticated;
grant select, insert, update, delete on table public.profiles to service_role;
