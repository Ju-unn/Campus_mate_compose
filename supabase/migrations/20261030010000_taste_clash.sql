-- 글 속 취향 부딪힘 감점(2026-10-30 사용자 승인, 실험 12 · 10-29 최종 추천 "v5 나누기 · 부딪힘이면 총점 ×0.6 · 가점 없음").
-- 자기소개 · "이런 사람이 좋아요" 글을 GPT 가 좋아함 / 싫어함 단어로 나누고(backend/app/matching/taste.py),
-- 단어마다 임베딩을 사전(taste_words)에 한 번만 두고, 사람은 사전 단어 번호 배열만 들고 있는다.
-- 카드를 고를 때 taste_clash_candidates 가 "나와 부딪히는 사람" 번호를 돌려주고, 서버가 match_candidates 결과와 겹쳐
-- 총점에 ×0.6 을 곱한다(scoring.TASTE_CLASH_PENALTY). 같은 취향 가점은 넣지 않는다. match_candidates 는 바꾸지 않는다.
--
-- 되돌리기(이 순서로):
--   drop function public.taste_clash_candidates(uuid);
--   alter table public.profile_vectors
--     drop column self_like_words, drop column self_dislike_words,
--     drop column want_like_words, drop column want_dislike_words;
--   drop table public.taste_words;
-- 서버만 먼저 되돌릴 때는 SQL 이 필요 없다: fetch_candidates 가 이 함수를 못 불러도 전원 "부딪힘 없음"으로 읽는다.
-- DB 까지 되돌릴 때는 반드시 서버를 먼저 되돌린다 — 새 서버는 4칸을 upsert 하므로 칸이 없으면 save_vectors 가 전부 실패한다.

-- 1. 단어 사전 ------------------------------------------------------------------
-- 모든 사용자가 같이 쓴다. 사람의 배열이 id 를 직접 들고 있어(FK 불가) 행을 지우거나 단어를 바꾸지 않는다 — insert 만 한다.
create table public.taste_words (
  id bigint generated always as identity primary key,
  word text not null unique check (char_length(word) between 1 and 40),
  -- 사람 글 임베딩과 같은 모델 · 차원(text-embedding-3-small, 512). 거리는 코사인(<=>).
  embedding extensions.vector(512) not null,
  created_at timestamptz not null default now()
);

-- 512차원 벡터(약 2KB)는 기본값이면 TOAST 로 밀려나 거리 계산마다 풀어야 한다. taste_clash_candidates 는 카드를 고를 때마다
-- 사람 단어 × 사전 전체를 비교하므로 plain(행 안에 그대로)으로 둔다 — 로컬 4,000단어 · 20명 비교가 17.4초 → 1.2초.
alter table public.taste_words alter column embedding set storage plain;

comment on table public.taste_words is '글에서 뽑은 취향 단어 사전 + 임베딩(10-30). FastAPI 전용 — 클라이언트 권한 없음. 지우거나 고치지 않는다';

-- 서버 전용: RLS 만 켜고 정책은 두지 않는다(ERD §2 "정책 없음"). service_role 은 읽고 넣기만 한다.
alter table public.taste_words enable row level security;
revoke all on table public.taste_words from anon, authenticated, service_role;
grant select, insert on table public.taste_words to service_role;
-- identity 컬럼은 테이블 insert 권한만으로 번호를 받으므로 시퀀스 권한이 필요 없다(student_verification_attempts 와 같다).
revoke all on sequence public.taste_words_id_seq from anon, authenticated, service_role;

-- 2. 사람별 단어 번호 -----------------------------------------------------------
-- null = 아직 나누지 않았거나 나누기 실패 → 그 사람은 부딪힘 검사를 하지 않는다(지금과 같음).
-- 빈 배열 = 글이 비었거나 항목이 없음. 테이블 단위 권한(service_role 만)이라 새 칸도 같은 권한을 받는다.
alter table public.profile_vectors
  add column self_like_words bigint[],
  add column self_dislike_words bigint[],
  add column want_like_words bigint[],
  add column want_dislike_words bigint[];

