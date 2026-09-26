-- 아바타 비동기 생성(Cloud Tasks). 기준 문서: docs/ERD.md §3, 계획서
-- docs/superpowers/plans/2026-09-25-avatar-async-cloud-tasks.md Part C.
-- 지금까지 pending 은 default 값일 뿐 아무도 넣지 않았다 — 이제 POST 가 pending 행을 먼저 넣고
-- 워커가 그 행을 ready/failed 로 바꾼다. 그래서 "한 사람에게 pending 은 한 줄"이 규칙이 된다.
--
-- 되돌리기(서버를 revert 할 때 이 인덱스가 발목을 잡는다 — 인덱스부터 지운다):
--   drop index if exists public.profile_avatars_one_pending;
--   alter table public.profile_avatars drop column if exists is_fallback;

-- 5회 연속 실패 보상으로 복사해 넣은 기본 아바타 행을 표시한다. 결과 화면이 "하트를 드렸어요" 안내를
-- 띄울지 판단하는 근거다(project_slice2_decisions_2026-09-19).
alter table public.profile_avatars
  add column is_fallback boolean not null default false;

comment on column public.profile_avatars.is_fallback is
  '5회 연속 실패 보상으로 넣은 기본 아바타 행이면 true. 정상 생성 결과와 구분해 결과 화면 안내를 고른다';

-- 중복 누름 차단의 마지막 방어선. 앱이 CTA 를 두 번 눌러도, 워커가 늦게 깨어나 POST 와 겹쳐도,
-- 두 번째 pending insert 가 23505 로 튕긴다. FastAPI 는 그 23505 를 "이미 만드는 중"으로 읽는다.
create unique index profile_avatars_one_pending
  on public.profile_avatars (profile_id)
  where status = 'pending';
