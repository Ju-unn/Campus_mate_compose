# 조각 3: 매칭 점수 · 벡터화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **실행 순서는 Part C(Supabase) → Part B(FastAPI) 다.** 조각 2와 같은 순서이고, **Part A(Flutter)는 이번에
> 없다**(아래 "Part A" 절에 이유). **Part C 는 파일 작성까지만 하고 클라우드 적용은 하지 않는다**
> (`[[supabase-apply-gate]]` — ERD 그림 · 사용자 검토 · 사용자 승인 후 별도 supabase 세션이 적용한다).

**Goal:** 온보딩을 마친 사용자의 성향 설문 · "나는"/"원해" 문장을 벡터로 만들어 저장하고, 두 사람 사이의
최종점수(설계 §6.7)를 계산해 **하드 필터를 통과한 후보를 점수 내림차순으로 돌려주는 함수와 엔드포인트**까지
만든다. 카드 지급 · 수락 · 알림은 조각 4다.

**Architecture:** 점수는 두 층으로 나눈다. **Postgres 함수 `match_candidates(owner)`** 가 하드 필터 +
집합 · 벡터 연산(성향점수 L2 · 태그점수 자카드 · 문장유사도 코사인)까지 한 SQL 안에서 끝내고(설계 §6.8),
**FastAPI `scoring.py`** 가 그 결과에 감점 계수(MBTI · 키 · 나이 · 흡연 · 종교 · 활동성)를 곱해 정렬한다.
계수는 분기가 많은 규칙이라 순수 파이썬 함수로 두면 표(설계 §6.4 판정 예시)를 그대로 단위 테스트로 옮길 수
있고, 데이터를 줄이는 무거운 일은 DB 가 한다. 벡터 생성은 새 백엔드 패키지 `backend/app/matching/` 안의
`sentences.py`(문장 템플릿, LLM 아님) · `embeddings.py`(OpenAI 임베딩) · `survey_vector.py`(8축 가중치)가
나눠 맡고, 온보딩 라우터의 저장 지점에서 **동기로 즉시 재생성**한다(§13 미결8 해결안 A).

**Tech Stack:** Postgres 17 + pgvector(`extensions.vector`, 조각 0에서 이미 켬) + FastAPI + httpx(PostgREST
직접 호출) + 기존 `openai` Python SDK(`text-embedding-3-small`, `dimensions=512`). **새 의존성 없음.**

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §6 전체(§6.1~§6.9),
`docs/ERD.md` §3(`profile_vectors`) · §2(권한 표), `frontend/docs/DESIGN.md` §8.5(라벨 문구)

## 새 의존성

| 구분 | 패키지 | 용도 | 근거 |
| --- | --- | --- | --- |
| 백엔드 | 없음 — 기존 `openai` 재사용 | `text-embedding-3-small` 임베딩 | 조각 2에서 이미 승인된 SDK. `client.embeddings.create` 호출만 추가 |
| 백엔드 | 없음 — 기존 `pgvector` 확장 재사용 | `vector(8)` · `vector(512)` 컬럼, `<->` · `<=>` 연산 | 조각 0 첫 마이그레이션에서 `extensions` 스키마에 이미 켬 |
| 백엔드 | 없음 — 자카드는 SQL 내장 배열 연산 | 태그점수 | `unnest` + `intersect`로 충분(YAGNI, `intarray` 확장 불필요) |

**이 표 밖의 새 의존성이 실행 중 필요해지면 코드 작성 전에 대장에게 보고한다**(사용자 승인 필요).

## Global Constraints

- **확정된 공식은 아래 "확정 전제"가 전부다.** 실행 중 다시 묻지 않는다. 설계 §6 과 다른 점이 보이면
  코드를 고치기 전에 대장에게 차이만 보고한다.
- **쓰기는 전부 FastAPI 가 `service_role` 로 한다.** 클라이언트(`authenticated`)에 `profile_vectors`
  권한 · 정책을 하나도 주지 않는다(`docs/ERD.md` §2 — `profile_vectors` = "RLS 정책 없음, FastAPI 전용").
- **새 테이블은 RLS 를 켜고, `revoke all ... from anon, authenticated, service_role` 뒤 필요한 것만 grant**
  한다(`docs/SUPABASE.md` §5).
- **새 함수는 `security definer` 를 쓰지 않고, `set search_path = ''` 를 반드시 건다**(마이그레이션
  `20260920061752` 에서 advisor WARN 으로 지적받은 항목 — 처음부터 붙여 같은 경고를 만들지 않는다).
  본문의 모든 식별자는 `public.` · `extensions.` 로 수식한다.
- **마이그레이션 파일명은 `supabase migration new <name>` 으로만 만든다**(`docs/SUPABASE.md` §4).
  **이미 클라우드에 적용된 마이그레이션 파일은 절대 수정하지 않는다** — 새 파일만 추가한다.
- **클라우드 적용 금지.** Part C 는 파일 작성 + 로컬 스택(`supabase db reset`, `supabase test db`)까지다.
- **커밋 · PR 에 AI/도구 표식을 넣지 않는다**(`[[feedback-no-tool-attribution]]`). 커밋 형식은
  `<이모지> <타입>(<scope>): <한국어 요약>`, `git add -A` 금지.
- **임베딩 실패가 사용자의 글을 잃게 하면 안 된다.** 항상 "본문 저장 → 벡터 재생성" 순서이고, 벡터 생성이
  실패해도 저장 응답은 200 이다(로그만 남긴다). 활성화 시점에 전체 재생성이 다시 돌아 빈 벡터를 메운다.
- **`openai` 클라이언트는 `max_retries=0`** 으로 만든다(조각 2 사용자 결정, `avatars.py` 와 동일).

## 확정 전제 (2026-09-19 사용자 최종 확정 — 다시 묻지 않는다)

```
성향점수   = 1 − ( L2거리(A.self_survey, B.self_survey) ÷ 최대가능거리 )     (0~1, pgvector `<->`)
태그점수   = 평균[ 자카드(A.관심사, B.관심사),
                  평균( 자카드(A.나의특징, B.이상형특징), 자카드(B.나의특징, A.이상형특징) ) ]
문장유사도 = 평균[ cos(A.원해, B.나는), cos(B.원해, A.나는) ]

최종점수 = (0.3 × 성향점수 + 0.2 × 태그점수 + 0.5 × 문장유사도)
           × MBTI계수(0.60~1.00) × 키계수(0.70~1.00) × 나이계수(0.70~1.00)
           × 흡연계수(불일치 0.5) × 종교계수(불일치 0.8) × 활동성계수
```

- **성향점수**: `self_survey` 8축(낯가림=axis 2 제외) pgvector L2. **낯가림 보너스 없음** —
  `shyness_score` 는 저장만 한다.
- **문장 재료**: "나는" = 학과 · 계열 + MBTI + 본인 얼굴상 · 인상 + 자기소개. "원해" = 선호 얼굴상 · 인상 +
  `ideal_note`(빈 문자열이면 그 부분 생략). **문장에 넣지 않는 것**: 설문 · 태그 · 나이 · 키 · 흡연 · 종교 ·
  닉네임 · 사진 · 학교 · 성별. MBTI 만 예외로 문장에도 계수에도 들어간다.
- **활동성계수**: 0~3일 1.0 / 4~7일 0.7 / 8~14일 0.4 / **15일 이상은 계수가 아니라 하드 필터로 제외**.
- **하드 필터**: 성별(반대) · 지역그룹 · 차단 · 15일 이상 미접속 · 일시중지.
- **재생성**: 자기소개 · 얼굴상 · `ideal_note` · 설문 저장 시 **즉시**(동기).
- **하지 않는 것**: LLM 재정렬, 수락 · 거절 학습, "원해" AI 초안, HNSW 인덱스(설계 §6.8 — 지금 붙이면
  정확도만 손해).

**문장 예시(김철수, 사용자 제공 — 설계 §6.7 · DESIGN.md §9 와 같은 예시)**

> **[나는]** "나는 컴퓨터공학과, 공대 계열 학생이다. MBTI는 ENFP다. 얼굴은 강아지상이고 부드러운 인상이다.
> 주말마다 산 타고 내려와서 맛집 찾아다니는 게 낙이에요. 등산은 혼자보다 같이 가는 걸 좋아해서 같이 갈 사람
> 있으면 초보 코스부터 천천히 알려드릴 수 있어요. 계획 짜는 걸 좋아해서 여행 가면 제가 일정 다 짭니다. 카페
> 가서 보드게임 하는 거 좋아하고, 영화는 장르 안 가리고 다 봐요. 술은 거의 안 마시고, 술자리보다는 낮에
> 만나서 뭐 하는 걸 더 좋아해요."
>
> **[원해]** "고양이상이나 여우상, 시크한 인상이 좋다. 말이 잘 통하는 사람이 제일 좋아요. 자기 일 열심히
> 하고 하고 싶은 게 확실한 사람한테 끌려요. 같이 새로운 데 다니는 거 좋아하면 더 좋고, 술 안 마셔도 괜찮은
> 사람이었으면 해요. 솔직하게 말하는 편이면 좋아요."

