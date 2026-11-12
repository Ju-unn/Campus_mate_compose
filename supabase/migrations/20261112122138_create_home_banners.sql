-- 홈 배너 슬라이드(홈 v3, 사용자 결정 11-12 「배너 서버에서 이미지 넣어주기로 하자 / 문구수정으로 앱 배포하면 너무 번거러워서」).
-- 그림(문구가 그림 안에 들어 있다)은 공개 버킷 home-banners 에 두고, 이 표의 줄이 어느 그림을 언제 어떤 순서로 보일지 정한다.
-- 앱은 GET /home/summary 의 banners 로만 받는다 — 클라이언트는 표를 직접 읽지 않는다(default deny, FastAPI 만 service_role 로 읽는다).
-- 줄 넣기 · 문구 바꾸기는 운영 SQL 로 한다(관리자 화면 없음). 줄이 몇 개뿐이라 인덱스는 두지 않는다.

create table public.home_banners (
  id uuid primary key default gen_random_uuid(),
  -- home-banners 버킷 안 경로(예 'xmas-1.webp'). 서버가 공개 주소로 바꿔 준다.
  image_path text not null,
  -- 그림 속 문구 그대로 — 화면 읽기(스크린리더)가 읽는다.
  alt_text text not null,
  -- 작은 수가 먼저. 같으면 먼저 넣은 줄이 먼저.
  sort_order integer not null default 0,
  starts_at timestamptz not null default now(),
  -- null = 끝 없음.
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  constraint home_banners_period check (ends_at is null or ends_at > starts_at),
  -- 빈 경로는 깨진 주소가 되고, 빈 문구는 화면 읽기가 아무것도 못 읽는다 — 운영 SQL 실수를 여기서 막는다.
  constraint home_banners_image_path_not_blank check (btrim(image_path) <> ''),
  constraint home_banners_alt_text_not_blank check (btrim(alt_text) <> '')
);

comment on table public.home_banners is
  '홈 배너 슬라이드. FastAPI 전용(클라이언트 접근 없음). 그림은 공개 버킷 home-banners, 문구는 그림 안';

alter table public.home_banners enable row level security;

revoke all on table public.home_banners from anon, authenticated, service_role;
grant select, insert, update, delete on table public.home_banners to service_role;

-- 배너 그림 버킷 — 누구나 주소로 볼 수 있는 홍보 그림이라 공개다(university-logos 와 같다). WebP 만, 장당 1MB.
-- storage.objects 정책은 두지 않는다 — 공개 버킷은 주소로 읽기만 되고, 올리기는 운영자가 service key 로 한다.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('home-banners', 'home-banners', true, 1048576, array['image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
