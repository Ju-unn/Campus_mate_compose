# 조각 2: 프로필 · 온보딩 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **실행 순서는 Part C(Supabase) → Part B(FastAPI) → Part A(Flutter) 다.** 프론트를 먼저 만들었던 조각 1b(Part
> A/B/C = 프론트/백엔드/DB)와 문자 배정 관례는 맞추되, 이번엔 스키마가 이미 ERD 에 대부분 확정돼 있고 화면이
> DB 컬럼을 직접 채우는 구조라 스키마 → 백엔드 → 프론트 순으로 진행한다. **Part C 는 파일 작성까지만 하고
> 클라우드 적용은 하지 않는다**(`[[supabase-apply-gate]]` — ERD 그림·사용자 검토·승인 후 별도 supabase 세션이 진행).

**Goal:** 학생증 인증을 마친 사용자가 닉네임부터 자기소개까지 프로필을 채우는 전체 온보딩(04-1~06-3, 11개+ 화면)과
그 아래 스키마·백엔드를 만들어, 온보딩을 끝내면 `profiles.status = 'active'` 로 전환되게 한다.

**Architecture:** 화면마다 하나의 PostgREST 리소스(또는 몇 개)를 FastAPI 라우터가 검증 후 `service_role` 로
갱신하는 기존 패턴(조각 1b `student_verification` 패키지)을 그대로 따른다. 새 백엔드 패키지
`backend/app/profile_onboarding/`를 만들고, 태그·아바타·하트 원장처럼 여러 화면이 공유하는 로직은 그 안에서
모듈로 분리한다. 프론트는 화면마다 `Notifier` 기반 ViewModel + 불변 `UiState` + `Repository` 인터페이스 +
Riverpod Provider 패턴(조각 1b `SchoolInfoViewModel` 참고)을 반복한다. 온보딩 순서는 서버가 계산해
`GET /profile-onboarding/next-step` 하나로 알려주고, `AuthRedirect`/게이트 리스너가 그 값으로 다음 화면을 정한다.

**Tech Stack:** FastAPI + httpx(PostgREST 직접 호출, SDK 없음) + `openai` Python SDK(신규, `max_retries=0`) +
`google-cloud-vision`(기존, SafeSearch 재사용) + Postgres `pgcrypto`(신규 확장, 전화번호 암호화) + Flutter +
Riverpod + go_router. **새 Flutter 패키지는 없다** — 슬라이더·다중선택 칩·범위 슬라이더 전부 Material 기본
위젯(`Slider`·`RangeSlider`·`ChoiceChip`/`FilterChip`+`Wrap`)으로 만든다.

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §5·§6·§7.6b·§8·표(2행), `docs/ERD.md`
§3·§8·§9·§12(검토 36), `frontend/docs/DESIGN.md` §5.4·§8.5·§9(화면 04-1~06-3)

## 새 의존성 (사용자 승인 완료분 + 이번에 확정한 것)

| 구분 | 패키지 | 용도 | 승인 근거 |
| --- | --- | --- | --- |
| 백엔드 | `openai` (Python SDK) | 아바타 생성(`gpt-image-1`) · 자기소개 AI 초안(챗 모델) | 2026-09-20 사용자 승인(대장 경유) — 호출 표면 확장 대비 SDK 유지보수 이득. **`max_retries=0` 필수**, 5회 실패 카운트는 앱 코드가 직접 셈 |
| 백엔드 | 없음 (`pgcrypto`는 Postgres 확장이지 Python 패키지가 아님) | 전화번호 컬럼 암호화 | 2026-09-20 사용자 승인 — `cryptography` 신규 의존성 대신 DB 내장 확장 사용, 새 Python 패키지 없음 |
| 백엔드 | 없음 — 기존 `google-cloud-vision` 재사용 | 사진 SafeSearch 검수 | 이미 조각 1b에서 승인됨(OCR 용도), 같은 클라이언트의 `safe_search_detection` 호출만 추가 |
| 프론트 | 없음 | 슬라이더·다중선택·범위 슬라이더 | Material 기본 위젯으로 충분(YAGNI) |

이 표 외 새 의존성이 실행 중 발견되면 코드 작성 전에 대장에게 다시 보고한다.

## Global Constraints

- **쓰기는 전부 FastAPI 가 `service_role` 로 한다.** 클라이언트(`authenticated`)에는 INSERT·UPDATE·DELETE
  정책·권한을 하나도 두지 않는다(`docs/SUPABASE.md` §5, `docs/ERD.md` §2).
- **새 테이블은 전부 RLS 를 켜고, grant 는 RLS 와 같은 마이그레이션에 둔다.** `revoke all ... from anon,
  authenticated, service_role` 뒤에 필요한 것만 준다(`docs/SUPABASE.md` §5).
- **클라이언트 Storage 정책은 두지 않는다.** 업로드는 FastAPI 가 멀티파트로 받아 `service_role` 로 대신
  올린다(조각 1b `StudentIdStorage` 패턴 재사용 — 서명 URL 발급 대신 프록시 업로드).
  `student-id-temp`·`profile-photos` 두 버킷과 같은 방식이다.
- **`security definer` 함수는 쓰지 않는다**(`docs/SUPABASE.md` §5).
- **마이그레이션 파일명은 `supabase migration new <name>` 으로만 만든다.** 직접 타임스탬프를 짓지 않는다
  (`docs/SUPABASE.md` §4).
- **클라우드 적용 금지.** Part C 는 파일 작성까지만 한다. `[[supabase-apply-gate]]` 통과 전까지 실제 프로젝트에
  손대지 않는다.
- **커밋·PR 에 AI/도구 표식을 넣지 않는다**(`[[feedback-no-tool-attribution]]`).
- **온보딩 하한값(태그 최소 3개, 사진 최소 2장 등)은 DB check 가 아니라 FastAPI 온보딩 완료 검사가 본다** — 조각
  0/1 에서 이미 확립된 관례(`profiles.interest_tags` 주석 참고). DB check 는 상한만 건다.
- **태그 문구(관심사 45·나의 특징 46·이상형 특징 44)는 erd 세션이 pen 04-5/04-6/06-2 에서 추출해 확정했다**
  (2026-09-20, 개수 45/46/44 일치 확인·수정 없음). Task B3/A2 의 상수 리스트는 이 라벨을 그대로 옮긴 것이며,
  이상형 특징의 "리더쉽 있는"은 2026-09-19 결정대로 "리더십 있는"으로 오타를 고쳐 옮긴다.
- **frontend `RealName` 값 객체(`frontend/lib/auth/model/real_name.dart`)에 최소 2자 검사를 추가한다**(백엔드
  `student_verification/schemas.py`·`router.py` 의 `Form(min_length=2, max_length=30)` 과 동일 규칙, 2026-09-20
  분석담당 리뷰 제안1 을 프론트에도 반영 — spec §13 백로그 41-⑤). Task A1 에 포함한다.
- **동물상 8종은 이미 확정.** `dog, cat, fox, bear, rabbit, deer, wolf, hamster` (`designMaterials/animal-face-*-2d-v1.png` 8개 에셋 파일명 그대로, DESIGN.md §5.4). ERD §8 "후보" 표기는 이 계획서로 확정한다.
- **아바타 버킷은 공개(public)로 만든다.** 경로는 순번이 아니라 `profile_id`(UUID) + 랜덤 파일명으로 열거를
  막는다. 쓰기(업로드·교체·삭제)는 `service_role` 전용, 클라이언트 직접 쓰기 금지(2026-09-20 사용자 승인).
- **전화번호는 Postgres `pgcrypto`(`pgp_sym_encrypt`/`pgp_sym_decrypt`)로 암호화한다.** 새 Python 의존성을
  추가하지 않는다. 키는 FastAPI 가 매 쿼리 파라미터로 넘기고, DB 로그에 남지 않는지 확인하는 절차를 Part C
  Task C2 에 명시한다. 복호화는 관리자 조회 전용 함수로만 하고 일반 API 응답에는 절대 내려주지 않는다
  (2026-09-20 사용자 승인).

---

## Part C: Supabase 마이그레이션 (파일 작성만, 적용 금지)

### Task C1: `profiles` 온보딩 컬럼 추가 + `looking_for` 폐지

**Files:**
- Create: `supabase/migrations/<timestamp>_add_slice2_profile_columns.sql` (파일명은 `supabase migration new add_slice2_profile_columns`로 생성)
- Modify: `supabase/tests/rls_slice0_test.sql:42`

**Interfaces:**
- Consumes: 없음(스키마 최초 작성)
- Produces: `profiles.nickname_changed_at` · `is_smoker` · `religion` · `animal_type` · `impression_type` ·
  `preferred_animal_types` · `preferred_impression_types` · `my_traits` · `ideal_traits` · `preferred_age_min/max` ·
  `acquisition_channel` · `acquisition_note` · `ideal_note` (신규 제안 컬럼) — Task B 전체와 Part A 전체가 이
  컬럼명을 그대로 쓴다.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `supabase migration new add_slice2_profile_columns` (저장소 루트에서)

- [ ] **Step 2: 파일 작성**

```sql
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
```

- [ ] **Step 3: `rls_slice0_test.sql` 의 `looking_for` 대입 제거**

`supabase/tests/rls_slice0_test.sql:42` 에서 `looking_for = 'female',` 를 지운다:

```sql
select lives_ok(
  $$update public.profiles
       set nickname = '가나', gender = 'male',
           birth_year = 2002, height_cm = 178, status = 'active'
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  '필수값을 채우면 active 로 바꿀 수 있다'
);
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations supabase/tests/rls_slice0_test.sql
git commit -m "🗃️ db(slice2): profiles 온보딩 컬럼 추가, looking_for 폐지"
```

### Task C2: `profile_private` 전화번호·카카오톡 아이디 + pgcrypto

**Files:**
- Create: `supabase/migrations/<timestamp>_add_slice2_profile_private_columns.sql`

**Interfaces:**
- Consumes: `public.profile_private`(조각1, `real_name` 컬럼 보유)
- Produces: `profile_private.phone_number`(`bytea`, pgcrypto 암호문) · `profile_private.kakao_id`(`text`) · 복호화
  전용 함수 `public.decrypt_phone_number(profile_id, key)` — Part B 의 `encryption.py` 가 이 함수명을 그대로
  부른다.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `supabase migration new add_slice2_profile_private_columns`

- [ ] **Step 2: 파일 작성**

```sql
-- 조각 2: 본인 전화번호(04-1, 필수) · 카카오톡 아이디(04-1b, 필수). 둘 다 profile_private 로 분리한다
-- (민감 값, ERD §3). 전화번호는 원본을 그대로 저장하되 컬럼 암호화(at-rest, 설계 §7.6b)한다.
-- 기준 문서: docs/ERD.md §3, 설계 §7.6b

create extension if not exists pgcrypto with schema extensions;

alter table public.profile_private
  add column phone_number bytea,
  add column kakao_id text;

comment on column public.profile_private.phone_number is
  'extensions.pgp_sym_encrypt(평문, 키) 암호문. 키는 FastAPI Secret Manager 전용, DB 에 저장하지 않는다';

-- 관리자 조회 전용 복호화 함수. security definer 를 안 쓴다(SUPABASE.md §5) — 호출자가 service_role 이므로
-- 이미 profile_private select 권한이 있고, 별도 권한 우회가 필요 없다. 일반 API 응답 경로에서는 절대 호출하지
-- 않는다(계획서 Part B Task B-encryption 참고) — 이 함수를 부르는 코드는 관리자 조회 엔드포인트 하나뿐이어야
-- 한다.
create or replace function public.decrypt_phone_number(p_profile_id uuid, p_key text)
returns text
language sql
stable
as $$
  select extensions.pgp_sym_decrypt(phone_number, p_key)
  from public.profile_private
  where profile_id = p_profile_id;
$$;

revoke all on function public.decrypt_phone_number(uuid, text) from public, anon, authenticated;
grant execute on function public.decrypt_phone_number(uuid, text) to service_role;
```