앞 3문장(학과 · MBTI · 얼굴상)은 템플릿이 고정 생성하고, 그 뒤는 사용자가 쓴 원문을 그대로 이어붙인다.
예시의 "부드러운 인상"은 `impression_type = kind`(화면 라벨 "선한상")의 문장형 표현이다 — Task B1 의
`IMPRESSION_PHRASES` 가 화면 라벨과 별개로 문장용 표현을 갖는 이유다.

## 실행 전 확인 사항 (코드 쓰기 전에 대장에게 보고 — 차이만)

1. **8축 가중치가 어디에도 정해져 있지 않다.** 설계 §6.2 는 "축별 가중치를 사전 곱셈"한다고만 쓰고 값은
   "조각 3 · 4 에서 산출"로 남겨 뒀다. 이 계획서는 **전 축 1.0(균등)** 으로 시작하고, 값을 `AXIS_WEIGHTS`
   상수 한 곳(Task B3)에 모아 나중에 한 줄 수정으로 조정할 수 있게 한다. 최대가능거리도 상수에서 계산한다.
2. **`major_field`(계열)를 입력받는 화면이 아직 없다.** 조각 1b `school-info` 는 학과 자유입력(`major`)만
   받는다. "나는" 문장은 계열이 `null` 이면 그 부분을 빼고 만든다("나는 컴퓨터공학과 학생이다.").
3. **`blocks`(조각 6) · `matching_paused`(조각 4) 가 아직 없다.** 하드 필터 두 개는 스키마가 생기는
   조각에서 `match_candidates` 에 추가한다 — 추가할 SQL 조각을 Task C2 에 주석으로 박아 둔다. 지금은 차단도
   일시중지도 만들 수단 자체가 없어 실제 동작 차이가 없다.
4. **태그를 고쳐도 임베딩을 다시 만들 필요가 없다.** 태그는 문장 재료가 아니라 자카드로만 쓰이고(설계
   §6.3), 자카드는 조회 시점에 계산한다. 메모리의 "자기소개 · 태그 · 얼굴상 · 원해 글 수정 시 즉시 재생성"
   중 태그만 무의미한 재생성이라 Task B4 의 호출 지점에서 뺀다.

---

## Part C: Supabase 마이그레이션 (파일 작성 + 로컬 검증까지, 클라우드 적용 금지)

### Task C1: `profile_vectors` 테이블

**Files:**
- Create: `supabase/migrations/<timestamp>_create_profile_vectors.sql` (`supabase migration new create_profile_vectors`)

**Interfaces:**
- Produces: 테이블 `public.profile_vectors(profile_id uuid pk, self_survey extensions.vector(8),
  shyness_score numeric, self_embedding extensions.vector(512), want_embedding extensions.vector(512),
  updated_at timestamptz)` — Task C2 · B4 가 이 이름을 그대로 쓴다.

**ERD 와의 차이(의도적)**: `docs/ERD.md` §3 그림은 `self_text vector(512)` 한 개만 그려 뒀다(2026-09-13
초안). 2026-09-19 공식 확정으로 `self_text` 는 폐지되고 **"나는"(`self_embedding`) · "원해"
(`want_embedding`) 두 개**가 됐다(설계 §6.3). ERD 그림 갱신은 erd 세션 몫으로 대장에게 보고한다.

- [ ] **Step 1: 마이그레이션 파일 생성**

```bash
cd supabase && supabase migration new create_profile_vectors
```

- [ ] **Step 2: 테이블 · RLS · 권한 작성**

```sql
-- 조각 3: 매칭 벡터 3종을 한 행에 둔다(설계 §6.3, ERD §3 "profile_vectors 는 1:1").
-- self_text(구 bio 임베딩)는 2026-09-19 공식 확정으로 폐지됐고 "나는"/"원해" 두 개로 나뉘었다.
-- 벡터 타입은 extensions 스키마에 있다(조각 0 create extension ... with schema extensions).
create table public.profile_vectors (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  -- 설문 8축(낯가림=axis 2 제외), 축별 가중치를 FastAPI 가 곱한 뒤 저장한다. 거리는 L2(<->).
  self_survey extensions.vector(8),
  -- 낯가림 원값(-1 -0.5 0 0.5 1). 2026-09-19부터 점수에 쓰지 않고 저장만 한다.
  shyness_score numeric,
  -- "나는"/"원해" 문장의 text-embedding-3-small 임베딩(dimensions=512). 거리는 코사인(<=>).
  self_embedding extensions.vector(512),
  want_embedding extensions.vector(512),
  updated_at timestamptz not null default now(),

  constraint profile_vectors_shyness_scale check (
    shyness_score is null or shyness_score in (-1, -0.5, 0, 0.5, 1)
  )
);

comment on table public.profile_vectors is
  '매칭 벡터 3종(설계 §6.3). FastAPI 전용 — 클라이언트 권한 없음';

alter table public.profile_vectors enable row level security;
-- 정책을 하나도 만들지 않는다 = authenticated 는 RLS 로 전부 막힌다(ERD §2 "정책 없음").

revoke all on table public.profile_vectors from anon, authenticated, service_role;
grant select, insert, update, delete on table public.profile_vectors to service_role;
```

- [ ] **Step 3: 로컬 스택에서 적용 확인**

Run: `cd supabase && supabase db reset`
Expected: 오류 없이 모든 마이그레이션 적용. `vector(512)` 컬럼 생성 실패("type vector does not exist")가
나면 `extensions.` 수식이 빠진 것이다.

- [ ] **Step 4: 커밋**

```bash
git add supabase/migrations/<timestamp>_create_profile_vectors.sql
git commit -m "🗃️ db(slice3): 매칭 벡터 테이블 profile_vectors 추가"
```

---

### Task C2: 자카드 함수 + 후보 조회 함수 `match_candidates`

**Files:**
- Create: `supabase/migrations/<timestamp>_create_match_candidates.sql`

**Interfaces:**
- Consumes: Task C1 의 `public.profile_vectors`
- Produces: `public.jaccard(text[], text[]) returns numeric`,
  `public.match_candidates(p_owner uuid) returns table (...)` — Part B `MatchingRepository` 가 PostgREST
  RPC(`POST /rest/v1/rpc/match_candidates`, body `{"p_owner": "..."}`)로 부른다.

- [ ] **Step 1: 마이그레이션 파일 생성**

```bash
cd supabase && supabase migration new create_match_candidates
```

- [ ] **Step 2: 자카드 함수 작성**

```sql
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
```

- [ ] **Step 3: 후보 조회 함수 작성**

```sql
-- 설계 §6.8: 하드 필터와 벡터 연산을 한 SQL 안에서 끝낸다. 감점 계수(MBTI·키·나이·흡연·종교·활동성)는
-- 분기가 많아 FastAPI scoring.py 가 곱한다 — 그래서 여기서는 계수의 재료 컬럼을 같이 돌려준다.
--
-- 최대가능거리 5.657 = 2 × sqrt(8) (8축이 단위 가중치로 정반대인 경우, 설계 §6.2).
--   축별 가중치를 균등 1.0 이 아닌 값으로 바꾸면 이 상수도 같이 바꾼다(FastAPI AXIS_WEIGHTS 와 짝).
-- pgvector `<=>` 는 코사인 "거리"라 유사도는 1 - 거리다.
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
    greatest(0, 1 - (me.self_survey <-> cv.self_survey) / 5.657),
    (
      public.jaccard(me.interest_tags, c.interest_tags)
      + (public.jaccard(me.my_traits, c.ideal_traits) + public.jaccard(c.my_traits, me.ideal_traits)) / 2
    ) / 2,
    greatest(0, (
      (1 - (me.want_embedding <=> cv.self_embedding))
      + (1 - (cv.want_embedding <=> me.self_embedding))
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

revoke all on function public.match_candidates(uuid) from public, anon, authenticated;
grant execute on function public.match_candidates(uuid) to service_role;
revoke all on function public.jaccard(text[], text[]) from public, anon, authenticated;
grant execute on function public.jaccard(text[], text[]) to service_role;
```

