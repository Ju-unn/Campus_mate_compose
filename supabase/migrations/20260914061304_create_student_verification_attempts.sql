-- 조각 1 스키마 5/5: 학생증 인증 시도 기록.
-- 기준 문서: docs/ERD.md §2 · §3 · §12-4
-- 초안(2026-09-14), 클라우드 미적용.
--
-- 재시도 횟수를 담는 방식은 시도 기록 테이블로 정했다(ERD §12-4, 2026-09-14 사용자 결정).
-- 제출 한 번에 한 행이고, 재시도 횟수는 컬럼 대신 이 테이블의 행 수로 FastAPI 가 센다.
-- profiles.student_verification 은 현재 상태만 담고, 반려 사유 · 재검토 이력은 여기 남는다.

create table public.student_verification_attempts (
  id bigint generated always as identity primary key,
  -- 계정을 지워 profiles 가 cascade 로 지워지면 시도 기록도 지워진다(탈퇴 30일 뒤, ERD §2).
  profile_id uuid not null references public.profiles (id) on delete cascade,
  -- student-id-temp 버킷의 객체 경로. 검증이 끝나 파일을 지워도 경로 문자열은 남는다.
  file_path text not null,
  -- 제출 직후 pending. none 은 "아직 내지 않음" 이라 시도 결과가 될 수 없다.
  result public.verification_status not null default 'pending' check (result <> 'none'),
  -- rejected 일 때 FastAPI 가 쓴다. 본인에게는 FastAPI 응답으로 내려준다.
  reject_reason text,
  submitted_at timestamptz not null default now(),
  -- 자동 대조나 사람 재검토가 끝난 시각. 끝나기 전에는 null.
  reviewed_at timestamptz
);

create index student_verification_attempts_profile_id_index
  on public.student_verification_attempts (profile_id);

comment on table public.student_verification_attempts is '학생증 제출 한 번에 한 행. FastAPI 전용';

-- RLS 는 켜고 정책은 두지 않는다. 클라이언트는 이 테이블을 읽지도 쓰지도 않는다(ERD §2).
alter table public.student_verification_attempts enable row level security;

-- 권한(ERD §2): anon · authenticated 는 없음, service_role 은 select·insert·update·delete.
-- identity 컬럼은 insert 권한만으로 번호를 받으므로 시퀀스 grant 는 따로 주지 않는다.
revoke all on table public.student_verification_attempts from anon, authenticated, service_role;
grant select, insert, update, delete on table public.student_verification_attempts to service_role;