- [ ] **Step 3: DB 로그에 키가 남지 않는지 확인하는 절차를 이 파일 주석과 `docs/SUPABASE.md`에 남긴다**

마이그레이션 파일 맨 끝에 아래 확인 절차 주석을 추가한다(실제 확인은 클라우드 적용 뒤 supabase 세션이 수행):

```sql
-- 적용 뒤 확인할 것(supabase 세션 몫, 이 파일 자체는 실행하지 않는다):
-- 1. Supabase 대시보드 Database > Query Performance(pg_stat_statements) 에서 이 함수·
--    pgp_sym_encrypt 호출이 찍힌 행을 열어 key 인자가 `$1`(파라미터 자리표시자)로만 보이는지 확인한다
--    (pg_stat_statements 는 기본적으로 리터럴 값을 정규화해 지우지만, PostgREST 가 파라미터 바인딩 없이
--    문자열을 그대로 SQL 에 이어붙이면 키가 그대로 남을 수 있어 확인이 필요하다).
-- 2. FastAPI 쪽은 키를 PostgREST RPC 호출의 JSON 바디 인자로만 넘기고, URL 쿼리스트링에는 절대 넣지 않는다
--    (URL 은 웹서버 접근 로그에 그대로 남는다) — Part B Task B-encryption 코드 리뷰에서 확인.
-- 3. Supabase 대시보드에서 손으로 복호화가 필요하면(신고·수사 협조): SQL Editor 에서
--    `select public.decrypt_phone_number('<profile_id>', '<Secret Manager 에서 복사한 키>');` 를 실행한다.
--    키를 대시보드 SQL 창에 붙여넣는 행위 자체가 감사 대상이므로, 실행 전후로 사유를 운영 기록에 남긴다.
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations
git commit -m "🗃️ db(slice2): profile_private 전화번호(pgcrypto)·카카오톡 아이디 컬럼"
```

### Task C3: 사진 · 아바타 스키마

**Files:**
- Create: `supabase/migrations/<timestamp>_add_avatar_schema.sql`

**Interfaces:**
- Consumes: `public.profile_photos`(조각0)
- Produces: `profile_photos.is_avatar_source` · `public.profile_avatars` 테이블 · `avatars` 버킷(공개) — Part B
  `avatars.py`, Part A 아바타 화면이 이 이름을 그대로 쓴다.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `supabase migration new add_avatar_schema`

- [ ] **Step 2: 파일 작성**

```sql
-- 조각 2: 아바타 원본 지정 + 생성 이력 + 공개 버킷. 기준 문서: docs/ERD.md §3·§9, ERD §12 검토2(공개로 결정).
create type public.avatar_status as enum ('pending', 'ready', 'failed');

alter table public.profile_photos
  add column is_avatar_source boolean not null default false;

-- 프로필당 1장만 원본으로 고를 수 있다.
create unique index profile_photos_one_avatar_source
  on public.profile_photos (profile_id)
  where is_avatar_source;

create table public.profile_avatars (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  -- 원본 사진이 지워져도(순서 변경 중 교체 등) 이력은 남긴다.
  source_photo_id uuid references public.profile_photos (id) on delete set null,
  storage_path text not null,
  status public.avatar_status not null default 'pending',
  created_at timestamptz not null default now()
);

comment on table public.profile_avatars is
  '아바타 생성 이력. 최신 status=ready 행이 현재 아바타다(ERD 읽는 법). 무료 재생성 횟수는 이 테이블의
   ready 행 개수로 FastAPI 가 센다(최초 1회 무료, 설계 §2.4)';

create index profile_avatars_profile_id_index on public.profile_avatars (profile_id);

alter table public.profile_avatars enable row level security;

create policy "profile avatars are readable by owner"
  on public.profile_avatars
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.profile_avatars from anon, authenticated, service_role;
grant select on table public.profile_avatars to authenticated;
grant select, insert, update, delete on table public.profile_avatars to service_role;

-- 공개 버킷(2026-09-20 사용자 결정) — 아바타는 실사진과 달리 항상 노출되는 그림이라 서명 URL이 필요 없다.
-- 경로는 {profile_id}/{uuid4()}.png 로 짓는다(Part B avatars.py) — profile_id 가 노출돼도 순번이 아니라 UUID라
-- 나열 공격이 안 되고, 파일명도 uuid4라 두 번째로 한 번 더 막는다. 업로드·교체·삭제는 FastAPI(service_role)
-- 전용이고 client Storage 정책은 두지 않는다(SUPABASE.md §5).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations
git commit -m "🗃️ db(slice2): 아바타 원본 지정·생성 이력·공개 버킷"
```

### Task C4: 성향 설문(`survey_answers`)

**Files:**
- Create: `supabase/migrations/<timestamp>_create_survey_answers.sql`

**Interfaces:**
- Consumes: `public.profiles`
- Produces: `public.survey_answers` — Part B `router.py` 의 설문 저장 엔드포인트, Part A 05-01~05-11 화면이 씀.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `supabase migration new create_survey_answers`

- [ ] **Step 2: 파일 작성**

```sql
-- 조각 2: 성향 설문 9축 원본값. 벡터화(profile_vectors)는 조각 3.
-- 기준 문서: docs/ERD.md §3, 설계 §6.2(5점 슬라이더 -1 -0.5 0 0.5 1, 나 1회만)
create table public.survey_answers (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  axis smallint not null,
  value numeric not null,
  answered_at timestamptz not null default now(),
  primary key (profile_id, axis),

  constraint survey_answers_axis_range check (axis between 1 and 9),
  constraint survey_answers_value_scale check (value in (-1, -0.5, 0, 0.5, 1))
);

comment on table public.survey_answers is '성향 설문 9축 원본. axis=2 가 낯가림(shyness), 조각3 profile_vectors 가중치 계산의 재료';

alter table public.survey_answers enable row level security;

create policy "survey answers are readable by owner"
  on public.survey_answers
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.survey_answers from anon, authenticated, service_role;
grant select on table public.survey_answers to authenticated;
grant select, insert, update, delete on table public.survey_answers to service_role;
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations
git commit -m "🗃️ db(slice2): survey_answers 테이블"
```

### Task C5: 하트 원장 앞당김(`entitlements` · `heart_transactions`)

**Files:**
- Create: `supabase/migrations/<timestamp>_create_heart_ledger.sql`

**Interfaces:**
- Consumes: `public.profiles`
- Produces: `public.entitlements` · `public.heart_transactions` — Part B `hearts.py` 의 하트 지급 함수가 이
  테이블에 쓴다. 조각 7(하트 스토어)이 그대로 이어받는다.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `supabase migration new create_heart_ledger`

- [ ] **Step 2: 파일 작성**

```sql
-- 조각 7 예정이던 하트 원장을 조각 2로 앞당긴다 — 아바타 생성 5회 연속 실패 보상(10하트)이 조각 2에 필요하기
-- 때문(2026-09-20 사용자 승인). 구매·환불 등 나머지 heart_reason 값은 조각 7이 실제로 쓴다.
-- 기준 문서: docs/ERD.md §6·§8
create type public.heart_reason as enum (
  'purchase', 'referral', 'promo', 'free_task', 'poll_vote',
  'extra_card', 'avatar_regen', 'refund', 'admin_adjust'
);

create table public.entitlements (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  heart_balance integer not null default 0,
  updated_at timestamptz not null default now(),

  constraint entitlements_balance_non_negative check (heart_balance >= 0)
);

comment on table public.entitlements is '하트 잔액 캐시. heart_transactions 합계와 항상 같아야 한다(FastAPI 가 한 트랜잭션에서 둘 다 쓴다)';

create table public.heart_transactions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  amount integer not null,
  reason public.heart_reason not null,
  ref_id uuid,
  created_at timestamptz not null default now(),

  constraint heart_transactions_amount_not_zero check (amount <> 0)
);

comment on table public.heart_transactions is
  '하트 원장. 적립은 양수·사용은 음수(ERD §6). 아바타 생성 5회 연속 실패 보상은 amount=10,
   reason=admin_adjust 로 남긴다(avatar_regen 은 아바타 재생성으로 하트를 "쓸 때" 쓰고, 이 보상은 운영
   보정이라 admin_adjust 가 더 정확하다 — 2026-09-20 계획서 결정)';

create index heart_transactions_profile_id_index on public.heart_transactions (profile_id);

alter table public.entitlements enable row level security;
alter table public.heart_transactions enable row level security;

create policy "entitlements are readable by owner"
  on public.entitlements for select to authenticated
  using ((select auth.uid()) = profile_id);

create policy "heart transactions are readable by owner"
  on public.heart_transactions for select to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.entitlements from anon, authenticated, service_role;
grant select on table public.entitlements to authenticated;
grant select, insert, update, delete on table public.entitlements to service_role;

revoke all on table public.heart_transactions from anon, authenticated, service_role;
grant select on table public.heart_transactions to authenticated;
grant select, insert, update, delete on table public.heart_transactions to service_role;
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations
git commit -m "🗃️ db(slice2): 하트 원장(entitlements·heart_transactions) 조각7에서 앞당김"
```

### Task C6: pgTAP `rls_slice2_test.sql` 작성

**Files:**
- Create: `supabase/tests/rls_slice2_test.sql`

**Interfaces:**
- Consumes: Task C1~C5 의 전체 스키마
- Produces: 없음(테스트 파일). `docs/ERD.md` §2 "사이클 B pgTAP 기대값의 기준"을 이번 조각 신규 테이블에도
  적용한다.

- [ ] **Step 1: `rls_slice1_test.sql` 을 본떠 새 파일 작성**

`supabase/tests/rls_slice1_test.sql` 과 같은 구조(`begin`/`rollback`, `set local role`)로 새 파일을 만든다.
최소 검증 항목(각각 `select ... ('...')` 한 줄씩, 정확한 개수는 작성 시 `select plan(N)` 에 맞춰 센다):

1. `profiles` 신규 컬럼 상한 check 4종(`preferred_animal_types`·`preferred_impression_types`·`my_traits`·
   `ideal_traits` 각 초과 시 `23514`)
2. `looking_for` 컬럼이 더 이상 존재하지 않는다(`throws_ok`로 `select looking_for from public.profiles` 시도 →
   `42703`)
3. `profile_avatars`: RLS 켜짐, 본인 행만 `select`, `anon`/`authenticated` insert·update·delete 는 `42501`
4. `profile_photos_one_avatar_source` 부분 유니크: 같은 프로필에 `is_avatar_source=true` 2행 insert 시도 →
   `23505`
5. `survey_answers`: `value` 5점 이외 값 insert 시 `23514`, 본인 행만 read
6. `entitlements`/`heart_transactions`: RLS 켜짐, 본인 행만 read, `service_role` 은 전부 가능
7. `avatars`·`profile-photos` 버킷 `public` 컬럼 값 각각 `true`/`false`(공개·비공개 확인)
8. 탈퇴 cascade: `auth.users` 삭제 시 `profile_avatars`·`survey_answers`·`entitlements`·`heart_transactions` 행도
   함께 지워진다

- [ ] **Step 2: `select plan(N)` 을 실제 assertion 개수로 맞춘다**

