-- 조각 0 스키마 1/4: 가입을 허용하는 대학과 학생인증 메일 도메인.
-- 기준 문서: docs/ERD.md §2 · §3 · §10

-- 벡터 컬럼은 조각 3에서 만들지만 확장은 첫 마이그레이션에서 켠다(frontend/CLAUDE.md §10.1).
-- 조각 3에서는 타입을 extensions.vector 로 쓰거나 search_path 에 extensions 가 있는지 확인한다.
create extension if not exists vector with schema extensions;

create table public.universities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  -- 지급 주기와 성비를 판단하는 지역그룹이자 매칭 풀. 첫 출시는 'seoul' 뿐이다(ERD §11-7).
  region_group text not null,
  created_at timestamptz not null default now(),

  -- 시드가 학교 이름으로 도메인을 짝짓는다.
  constraint universities_name_unique unique (name)
);

comment on table public.universities is '가입을 허용하는 대학';

-- 학생인증 화이트리스트. ac.kr 이 아닌 학교도 있고 학교당 도메인이 여러 개일 수 있어
-- 접미사 규칙이 아니라 명시적 목록으로 둔다.
create table public.university_email_domains (
  domain text primary key,
  university_id uuid not null references public.universities (id) on delete cascade,

  -- 메일 주소의 도메인은 소문자로 바꿔 비교한다. 대문자 · '@' · 공백이 섞인 입력 실수도 여기서 막는다.
  constraint university_email_domains_domain_format check (domain ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$')
);

comment on table public.university_email_domains is '학생인증 메일 도메인 화이트리스트. 학교당 여러 개';

create index university_email_domains_university_id_index
  on public.university_email_domains (university_id);

-- RLS: 가입 화면이 로그인 전에 학교와 도메인을 확인하므로 anon 까지 전체 읽기를 연다.
-- 소유자 조건이 없는 공개 참조 테이블 예외다(frontend/CLAUDE.md §10.1). 쓰기 정책은 두지 않는다.
alter table public.universities enable row level security;
alter table public.university_email_domains enable row level security;

create policy "universities are readable by everyone"
  on public.universities
  for select
  to anon, authenticated
  using (true);

create policy "university email domains are readable by everyone"
  on public.university_email_domains
  for select
  to anon, authenticated
  using (true);

-- 권한: 자동 grant 를 믿지 않고 테이블마다 필요한 것만 준다(ERD §2).
-- service_role 까지 revoke 해야 자동 grant 유무(프로젝트 설정·적용 시점)와 상관없이 결과가 같다.
-- 클라이언트 쓰기는 권한 단계에서 42501 로 끝나고, 쓰기는 FastAPI 가 service_role 로 한다.
revoke all on table public.universities, public.university_email_domains from anon, authenticated, service_role;
grant select on table public.universities, public.university_email_domains to anon, authenticated;
grant select, insert, update, delete on table public.universities, public.university_email_domains to service_role;
