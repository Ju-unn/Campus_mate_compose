-- 관리자 웹 대시보드 D0(설계 바탕화면 관리자_대시보드_설계_10-18.md §6 · §7): 관리자 명단.
-- 서버 관문 get_admin_caller(backend/app/admin/caller.py)가 로그인 → 2단계(aal2) 다음에 이 표에 있는지 본다.
-- 관리자 = 운영자 전용 구글 계정 1명(사용자 결정 10-18). 화면에서 관리자를 더하는 기능은 없다 —
-- 대장이 사용자 승인 뒤 SQL 한 줄로 넣는다: insert into public.admin_users (user_id) values ('<auth 사용자 id>');
-- 시험: supabase/tests/admin_foundation_test.sql · rls_slice0_test.sql(권한 목록)

create table public.admin_users (
  -- auth 계정이 지워지면 명단에서도 빠진다. 작업 기록(admin_actions)은 FK 가 없어 남는다.
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table public.admin_users is
  '관리자 웹 대시보드 명단(auth 사용자 id). FastAPI 전용 — get_admin_caller 가 읽는다, 클라이언트 접근 없음. '
  '등록은 사용자 승인 뒤 SQL 한 줄(insert into public.admin_users (user_id) values (...)).';

-- RLS: 정책 없음 = 앱 · 브라우저는 읽지도 쓰지도 못한다(unknown_email_domain_attempts · school_email_claims 와 같다).
alter table public.admin_users enable row level security;

revoke all on table public.admin_users from anon, authenticated, service_role;
grant select, insert, update, delete on table public.admin_users to service_role;