`grep -c "^select .*(" supabase/tests/rls_slice2_test.sql` 로 assertion 함수 호출 수를 센 뒤 `plan()` 값과
비교한다.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/rls_slice2_test.sql
git commit -m "✅ test(slice2): rls_slice2_test.sql pgTAP 작성"
```

---

## Part B: FastAPI 백엔드

새 패키지 `backend/app/profile_onboarding/`. 조각 1b `student_verification` 패키지와 같은 내부 구조
(`router.py`·`schemas.py`·`repository.py`)를 따르고, `current_user.py` 는 새로 만들지 않고
`app.student_verification.current_user.get_current_user_id` 를 그대로 재사용한다(같은 인증 방식, 중복 코드
아님).

### Task B1: 설정 값 추가

**Files:**
- Modify: `backend/pyproject.toml`
- Modify: `backend/app/settings.py`

**Interfaces:**
- Produces: `Settings.openai_api_key` · `Settings.phone_encryption_key` — 이후 모든 Task B가 씀.

- [ ] **Step 1: `pyproject.toml` 에 `openai` 추가**

```toml
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.32",
    "httpx>=0.27",
    "pydantic-settings>=2.6",
    "google-cloud-vision>=3.9",
    "python-multipart>=0.0.9",
    # 조각 2: 아바타 생성(gpt-image-1)·자기소개 AI 초안. max_retries=0 으로 호출한다(2026-09-20 사용자 결정).
    "openai>=1.50",
]
```

- [ ] **Step 2: `settings.py` 에 필드 추가**

```python
class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str
    auth_hook_signing_secret: str
    discord_webhook_url: str
    google_cloud_project: str
    # 조각 2: Secret Manager 키 이름 `openai-api-key`(2026-09-19 준비 가이드 메모)
    openai_api_key: str
    # 조각 2: Secret Manager 키 이름 `phone-number-encryption-key` — pgcrypto pgp_sym_encrypt/decrypt 에 넘긴다.
    phone_encryption_key: str
```

- [ ] **Step 3: Commit**

```bash
git add backend/pyproject.toml backend/app/settings.py
git commit -m "⚙️ chore(slice2): openai SDK·전화번호 암호화 키 설정 추가"
```

### Task B2: 전화번호 암호화 헬퍼

**Files:**
- Create: `backend/app/profile_onboarding/encryption.py`
- Test: `backend/tests/profile_onboarding/test_encryption.py`

**Interfaces:**
- Consumes: `Settings.phone_encryption_key`
- Produces: `encrypt_phone_number_payload(phone: str, key: str) -> dict` — Task B3 의 repository 가 PostgREST RPC
  바디에 그대로 넣는다.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from app.profile_onboarding.encryption import encrypt_phone_number_payload


def test_encrypt_phone_number_payload_uses_pgcrypto_sql_function():
    payload = encrypt_phone_number_payload("01012345678", "test-key")
    assert payload == {
        "phone_number": "pgp_sym_encrypt.01012345678.test-key",
    }
```

(주: 실제 값은 Postgres 안에서 계산되므로, 이 테스트는 "PostgREST 에 넘길 payload 모양"만 검증한다 —
실제 암호문 비교는 pgTAP(Task C6) 몫이다. 아래 Step3 구현에서 이 자리표시자 문자열을 실제 PostgREST 컬럼
표현식으로 바꾼다.)

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_encryption.py -v`
Expected: FAIL with "No module named 'app.profile_onboarding'"

- [ ] **Step 3: 구현**

PostgREST 는 컬럼 값에 SQL 표현식을 직접 못 넣는다 — insert/update 바디는 JSON 값이어야 한다. 그래서 암호화는
PostgREST REST 가 아니라 **RPC 함수**로 한다. Task C2 의 `decrypt_phone_number` 와 짝을 이루는
`encrypt_phone_number` RPC 함수를 Task C2 마이그레이션에 추가해야 한다 — 이 Step 은 Task C2 를 다음처럼
보강한다(구현 시점에 Task C2 파일에 아래 함수를 이어붙인다, 이 계획서에 사후 추가):

```sql
-- Task C2 파일 끝에 추가
create or replace function public.set_phone_number(p_profile_id uuid, p_phone text, p_key text)
returns void
language sql
as $$
  update public.profile_private
  set phone_number = extensions.pgp_sym_encrypt(p_phone, p_key), updated_at = now()
  where profile_id = p_profile_id;
$$;

revoke all on function public.set_phone_number(uuid, text, text) from public, anon, authenticated;
grant execute on function public.set_phone_number(uuid, text, text) to service_role;
```

`encryption.py` 는 이 RPC 를 호출하는 얇은 wrapper만 둔다(암호화 로직 자체는 DB 안에 있다):

```python
import httpx
from uuid import UUID


async def set_encrypted_phone_number(
    postgrest_url: str, service_role_key: str, client: httpx.AsyncClient,
    profile_id: UUID, phone_number: str, encryption_key: str,
) -> None:
    response = await client.post(
        f"{postgrest_url}/rpc/set_phone_number",
        json={"p_profile_id": str(profile_id), "p_phone": phone_number, "p_key": encryption_key},
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        },
    )
    response.raise_for_status()
```

**주의(구현자에게):** 위 Step 1의 자리표시자 테스트는 삭제하고, 이 wrapper 함수를 `httpx` 목으로 호출해
"RPC 엔드포인트 URL·JSON 바디에 평문 키가 들어간다"만 검증하는 테스트로 바꿔 쓴다(암호화 자체의 정확성은
pgTAP 이 검증하므로 여기서 재검증하지 않는다 — DRY).

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_encryption.py -v`

- [ ] **Step 5: Commit**

```bash
git add backend/app/profile_onboarding/encryption.py backend/tests/profile_onboarding/test_encryption.py supabase/migrations
git commit -m "🔒 feat(slice2): 전화번호 pgcrypto RPC 래퍼"
```

### Task B3: 태그 풀 · 검증

**Files:**
- Create: `backend/app/profile_onboarding/tags.py`
- Test: `backend/tests/profile_onboarding/test_tags.py`

**Interfaces:**
- Produces: `INTEREST_TAGS`(45개) · `MY_TRAITS`(46개) · `IDEAL_TRAITS`(44개) 상수 리스트, `validate_tag_selection(pool, selected, minimum=3, maximum=5) -> None`(범위 밖·풀에 없는 값이면 `ValueError`) — Task B4가 씀.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import pytest
from app.profile_onboarding.tags import INTEREST_TAGS, validate_tag_selection


def test_validate_tag_selection_rejects_unknown_tag():
    with pytest.raises(ValueError, match="목록에 없는 태그"):
        validate_tag_selection(INTEREST_TAGS, ["없는태그"])


def test_validate_tag_selection_rejects_too_few():
    with pytest.raises(ValueError, match="최소 3개"):
        validate_tag_selection(INTEREST_TAGS, INTEREST_TAGS[:2])


def test_validate_tag_selection_rejects_too_many():
    with pytest.raises(ValueError, match="최대 5개"):
        validate_tag_selection(INTEREST_TAGS, INTEREST_TAGS[:6])


def test_validate_tag_selection_accepts_valid_range():
    validate_tag_selection(INTEREST_TAGS, INTEREST_TAGS[:3])


def test_interest_tags_pool_size():
    assert len(INTEREST_TAGS) == 45
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_tags.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: 구현**

```python
# 태그 문구는 pen 04-5(관심사)·04-6(나의 특징)·06-2(이상형 특징)의 최종 라벨을 그대로 옮긴 것이다
# (erd 세션이 2026-09-20 추출, 개수 45/46/44 일치 확인. 2026-09-19 결정대로 이상형 특징의 "리더쉽 있는"만
# "리더십 있는"으로 오타 수정 — 메모리 project_slice2_decisions_2026-09-19).
INTEREST_TAGS: list[str] = [
    "카페가기", "자전거", "패션", "반려동물", "술", "산책", "피트니스", "게임", "악기연주", "애니",
    "공연관람", "격투기", "미용", "음악감상", "학회", "사진촬영", "영화", "맛집투어", "웹툰", "드라이브",
    "댄스", "봉사활동", "쇼핑", "요가·필라테스", "덕질", "자기계발", "드라마", "IT", "노래부르기", "독서·아티클",
    "전시회관람", "글쓰기", "외국어·어학", "요리", "스포츠", "재테크", "그림그리기", "인테리어", "여행", "스타트업",
    "연극·뮤지컬", "등산", "캠핑", "러닝", "보드게임",
]  # len == 45

MY_TRAITS: list[str] = [
    "깨끗한 피부", "좋은 비율", "달달한 목소리", "섹시한 두뇌", "타투", "워커홀릭", "애교 천재", "긍정적인 마인드",
    "고학력", "건강미", "뛰어난 노래 실력", "리액션 부자", "솔직한 성격", "훌륭한 매너", "동안", "애정 표현 부자",
    "유머러스", "맛집 고수", "높은 자존감", "츤데레", "철저한 자기관리", "계획적", "눈웃음", "자차 보유", "고양이상",
    "강아지상", "짙은 눈썹", "하얀 피부", "구릿빛 피부", "요리 잘하는", "리더십", "감성적", "웃음이 많은",
    "공감 잘하는", "배려심 깊은", "안정적인", "한결같은", "성실한", "차분한", "엉뚱한", "허세 없는", "미소가 예쁜",
    "운동 매니아", "운전 잘하는", "집안일 잘하는", "좋은 체력",
]  # len == 46

IDEAL_TRAITS: list[str] = [
    # "리더십 있는": pen 원본은 "리더쉽 있는" — 2026-09-19 결정으로 오타 수정해 옮긴다.
    "연상", "연하", "동갑", "애교 많은", "두뇌가 섹시한", "진한 이목구비", "인상이 좋은", "귀여운", "어른스러운",
    "매너 좋은", "진지한", "연락 잘하는", "애정 표현 많은", "섹시한", "다정한", "이성 친구 없는",
    "자기 관리 철저한", "솔직한", "외향적인", "가까이 사는", "리더십 있는", "긍정적인", "옷 잘 입는",
    "말 예쁘게 하는", "계획적인", "여행 좋아하는", "부지런한", "자차가 있는", "자신감 있는", "자존감이 높은",
    "논리적인", "가정적인", "유머러스한", "공감 잘하는", "배려심 깊은", "차분한", "웃음이 많은", "동안인",
    "요리 잘하는", "운동 좋아하는", "대화가 잘 통하는", "취미가 잘 맞는", "술 잘 안 마시는", "한결같은",
]  # len == 44


def validate_tag_selection(
    pool: list[str], selected: list[str], minimum: int = 3, maximum: int = 5
) -> None:
    unknown = set(selected) - set(pool)
    if unknown:
        raise ValueError(f"목록에 없는 태그: {sorted(unknown)}")
    if len(selected) < minimum:
        raise ValueError(f"최소 {minimum}개를 골라야 해요")
    if len(selected) > maximum:
        raise ValueError(f"최대 {maximum}개까지 고를 수 있어요")
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_tags.py -v`

- [ ] **Step 5: Commit**

```bash
git add backend/app/profile_onboarding/tags.py backend/tests/profile_onboarding/test_tags.py
git commit -m "🏷️ feat(slice2): 관심사·나의특징·이상형특징 태그 풀·검증"
```

### Task B4: 하트 원장 지급 헬퍼

**Files:**
- Create: `backend/app/profile_onboarding/hearts.py`
- Test: `backend/tests/profile_onboarding/test_hearts.py`

**Interfaces:**
- Consumes: PostgREST(`entitlements`·`heart_transactions`, Task C5)
- Produces: `async def grant_hearts(postgrest_url, service_role_key, client, profile_id, amount, reason, ref_id=None) -> None` — Task B6(아바타)가 5회 실패 보상(10, `admin_adjust`)에 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import httpx
import pytest
from app.profile_onboarding.hearts import grant_hearts


@pytest.mark.asyncio
async def test_grant_hearts_posts_transaction_and_upserts_balance():
    requests = []

    async def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json=[{"heart_balance": 10}] if "rpc" in request.url.path else [])

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    await grant_hearts(
        "https://x.test/rest/v1", "key", client,
        profile_id="00000000-0000-0000-0000-0000000000aa",
        amount=10, reason="admin_adjust",
    )
    assert any("heart_transactions" in r.url.path or "rpc" in r.url.path for r in requests)
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_hearts.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: 구현**

