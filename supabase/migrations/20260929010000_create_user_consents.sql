-- 가입 동의 기록(화면 02-c, 사용자 결정 2026-09-29). 기준 문서: docs/ERD.md §3 user_consents
-- 계획서: docs/superpowers/plans/2026-09-29-signup-consent.md Task 1
-- 필수 4항목만 쌓는다. 마케팅(선택)은 notification_settings.marketing · marketing_consented_at 을 쓴다.
-- 판(version)은 FastAPI 상수 CONSENT_VERSION(app/consents/policy.py)이다. 약관을 고치면 판이 올라가
-- 이미 가입한 계정도 모두 다시 동의한다.
create type public.consent_kind as enum ('terms', 'privacy', 'sensitive_religion', 'overseas_transfer');

create table public.user_consents (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  kind public.consent_kind not null,
  version text not null check (version ~ '^\d{4}-\d{2}-\d{2}$'),
  agreed_at timestamptz not null default now(),
  primary key (profile_id, kind, version)
);

comment on table public.user_consents is
  '가입 동의 기록(화면 02-c). FastAPI 전용 — 동의 시각은 서버가 적는다. 탈퇴 계정 삭제 때 같이 지운다';

alter table public.user_consents enable row level security;

-- referrals 와 같은 규칙: 정책 없음 = 클라이언트는 자기 기록도 못 읽는다. 기록은 고치지 않는다(update · delete 없음).
revoke all on table public.user_consents from anon, authenticated, service_role;
grant select, insert on table public.user_consents to service_role;
