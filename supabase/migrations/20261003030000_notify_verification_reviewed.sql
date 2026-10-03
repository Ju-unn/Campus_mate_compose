-- 결함 A7 · 결정 3(2026-10-01): 학생증 검토 결과 알림.
-- 대시보드에서 profiles.student_verification 을 pending → verified/rejected 로 바꾸는 순간
-- FastAPI POST /hooks/verification-reviewed 를 부른다. 서버가 상태를 다시 읽고 FCM 으로 보낸다.
-- 자동 판정(OCR 통과)도 pending → verified 라 같이 불린다 — 앱이 켜져 있으면 배너 없이 화면만 새로 고친다.
--
-- 주소와 공유 비밀은 Supabase Vault 에서 읽는다(이름 verification_hook_url · verification_hook_secret).
-- 값은 마이그레이션 · 저장소에 두지 않고 운영에서 사람이 넣는다. 둘 중 하나라도 없으면 아무것도 보내지 않는다 —
-- 로컬 DB 와 pgTAP 은 밖으로 요청을 내지 않는다.

create extension if not exists pg_net;

create function public.notify_verification_reviewed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  hook_url text;
  hook_secret text;
begin
  select decrypted_secret into hook_url
    from vault.decrypted_secrets where name = 'verification_hook_url';
  select decrypted_secret into hook_secret
    from vault.decrypted_secrets where name = 'verification_hook_secret';

  if hook_url is null or hook_secret is null then
    return new;
  end if;

  -- pg_net 은 커밋 뒤에 보낸다 — 대시보드 저장이 롤백되면 알림도 안 나간다.
  -- 서버 첫 깨움이 5초를 넘을 수 있어(A17) 기본 2초 대신 10초를 기다린다.
  perform net.http_post(
    url := hook_url,
    body := jsonb_build_object('profile_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', hook_secret),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

comment on function public.notify_verification_reviewed() is
  '학생증 검토 결과(pending → verified/rejected) 알림 웹훅. Vault 값이 없으면 건너뛴다(결함 A7)';

-- security definer 함수는 트리거만 부른다 — 누구도 직접 부를 수 없게 기본 public 실행 권한을 걷는다(home_stats 와 같은 관례).
revoke execute on function public.notify_verification_reviewed() from public, anon, authenticated;

create trigger on_student_verification_reviewed
  after update of student_verification on public.profiles
  for each row
  when (old.student_verification = 'pending' and new.student_verification in ('verified', 'rejected'))
  execute function public.notify_verification_reviewed();