잔액 캐시(`entitlements.heart_balance`)와 원장(`heart_transactions`)을 한 트랜잭션에서 같이 써야 하므로
(ERD §6 "지급·차감은 FastAPI가 한 트랜잭션에서 둘 다 쓴다"), PostgREST 두 번 호출로는 원자성이 안 나온다 —
Postgres 함수 하나로 묶는다. **이 Task 는 Task C5 마이그레이션에 아래 RPC 함수를 이어붙이는 작업을 포함한다**
(구현 시점에 Task C5 파일에 사후 추가):

```sql
-- Task C5 파일 끝에 추가
create or replace function public.grant_hearts(p_profile_id uuid, p_amount integer, p_reason public.heart_reason, p_ref_id uuid default null)
returns void
language plpgsql
as $$
begin
  insert into public.heart_transactions (profile_id, amount, reason, ref_id)
  values (p_profile_id, p_amount, p_reason, p_ref_id);

  insert into public.entitlements (profile_id, heart_balance, updated_at)
  values (p_profile_id, p_amount, now())
  on conflict (profile_id) do update
    set heart_balance = public.entitlements.heart_balance + excluded.heart_balance,
        updated_at = now();
end;
$$;

revoke all on function public.grant_hearts(uuid, integer, public.heart_reason, uuid) from public, anon, authenticated;
grant execute on function public.grant_hearts(uuid, integer, public.heart_reason, uuid) to service_role;
```

```python
import httpx
from uuid import UUID


async def grant_hearts(
    postgrest_url: str, service_role_key: str, client: httpx.AsyncClient,
    profile_id: UUID | str, amount: int, reason: str, ref_id: str | None = None,
) -> None:
    response = await client.post(
        f"{postgrest_url}/rpc/grant_hearts",
        json={"p_profile_id": str(profile_id), "p_amount": amount, "p_reason": reason, "p_ref_id": ref_id},
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        },
    )
    response.raise_for_status()
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_hearts.py -v`

- [ ] **Step 5: Commit**

```bash
git add backend/app/profile_onboarding/hearts.py backend/tests/profile_onboarding/test_hearts.py supabase/migrations
git commit -m "💜 feat(slice2): 하트 원장 지급 RPC·헬퍼"
```

### Task B5: 사진 업로드 + SafeSearch 검수

**Files:**
- Create: `backend/app/profile_onboarding/photos.py`
- Test: `backend/tests/profile_onboarding/test_photos.py`

**Interfaces:**
- Consumes: `google.cloud.vision.ImageAnnotatorAsyncClient`(조각 1b 재사용), `profile-photos` 버킷(조각0)
- Produces: `async def check_safe_search(client, image_bytes) -> bool`(부적절하면 `False`) — Task B7 라우터가 씀.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import pytest
from unittest.mock import AsyncMock
from app.profile_onboarding.photos import check_safe_search


@pytest.mark.asyncio
async def test_check_safe_search_rejects_likely_adult_content():
    vision_client = AsyncMock()
    vision_client.safe_search_detection.return_value.safe_search_annotation.adult = 4  # LIKELY
    vision_client.safe_search_detection.return_value.safe_search_annotation.violence = 1
    result = await check_safe_search(vision_client, b"fake-image-bytes")
    assert result is False


@pytest.mark.asyncio
async def test_check_safe_search_accepts_clean_photo():
    vision_client = AsyncMock()
    vision_client.safe_search_detection.return_value.safe_search_annotation.adult = 1  # VERY_UNLIKELY
    vision_client.safe_search_detection.return_value.safe_search_annotation.violence = 1
    result = await check_safe_search(vision_client, b"fake-image-bytes")
    assert result is True
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_photos.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: 구현**

```python
from google.cloud import vision

# Vision Likelihood enum: UNKNOWN=0 VERY_UNLIKELY=1 UNLIKELY=2 POSSIBLE=3 LIKELY=4 VERY_LIKELY=5
_REJECT_THRESHOLD = 4  # LIKELY 이상이면 거부(사전 결정, project_slice2_decisions_2026-09-19)


async def check_safe_search(vision_client: vision.ImageAnnotatorAsyncClient, image_bytes: bytes) -> bool:
    response = await vision_client.safe_search_detection(image=vision.Image(content=image_bytes))
    annotation = response.safe_search_annotation
    return annotation.adult < _REJECT_THRESHOLD and annotation.violence < _REJECT_THRESHOLD
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_photos.py -v`

- [ ] **Step 5: Commit**

```bash
git add backend/app/profile_onboarding/photos.py backend/tests/profile_onboarding/test_photos.py
git commit -m "🖼️ feat(slice2): SafeSearch 사진 검수"
```

### Task B6: 아바타 생성(OpenAI SDK) + 5회 실패 폴백

**Files:**
- Create: `backend/app/profile_onboarding/avatars.py`
- Test: `backend/tests/profile_onboarding/test_avatars.py`

**Interfaces:**
- Consumes: `openai.AsyncOpenAI`(신규 SDK), `Task B4.grant_hearts`, `avatars` 공개 버킷(Task C3)
- Produces: `class AvatarGenerator` with `async def generate(profile_id, source_photo_bytes) -> AvatarResult` —
  Task B7 라우터가 씀. `AvatarResult(status: Literal["ready","failed"], storage_path: str | None)`.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import pytest
from unittest.mock import AsyncMock
from app.profile_onboarding.avatars import AvatarGenerator, MAX_CONSECUTIVE_FAILURES


@pytest.mark.asyncio
async def test_generate_returns_ready_on_first_success():
    openai_client = AsyncMock()
    openai_client.images.edit.return_value.data = [AsyncMock(b64_json="ZmFrZQ==")]
    storage = AsyncMock()
    storage.upload.return_value = "profile-id/uuid.png"

    generator = AvatarGenerator(openai_client, storage, failure_counts={})
    result = await generator.generate("profile-id", b"source-photo")

    assert result.status == "ready"
    assert result.storage_path == "profile-id/uuid.png"


@pytest.mark.asyncio
async def test_generate_counts_failures_independently_of_sdk_retries():
    # SDK 는 max_retries=0 이라 재시도하지 않는다 — 실패 카운트는 전부 이 클래스가 센다(2026-09-20 결정).
    openai_client = AsyncMock()
    openai_client.images.edit.side_effect = Exception("openai down")
    storage = AsyncMock()
    failure_counts: dict[str, int] = {}
    generator = AvatarGenerator(openai_client, storage, failure_counts)

    for _ in range(MAX_CONSECUTIVE_FAILURES - 1):
        result = await generator.generate("profile-id", b"source-photo")
        assert result.status == "failed"
        assert result.is_final_failure is False

    final = await generator.generate("profile-id", b"source-photo")
    assert final.status == "failed"
    assert final.is_final_failure is True  # 5번째부터 기본 아바타+하트10 트리거


@pytest.mark.asyncio
async def test_generate_resets_failure_count_after_success():
    openai_client = AsyncMock()
    storage = AsyncMock()
    storage.upload.return_value = "path.png"
    failure_counts = {"profile-id": 3}
    openai_client.images.edit.return_value.data = [AsyncMock(b64_json="ZmFrZQ==")]

    generator = AvatarGenerator(openai_client, storage, failure_counts)
    await generator.generate("profile-id", b"source-photo")

    assert failure_counts["profile-id"] == 0
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_avatars.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: 구현**

```python
import base64
import logging
from dataclasses import dataclass
from typing import Literal
from uuid import uuid4

from openai import AsyncOpenAI

_logger = logging.getLogger(__name__)

# "5회 연속 실패 → 기본 아바타+하트10"(project_slice2_decisions_2026-09-19). SDK 자체 재시도는 끄고
# (max_retries=0, get_openai_client 참고) 이 숫자는 우리 코드가 직접 센다 — SDK 재시도와 겹치면 안 된다
# (2026-09-20 사용자 결정).
MAX_CONSECUTIVE_FAILURES = 5


@dataclass(frozen=True)
class AvatarResult:
    status: Literal["ready", "failed"]
    storage_path: str | None
    is_final_failure: bool = False


class AvatarGenerator:
    """실패 횟수는 프로세스 안 dict 로 세지 않고 profile_avatars 테이블의 최근 연속 failed 행 개수로
    센다(재배포·다중 인스턴스에도 카운트가 유지되도록) — 아래 failure_counts 인자는 그 카운트를 호출부가
    미리 조회해 넘겨주는 자리다(테스트를 위한 의존성 주입, 실제 조회는 avatars_repository.py 몫)."""

    def __init__(self, openai_client: AsyncOpenAI, storage, failure_counts: dict[str, int]):
        self._openai_client = openai_client
        self._storage = storage
        self._failure_counts = failure_counts

    async def generate(self, profile_id: str, source_photo_bytes: bytes) -> AvatarResult:
        try:
            response = await self._openai_client.images.edit(
                model="gpt-image-1",
                image=source_photo_bytes,
                prompt=(
                    "Turn this photo into a soft, friendly cartoon avatar illustration, "
                    "keeping the same hairstyle and general look, no text, no watermark."
                ),
            )
            image_bytes = base64.b64decode(response.data[0].b64_json)
        except Exception:
            _logger.exception("아바타 생성 실패 — profile_id=%s", profile_id)
            self._failure_counts[profile_id] = self._failure_counts.get(profile_id, 0) + 1
            is_final = self._failure_counts[profile_id] >= MAX_CONSECUTIVE_FAILURES
            return AvatarResult(status="failed", storage_path=None, is_final_failure=is_final)

        self._failure_counts[profile_id] = 0
        path = f"{profile_id}/{uuid4()}.png"
        storage_path = await self._storage.upload(path, image_bytes, "image/png")
        return AvatarResult(status="ready", storage_path=storage_path)


def get_openai_client(api_key: str) -> AsyncOpenAI:
    # max_retries=0 — SDK 자체 재시도를 끄고, 실패 카운트는 AvatarGenerator 가 직접 센다(2026-09-20 결정).
    return AsyncOpenAI(api_key=api_key, max_retries=0)
```

**주의(구현자에게):** 실제 라우터(Task B7)에서는 `failure_counts` 를 프로세스 메모리 dict 로 두면 재배포 시
카운트가 사라진다 — `profile_avatars` 테이블에서 `profile_id` 기준 `created_at desc` 로 최근 행을 훑어
연속된 `failed` 개수를 세는 작은 repository 함수를 Task B7에서 추가하고, 그 결과를 `failure_counts` 자리에
주입한다(이 Task 의 단위 테스트는 그 조회 없이 순수 로직만 검증한다 — 관심사 분리).

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_avatars.py -v`

- [ ] **Step 5: Commit**

```bash
git add backend/app/profile_onboarding/avatars.py backend/tests/profile_onboarding/test_avatars.py
git commit -m "🎨 feat(slice2): OpenAI 아바타 생성·5회 실패 카운트"
```

### Task B7: 자기소개 AI 초안(OpenAI 챗)

**Files:**
- Create: `backend/app/profile_onboarding/bio_draft.py`
- Test: `backend/tests/profile_onboarding/test_bio_draft.py`

**Interfaces:**
- Consumes: `openai.AsyncOpenAI`(Task B6 과 같은 클라이언트, `max_retries=0`)
- Produces: `async def generate_bio_draft(openai_client, survey_summary, interest_tags, my_traits) -> str` —
  Task B8 라우터가 씀.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import pytest
from unittest.mock import AsyncMock
from app.profile_onboarding.bio_draft import generate_bio_draft


@pytest.mark.asyncio
async def test_generate_bio_draft_returns_completion_text():
    openai_client = AsyncMock()
    openai_client.chat.completions.create.return_value.choices = [
        AsyncMock(message=AsyncMock(content="안녕하세요! 활발하고 여행을 좋아해요."))
    ]
    draft = await generate_bio_draft(
        openai_client, survey_summary="외향적", interest_tags=["여행", "카페"], my_traits=["유머있는"]
    )
    assert draft == "안녕하세요! 활발하고 여행을 좋아해요."
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_bio_draft.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: 구현**

```python
from openai import AsyncOpenAI

