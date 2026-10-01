-- 학교 로고(2026-10-01 사용자 결정). 로고 그림은 공개 버킷에 두고, universities 표엔 그 버킷 안
-- 파일 이름만 둔다 — 학교를 새로 열 때 앱 업데이트 없이 로고가 붙는다.
-- 업로드 파일 이름 꼴은 uni-<16자리16진수>.webp(예: uni-75ee0c4a522d491b.webp), 가장 큰 파일이 56KB다.
-- 업로드 · 값 채우기는 대장이 운영에서 service_role 로 따로 한다. 이 마이그레이션은 칸과 버킷만 만든다.
alter table public.universities
  add column logo_path text,
  add constraint universities_logo_path_format
    check (logo_path is null or logo_path ~ '^[a-z0-9-]+\.webp$');

comment on column public.universities.logo_path is
  '공개 버킷 university-logos 안 파일 이름. null = 로고 없음, 앱은 학교 이름만 보여준다';

-- universities 는 이미 anon · authenticated 전체 읽기다(20260913054542) — logo_path 도 같이 공개되지만
-- 파일 이름일 뿐이라 문제없다.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('university-logos', 'university-logos', true, 102400, array['image/webp'])
on conflict (id) do nothing;

-- storage.objects 정책은 두지 않는다(ERD §9 관례, profile-photos·avatars 와 같다) — 공개 버킷이라
-- 파일 주소로 읽는 것은 정책 없이도 되고, 목록 조회 · 쓰기는 정책이 없어 막힌다. 업로드 · 교체는
-- 대장이 service_role 로 한다.