**limit 을 두지 않는 이유**: 계수를 곱하기 전 순서로 자르면 계수가 큰 후보(최악 조합 0.047배)가 잘려나갈
수 있다. 초기 코호트는 수천 명이고 설계 §6.8 이 "인덱스 없이 전체 스캔해도 수십 밀리초"라고 적어 뒀으므로
전량을 돌려주고 FastAPI 가 정렬 · 절단한다. 벡터가 수만 개를 넘으면 그때 HNSW 인덱스와 `limit` 을 넣는다.

- [ ] **Step 4: 로컬 스택에서 함수 동작 확인**

Run: `cd supabase && supabase db reset` 후

```bash
supabase db execute --sql "select public.jaccard(array['a','b','c'], array['b','c','d']);"
```

Expected: `0.5` (교집합 2 ÷ 합집합 4)

- [ ] **Step 5: 커밋**

```bash
git add supabase/migrations/<timestamp>_create_match_candidates.sql
git commit -m "🗃️ db(slice3): 자카드·후보 조회 함수 match_candidates 추가"
```

---

### Task C3: pgTAP 회귀 테스트

**Files:**
- Create: `supabase/tests/rls_slice3_test.sql`

**Interfaces:**
- Consumes: Task C1 · C2 의 테이블 · 함수

- [ ] **Step 1: 실패하는 테스트 작성**

`supabase/tests/rls_slice2_test.sql` 의 뼈대(트랜잭션 · `plan(n)` · `finish()` · `rollback`)를 그대로
따른다. 준비 구간도 같은 UUID 관례(`...aa` · `...bb` · 대학 `...01`)를 쓴다.

```sql
-- 조각 3 RLS · 권한 · 점수 함수 검증. 기대값 기준은 docs/ERD.md §2.
-- 로컬 스택에서 `supabase test db` 로 돌린다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- 준비 --------------------------------------------------------------------
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('test.ac.kr', '00000000-0000-0000-0000-000000000001');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'm3-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000bb', 'm3-b@test.ac.kr');

update public.profiles set
  gender = 'male', status = 'active', interest_tags = array['카페가기','등산','영화'],
  my_traits = array['유머러스한','다정한','계획적인'], ideal_traits = array['다정한','활발한','솔직한'],
  height_cm = 180, birth_year = 2002, mbti = 'ENFP', last_active_at = now()
where id = '00000000-0000-0000-0000-0000000000aa';

update public.profiles set
  gender = 'female', status = 'active', interest_tags = array['카페가기','등산','전시회'],
  my_traits = array['다정한','활발한','차분한'], ideal_traits = array['유머러스한','다정한','성실한'],
  height_cm = 165, birth_year = 2003, mbti = 'ISFJ', last_active_at = now()
where id = '00000000-0000-0000-0000-0000000000bb';

insert into public.profile_vectors (profile_id, self_survey, shyness_score, self_embedding, want_embedding)
values
  ('00000000-0000-0000-0000-0000000000aa',
   '[1,0,0,0,0,0,0,0]', 0.5,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector),
  ('00000000-0000-0000-0000-0000000000bb',
   '[1,0,0,0,0,0,0,0]', -0.5,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
   ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector);

-- 1. 구조 · 제약 ------------------------------------------------------------
select has_table('public', 'profile_vectors', 'profile_vectors 테이블이 있다');
select col_type_is('public', 'profile_vectors', 'self_survey', 'extensions.vector(8)',
  'self_survey 는 8차원 벡터다');
select col_type_is('public', 'profile_vectors', 'self_embedding', 'extensions.vector(512)',
  '"나는" 임베딩은 512차원이다');
select col_type_is('public', 'profile_vectors', 'want_embedding', 'extensions.vector(512)',
  '"원해" 임베딩은 512차원이다');
select throws_ok(
  $$update public.profile_vectors set shyness_score = 0.3
     where profile_id = '00000000-0000-0000-0000-0000000000aa'$$,
  '23514', null, 'shyness_score 는 5점 척도 값만 받는다'
);

-- 2. RLS · 권한 -------------------------------------------------------------
select is(
  (select relrowsecurity from pg_class where oid = 'public.profile_vectors'::regclass),
  true, 'profile_vectors 는 RLS 가 켜져 있다'
);
select is(
  (select count(*) from pg_policies where tablename = 'profile_vectors'),
  0::bigint, 'profile_vectors 에는 정책이 하나도 없다(FastAPI 전용)'
);
select ok(
  not has_table_privilege('authenticated', 'public.profile_vectors', 'select'),
  'authenticated 는 profile_vectors 를 읽지 못한다'
);
select ok(
  has_table_privilege('service_role', 'public.profile_vectors', 'select, insert, update, delete'),
  'service_role 만 profile_vectors 를 읽고 쓴다'
);
select ok(
  not has_function_privilege('authenticated', 'public.match_candidates(uuid)', 'execute'),
  'authenticated 는 match_candidates 를 부르지 못한다'
);

-- 3. 점수 계산 ---------------------------------------------------------------
select is(public.jaccard(array['a','b','c'], array['b','c','d']), 0.5::numeric,
  '자카드는 교집합 ÷ 합집합이다');
select is(
  (select round(tag_score, 4) from public.match_candidates('00000000-0000-0000-0000-0000000000aa')),
  round(((2::numeric/4) + ((1::numeric/5) + (2::numeric/4)) / 2) / 2, 4),
  '태그점수 = 평균[관심사 자카드, 양방향 특징 자카드의 평균]'
);

select * from finish();
rollback;
```

- [ ] **Step 2: 테스트 실행해서 통과 확인**

Run: `cd supabase && supabase test db`
Expected: `rls_slice3_test.sql .. ok` (12/12). 조각 0 · 1 · 2 테스트도 함께 통과해야 한다 — 새 테이블이
"모든 테이블에 RLS" · 전 테이블 ACL 표를 보는 `rls_slice0_test.sql` 기대값을 깨지 않는지 같이 확인한다.
깨지면 조각 0 테스트의 기대 테이블 목록에 `profile_vectors` 를 추가한다(같은 커밋).

- [ ] **Step 3: 커밋**

```bash
git add supabase/tests/rls_slice3_test.sql
git commit -m "✅ test(slice3): profile_vectors 권한·점수 함수 pgTAP 추가"
```

---

## Part B: FastAPI (`backend/app/matching/`)

### Task B1: "나는"/"원해" 문장 템플릿

**Files:**
- Create: `backend/app/matching/__init__.py` (빈 파일)
- Create: `backend/app/matching/sentences.py`
- Test: `backend/tests/matching/test_sentences.py`

**Interfaces:**
- Produces:
  - `self_sentence(profile: dict) -> str` — 키 `major`, `major_field`, `mbti`, `animal_type`,
    `impression_type`, `bio`
  - `want_sentence(profile: dict) -> str` — 키 `preferred_animal_types`(list[str]),
    `preferred_impression_types`(list[str]), `ideal_note`
  - 두 함수 모두 재료가 전부 비면 `""` 를 돌려준다(Task B4 가 그때 임베딩을 만들지 않는다).

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from app.matching.sentences import self_sentence, want_sentence


def test_self_sentence_follows_the_kim_cheolsu_example():
    """설계 §6.7 의 예시 앞 3문장은 템플릿이 만들고, 자기소개 원문은 그대로 이어붙인다."""
    sentence = self_sentence({
        "major": "컴퓨터공학과", "major_field": "engineering", "mbti": "ENFP",
        "animal_type": "dog", "impression_type": "kind",
        "bio": "주말마다 산 타고 내려와서 맛집 찾아다니는 게 낙이에요.",
    })

    assert sentence == (
        "나는 컴퓨터공학과, 공대 계열 학생이다. MBTI는 ENFP다. "
        "얼굴은 강아지상이고 선한 인상이다. "
        "주말마다 산 타고 내려와서 맛집 찾아다니는 게 낙이에요."
    )


def test_self_sentence_skips_missing_pieces():
    """계열 입력 화면이 아직 없고 MBTI 는 '모름'이 허용된다 — 빈 자리는 문장에서 통째로 뺀다."""
    sentence = self_sentence({
        "major": "컴퓨터공학과", "major_field": None, "mbti": None,
        "animal_type": "dog", "impression_type": "kind", "bio": "",
    })

    assert sentence == "나는 컴퓨터공학과 학생이다. 얼굴은 강아지상이고 선한 인상이다."