# 재료는 성향 설문 + 관심사 태그(04-5) + 나의 특징(04-6)뿐이다 — 이상형 답변은 자기소개 재료에서 제외한다
# (자기소개는 나에 대한 글이라서, 설계 §13-72).
_SYSTEM_PROMPT = (
    "너는 대학생 소개팅 앱의 자기소개 초안을 써주는 도우미야. "
    "2~3문장, 담백하고 과하지 않은 톤으로, 존댓말로 써줘. 이모지는 쓰지 마."
)


async def generate_bio_draft(
    openai_client: AsyncOpenAI, survey_summary: str, interest_tags: list[str], my_traits: list[str]
) -> str:
    user_prompt = (
        f"성향: {survey_summary}\n관심사: {', '.join(interest_tags)}\n나의 특징: {', '.join(my_traits)}"
    )
    response = await openai_client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": _SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
    )
    return response.choices[0].message.content
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_bio_draft.py -v`

- [ ] **Step 5: Commit**

```bash
git add backend/app/profile_onboarding/bio_draft.py backend/tests/profile_onboarding/test_bio_draft.py
git commit -m "✍️ feat(slice2): 자기소개 AI 초안(gpt-4o-mini)"
```

### Task B8: 온보딩 완료 판정 · 다음 단계 계산

**Files:**
- Create: `backend/app/profile_onboarding/onboarding_progress.py`
- Test: `backend/tests/profile_onboarding/test_onboarding_progress.py`

**Interfaces:**
- Consumes: 없음(순수 함수, `dict` 입력)
- Produces: `OnboardingStep` 문자열 상수들 · `next_step(profile: dict) -> str`(모두 채워졌으면 `"complete"`) —
  Task B9 라우터, Part A `AuthRedirect` 확장이 이 문자열 값을 그대로 씀.

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from app.profile_onboarding.onboarding_progress import next_step

_EMPTY_PROFILE = {
    "nickname": None, "phone_set": False, "kakao_id_set": False,
    "photo_count": 0, "has_avatar_source": False, "avatar_ready": False,
    "animal_type": None, "impression_type": None,
    "interest_tags": [], "my_traits": [],
    "survey_answer_count": 0, "religion": None, "is_smoker": None,
    "preferred_age_min": None, "preferred_animal_types": [], "preferred_impression_types": [],
    "ideal_traits": [], "ideal_note_seen": False, "bio": None,
}


def test_next_step_starts_at_basic_info():
    assert next_step(_EMPTY_PROFILE) == "basic_info"


def test_next_step_moves_to_kakao_id_after_basic_info():
    profile = {**_EMPTY_PROFILE, "nickname": "가나", "phone_set": True}
    assert next_step(profile) == "kakao_id"


def test_next_step_is_complete_when_everything_filled():
    profile = {
        "nickname": "가나", "phone_set": True, "kakao_id_set": True,
        "photo_count": 2, "has_avatar_source": True, "avatar_ready": True,
        "animal_type": "dog", "impression_type": "kind",
        "interest_tags": ["a", "b", "c"], "my_traits": ["a", "b", "c"],
        "survey_answer_count": 9, "religion": "none", "is_smoker": False,
        "preferred_age_min": 20, "preferred_animal_types": [], "preferred_impression_types": [],
        "ideal_traits": ["a", "b", "c"], "ideal_note_seen": True, "bio": "안녕하세요",
    }
    assert next_step(profile) == "complete"
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_onboarding_progress.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: 구현**

```python
# 순서는 DESIGN.md §9 04-1~06-3 화면 순서를 그대로 따른다. 각 단계는 "이 단계까지 끝났다"는 최소 조건만 본다
# — 태그 개수 3~5 같은 상세 규칙은 저장 시점(Task B9 각 엔드포인트)에서 tags.validate_tag_selection 이 본다.
_STEPS = [
    ("basic_info", lambda p: p["nickname"] and p["phone_set"]),
    ("kakao_id", lambda p: p["kakao_id_set"]),
    ("photos", lambda p: p["photo_count"] >= 2 and p["has_avatar_source"]),
    ("avatar", lambda p: p["avatar_ready"]),
    ("appearance_type", lambda p: p["animal_type"] and p["impression_type"]),
    ("interests", lambda p: len(p["interest_tags"]) >= 3),
    ("my_traits", lambda p: len(p["my_traits"]) >= 3),
    ("survey", lambda p: p["survey_answer_count"] >= 9 and p["religion"] is not None and p["is_smoker"] is not None),
    ("ideal_conditions", lambda p: p["preferred_age_min"] is not None),
    ("ideal_traits", lambda p: len(p["ideal_traits"]) >= 3),
    ("ideal_note", lambda p: p["ideal_note_seen"]),
    ("bio", lambda p: p["bio"]),
]


def next_step(profile: dict) -> str:
    for step_name, is_done in _STEPS:
        if not is_done(profile):
            return step_name
    return "complete"
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && pytest tests/profile_onboarding/test_onboarding_progress.py -v`

- [ ] **Step 5: Commit**

```bash
git add backend/app/profile_onboarding/onboarding_progress.py backend/tests/profile_onboarding/test_onboarding_progress.py
git commit -m "🧭 feat(slice2): 온보딩 다음 단계 계산"
```

### Task B9: 라우터 · 스키마 배선

**Files:**
- Create: `backend/app/profile_onboarding/__init__.py`
- Create: `backend/app/profile_onboarding/schemas.py`
- Create: `backend/app/profile_onboarding/repository.py`
- Create: `backend/app/profile_onboarding/router.py`
- Modify: `backend/app/main.py`(라우터 등록)
- Test: `backend/tests/profile_onboarding/test_router.py`

**Interfaces:**
- Consumes: Task B1~B8 전체
- Produces: 아래 엔드포인트 — Part A 전체 화면이 호출.

| 메서드 · 경로 | 화면 | 바디 | 비고 |
| --- | --- | --- | --- |
| `GET /profile-onboarding/nickname-availability?nickname=` | 04-1 | - | `profiles_nickname_unique`(lower) 위반 여부를 `select`로 먼저 확인 |
| `POST /profile-onboarding/basic-info` | 04-1 | nickname, birthYear, heightCm, phoneNumber, gender, mbti | 닉네임 unique 위반(PostgREST 23505) 시 409 "이미 있는 닉네임" |
| `POST /profile-onboarding/kakao-id` | 04-1b | kakaoId | |
| `POST /profile-onboarding/photos` (multipart) | 04-2 | photo 파일, position, isAvatarSource | SafeSearch 실패 시 422 |
| `POST /profile-onboarding/avatar/generate` | 04-3 | - | AvatarGenerator 호출, 5회째 실패면 fallback + `grant_hearts(10, admin_adjust)` |
| `POST /profile-onboarding/appearance-type` | 04-4 | animalType, impressionType | |
| `POST /profile-onboarding/interests` | 04-5 | tags | `validate_tag_selection(INTEREST_TAGS, ...)` |
| `POST /profile-onboarding/my-traits` | 04-6 | traits | `validate_tag_selection(MY_TRAITS, ...)` |
| `POST /profile-onboarding/survey` | 05-01~11 | answers(axis→value), religion, isSmoker | |
| `POST /profile-onboarding/ideal-conditions` | 06-1 | preferredAgeMin/Max, preferredHeightMin/Max, preferredMbtiFlags, preferredAnimalTypes, preferredImpressionTypes | 기존 조각0 컬럼도 여기서 처음 채워짐 |
| `POST /profile-onboarding/ideal-traits` | 06-2 | traits | `validate_tag_selection(IDEAL_TRAITS, ...)` |
| `POST /profile-onboarding/ideal-note` | 06-2a | note(선택, 건너뛰기 가능) | `ideal_note_seen` 은 건너뛰어도 true(다시 안 보여줌) |
| `POST /profile-onboarding/bio-draft` | 06-2b | - | `bio_draft_generated_at` 이미 있으면 409(재생성 금지, §13-71) |
| `POST /profile-onboarding/bio` | 06-3 | bio | 저장 후 `next_step()=="complete"` 면 `profiles.status='active'` 로 전환 |
| `GET /profile-onboarding/next-step` | 게이트 | - | Task B8 결과 그대로 반환, Part A 라우터가 씀 |

- [ ] **Step 1: 스키마 작성**

```python
# schemas.py
from pydantic import BaseModel


class BasicInfoRequest(BaseModel):
    nickname: str
    birth_year: int
    height_cm: int
    phone_number: str
    gender: str
    mbti: str | None = None


class KakaoIdRequest(BaseModel):
    kakao_id: str


class AppearanceTypeRequest(BaseModel):
    animal_type: str
    impression_type: str


class TagsRequest(BaseModel):
    tags: list[str]


class SurveyRequest(BaseModel):
    answers: dict[int, float]  # axis -> value
    religion: str
    is_smoker: bool


class IdealConditionsRequest(BaseModel):
    preferred_age_min: int
    preferred_age_max: int
    preferred_height_min: int | None = None
    preferred_height_max: int | None = None
    preferred_mbti_flags: dict[str, bool] = {}
    preferred_animal_types: list[str] = []
    preferred_impression_types: list[str] = []


class IdealNoteRequest(BaseModel):
    note: str | None = None


class BioRequest(BaseModel):
    bio: str


class NextStepResponse(BaseModel):
    step: str
```

- [ ] **Step 2: repository.py — 조각 1b `StudentVerificationRepository` 와 같은 패턴으로 PostgREST 직접 호출**

각 엔드포인트마다 조각 1b `repository.py`(Task 참고 코드 상단에 인용한 실제 파일)와 동일하게, `httpx.AsyncClient`
로 PostgREST 에 GET/PATCH/POST 하는 짧은 메서드를 하나씩 둔다. 예시 하나만 보이고 나머지는 같은 모양으로
반복한다(이미 조각 1b 에서 검증된 패턴이라 새로 설계하지 않는다):

```python
async def update_basic_info(self, profile_id, nickname, birth_year, height_cm, gender, mbti) -> None:
    response = await self._client.patch(
        f"{self._postgrest_url}/profiles",
        params={"id": f"eq.{profile_id}"},
        json={
            "nickname": nickname, "birth_year": birth_year, "height_cm": height_cm,
            "gender": gender, "mbti": mbti,
        },
        headers=self._headers,
    )
    if response.status_code == 409:
        raise ValueError("이미 있는 닉네임이에요")
    response.raise_for_status()
```

나머지 메서드(`fetch_onboarding_snapshot`, `insert_photo`, `mark_avatar_source`, `insert_avatar_attempt`,
`update_interests`, `update_my_traits`, `insert_survey_answers`, `update_ideal_conditions`,
`update_ideal_traits`, `update_ideal_note`, `mark_bio_draft_generated`, `update_bio_and_maybe_activate`)도
같은 `httpx` PATCH/POST/GET 패턴을 반복한다. `fetch_onboarding_snapshot` 만 Task B8 의 `next_step()` 입력
모양(`dict`)에 맞춰 `profiles`·`profile_photos`·`survey_answers`·`profile_private` 를 조인 없이 개별 조회 후
합쳐 돌려준다(PostgREST 는 조인 대신 `select=profile_photos(count)` 같은 임베드 쿼리를 쓸 수 있다 — 조각 1b
`fetch_gate_status`의 `universities(name)` 임베드와 같은 방식).

- [ ] **Step 3: router.py — 표의 엔드포인트를 조각 1b `router.py` 와 같은 함수형 스타일로 구현**

```python
@router.get("/profile-onboarding/next-step")
async def get_next_step(authorization: str | None = Header(default=None)) -> NextStepResponse:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = ProfileOnboardingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    snapshot = await repo.fetch_onboarding_snapshot(profile_id)
    return NextStepResponse(step=next_step(snapshot))
