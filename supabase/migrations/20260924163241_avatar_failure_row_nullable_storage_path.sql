-- 조각 2 후속: 아바타 생성 실패 이력에는 저장할 경로가 없다. storage_path 가 not null 이라
-- insert_avatar_attempt(profile_id, 'failed', None) 이 23502 로 튕겨 실패 행이 한 줄도 쌓이지 않았고,
-- 그래서 "5회 연속 실패 → 기본 아바타 + 하트 10"(project_slice2_decisions_2026-09-19)이 영원히 걸리지
-- 않았다(운영 00018-pxb). 기준 문서: docs/ERD.md §3.
alter table public.profile_avatars
  alter column storage_path drop not null;

-- 경로가 실제로 필요한 것은 ready 행뿐이다(최신 ready 행이 현재 아바타). 지금까지 들어간 행은 전부
-- storage_path 가 not null 이므로 이 check 는 위반 행 없이 바로 valid 로 붙는다.
alter table public.profile_avatars
  add constraint profile_avatars_ready_has_storage_path
  check (status <> 'ready' or storage_path is not null);
