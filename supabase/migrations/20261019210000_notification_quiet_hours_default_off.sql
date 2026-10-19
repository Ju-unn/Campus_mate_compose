-- 방해 금지 시간(22~08시, notification_settings.quiet_hours)을 새 가입자에게는 처음에 꺼 둔다(사용자 결정 2026-10-19).
-- 기존 사용자의 값은 바꾸지 않는다:
--   1) 설정 행이 아직 없는 기존 사용자는 서버가 "행 없음 = 켜짐(true)"으로 보고 있었다. 기본값을 바꾸면 그들이 조용히 꺼짐이 되므로,
--      지금 시점의 값(전부 켜짐, 마케팅 꺼짐 = 컬럼 기본값 그대로)을 행으로 먼저 채우되 quiet_hours 만 true 를 명시한다.
--   2) 그다음 컬럼 기본값을 false 로 바꾼다 — 이후 가입자는 행이 없어도(서버 NOTIFICATION_DEFAULTS) 행이 생겨도(예: 마케팅 동의 upsert) 꺼짐이다.
-- 이미 행이 있는 사용자(true 든 false 든)는 건드리지 않는다. 함수 · 권한 변경이 없어 revoke 는 해당 없음.
-- 적용 순서: 이 마이그레이션 → 서버 배포(NOTIFICATION_DEFAULTS) → 앱.
-- 시험: supabase/tests/notification_quiet_hours_default_test.sql

insert into public.notification_settings (profile_id, quiet_hours)
select p.id, true
from public.profiles p
where not exists (select 1 from public.notification_settings s where s.profile_id = p.id);

alter table public.notification_settings
  alter column quiet_hours set default false;