```

나머지 엔드포인트도 조각 1b `submit_student_verification`과 같은 구조(설정→인증→repository→검증→저장→응답)를
따른다. `POST /profile-onboarding/avatar/generate` 만 Task B6 `AvatarGenerator`와 Task B4 `grant_hearts`를
같이 호출한다:

```python
@router.post("/profile-onboarding/avatar/generate")
async def generate_avatar(authorization: str | None = Header(default=None)) -> dict:
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_current_user_id(settings, client, authorization)
    repo = ProfileOnboardingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)

    source_photo = await repo.fetch_avatar_source_photo_bytes(profile_id)
    recent_failures = await repo.count_recent_consecutive_avatar_failures(profile_id)
    generator = AvatarGenerator(
        _openai_client_override or get_openai_client(settings.openai_api_key),
        AvatarStorage(settings.storage_url, settings.supabase_service_role_key, client),
        failure_counts={str(profile_id): recent_failures},
    )
    result = await generator.generate(str(profile_id), source_photo)

    if result.status == "ready":
        await repo.insert_avatar_attempt(profile_id, "ready", result.storage_path)
        return {"status": "ready"}

    await repo.insert_avatar_attempt(profile_id, "failed", None)
    if result.is_final_failure:
        fallback_path = await repo.assign_fallback_avatar(profile_id)  # mascot-{gender}.png 를 avatars 버킷에 복사
        await grant_hearts(
            settings.postgrest_url, settings.supabase_service_role_key, client,
            profile_id=profile_id, amount=10, reason="admin_adjust",
        )
        return {"status": "fallback", "storage_path": fallback_path, "compensation_hearts": 10}
    return {"status": "failed"}
```

- [ ] **Step 4: `main.py` 에 라우터 등록**

`app/main.py` 에서 기존 `student_verification.router` 를 등록하는 줄 옆에 한 줄 추가:

```python
from app.profile_onboarding.router import router as profile_onboarding_router
app.include_router(profile_onboarding_router)
```

- [ ] **Step 5: 통합 테스트 작성 — 최소 3개 대표 경로만**

```python
# test_router.py — 조각 1b test_router.py 패턴(FastAPI TestClient + httpx.MockTransport)을 그대로 따른다.
# 1) 닉네임 중복 시 409, 2) 태그 3개 미만이면 422, 3) 5회 연속 실패 시 하트 10 지급 확인.
# 실제 코드는 조각 1b backend/tests/student_verification/test_router.py 를 참고해 같은 방식으로 작성한다.
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `cd backend && pytest tests/profile_onboarding/ -v`

- [ ] **Step 7: Commit**

```bash
git add backend/app/profile_onboarding backend/app/main.py backend/tests/profile_onboarding/test_router.py
git commit -m "🌐 feat(slice2): 프로필 온보딩 라우터 배선"
```

---

## Part A: Flutter 프론트엔드

새 feature 루트는 기존 `frontend/lib/profile/`(현재 빈 폴더)를 쓴다. 화면마다 `view/`·`viewmodel/`·`model/`
서브폴더에 조각 1b `SchoolInfoScreen`/`SchoolInfoViewModel` 패턴(Notifier + 불변 UiState + `_copyWith` +
Repository Provider)을 반복한다.

### Task A1: 게이트 확장 — 온보딩 다음 화면 계산

**Files:**
- Create: `frontend/lib/profile/model/onboarding_step.dart`
- Create: `frontend/lib/profile/model/onboarding_repository.dart`
- Create: `frontend/lib/profile/model/http_onboarding_repository.dart`
- Create: `frontend/lib/profile/model/onboarding_repository_provider.dart`
- Modify: `frontend/lib/core/router/app_routes.dart`
- Modify: `frontend/lib/core/router/auth_redirect.dart`
- Modify: `frontend/lib/auth/model/verification_gate.dart`
- Test: `frontend/test/core/router/auth_redirect_test.dart`

**Interfaces:**
- Consumes: `GET /profile-onboarding/next-step`(Task B9)
- Produces: `OnboardingStep` enum, `AuthRedirect` 가 `VerificationGate.complete` 뒤에도 이 값으로 계속 리다이렉트
  — Part A 나머지 모든 화면의 "다음" 버튼이 여기 등록된 라우트로 이동한다.

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
// auth_redirect_test.dart 에 추가할 케이스
test('검증은 끝났지만 온보딩이 남았으면 온보딩 화면으로 보낸다', () {
  final redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.interests);
  expect(redirect.resolve(AppRoutes.home), AppRoutes.onboardingInterests);
});

test('온보딩까지 전부 끝났으면 홈에 머무른다', () {
  final redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.complete);
  expect(redirect.resolve(AppRoutes.home), isNull);
});
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd frontend && flutter test test/core/router/auth_redirect_test.dart`
Expected: FAIL — `AuthRedirect` 생성자 인자 개수 불일치

- [ ] **Step 3: `OnboardingStep` enum + 라우트 추가**

```dart
// onboarding_step.dart
enum OnboardingStep {
  basicInfo, kakaoId, photos, avatar, appearanceType,
  interests, myTraits, survey, idealConditions, idealTraits, idealNote, bio,
  complete;

  static OnboardingStep fromWire(String value) => switch (value) {
    'basic_info' => basicInfo,
    'kakao_id' => kakaoId,
    'photos' => photos,
    'avatar' => avatar,
    'appearance_type' => appearanceType,
    'interests' => interests,
    'my_traits' => myTraits,
    'survey' => survey,
    'ideal_conditions' => idealConditions,
    'ideal_traits' => idealTraits,
    'ideal_note' => idealNote,
    'bio' => bio,
    _ => complete,
  };
}
```

`app_routes.dart` 에 각 단계별 경로 상수 추가(`onboardingBasicInfo`, `onboardingKakaoId`, ... `onboardingBio`).

- [ ] **Step 4: `AuthRedirect` 확장**

```dart
class AuthRedirect {
  const AuthRedirect(this._isAuthenticated, this._gate, this._onboardingStep);

  final bool _isAuthenticated;
  final VerificationGate _gate;
  final OnboardingStep _onboardingStep;

  String? resolve(String location) {
    if (_isAuthenticated) {
      return _resolveForMember(location);
    }
    return _resolveForGuest(location);
  }

  String? _resolveForMember(String location) {
    final gateTarget = _gateTarget();
    if (gateTarget != null) {
      return location == gateTarget ? null : gateTarget;
    }
    final onboardingTarget = _onboardingTarget();
    if (onboardingTarget != null) {
      return location == onboardingTarget ? null : onboardingTarget;
    }
    if (_isBeforeHome(location)) {
      return AppRoutes.home;
    }
    return null;
  }

  String? _onboardingTarget() => switch (_onboardingStep) {
    OnboardingStep.basicInfo => AppRoutes.onboardingBasicInfo,
    OnboardingStep.kakaoId => AppRoutes.onboardingKakaoId,
    OnboardingStep.photos => AppRoutes.onboardingPhotos,
    OnboardingStep.avatar => AppRoutes.onboardingAvatar,
    OnboardingStep.appearanceType => AppRoutes.onboardingAppearanceType,
    OnboardingStep.interests => AppRoutes.onboardingInterests,
    OnboardingStep.myTraits => AppRoutes.onboardingMyTraits,
    OnboardingStep.survey => AppRoutes.onboardingSurvey,
    OnboardingStep.idealConditions => AppRoutes.onboardingIdealConditions,
    OnboardingStep.idealTraits => AppRoutes.onboardingIdealTraits,
    OnboardingStep.idealNote => AppRoutes.onboardingIdealNote,
    OnboardingStep.bio => AppRoutes.onboardingBio,
    OnboardingStep.complete => null,
  };

  // _gateTarget()·_isBeforeHome()·_resolveForGuest() 는 기존 그대로, _isBeforeHome 목록에
  // 온보딩 경로 전체를 추가한다(화면을 새로고침해도 안 벗어나게).
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd frontend && flutter test test/core/router/auth_redirect_test.dart`

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/profile/model frontend/lib/core/router frontend/lib/auth/model/verification_gate.dart frontend/test/core/router/auth_redirect_test.dart
git commit -m "🧭 feat(slice2): 온보딩 단계 게이트 확장"
```

### Task A2: 공용 태그 선택 위젯 + 관심사/나의특징/이상형특징 3화면

**Files:**
- Create: `frontend/lib/profile/view/tag_picker_screen.dart`
- Create: `frontend/lib/profile/viewmodel/tag_picker_view_model.dart`
- Create: `frontend/lib/profile/viewmodel/tag_picker_ui_state.dart`
- Create: `frontend/lib/profile/model/tags.dart`(45/46/44 라벨 — Task B3 와 마찬가지로 pen 라벨 대기)
- Test: `frontend/test/profile/viewmodel/tag_picker_view_model_test.dart`

**Interfaces:**
- Consumes: `POST /profile-onboarding/interests`·`/my-traits`·`/ideal-traits`(Task B9), `tags.dart` 상수
- Produces: `TagPickerScreen({required TagPickerKind kind})` — 04-5·04-6·06-2 세 화면이 `kind` 만 다르게 넘겨
  재사용한다("14c 수정 › 도 04-5·04-6·06-2 를 편집 모드로 재사용"한다는 DESIGN §9 기존 관례와 같은 방향).

이 세 화면은 헤드라인·최소/최대 개수(3~5)·저장 API 만 다르고 위젯 구조가 동일하므로 화면 3개를 한 위젯 +
`enum TagPickerKind`로 만든다(백엔드 Task B3 의 세 상수 리스트, B9 의 세 엔드포인트와 1:1 대응).

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
test('3개 미만 고르면 다음 버튼이 비활성', () {
  final vm = container.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier);
  vm.toggle('여행');
  vm.toggle('카페');
  final state = container.read(tagPickerViewModelProvider(TagPickerKind.interests));
  expect(state.canSubmit, isFalse);
});

test('5개 넘게 고르려 하면 무시한다', () {
  final vm = container.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier);
  for (final tag in interestTags.take(6)) {
    vm.toggle(tag);
  }
  final state = container.read(tagPickerViewModelProvider(TagPickerKind.interests));
  expect(state.selected.length, 5);
});
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd frontend && flutter test test/profile/viewmodel/tag_picker_view_model_test.dart`

- [ ] **Step 3: `tags.dart` 라벨 작성 + `TagPickerKind`·ViewModel 구현**

태그 문구는 백엔드 Task B3 의 `INTEREST_TAGS`/`MY_TRAITS`/`IDEAL_TRAITS`(erd 세션이 pen 04-5/04-6/06-2 에서
추출한 최종 라벨, 2026-09-20)와 완전히 동일한 순서·문구로 옮긴다. 두 언어에서 값이 갈리면 서버가 거부하는
태그를 클라이언트가 보여주게 된다.

```dart
// tags.dart
const List<String> interestTags = [
  '카페가기', '자전거', '패션', '반려동물', '술', '산책', '피트니스', '게임', '악기연주', '애니',
  '공연관람', '격투기', '미용', '음악감상', '학회', '사진촬영', '영화', '맛집투어', '웹툰', '드라이브',
  '댄스', '봉사활동', '쇼핑', '요가·필라테스', '덕질', '자기계발', '드라마', 'IT', '노래부르기', '독서·아티클',
  '전시회관람', '글쓰기', '외국어·어학', '요리', '스포츠', '재테크', '그림그리기', '인테리어', '여행', '스타트업',
  '연극·뮤지컬', '등산', '캠핑', '러닝', '보드게임',
]; // len == 45

const List<String> myTraits = [
  '깨끗한 피부', '좋은 비율', '달달한 목소리', '섹시한 두뇌', '타투', '워커홀릭', '애교 천재', '긍정적인 마인드',
  '고학력', '건강미', '뛰어난 노래 실력', '리액션 부자', '솔직한 성격', '훌륭한 매너', '동안', '애정 표현 부자',
  '유머러스', '맛집 고수', '높은 자존감', '츤데레', '철저한 자기관리', '계획적', '눈웃음', '자차 보유', '고양이상',
  '강아지상', '짙은 눈썹', '하얀 피부', '구릿빛 피부', '요리 잘하는', '리더십', '감성적', '웃음이 많은',
  '공감 잘하는', '배려심 깊은', '안정적인', '한결같은', '성실한', '차분한', '엉뚱한', '허세 없는', '미소가 예쁜',
  '운동 매니아', '운전 잘하는', '집안일 잘하는', '좋은 체력',
]; // len == 46