def test_want_sentence_joins_animal_types_with_korean_particle():
    sentence = want_sentence({
        "preferred_animal_types": ["cat", "fox"],
        "preferred_impression_types": ["chic"],
        "ideal_note": "말이 잘 통하는 사람이 제일 좋아요.",
    })

    assert sentence == "고양이상이나 여우상, 시크한 인상이 좋다. 말이 잘 통하는 사람이 제일 좋아요."


def test_want_sentence_is_empty_when_nothing_was_entered():
    assert want_sentence(
        {"preferred_animal_types": [], "preferred_impression_types": [], "ideal_note": ""}
    ) == ""
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && python -m pytest tests/matching/test_sentences.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.matching'`

- [ ] **Step 3: 구현**

```python
"""매칭 문장 2종을 서버 템플릿으로 조립한다(설계 §6.3·§6.7 — LLM 을 쓰지 않는다).

앞부분(학과·계열·MBTI·얼굴상)만 템플릿이 만들고, 자기소개와 "이런 사람이 좋아요" 글은 사용자가 쓴
원문을 그대로 이어붙인다. 재료가 없는 자리는 문장째로 뺀다 — 빈칸이 들어간 문장을 임베딩하면
"MBTI는 다" 같은 잡음이 벡터에 섞인다."""

# 화면 라벨(frontend profile_enums.dart)과 같은 문구다.
ANIMAL_LABELS = {
    "dog": "강아지상", "cat": "고양이상", "fox": "여우상", "bear": "곰상",
    "rabbit": "토끼상", "deer": "사슴상", "wolf": "늑대상", "hamster": "햄스터상",
}

# 인상은 화면 라벨("선한상")을 그대로 쓰면 "선한상 인상이다" 가 돼 어색하다 — 문장용 표현을 따로 둔다
# (설계 §6.7 예시의 "부드러운 인상"이 이 자리다).
IMPRESSION_PHRASES = {
    "arab": "이국적인", "tofu": "부드러운", "kind": "선한", "chic": "시크한", "innocent": "청순한",
}

MAJOR_FIELD_LABELS = {
    "humanities": "인문", "social": "사회", "business": "상경", "engineering": "공대",
    "natural_science": "자연과학", "medical": "의약", "arts_sports": "예체능", "education": "교육",
}


def _has_final_consonant(word: str) -> bool:
    """마지막 글자에 받침이 있으면 "이나", 없으면 "나" 를 붙인다(한글 음절 = 0xAC00 + 28 × n + 받침)."""
    last = word[-1]
    return "가" <= last <= "힣" and (ord(last) - 0xAC00) % 28 != 0


def _join_or(words: list[str]) -> str:
    joined = words[0]
    for word in words[1:]:
        joined += ("이나 " if _has_final_consonant(joined) else "나 ") + word
    return joined


def self_sentence(profile: dict) -> str:
    parts: list[str] = []

    major, field = profile.get("major"), MAJOR_FIELD_LABELS.get(profile.get("major_field") or "")
    if major and field:
        parts.append(f"나는 {major}, {field} 계열 학생이다.")
    elif major:
        parts.append(f"나는 {major} 학생이다.")

    if profile.get("mbti"):
        parts.append(f"MBTI는 {profile['mbti']}다.")

    animal = ANIMAL_LABELS.get(profile.get("animal_type") or "")
    impression = IMPRESSION_PHRASES.get(profile.get("impression_type") or "")
    if animal and impression:
        parts.append(f"얼굴은 {animal}이고 {impression} 인상이다.")

    if (profile.get("bio") or "").strip():
        parts.append(profile["bio"].strip())

    return " ".join(parts)


def want_sentence(profile: dict) -> str:
    parts: list[str] = []

    animals = [ANIMAL_LABELS[a] for a in profile.get("preferred_animal_types") or [] if a in ANIMAL_LABELS]
    impressions = [
        IMPRESSION_PHRASES[i] for i in profile.get("preferred_impression_types") or []
        if i in IMPRESSION_PHRASES
    ]
    wanted = []
    if animals:
        wanted.append(_join_or(animals))
    if impressions:
        wanted.append(f"{_join_or(impressions)} 인상")
    if wanted:
        parts.append(f"{', '.join(wanted)}이 좋다.")

    if (profile.get("ideal_note") or "").strip():
        parts.append(profile["ideal_note"].strip())

    return " ".join(parts)
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd backend && python -m pytest tests/matching/test_sentences.py -v`
Expected: 4 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/app/matching/__init__.py backend/app/matching/sentences.py backend/tests/matching/test_sentences.py
git commit -m "✨ feat(matching): 나는·원해 문장 서버 템플릿 추가"
```

---

### Task B2: 임베딩 호출

**Files:**
- Create: `backend/app/matching/embeddings.py`
- Test: `backend/tests/matching/test_embeddings.py`

**Interfaces:**
- Consumes: 기존 `openai.AsyncOpenAI` (조각 2 `avatars.get_openai_client` 와 같은 방식으로 주입받는다)
- Produces: `async embed(openai_client, texts: list[str]) -> list[list[float]]`,
  상수 `EMBEDDING_MODEL = "text-embedding-3-small"`, `EMBEDDING_DIMENSIONS = 512`

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from types import SimpleNamespace
from unittest.mock import AsyncMock

from app.matching.embeddings import EMBEDDING_DIMENSIONS, EMBEDDING_MODEL, embed


async def test_embed_sends_both_sentences_in_one_call():
    """문장 2개를 한 번의 호출로 보낸다 — 호출 수와 지연을 반으로 줄인다."""
    client = AsyncMock()
    client.embeddings.create.return_value = SimpleNamespace(
        data=[SimpleNamespace(embedding=[0.1] * 512), SimpleNamespace(embedding=[0.2] * 512)]
    )

    vectors = await embed(client, ["나는 ...", "원해 ..."])

    client.embeddings.create.assert_awaited_once_with(
        model=EMBEDDING_MODEL, dimensions=EMBEDDING_DIMENSIONS, input=["나는 ...", "원해 ..."]
    )
    assert [len(v) for v in vectors] == [512, 512]


async def test_embed_returns_nothing_for_empty_input():
    """빈 문장은 임베딩하지 않는다 — 의미 없는 벡터에 요금을 내지 않는다."""
    client = AsyncMock()

    assert await embed(client, []) == []
    client.embeddings.create.assert_not_awaited()
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && python -m pytest tests/matching/test_embeddings.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.matching.embeddings'`

- [ ] **Step 3: 구현**

```python
from openai import AsyncOpenAI

# 512차원은 설계 §6.3 표에 확정돼 있다. text-embedding-3-small 은 dimensions 파라미터로 줄여 받을 수 있고,
# 줄여도 상위 차원이 잘리는 게 아니라 정규화된 축소 벡터가 온다(OpenAI 문서).
EMBEDDING_MODEL = "text-embedding-3-small"
EMBEDDING_DIMENSIONS = 512


async def embed(openai_client: AsyncOpenAI, texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    response = await openai_client.embeddings.create(
        model=EMBEDDING_MODEL, dimensions=EMBEDDING_DIMENSIONS, input=texts
    )
    return [item.embedding for item in response.data]
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd backend && python -m pytest tests/matching/test_embeddings.py -v`
Expected: 2 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/app/matching/embeddings.py backend/tests/matching/test_embeddings.py
git commit -m "✨ feat(matching): text-embedding-3-small 임베딩 호출 추가"
```

---

### Task B3: 설문 벡터 (8축 가중치 + 낯가림 분리)

**Files:**
- Create: `backend/app/matching/survey_vector.py`
- Test: `backend/tests/matching/test_survey_vector.py`

**Interfaces:**
- Produces: `AXIS_WEIGHTS: dict[int, float]`, `MAX_SURVEY_DISTANCE: float`,
  `survey_vector(answers: dict[int, float]) -> tuple[list[float], float | None]`
  (8축 가중치 곱한 벡터, 낯가림 원값)

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import math

from app.matching.survey_vector import AXIS_WEIGHTS, MAX_SURVEY_DISTANCE, survey_vector


def test_survey_vector_drops_shyness_and_applies_weights():
    """axis 2(낯가림)는 벡터에서 빠지고 원값만 따로 돌려준다(설계 §6.2)."""
    answers = {1: 1.0, 2: -0.5, 3: 0.5, 4: 0, 5: 0, 6: 0, 7: 0, 8: 0, 9: 1.0}

    vector, shyness = survey_vector(answers)

    assert len(vector) == 8
    assert shyness == -0.5
    assert vector[0] == 1.0 * AXIS_WEIGHTS[1]
    assert vector[7] == 1.0 * AXIS_WEIGHTS[9]


def test_survey_vector_treats_unanswered_axis_as_neutral():
    """온보딩은 9축을 다 받지만, 한 축이 비어도 500 대신 중립 0 으로 본다."""
    vector, shyness = survey_vector({1: 1.0})

    assert vector[1:] == [0.0] * 7
    assert shyness is None


def test_max_distance_matches_the_weights():
    """최대가능거리는 가중치에서 계산한다 — SQL 상수 5.657 과 같아야 한다(설계 §6.2)."""
    expected = 2 * math.sqrt(sum(w * w for a, w in AXIS_WEIGHTS.items() if a != 2))

    assert MAX_SURVEY_DISTANCE == expected
    assert round(MAX_SURVEY_DISTANCE, 3) == 5.657
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && python -m pytest tests/matching/test_survey_vector.py -v`
Expected: FAIL — `ModuleNotFoundError`

