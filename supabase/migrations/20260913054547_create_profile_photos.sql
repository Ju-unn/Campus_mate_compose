-- 조각 0 스키마 3/4: 실사진 메타데이터. 이미지 파일은 profile-photos 비공개 버킷에 있다.
-- 기준 문서: docs/ERD.md §2 · §3 · §10

create table public.profile_photos (
  id uuid primary key default gen_random_uuid(),
  -- 계정을 지워 profiles 가 cascade 로 지워지면 이 행도 지워지지만 Storage 파일은 남는다.
  -- 사진 파일 삭제는 FastAPI 몫이다(ERD §3).
  profile_id uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null,
  -- 노출 순서. 0 이 대표 사진이다. 최대 4장이라 0~3이고, 최소 2장은 FastAPI 온보딩 완료 검사가 본다.
  position smallint not null,
  created_at timestamptz not null default now(),

  constraint profile_photos_position_range check (position between 0 and 3),
  -- 두 행이 같은 파일을 가리키면 한 행을 지울 때 남은 행의 사진도 사라진다.
  constraint profile_photos_storage_path_unique unique (storage_path),
  -- 순서를 맞바꿀 때 중간 충돌이 나지 않도록 커밋 시점에 검사한다.
  -- deferrable 제약은 on conflict 대상으로 쓸 수 없다.
  -- 이 제약의 인덱스가 profile_id 로 찾는 조회도 받는다.
  constraint profile_photos_profile_position_unique
    unique (profile_id, position) deferrable initially deferred
);

comment on table public.profile_photos is '실사진 메타데이터. 이미지 파일은 Storage 에 있다';

-- RLS: 본인 사진 행 읽기만. 추가·순서 변경·삭제는 FastAPI 가 한다(ERD §2).
alter table public.profile_photos enable row level security;

create policy "profile photos are readable by owner"
  on public.profile_photos
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

-- 권한(ERD §2): anon 은 없음, authenticated 는 select, service_role 은 select·insert·update·delete.
revoke all on table public.profile_photos from anon, authenticated, service_role;
grant select on table public.profile_photos to authenticated;
grant select, insert, update, delete on table public.profile_photos to service_role;