const List<String> idealTraits = [
  // "리더십 있는": pen 원본은 "리더쉽 있는" — 2026-09-19 결정으로 오타 수정해 옮긴다.
  '연상', '연하', '동갑', '애교 많은', '두뇌가 섹시한', '진한 이목구비', '인상이 좋은', '귀여운', '어른스러운',
  '매너 좋은', '진지한', '연락 잘하는', '애정 표현 많은', '섹시한', '다정한', '이성 친구 없는',
  '자기 관리 철저한', '솔직한', '외향적인', '가까이 사는', '리더십 있는', '긍정적인', '옷 잘 입는',
  '말 예쁘게 하는', '계획적인', '여행 좋아하는', '부지런한', '자차가 있는', '자신감 있는', '자존감이 높은',
  '논리적인', '가정적인', '유머러스한', '공감 잘하는', '배려심 깊은', '차분한', '웃음이 많은', '동안인',
  '요리 잘하는', '운동 좋아하는', '대화가 잘 통하는', '취미가 잘 맞는', '술 잘 안 마시는', '한결같은',
]; // len == 44
```

`INTEREST_TAGS`/`MY_TRAITS`/`IDEAL_TRAITS` 는 위 세 상수의 별칭이 아니라 테스트 코드에서 쓰는 표기다 — 실제
Dart 관례(lowerCamelCase 상수)에 맞춰 `interestTags`/`myTraits`/`idealTraits` 로 선언하고, 이어지는 `TagPickerKind`
정의에서 그 이름을 그대로 참조한다.

```dart
enum TagPickerKind {
  interests(pool: interestTags, endpoint: 'interests', headline: '관심사를 골라주세요'),
  myTraits(pool: myTraits, endpoint: 'my-traits', headline: '나를 표현하는 특징을 골라주세요'),
  idealTraits(pool: idealTraits, endpoint: 'ideal-traits', headline: '어떤 분을 만나고 싶나요?');

  const TagPickerKind({required this.pool, required this.endpoint, required this.headline});
  final List<String> pool;
  final String endpoint;
  final String headline;
}

class TagPickerViewModel extends FamilyNotifier<TagPickerUiState, TagPickerKind> {
  @override
  TagPickerUiState build(TagPickerKind arg) => const TagPickerUiState();