- [ ] **Step 3: 구현**

```python
import math

# 설계 §6.2 는 "축별 가중치를 저장 전에 곱한다"까지만 정하고 값은 조각 3·4 로 미뤘다. 지금은 전 축 균등
# 1.0 으로 시작한다 — 실제 데이터를 보고 조정할 때 이 표 한 곳만 고치면 된다.
# 값을 바꾸면 match_candidates SQL 의 상수 5.657 도 MAX_SURVEY_DISTANCE 로 맞춰 바꿔야 한다.
AXIS_WEIGHTS = {1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0, 5: 1.0, 6: 1.0, 7: 1.0, 8: 1.0, 9: 1.0}

SHYNESS_AXIS = 2  # 낯가림. 유유상종이 아니라 다를수록 좋은 축이라 같은 L2 에 넣지 않는다.
_VECTOR_AXES = [axis for axis in sorted(AXIS_WEIGHTS) if axis != SHYNESS_AXIS]

# 각 축이 [-w, +w] 라서 한 축의 최대 차이는 2w, 전체는 그 유클리드 합이다.
MAX_SURVEY_DISTANCE = 2 * math.sqrt(sum(AXIS_WEIGHTS[axis] ** 2 for axis in _VECTOR_AXES))


def survey_vector(answers: dict[int, float]) -> tuple[list[float], float | None]:
    vector = [float(answers.get(axis, 0)) * AXIS_WEIGHTS[axis] for axis in _VECTOR_AXES]
    shyness = answers.get(SHYNESS_AXIS)
    return vector, None if shyness is None else float(shyness)
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd backend && python -m pytest tests/matching/test_survey_vector.py -v`
Expected: 3 passed

- [ ] **Step 5: 커밋**

```bash
git add backend/app/matching/survey_vector.py backend/tests/matching/test_survey_vector.py
git commit -m "✨ feat(matching): 설문 8축 가중치 벡터 변환 추가"
```

---

### Task B4: 벡터 저장 · 재생성 (`MatchingRepository` + `refresh_vectors`)

**Files:**
- Create: `backend/app/matching/repository.py`
- Create: `backend/app/matching/vectors.py`
- Modify: `backend/app/profile_onboarding/router.py` (재생성 호출 지점 5곳 + 활성화 시 전체 재생성)
- Test: `backend/tests/matching/test_vectors.py`

**Interfaces:**
- Consumes: Task B1 `self_sentence`/`want_sentence`, B2 `embed`, B3 `survey_vector`,
  Task C1 테이블, 기존 `ProfileOnboardingRepository._patch_profile` 패턴
- Produces:
  - `MatchingRepository(postgrest_url, service_role_key, client)` with
    `fetch_vector_materials(profile_id) -> dict`, `save_vectors(profile_id, **fields) -> None`,
    `fetch_candidates(profile_id) -> list[dict]`(Task B6 이 쓴다),
    `fetch_owner(profile_id) -> dict`(Task B6 이 쓴다)
  - `async refresh_vectors(repo, openai_client, profile_id) -> None` — 실패해도 예외를 밖으로 던지지 않는다

- [ ] **Step 1: 실패하는 테스트 작성**

```python
import json
from unittest.mock import AsyncMock

import httpx

from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors

PROFILE_ID = "11111111-1111-1111-1111-111111111111"


def _repo(handler) -> MatchingRepository:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return MatchingRepository("https://x.supabase.co/rest/v1", "service-key", client)


def _materials_handler(saved: list[dict]):
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/profiles" in url and request.method == "GET":
            return httpx.Response(200, json=[{
                "major": "컴퓨터공학과", "major_field": None, "mbti": "ENFP",
                "animal_type": "dog", "impression_type": "kind", "bio": "등산 좋아해요.",
                "preferred_animal_types": ["cat"], "preferred_impression_types": ["chic"],
                "ideal_note": "말 잘 통하는 사람이요.",
            }])
        if "/survey_answers" in url:
            return httpx.Response(200, json=[{"axis": 1, "value": 1.0}, {"axis": 2, "value": -0.5}])
        if "/profile_vectors" in url:
            saved.append(json.loads(request.content))
            return httpx.Response(201, json=[])
        return httpx.Response(200, json=[])

    return handler


async def test_refresh_vectors_saves_all_three_vectors():
    saved: list[dict] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.return_value = type("R", (), {"data": [
        type("D", (), {"embedding": [0.1] * 512})(), type("D", (), {"embedding": [0.2] * 512})(),
    ]})()

    await refresh_vectors(_repo(_materials_handler(saved)), openai_client, PROFILE_ID)

    assert len(saved) == 1
    assert len(saved[0]["self_survey"]) == 8
    assert saved[0]["shyness_score"] == -0.5
    assert len(saved[0]["self_embedding"]) == 512
    assert len(saved[0]["want_embedding"]) == 512


async def test_refresh_vectors_swallows_openai_failure():
    """임베딩이 죽어도 사용자의 저장은 이미 끝났다 — 여기서 예외를 올리면 200 이 500 이 된다."""
    saved: list[dict] = []
    openai_client = AsyncMock()
    openai_client.embeddings.create.side_effect = Exception("openai down")

    await refresh_vectors(_repo(_materials_handler(saved)), openai_client, PROFILE_ID)

    assert saved == []
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && python -m pytest tests/matching/test_vectors.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.matching.repository'`

- [ ] **Step 3: `MatchingRepository` 구현**

```python
from uuid import UUID

import httpx

from app.profile_onboarding.repository import _raise_for_status

_MATERIAL_COLUMNS = (
    "major,major_field,mbti,animal_type,impression_type,bio,"
    "preferred_animal_types,preferred_impression_types,ideal_note"
)
_OWNER_COLUMNS = (
    "id,gender,mbti,preferred_mbti_flags,height_cm,preferred_height_min,preferred_height_max,"
    "birth_year,preferred_age_min,preferred_age_max,is_smoker,religion"
)


class MatchingRepository:
    """매칭 벡터·후보 조회를 PostgREST 로 한다(ProfileOnboardingRepository 와 같은 패턴).
    설계 §6.8 의 "카드 생성은 MatchingRepository 인터페이스 뒤에 둔다"가 이 클래스다."""

    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = client

    async def fetch_vector_materials(self, profile_id: UUID | str) -> dict:
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}", "select": _MATERIAL_COLUMNS},
            headers=self._headers,
        )
        _raise_for_status(response)
        rows = response.json()
        profile = rows[0] if rows else {}

        answers_response = await self._client.get(
            f"{self._postgrest_url}/survey_answers",
            params={"profile_id": f"eq.{profile_id}", "select": "axis,value"},
            headers=self._headers,
        )
        _raise_for_status(answers_response)
        profile["survey_answers"] = {r["axis"]: float(r["value"]) for r in answers_response.json()}
        return profile

    async def save_vectors(self, profile_id: UUID | str, **fields) -> None:
        """한 행 upsert. PostgREST 는 PK 충돌 시 merge-duplicates 로 갱신한다."""
        response = await self._client.post(
            f"{self._postgrest_url}/profile_vectors",
            json={"profile_id": str(profile_id), "updated_at": "now()", **fields},
            headers={**self._headers, "Prefer": "resolution=merge-duplicates"},
        )
        _raise_for_status(response)

    async def fetch_owner(self, profile_id: UUID | str) -> dict:
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}", "select": _OWNER_COLUMNS},
            headers=self._headers,
        )
        _raise_for_status(response)
        return response.json()[0]

    async def fetch_candidates(self, profile_id: UUID | str) -> list[dict]:
        response = await self._client.post(
            f"{self._postgrest_url}/rpc/match_candidates",
            json={"p_owner": str(profile_id)},
            headers=self._headers,
        )
        _raise_for_status(response)
        return response.json()
```

