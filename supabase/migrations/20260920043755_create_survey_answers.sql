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