  void toggle(String tag) {
    final selected = {...state.selected};
    if (selected.contains(tag)) {
      selected.remove(tag);
    } else if (selected.length < 5) {
      selected.add(tag);
    }
    state = state.copyWith(selected: selected);
  }

  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    final repository = ref.read(tagPickerRepositoryProvider);
    final result = await repository.submit(arg.endpoint, state.selected.toList());
    state = result.when(
      onSuccess: (_) => state.copyWith(isSubmitting: false, completed: true),
      onFailure: (failure) => state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
    if (state.completed) {
      unawaited(ref.read(verificationGateListenableProvider).refresh());
    }
  }
}
```

`TagPickerUiState.canSubmit => selected.length >= 3 && selected.length <= 5`.

- [ ] **Step 4: 화면 위젯 — `Wrap` + `FilterChip`**

```dart
class TagPickerScreen extends ConsumerWidget {
  const TagPickerScreen({required this.kind, super.key});
  final TagPickerKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tagPickerViewModelProvider(kind));
    final viewModel = ref.read(tagPickerViewModelProvider(kind).notifier);
    return Scaffold(
      appBar: AppBar(title: Text(kind.headline)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in kind.pool)
                FilterChip(
                  label: Text(tag),
                  selected: state.selected.contains(tag),
                  onSelected: (_) => viewModel.toggle(tag),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppButton.primary(
            label: '다음',
            enabled: state.canSubmit && !state.isSubmitting,
            onPressed: viewModel.submit,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd frontend && flutter test test/profile/`

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/profile/view/tag_picker_screen.dart frontend/lib/profile/viewmodel frontend/lib/profile/model/tags.dart frontend/test/profile
git commit -m "🏷️ feat(slice2): 태그 선택 공용 화면(관심사·나의특징·이상형특징)"
```

### Task A3: 기본 정보(04-1) + 카카오톡 아이디(04-1b)

**Files:**
- Create: `frontend/lib/profile/view/basic_info_screen.dart`
- Create: `frontend/lib/profile/viewmodel/basic_info_view_model.dart`
- Create: `frontend/lib/profile/viewmodel/basic_info_ui_state.dart`
- Create: `frontend/lib/profile/view/kakao_id_screen.dart`
- Create: `frontend/lib/profile/viewmodel/kakao_id_view_model.dart`
- Test: `frontend/test/profile/viewmodel/basic_info_view_model_test.dart`

**Interfaces:**
- Consumes: `GET /profile-onboarding/nickname-availability`, `POST /profile-onboarding/basic-info`,
  `POST /profile-onboarding/kakao-id`(Task B9)
- Produces: 없음(마지막 소비 화면 아님) — Task A1 라우트에 연결.

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
test('닉네임 입력이 바뀌면 300ms 디바운스 후 중복 확인을 부른다', () async {
  final vm = container.read(basicInfoViewModelProvider.notifier);
  vm.changeNickname('가나다');
  await Future.delayed(const Duration(milliseconds: 350));
  verify(() => mockRepository.checkNicknameAvailability('가나다')).called(1);
});

test('중복 닉네임이면 인라인 에러를 보여준다', () async {
  when(() => mockRepository.checkNicknameAvailability(any()))
      .thenAnswer((_) async => const Result.success(false));
  final vm = container.read(basicInfoViewModelProvider.notifier);
  vm.changeNickname('중복닉네임');
  await Future.delayed(const Duration(milliseconds: 350));
  final state = container.read(basicInfoViewModelProvider);
  expect(state.nicknameError, '이미 있는 닉네임이에요');
});
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd frontend && flutter test test/profile/viewmodel/basic_info_view_model_test.dart`

- [ ] **Step 3: 구현 — 조각1b `SchoolInfoViewModel` 패턴 + 닉네임 디바운스**

```dart
class BasicInfoViewModel extends Notifier<BasicInfoUiState> {
  Timer? _debounce;

  @override
  BasicInfoUiState build() => const BasicInfoUiState();

  void changeNickname(String value) {
    state = state.copyWith(nickname: value, nicknameError: null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _checkNickname(value));
  }

  Future<void> _checkNickname(String value) async {
    if (value.length < 2) return;
    final repository = ref.read(basicInfoRepositoryProvider);
    final result = await repository.checkNicknameAvailability(value);
    result.when(
      onSuccess: (available) => state = state.copyWith(
        nicknameError: available ? null : '이미 있는 닉네임이에요',
      ),
      onFailure: (_) {},
    );
  }

  // changeBirthYear · changeHeight · changePhoneNumber · changeGender · changeMbti 는
  // SchoolInfoViewModel._copyWith 와 같은 _keep 패턴으로 각 필드만 바꾼다(반복 생략).

  Future<void> submit() async {
    if (!state.isValid) return;
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    final repository = ref.read(basicInfoRepositoryProvider);
    final result = await repository.submit(state.toRequest());
    state = result.when(
      onSuccess: (_) => state.copyWith(isSubmitting: false, completed: true),
      onFailure: (failure) => state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
    if (state.completed) {
      unawaited(ref.read(verificationGateListenableProvider).refresh());
    }
  }
}
```

`KakaoIdViewModel` 은 `SchoolInfoViewModel` 과 거의 동일(필드 1개, 건너뛰기 없음 — §13-100 버튼 비활성 규칙)하므로
그 파일을 그대로 본떠 작성한다(새 패턴 설계 없음).

- [ ] **Step 4: 화면 위젯 — `text-field`·`nickname-field` 인라인 에러 표시**

두 화면 모두 조각 1b `SchoolInfoScreen`(`frontend/lib/auth/view/school_info_screen.dart`)과 같은 레이아웃
골격(App Bar 없음/뒤로가기 없음, 헤드라인 + 입력 필드 + 하단 고정 버튼)을 그대로 따른다. 닉네임 필드만
`state.nicknameError` 를 `TextField.decoration.errorText` 로 보여주는 인라인 검증이 추가된다.

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd frontend && flutter test test/profile/`

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/profile/view/basic_info_screen.dart frontend/lib/profile/view/kakao_id_screen.dart frontend/lib/profile/viewmodel frontend/test/profile
git commit -m "📝 feat(slice2): 기본 정보·카카오톡 아이디 화면"
```

### Task A4: 사진 업로드(04-2) · 아바타 생성(04-3)

**Files:**
- Create: `frontend/lib/profile/view/photos_screen.dart`
- Create: `frontend/lib/profile/viewmodel/photos_view_model.dart`
- Create: `frontend/lib/profile/view/avatar_generation_screen.dart`
- Create: `frontend/lib/profile/viewmodel/avatar_generation_view_model.dart`
- Test: `frontend/test/profile/viewmodel/avatar_generation_view_model_test.dart`

**Interfaces:**
- Consumes: `image_picker`(기존 의존성) → `flutter_image_compress`(기존) → `POST /profile-onboarding/photos`,
  `POST /profile-onboarding/avatar/generate`(Task B9)

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
test('아바타 생성 실패 응답을 받으면 다시 시도 버튼을 보여준다', () async {
  when(() => mockRepository.generateAvatar())
      .thenAnswer((_) async => const Result.success(AvatarGenerationOutcome.failed()));
  final vm = container.read(avatarGenerationViewModelProvider.notifier);
  await vm.generate();
  final state = container.read(avatarGenerationViewModelProvider);
  expect(state.canRetry, isTrue);
});

test('fallback 응답을 받으면 보상 하트 안내 다이얼로그 상태를 켠다', () async {
  when(() => mockRepository.generateAvatar()).thenAnswer(
    (_) async => const Result.success(AvatarGenerationOutcome.fallback(compensationHearts: 10)),
  );
  final vm = container.read(avatarGenerationViewModelProvider.notifier);
  await vm.generate();
  final state = container.read(avatarGenerationViewModelProvider);
  expect(state.showCompensationDialog, isTrue);
  expect(state.compensationHearts, 10);
});
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd frontend && flutter test test/profile/viewmodel/avatar_generation_view_model_test.dart`

- [ ] **Step 3: `PhotosViewModel` — 조각 1b `StudentVerificationViewModel`의 이미지 압축·업로드 패턴 재사용**

`frontend/lib/auth/model/image_compressor.dart`(이미 있음)를 그대로 재사용해 업로드 전 압축한다. 최소 2장·
최대 4장, 그 중 정확히 1장을 `isAvatarSource=true` 로 표시하는 상태만 `PhotosUiState` 에 둔다(개수 검증은
"다음" 버튼 활성화 조건으로, 서버 하한 검증과 별개로 UX 상 먼저 막는다).

- [ ] **Step 4: `AvatarGenerationViewModel` — 로딩 토스트 + 재시도 + 실패 다이얼로그**

```dart
enum AvatarGenerationStatus { idle, generating, ready, failed, fallback }

class AvatarGenerationViewModel extends Notifier<AvatarGenerationUiState> {
  @override
  AvatarGenerationUiState build() => const AvatarGenerationUiState();

  Future<void> generate() async {
    state = state.copyWith(status: AvatarGenerationStatus.generating);
    final repository = ref.read(avatarRepositoryProvider);
    final result = await repository.generateAvatar();
    state = result.when(
      onSuccess: (outcome) => outcome.when(
        ready: (path) => state.copyWith(status: AvatarGenerationStatus.ready, avatarPath: path, completed: true),
        failed: () => state.copyWith(status: AvatarGenerationStatus.failed),
        fallback: (hearts) => state.copyWith(
          status: AvatarGenerationStatus.fallback,
          showCompensationDialog: true,
          compensationHearts: hearts,
          completed: true,
        ),
      ),
      onFailure: (failure) => state.copyWith(
        status: AvatarGenerationStatus.failed,
        errorMessage: failure.toDisplayMessage(),
      ),
    );
    if (state.completed) {
      unawaited(ref.read(verificationGateListenableProvider).refresh());
    }
  }
}
```

화면은 DESIGN §9 04-3 규칙대로 "변환 중" 토스트를 하단 CTA 버튼 바로 위·가로 중앙에 두고(§13-56), 실패 시
"다시 시도" 버튼, `fallback` 상태에서는 "서버 오류로 하트 10개 드렸어요, 설정 > 아바타 재생성 에서 다시 만들
수 있어요" 다이얼로그를 띄운다(project_slice2_decisions_2026-09-19에 적힌 정확한 문구 그대로).

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd frontend && flutter test test/profile/`

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/profile/view/photos_screen.dart frontend/lib/profile/view/avatar_generation_screen.dart frontend/lib/profile/viewmodel frontend/test/profile
git commit -m "📸 feat(slice2): 사진 업로드·아바타 생성 화면"
```

### Task A5: 외모 타입(04-4) · 성향 설문(05-01~11) · 이상형 조건(06-1)

**Files:**
- Create: `frontend/lib/profile/view/appearance_type_screen.dart`
- Create: `frontend/lib/profile/view/survey_screen.dart`(9축 슬라이더 + 종교 + 흡연, 11 화면을 `PageView` 하나로)
- Create: `frontend/lib/profile/view/ideal_conditions_screen.dart`
- Create: `frontend/lib/profile/viewmodel/appearance_type_view_model.dart`
- Create: `frontend/lib/profile/viewmodel/survey_view_model.dart`
- Create: `frontend/lib/profile/viewmodel/ideal_conditions_view_model.dart`
- Test: `frontend/test/profile/viewmodel/survey_view_model_test.dart`

**Interfaces:**
- Consumes: `POST /profile-onboarding/appearance-type`·`/survey`·`/ideal-conditions`(Task B9)

이 세 화면은 전부 Task A3 의 `_copyWith`+`Notifier` 패턴을 반복하는 "여러 선택지 중 고르고 다음" 형태라 새
아키텍처가 필요 없다. 화면별 핵심만 적는다:

- [ ] **Step 1: `appearance_type_screen.dart`** — `animal-type-picker`·`impression-picker` 각 단일 선택
  (`ChoiceChip` 그리드), 둘 다 골라야 "다음" 활성화.

- [ ] **Step 2: `survey_screen.dart`** — `PageView`(9페이지, 축마다 1개) + 마지막에 종교 선택(`ChoiceChip` 4개)
  + 흡연 토글(`Switch`) 페이지 2개를 이어붙여 총 11페이지. 슬라이더는 `Slider(value: ..., divisions: 4, min: -1,
  max: 1)`(5단계 -1/-0.5/0/0.5/1, Material 기본 위젯). 실패하는 테스트부터 작성:

```dart
test('9축을 전부 답하고 종교·흡연을 고르면 제출 가능하다', () {
  final vm = container.read(surveyViewModelProvider.notifier);
  for (var axis = 1; axis <= 9; axis++) {
    vm.answer(axis, 0.5);
  }
  vm.changeReligion(Religion.none);
  vm.changeIsSmoker(false);
  final state = container.read(surveyViewModelProvider);
  expect(state.canSubmit, isTrue);
});
```

- [ ] **Step 3: `ideal_conditions_screen.dart`** — `RangeSlider`(나이·키 각각, "상관없어요" 체크 시 비활성 +
  전송 값 null), `mbti-toggle`(8극 각각 `FilterChip` on/off), `animal-type-picker`/`impression-picker` 다중
  선택(최대 3, Task A2 의 토글 카운트 제한 로직 재사용).

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd frontend && flutter test test/profile/`

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/profile/view/appearance_type_screen.dart frontend/lib/profile/view/survey_screen.dart frontend/lib/profile/view/ideal_conditions_screen.dart frontend/lib/profile/viewmodel frontend/test/profile
git commit -m "🎚️ feat(slice2): 외모 타입·성향 설문·이상형 조건 화면"
```

### Task A6: 이런 사람이 좋아요(06-2a) · 자기소개 AI 초안(06-2b) · 자기소개 저장(06-3)

**Files:**
- Create: `frontend/lib/profile/view/ideal_note_screen.dart`
- Create: `frontend/lib/profile/view/bio_draft_loading_screen.dart`
- Create: `frontend/lib/profile/view/bio_screen.dart`
- Create: `frontend/lib/profile/viewmodel/ideal_note_view_model.dart`
- Create: `frontend/lib/profile/viewmodel/bio_view_model.dart`
- Test: `frontend/test/profile/viewmodel/bio_view_model_test.dart`

**Interfaces:**
- Consumes: `POST /profile-onboarding/ideal-note`·`/bio-draft`·`/bio`(Task B9)

- [ ] **Step 1: `ideal_note_screen.dart`** — 자유 텍스트 1개, 상단 "건너뛰기"(`button-text`) + 하단
  "다음"(`button-primary`). 건너뛰어도 서버에 빈 값으로 저장해 `ideal_note_seen=true` 를 만든다(다시 안 보여줌).

- [ ] **Step 2: 실패하는 테스트 작성(`bio_view_model_test.dart`)**

```dart
test('초안 생성 화면 진입 시 자동으로 draft API 를 부르고 결과를 06-3 입력값으로 채운다', () async {
  when(() => mockRepository.generateBioDraft())
      .thenAnswer((_) async => const Result.success('안녕하세요! 활발한 성격이에요.'));
  final vm = container.read(bioViewModelProvider.notifier);
  await vm.loadDraft();
  final state = container.read(bioViewModelProvider);
  expect(state.bio, '안녕하세요! 활발한 성격이에요.');
});

test('생성 실패하면 빈 값으로 06-3 에 진입한다("직접 쓸게요")', () async {
  when(() => mockRepository.generateBioDraft())
      .thenAnswer((_) async => const Result.failure(UnknownFailure()));
  final vm = container.read(bioViewModelProvider.notifier);
  await vm.loadDraft();
  final state = container.read(bioViewModelProvider);
  expect(state.bio, '');
});
```

- [ ] **Step 3: 테스트 실행해 실패 확인**

Run: `cd frontend && flutter test test/profile/viewmodel/bio_view_model_test.dart`

- [ ] **Step 4: 구현**

`bio_draft_loading_screen.dart` 는 좌상단 뒤로가기만 있고 제목·진행 점이 없다(§13-70). 진입 즉시
`BioViewModel.loadDraft()` 를 부르고, 성공·실패 어느 쪽이든 06-3(`bio_screen.dart`)으로 이동해 그 결과값을
`TextField` 의 실제 입력값(placeholder 아님, §13-71)으로 채운다. "다시 만들기" 버튼은 만들지 않는다
(2026-09-13 결정). `bio_screen.dart` 제출 시 `POST /profile-onboarding/bio` 호출 → 성공하면
`next-step` 이 `complete` 가 되어 `AuthRedirect` 가 홈으로 보낸다.

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd frontend && flutter test test/profile/`

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/profile/view/ideal_note_screen.dart frontend/lib/profile/view/bio_draft_loading_screen.dart frontend/lib/profile/view/bio_screen.dart frontend/lib/profile/viewmodel frontend/test/profile
git commit -m "💬 feat(slice2): 이런 사람이 좋아요·자기소개 AI 초안·자기소개 화면"
```

### Task A7: 라우터 배선 마무리

**Files:**
- Modify: `frontend/lib/core/router/app_router.dart`

**Interfaces:**
- Consumes: Task A1~A6 전체 화면
- Produces: 없음(배선)

- [ ] **Step 1: `app_router.dart` 에 11개 `GoRoute` 추가**

`AppRoutes` 의 각 온보딩 상수를 `GoRoute(path: ..., builder: ...)` 로 등록한다. 기존 `studentVerification`·
`schoolInfo` 라우트 등록부 바로 아래에 순서대로 이어붙인다(패턴 반복, 새 설계 없음).

- [ ] **Step 2: 수동 확인**

Run: `cd frontend && flutter run` 뒤 테스트 계정으로 3c(학과·학번) 통과까지 진행해, 04-1부터 06-3까지
순서대로 넘어가는지, 앱을 완전히 껐다 켜도 중간 화면부터 다시 시작하는지 확인한다.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/core/router/app_router.dart
git commit -m "🧭 feat(slice2): 온보딩 화면 라우팅 배선"
```

### Task A8: `RealName` 최소 2자 검사(분석담당 리뷰 반영)

**Files:**
- Modify: `frontend/lib/auth/model/real_name.dart`
- Test: `frontend/test/auth/model/real_name_test.dart`

**Interfaces:**
- Consumes: 없음(순수 값 객체)
- Produces: 없음 — 기존 `RealName.tryParse(String) -> RealName?` 시그니처 그대로, 검증 규칙만 강화한다.

조각 1b 리뷰(2026-09-20, 분석담당 제안1)에서 백엔드 `student_verification/schemas.py`·`router.py` 가
`Form(min_length=2, max_length=30)`으로 이미 고쳤지만 프론트 값 객체는 상한(30자)만 보고 하한이 없었다 —
1글자 실명은 학생증 대조를 사실상 무력화한다. 서버가 신뢰 경계이므로 이 수정이 없어도 보안엔 문제 없지만,
사용자가 1글자를 입력하고도 화면상 오류 없이 제출 버튼을 누를 수 있는 건 UX 결함이다(spec §13 백로그 41-⑤).

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
// real_name_test.dart 에 추가
test('1자면 null', () {
  expect(RealName.tryParse('김'), isNull);
});

test('2자면 통과', () {
  expect(RealName.tryParse('김가')!.toRequestValue(), '김가');
});
```

- [ ] **Step 2: 테스트 실행해 실패 확인**

Run: `cd frontend && flutter test test/auth/model/real_name_test.dart`
Expected: FAIL — `김` 이 `RealName`으로 파싱됨(현재는 `isEmpty` 만 본다)

- [ ] **Step 3: 구현**

```dart
// real_name.dart — tryParse 안의 조건문만 수정
static RealName? tryParse(String raw) {
  final normalized = raw.trim();
  // 서버 student_verification/schemas.py·router.py 의 Form(min_length=2, max_length=30) 과 하한·상한을 맞춘다
  // (2026-09-20 분석담당 리뷰 제안1 — 1글자 실명은 OCR 부분문자열 대조를 사실상 무력화한다).
  if (normalized.length < 2 || normalized.length > 30) {
    return null;
  }
  return RealName._(normalized);
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd frontend && flutter test test/auth/model/real_name_test.dart`
Expected: PASS — 기존 3개 + 새 2개 = 5개

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/auth/model/real_name.dart frontend/test/auth/model/real_name_test.dart
git commit -m "✅ feat(slice2): RealName 최소 2자 검사(서버와 동일 규칙)"
```

---

## 실행 순서·보류 항목 요약

1. **Part C 부터** — 파일만 작성, 커밋, draft PR. 클라우드 적용 금지.
2. **Part B** — Task B2/B4 는 각각 Task C2/C5 마이그레이션 파일에 RPC 함수(`set_phone_number`·`grant_hearts`)를
   사후 추가해야 한다 — Part C 커밋 뒤에 와서 보강하는 구조다. 태그 라벨(Task B3)은 erd 세션이 2026-09-20
   확정해 이미 채워져 있어 더는 순서 제약이 없다.
3. **Part A** — Task A8(RealName 최소 2자)은 다른 태스크와 독립적이라 아무 때나 끼워 넣어도 된다.
4. 계획서 전체 커밋 뒤 draft PR을 올리고, 새 의존성 표(`openai`)를 대장에게 별도 보고한다. 코드 착수는 사용자
   승인 후.
