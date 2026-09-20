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
