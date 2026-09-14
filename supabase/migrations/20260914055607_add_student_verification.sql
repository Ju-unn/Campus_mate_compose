-- 조각 1 스키마 1/5: 학생증 인증 상태.
-- 기준 문서: docs/ERD.md §3 · §8 · §12-4
--
-- 초안, 클라우드 미적용. enum 값은 만든 뒤 지울 수 없어(ERD §8) 아래 4개 값을 먼저 확정했다(2026-09-14 사용자 결정).
-- 재시도 횟수는 여기 두지 않고 student_verification_attempts 의 행 수로 센다(ERD §12-4).

-- none 은 아직 학생증을 내지 않음, pending 은 자동 대조가 애매해 사람이 재검토하는 중(3b "조금 더 확인이 필요해요").
create type public.verification_status as enum ('none', 'pending', 'verified', 'rejected');

-- 상태는 FastAPI 만 바꾼다. profiles 에는 클라이언트 update 권한이 없어(조각 0)
-- 사용자가 자기 상태를 verified 로 바꾸는 우회는 권한 단계에서 막힌다.
-- 본인은 기존 select 권한으로 자기 상태를 읽는다(3b 대기 화면 · 16e).
alter table public.profiles
  add column student_verification public.verification_status not null default 'none';