- [ ] **Step 4: `refresh_vectors` 구현**

```python
import logging
from uuid import UUID

from openai import AsyncOpenAI

from app.matching.embeddings import embed
from app.matching.repository import MatchingRepository
from app.matching.sentences import self_sentence, want_sentence
from app.matching.survey_vector import survey_vector

_logger = logging.getLogger(__name__)


async def refresh_vectors(
    repo: MatchingRepository, openai_client: AsyncOpenAI, profile_id: UUID | str
) -> None:
    """설문·문장 벡터를 다시 만들어 저장한다(설계 §6.3 "수정하면 즉시 재생성").

    호출자는 이미 사용자의 글을 저장한 뒤다. 여기서 실패해도 그 저장을 되돌리지 않고 로그만 남긴다 —
    벡터가 없는 프로필은 match_candidates 의 `is not null` 조건에서 후보로만 빠지고, 다음 저장이나
    온보딩 완료 시점의 전체 재생성이 메운다."""
    try:
        materials = await repo.fetch_vector_materials(profile_id)
        vector, shyness = survey_vector(materials.get("survey_answers") or {})
        sentences = [self_sentence(materials), want_sentence(materials)]
        # 두 문장 다 비면 임베딩을 부르지 않는다(온보딩 초반). 설문만이라도 저장한다.
        embeddings = await embed(openai_client, sentences) if any(sentences) else []

        fields = {"self_survey": vector, "shyness_score": shyness}
        if embeddings:
            fields["self_embedding"] = embeddings[0]
            fields["want_embedding"] = embeddings[1]
        await repo.save_vectors(profile_id, **fields)
    except Exception:  # noqa: BLE001 — 벡터 실패가 사용자 저장을 깨지 않게 한다
        _logger.exception("매칭 벡터 재생성 실패: profile_id=%s", profile_id)
```

- [ ] **Step 5: 테스트 실행해서 통과 확인**

Run: `cd backend && python -m pytest tests/matching/test_vectors.py -v`
Expected: 2 passed

빈 문장일 때 임베딩을 안 부르므로 두 번째 테스트에서 `saved` 가 비는지 확인한다 — 첫 테스트는 문장이
있으니 저장이 1건이어야 한다.

- [ ] **Step 6: 온보딩 라우터에 재생성 호출 연결**

`backend/app/profile_onboarding/router.py` 의 아래 핸들러 끝(저장 성공 후)에 한 줄씩 넣는다.
**태그 3종(`interests`·`my-traits`·`ideal-traits`)에는 넣지 않는다** — 태그는 문장 재료가 아니고
자카드는 조회 시점에 계산한다(설계 §6.3).

| 핸들러 | 이유 |
| --- | --- |
| `submit_basic_info` | MBTI 가 "나는" 문장에 들어간다 |
| `submit_appearance_type` | 본인 얼굴상·인상 |
| `submit_survey` | `self_survey` · `shyness_score` |
| `submit_ideal_conditions` | 선호 얼굴상·인상이 "원해" 문장에 들어간다 |
| `submit_ideal_note` | "이런 사람이 좋아요" 자유 글 |
| `submit_bio` | 자기소개 |
| `complete_onboarding`(`status = active` 로 바꾸는 지점) | 안전망 — 위 호출이 실패했어도 활성화 때 다시 만든다 |

```python
from app.matching.repository import MatchingRepository
from app.matching.vectors import refresh_vectors


async def _refresh_vectors(settings: Settings, client: httpx.AsyncClient, profile_id: UUID) -> None:
    repo = MatchingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    openai_client = _openai_client_override or get_openai_client(settings.openai_api_key)
    await refresh_vectors(repo, openai_client, profile_id)
```

각 핸들러에서는 저장 직후 `await _refresh_vectors(settings, client, profile_id)` 한 줄을 부른다.

- [ ] **Step 7: 기존 테스트가 안 깨지는지 확인**

Run: `cd backend && python -m pytest -q`
Expected: 기존 119건 + 새 테스트 전부 통과. `test_onboarding_router.py` 의 `_wire` 목이
`/profile_vectors` POST 와 `survey_answers` GET 을 이미 기본 200 으로 받아주므로 수정이 필요 없는지
확인하고, 필요하면 `_wire` 에 분기를 한 줄 추가한다(조각 2 리뷰 때와 같은 방식).

- [ ] **Step 8: 커밋**

```bash
git add backend/app/matching/repository.py backend/app/matching/vectors.py \
        backend/app/profile_onboarding/router.py backend/tests/matching/test_vectors.py
git commit -m "✨ feat(matching): 벡터 저장소와 저장 시 즉시 재생성 연결"
```

---

### Task B5: 감점 계수와 최종점수

**Files:**
- Create: `backend/app/matching/scoring.py`
- Test: `backend/tests/matching/test_scoring.py`

**Interfaces:**
- Produces: `mbti_coefficient(a, b) -> float`, `range_coefficient(...) -> float`,
  `activity_coefficient(last_active_at) -> float`, `final_score(owner, candidate) -> float`,
  `rank(owner: dict, candidates: list[dict]) -> list[dict]`

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from datetime import datetime, timedelta, timezone

from app.matching.scoring import activity_coefficient, final_score, mbti_coefficient, rank

# 설계 §6.4 판정 예시: 내 설정이 E ok, I ok, N ok, S no, T ok, F no, J ok, P ok
MY_FLAGS = {"E": True, "I": True, "N": True, "S": False, "T": True, "F": False, "J": True, "P": True}
ALL_OK = {}


def test_mbti_coefficient_matches_the_spec_table():
    assert mbti_coefficient(MY_FLAGS, "ENTJ", ALL_OK, "ENFP") == 1.00
    assert round(mbti_coefficient(MY_FLAGS, "ESTJ", ALL_OK, "ENFP"), 2) == 0.90
    assert round(mbti_coefficient(MY_FLAGS, "ESFJ", ALL_OK, "ENFP"), 2) == 0.80


def test_mbti_coefficient_is_one_when_partner_mbti_is_unknown():
    """모른다는 이유로 불이익을 주지 않는다(설계 §6.4)."""
    assert mbti_coefficient(MY_FLAGS, None, ALL_OK, "ENFP") == 1.00


def test_activity_coefficient_steps():
    now = datetime.now(timezone.utc)
    assert activity_coefficient(now - timedelta(days=1)) == 1.0
    assert activity_coefficient(now - timedelta(days=5)) == 0.7
    assert activity_coefficient(now - timedelta(days=10)) == 0.4


def test_final_score_multiplies_weighted_sum_by_every_coefficient():
    """가중합 0.3/0.2/0.5 에 계수를 전부 곱한다(설계 §6.7)."""
    now = datetime.now(timezone.utc)
    owner = {
        "mbti": "ENFP", "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": False, "religion": "none",
    }
    candidate = {
        "trait_score": 1.0, "tag_score": 1.0, "text_score": 1.0, "mbti": "ENFP",
        "preferred_mbti_flags": ALL_OK, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": 2003, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": True, "religion": "buddhist",
        "last_active_at": now.isoformat(),
    }

    # 가중합 1.0 × MBTI 1.0 × 키 1.0 × 나이 1.0 × 흡연 0.5(비흡연자에게 흡연자) × 종교 0.8 × 활동성 1.0
    assert round(final_score(owner, candidate), 4) == 0.40


def test_rank_sorts_by_final_score():
    now = datetime.now(timezone.utc).isoformat()
    owner = {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2002,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": True, "religion": "none",
    }
    base = {
        "mbti": None, "preferred_mbti_flags": ALL_OK, "height_cm": 165,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": True, "religion": "none",
        "last_active_at": now, "tag_score": 0, "text_score": 0,
    }
    ranked = rank(owner, [
        {**base, "candidate_id": "low", "trait_score": 0.1},
        {**base, "candidate_id": "high", "trait_score": 0.9},
    ])

    assert [c["candidate_id"] for c in ranked] == ["high", "low"]
    assert ranked[0]["score"] > ranked[1]["score"]
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && python -m pytest tests/matching/test_scoring.py -v`
Expected: FAIL — `ModuleNotFoundError`

- [ ] **Step 3: 구현**

```python
"""최종점수(설계 §6.7)의 감점 계수 부분. 점수 3종(성향·태그·문장)은 SQL 이 이미 계산해 온다.

계수를 SQL 이 아니라 여기서 곱하는 이유: MBTI 8극 토글·범위 벗어남 단계처럼 분기가 많은 규칙이라
설계 §6.4·§6.5 의 판정 표를 그대로 단위 테스트로 옮길 수 있는 쪽이 낫다. 후보 수가 커져 파이썬
정렬이 느려지면 이 모듈의 규칙을 SQL 함수로 내린다."""

