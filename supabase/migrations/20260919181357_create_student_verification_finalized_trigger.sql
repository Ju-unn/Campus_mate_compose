-- 조각 1b: 학생증 인증이 확정(verified/rejected)되는 순간 임시 사진을 지운다.
-- FastAPI 자동 통과든 사람이 Supabase 대시보드에서 손으로 바꾼 경우든 이 트리거 하나로 처리한다
-- (2026-09-19 설계 — 두 경로가 결국 같은 UPDATE 문을 타므로 삭제 코드를 한 곳에만 둔다).
-- 보관 기간 없이 확정 즉시 삭제(2026-09-20 재확인).
-- 기준 문서: 설계 §7.3·§7.4, docs/ERD.md §9

create or replace function public.handle_student_verification_finalized()
returns trigger
language plpgsql
as $$
declare
  latest_path text;
begin
  -- pending 에서 확정으로 바뀔 때만 지운다. none 에서 곧장 바뀌는 경로는 없다(라우터·FastAPI 가 강제).
  if old.student_verification is distinct from 'pending'
     or new.student_verification not in ('verified', 'rejected') then
    return new;
  end if;

  select file_path into latest_path
    from public.student_verification_attempts
    where profile_id = new.id
    order by submitted_at desc
    limit 1;

  if latest_path is not null then
    delete from storage.objects
      where bucket_id = 'student-id-temp' and name = latest_path;
  end if;

  return new;
end;
$$;

-- SECURITY DEFINER 를 안 쓴다 — 이 UPDATE 를 실행하는 두 주체(FastAPI 의 service_role, Supabase
-- 대시보드의 postgres/superuser 연결) 모두 storage.objects 에 이미 충분한 권한이 있다(2026-09-19 설계).
create trigger student_verification_finalized
  after update of student_verification on public.profiles
  for each row
  execute function public.handle_student_verification_finalized();