comment on column public.profile_vectors.self_like_words is '자기소개(bio)에서 뽑은 좋아함 단어의 taste_words.id. null 은 아직 없음';
comment on column public.profile_vectors.self_dislike_words is '자기소개(bio)에서 뽑은 싫어함 단어의 taste_words.id. null 은 아직 없음';
comment on column public.profile_vectors.want_like_words is '"이런 사람이 좋아요"(ideal_note)에서 뽑은 좋아함 단어의 taste_words.id. null 은 아직 없음';
comment on column public.profile_vectors.want_dislike_words is '"이런 사람이 좋아요"(ideal_note)에서 뽑은 싫어함 단어의 taste_words.id. null 은 아직 없음';

-- 3. 부딪히는 사람 --------------------------------------------------------------
-- 기준 사람(p_owner)과 부딪히는 사람의 profile_id 를 jsonb 배열 한 덩어리로 돌려준다(행 수 상한에 안 걸리게 match_candidates 와 같은 모양).
-- 부딪힘 = 아래 6쌍 중 하나라도 단어 임베딩 비슷함(1 - 코사인 거리)이 0.6 초과인 단어 짝이 있음:
--   1 나 self_like × 상대 self_dislike     2 나 self_dislike × 상대 self_like
--   3 나 want_like × 상대 self_dislike     4 나 want_dislike × 상대 self_like
--   5 상대 want_like × 나 self_dislike     6 상대 want_dislike × 나 self_like
-- 방법: 기준 사람의 단어마다 사전 전체와 비교해 0.6 초과인 사전 단어 번호 묶음을 칸별로 만들고(가까운 짝 목록은 저장하지 않는다),
-- 다른 사람들의 배열과 && (겹침)로 찾는다. 후보 거르기(성별 · 지역 · 차단 등)는 하지 않는다 — 서버가 match_candidates 결과와 겹쳐 본다.
-- null 배열은 && 가 null 이라 걸리지 않는다. 기준 사람 자신은 뺀다.
create or replace function public.taste_clash_candidates(p_owner uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with me as (
    select v.self_like_words as sl, v.self_dislike_words as sd, v.want_like_words as wl, v.want_dislike_words as wd
    from public.profile_vectors v
    where v.profile_id = p_owner
  ),
  mine as (
    select 'sl' as slot, unnest(sl) as word_id from me
    union all select 'sd', unnest(sd) from me
    union all select 'wl', unnest(wl) from me
    union all select 'wd', unnest(wd) from me
  ),
  -- 단어마다 사전 전체와 한 번씩만 비교한다(같은 단어가 여러 칸에 있어도).
  close_words as (
    select d.word_id as a, w.id as b
    from (select distinct word_id from mine) d
    join public.taste_words mw on mw.id = d.word_id
    cross join public.taste_words w
    where 1 - (mw.embedding operator(extensions.<=>) w.embedding) > 0.6
  ),
  zones as (
    select
      coalesce(array_agg(distinct c.b) filter (where m.slot = 'sl'), '{}') as sl,
      coalesce(array_agg(distinct c.b) filter (where m.slot = 'sd'), '{}') as sd,
      coalesce(array_agg(distinct c.b) filter (where m.slot = 'wl'), '{}') as wl,
      coalesce(array_agg(distinct c.b) filter (where m.slot = 'wd'), '{}') as wd
    from mine m
    join close_words c on c.a = m.word_id
  )
  select coalesce(jsonb_agg(cv.profile_id), '[]'::jsonb)
  from zones z
  join public.profile_vectors cv on cv.profile_id <> p_owner
   and (
        cv.self_dislike_words && z.sl      -- 1
     or cv.self_like_words    && z.sd      -- 2
     or cv.self_dislike_words && z.wl      -- 3
     or cv.self_like_words    && z.wd      -- 4
     or cv.want_like_words    && z.sd      -- 5
     or cv.want_dislike_words && z.sl      -- 6
   )
$$;

comment on function public.taste_clash_candidates(uuid) is
  '기준 사람과 글 속 취향이 부딪히는 사람의 profile_id 를 jsonb 배열로(10-30). 6쌍 · 비슷함 0.6 초과. 거르기는 하지 않는다 — 서버가 match_candidates 와 겹쳐 총점에 ×0.6';

-- security invoker + service_role 만 부른다(match_candidates 와 같은 관례).
revoke all on function public.taste_clash_candidates(uuid) from public, anon, authenticated;
grant execute on function public.taste_clash_candidates(uuid) to service_role;