import math
from datetime import datetime, timezone

_AXES = (("E", "I"), ("N", "S"), ("T", "F"), ("J", "P"))


def _fit(flags: dict, mbti: str | None) -> float:
    """상대 4글자 중 내가 ok 로 둔 글자 비율. 한 축에서 양쪽을 다 끄면 그 축은 보지 않는다(설계 §6.4)."""
    ok = 0
    for left, right in _AXES:
        left_ok, right_ok = flags.get(left, True), flags.get(right, True)
        if left_ok == right_ok:  # 둘 다 ok 거나 둘 다 no = 상관없음
            ok += 1
        elif (left in mbti and left_ok) or (right in mbti and right_ok):
            ok += 1
    return ok / 4


def mbti_coefficient(
    my_flags: dict, partner_mbti: str | None, partner_flags: dict, my_mbti: str | None
) -> float:
    if not partner_mbti or not my_mbti:
        return 1.00
    both = math.sqrt(_fit(my_flags, partner_mbti) * _fit(partner_flags, my_mbti))
    return 0.6 + 0.4 * both


def _one_way_range(value: int | None, low: int | None, high: int | None, near: int) -> float:
    """범위 안 1.00 / near 이내로 벗어나면 0.85 / 그 밖은 0.70 / 범위 미지정은 1.00(설계 §6.5·§6.7)."""
    if value is None or (low is None and high is None):
        return 1.00
    over = max((low - value) if low is not None else 0, (value - high) if high is not None else 0)
    if over <= 0:
        return 1.00
    return 0.85 if over <= near else 0.70


def range_coefficient(
    my_value: int | None, my_low: int | None, my_high: int | None,
    partner_value: int | None, partner_low: int | None, partner_high: int | None, near: int,
) -> float:
    return math.sqrt(
        _one_way_range(partner_value, my_low, my_high, near)
        * _one_way_range(my_value, partner_low, partner_high, near)
    )


def activity_coefficient(last_active_at: datetime | str) -> float:
    if isinstance(last_active_at, str):
        last_active_at = datetime.fromisoformat(last_active_at)
    days = (datetime.now(timezone.utc) - last_active_at).days
    if days <= 3:
        return 1.0
    if days <= 7:
        return 0.7
    return 0.4  # 15일 이상은 SQL 하드 필터에서 이미 빠졌다


def final_score(owner: dict, candidate: dict) -> float:
    weighted = (
        0.3 * float(candidate["trait_score"])
        + 0.2 * float(candidate["tag_score"])
        + 0.5 * float(candidate["text_score"])
    )
    smoking = 0.5 if owner["is_smoker"] is False and candidate["is_smoker"] is True else 1.0
    religion = 0.8 if owner["religion"] != candidate["religion"] else 1.0
    return (
        weighted
        * mbti_coefficient(
            owner["preferred_mbti_flags"] or {}, candidate["mbti"],
            candidate["preferred_mbti_flags"] or {}, owner["mbti"],
        )
        * range_coefficient(
            owner["height_cm"], owner["preferred_height_min"], owner["preferred_height_max"],
            candidate["height_cm"], candidate["preferred_height_min"],
            candidate["preferred_height_max"], near=5,
        )
        * range_coefficient(
            owner["birth_year"], owner["preferred_age_min"], owner["preferred_age_max"],
            candidate["birth_year"], candidate["preferred_age_min"],
            candidate["preferred_age_max"], near=2,
        )
        * smoking
        * religion
        * activity_coefficient(candidate["last_active_at"])
    )
```

**나이 계수 주의**: `preferred_age_*` 는 "나이"인데 `birth_year` 는 "태어난 해"라 그대로 넘기면 부호가
반대다. 나이로 바꿔서 넘긴다 — 기준은 가입 나이와 같은 Asia/Seoul 올해(조각 2 `schemas.SEOUL` 재사용).
위 구현의 나이 항을 아래로 쓴다.

```python
from app.profile_onboarding.schemas import SEOUL


def _age(profile: dict) -> int | None:
    """설계 §6.1 의 나이는 만 나이가 아니라 "올해 − 태어난 해"다(가입 자격 계산과 같은 기준)."""
    birth_year = profile.get("birth_year")
    return None if birth_year is None else datetime.now(SEOUL).year - birth_year
```

```python
        * range_coefficient(
            _age(owner), owner["preferred_age_min"], owner["preferred_age_max"],
            _age(candidate), candidate["preferred_age_min"], candidate["preferred_age_max"],
            near=2,
        )
```

테스트에 경계값 한 건을 추가한다 — 내 선호 22~27, 상대 나이 28 이면 `0.85`, 30 이면 `0.70`
(상대는 범위를 지정하지 않아 반대 방향은 1.00, 기하평균이라 각각 √0.85 · √0.70).

```python
def test_age_coefficient_uses_age_not_birth_year():
    this_year = datetime.now(SEOUL).year
    owner = {
        "mbti": None, "preferred_mbti_flags": {}, "height_cm": 180,
        "preferred_height_min": None, "preferred_height_max": None,
        "birth_year": this_year - 25, "preferred_age_min": 22, "preferred_age_max": 27,
        "is_smoker": True, "religion": "none",
    }
    candidate = {
        "trait_score": 1.0, "tag_score": 1.0, "text_score": 1.0, "mbti": None,
        "preferred_mbti_flags": {}, "height_cm": 165, "preferred_height_min": None,
        "preferred_height_max": None, "birth_year": this_year - 28, "preferred_age_min": None,
        "preferred_age_max": None, "is_smoker": True, "religion": "none",
        "last_active_at": datetime.now(timezone.utc).isoformat(),
    }

    assert round(final_score(owner, candidate), 4) == round(math.sqrt(0.85), 4)
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd backend && python -m pytest tests/matching/test_scoring.py -v`
Expected: 6 passed (나이 경계값 테스트 포함)

- [ ] **Step 5: `rank` 추가**

```python
def rank(owner: dict, candidates: list[dict]) -> list[dict]:
    scored = [{**c, "score": final_score(owner, c)} for c in candidates]
    return sorted(scored, key=lambda c: c["score"], reverse=True)
```

- [ ] **Step 6: 커밋**

```bash
git add backend/app/matching/scoring.py backend/tests/matching/test_scoring.py
git commit -m "✨ feat(matching): MBTI·키·나이·흡연·종교·활동성 계수와 최종점수 추가"
```

---

### Task B6: 후보 조회 엔드포인트

**Files:**
- Create: `backend/app/matching/router.py`
- Modify: `backend/app/main.py` (라우터 등록)
- Test: `backend/tests/matching/test_matching_router.py`

**Interfaces:**
- Consumes: Task B4 `MatchingRepository`, B5 `rank`, 기존 `get_verified_user_id`
- Produces: `GET /matching/candidates?limit=10` →
  `{"candidates": [{"profile_id": "...", "score": 0.83}, ...]}`

**표시용 프로필 정보(닉네임·아바타)는 넣지 않는다** — 카드 화면은 조각 4 이고, 지금 필요한 건 점수가
맞는지 보는 것이다(YAGNI).

- [ ] **Step 1: 실패하는 테스트 작성**

```python
from collections.abc import Callable
from datetime import datetime, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

import app.matching.router as router_module
from app.main import app
from app.settings import Settings

PROFILE_ID = "11111111-1111-1111-1111-111111111111"
AUTH_HEADERS = {"Authorization": "Bearer valid-token"}


@pytest.fixture(autouse=True)
def overrides(monkeypatch):
    monkeypatch.setattr(router_module, "get_settings", lambda: Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/t",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test",
    ))
    yield
    router_module._client_override = None


