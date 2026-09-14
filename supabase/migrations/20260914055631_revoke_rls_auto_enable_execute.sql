-- 조각 1 스키마 4/6: Supabase advisor 보안 WARN 0028 · 0029 대응.
-- 기준 문서: docs/ERD.md §12-34 (2026-09-14 사용자 결정)
-- 초안(2026-09-14, 미적용).
--
-- public.rls_auto_enable() 은 우리 마이그레이션이 아니라 클라우드 프로젝트를 만들 때 켠 자동 RLS 옵션이 만든 함수로 보인다.
-- event trigger 전용이라 RPC 로 불러도 실행되지 않지만 anon · authenticated 에 실행 권한이 있어 경고가 뜬다.
-- 우리 마이그레이션은 테이블마다 RLS 를 직접 켜므로 이 함수에 기대지 않는다.
-- 로컬 fresh DB 에는 이 함수가 없으므로 있을 때만 revoke 한다.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from anon, authenticated, public;
  end if;
end
$$;
