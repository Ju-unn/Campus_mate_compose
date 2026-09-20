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