def _wire(handler: Callable[[httpx.Request], httpx.Response]) -> TestClient:
    def wrapped(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url and request.method == "GET":
            return httpx.Response(200, json=[{"student_verification": "verified", "department": "컴공"}])
        return handler(request)

    router_module._client_override = httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    return TestClient(app)


def test_candidates_are_sorted_by_score_and_cut_to_limit():
    now = datetime.now(timezone.utc).isoformat()
    owner = {
        "id": PROFILE_ID, "gender": "male", "mbti": None, "preferred_mbti_flags": {},
        "height_cm": 180, "preferred_height_min": None, "preferred_height_max": None,
        "birth_year": 2002, "preferred_age_min": None, "preferred_age_max": None,
        "is_smoker": True, "religion": "none",
    }
    candidate = {
        "mbti": None, "preferred_mbti_flags": {}, "height_cm": 165,
        "preferred_height_min": None, "preferred_height_max": None, "birth_year": 2003,
        "preferred_age_min": None, "preferred_age_max": None, "is_smoker": True,
        "religion": "none", "last_active_at": now, "tag_score": 0, "text_score": 0,
    }

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/rpc/match_candidates" in url:
            return httpx.Response(200, json=[
                {**candidate, "candidate_id": "low", "trait_score": 0.1},
                {**candidate, "candidate_id": "high", "trait_score": 0.9},
            ])
        if "/profiles" in url:
            return httpx.Response(200, json=[owner])
        return httpx.Response(200, json=[])

    response = _wire(handler).get("/matching/candidates", headers=AUTH_HEADERS, params={"limit": 1})

    assert response.status_code == 200
    body = response.json()
    assert [c["profile_id"] for c in body["candidates"]] == ["high"]
    assert body["candidates"][0]["score"] > 0


def test_candidates_requires_verified_student():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    def unverified(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "/auth/v1/user" in url:
            return httpx.Response(200, json={"id": PROFILE_ID})
        if "student_verification" in url:
            return httpx.Response(200, json=[{"student_verification": "pending", "department": None}])
        return handler(request)

    router_module._client_override = httpx.AsyncClient(transport=httpx.MockTransport(unverified))
    response = TestClient(app).get("/matching/candidates", headers=AUTH_HEADERS)

    assert response.status_code == 403
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd backend && python -m pytest tests/matching/test_matching_router.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.matching.router'`

- [ ] **Step 3: 라우터 구현**

```python
from functools import lru_cache

import httpx
from fastapi import APIRouter, Header, Query

from app.matching.repository import MatchingRepository
from app.matching.scoring import rank
from app.settings import Settings
from app.student_verification.current_user import get_verified_user_id

router = APIRouter()

_client_override: httpx.AsyncClient | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()


@router.get("/matching/candidates")
async def get_candidates(
    limit: int = Query(default=10, ge=1, le=100),
    authorization: str | None = Header(default=None),
) -> dict:
    """하드 필터를 통과한 후보를 최종점수 내림차순으로 돌려준다(설계 §6.7·§6.8).
    카드 지급·수락은 조각 4 다 — 여기서는 순위만 본다."""
    settings = get_settings()
    client = _client_override or httpx.AsyncClient()
    profile_id = await get_verified_user_id(settings, client, authorization)

    repo = MatchingRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    owner = await repo.fetch_owner(profile_id)
    candidates = await repo.fetch_candidates(profile_id)

    ranked = rank(owner, candidates)[:limit]
    return {
        "candidates": [
            {"profile_id": c["candidate_id"], "score": round(c["score"], 4)} for c in ranked
        ]
    }
```

`backend/app/main.py` 에 `app.include_router(matching_router)` 한 줄을 추가한다(기존 두 라우터와 같은 방식).

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd backend && python -m pytest tests/matching/test_matching_router.py -v`
Expected: 2 passed

- [ ] **Step 5: 전체 테스트 실행**

Run: `cd backend && python -m pytest -q`
Expected: 기존 119건 + 조각 3 신규 전부 통과

- [ ] **Step 6: 커밋**

```bash
git add backend/app/matching/router.py backend/app/main.py backend/tests/matching/test_matching_router.py
git commit -m "✨ feat(matching): 후보 조회 엔드포인트 추가"
```

---

## Part A: Flutter — 이번 조각에는 없다

조각 3 의 산출물은 전부 서버 안에서 끝난다. 카드 UI · 수락 · 알림은 조각 4 이고, 문장 재료를 받는 화면
(자기소개 `06-2b` · "이런 사람이 좋아요" `7b-2` · 얼굴상 `04-4`/`06-1` · 설문)은 **조각 2 에서 이미 다
만들었다**. FCM · `firebase_messaging` 도 조각 4 다. 새 화면을 미리 만들지 않는다.

---

## 임베딩 비용 추정

| 항목 | 값 | 근거 |
| --- | --- | --- |
| 모델 단가 | $0.02 / 1M 토큰 | `text-embedding-3-small`(실행 시점에 현재가 재확인) |
| "나는" 문장 | 템플릿 3문장(~60자) + 자기소개(~300자) ≈ 360자 ≈ **500 토큰** | 한글은 대략 글자당 1.2~1.5 토큰 |
| "원해" 문장 | 템플릿 1문장(~30자) + 자유 글(~200자) ≈ 230자 ≈ **320 토큰** | 위와 같음 |
| 1회 재생성 | 약 **820 토큰**(넉넉히 1,000) | 두 문장을 한 번의 호출로 보낸다 |
| 1인당 재생성 횟수 | 온보딩 중 3~4회 + 이후 수정 때마다 | 호출 지점 6곳(Task B4 표) |
| **1인당 총계** | 약 **4,000 토큰 = $0.00008** | 1,000 토큰 × 4회 |
| **사용자 1,000명** | 약 400만 토큰 = **$0.08** | |
| **사용자 10,000명** | 약 4,000만 토큰 = **$0.8** | |

**결론: 요금은 사실상 무시해도 된다.** 실제 비용은 돈이 아니라 **저장 응답에 붙는 지연**(임베딩 호출
100~300ms)이다. 그래서 동기로 두되 실패는 삼킨다(Task B4). 백그라운드 큐를 지금 만들지 않는 이유도
같다 — 큐 인프라(워커 프로세스·재시도 저장소)가 지연 300ms 를 없애자고 들이기엔 과하다. 지연이
문제가 되면 그때 FastAPI `BackgroundTasks` 한 줄로 옮긴다(같은 프로세스, 새 의존성 없음).

**재생성 방식 택1 — 동기(즉시), 이유**: ① 저장 엔드포인트가 이미 OpenAI 를 동기로 부르고 있다
(`avatar/generate` · `bio-draft`)라 새로운 종류의 지연이 아니다. ② 큐를 쓰면 "저장했는데 아직 매칭에
안 잡히는" 중간 상태가 생기고, 그 상태를 사용자에게 설명할 화면이 없다. ③ 실패해도 다음 저장 ·
온보딩 완료 시점이 메우므로 큐의 재시도 이점이 작다.

---

## 테스트 전략

| 층 | 무엇을 | 어떻게 |
| --- | --- | --- |
| 문장 템플릿 | 김철수 예시 재현 · 빈 재료 생략 · 조사(이나/나) | 순수 함수 단위 테스트(Task B1) |
| 설문 벡터 | 낯가림 분리 · 가중치 적용 · 최대가능거리가 SQL 상수와 일치 | 순수 함수 단위 테스트(Task B3) |
| 계수 | 설계 §6.4 판정 표 3행 · 모름 1.00 · 키/나이 경계값 · 활동성 단계 | 순수 함수 단위 테스트(Task B5) |
| 임베딩 · 저장 | 한 번의 호출로 2문장 · 실패 시 저장 응답을 깨지 않음 | `AsyncMock` + `httpx.MockTransport`(Task B2·B4) |
| 엔드포인트 | 정렬 · limit · 인증 관문 403 | `TestClient` + `MockTransport`(조각 2 `_wire` 패턴, Task B6) |
| DB | RLS 정책 0건 · ACL · 벡터 차원 · 자카드 · 태그점수 식 | pgTAP `supabase test db`(Task C3) |

**실제 OpenAI · 실제 Supabase 클라우드는 테스트에서 부르지 않는다.** 로컬 스택(Docker)은 pgTAP 에만
쓴다. 점수 공식이 SQL 과 파이썬에 나뉘어 있으므로, **최대가능거리 상수(5.657)가 양쪽에서 같은지**를
Task B3 테스트가 못 박는다 — 가중치를 바꾸고 SQL 을 안 바꾸면 그 테스트가 먼저 깨진다.

---

## 백로그 (이번 조각에서 하지 않는다)

- HNSW 인덱스(설계 §6.8 — 벡터가 수만 개를 넘을 때)
- 계수까지 SQL 로 내리기(후보 수가 수만 명이 될 때)
- `blocks`(조각 6) · `matching_paused` · "이미 카드로 받은 사람"(조각 4) 하드 필터 추가
- 축별 가중치 실측 조정(데이터가 쌓인 뒤)
- 벡터가 없는 프로필을 찾아 메우는 정기 복구 배치(지금은 다음 저장 · 온보딩 완료가 메운다)
- ERD.md §3 `profile_vectors` 그림 갱신(`self_text` → `self_embedding`/`want_embedding`) — erd 세션 몫
