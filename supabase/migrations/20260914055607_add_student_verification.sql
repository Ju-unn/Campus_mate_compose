-- 조각 1 스키마 1/4: 학생증 인증 상태.
-- 기준 문서: docs/ERD.md §3 · §8 · §12-4
--
-- 초안(2026-09-14, 미적용). enum 값은 만든 뒤 지울 수 없으므로(ERD §8)
-- 아래 4개 값을 사용자가 확정하기 전에는 클라우드에 적용하지 않는다.
-- 재시도 횟수를 담을 곳(ERD §12-4)도 아직 정하지 않아 여기 넣지 않았다.

-- none 은 아직 학생증을 내지 않음, pending 은 자동 대조가 애매해 사람이 재검토하는 중(3b "조금 더 확인이 필요해요").
create type public.verification_status as enum ('none', 'pending', 'verified', 'rejected');

-- 상태는 FastAPI 만 바꾼다. profiles 에는 클라이언트 update 권한이 없어(조각 0)
-- 사용자가 자기 상태를 verified 로 바꾸는 우회는 권한 단계에서 막힌다.
-- 본인은 기존 select 권한으로 자기 상태를 읽는다(3b 대기 화면 · 16e).
alter table public.profiles
  add column student_verification public.verification_status not null default 'none';
