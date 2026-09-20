-- 조각 1b: 3c(학과·학번 확인) 화면이 쓰는 컬럼. 학생증과 대조하지 않는 자기 입력값이다(설계 §7.3, §13 미결66).
-- 학과는 별도 컬럼을 새로 만들지 않고 기존 public.profiles.major 를 재사용한다(2026-09-20 결정).
-- 기준 문서: docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md §7.3

alter table public.profiles
  add column student_number text;

comment on column public.profiles.student_number is '자기 입력, 학생증 대조 없음(2026-09-13 결정)';

-- 기존 profiles grant(조각 0)는 테이블 단위라 이 새 컬럼도 자동으로 포함된다 — 컬럼 단위 grant 가
-- 아니므로 여기서 다시 명시할 문장이 없다(2026-09-20 분석담당 리뷰 — 제안6, 종전 주석은 아래에 없는
-- grant 문이 있는 것처럼 적혀 있었다). authenticated 는 본인 행 select 만(조각 0 RLS 그대로,
-- 쓰기는 FastAPI 전용 — SUPABASE.md §5).
