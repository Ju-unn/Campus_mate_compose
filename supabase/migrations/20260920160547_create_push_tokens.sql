-- 조각 4: FCM 토큰과 알림 스위치(ERD §4, 화면 16d `NMgCa`).
create type public.device_platform as enum ('android', 'ios');

-- 토큰이 PK 다 — 같은 기기를 다른 계정으로 로그인하면 토큰의 주인만 바뀐다(중복 행이 생기지 않는다).
create table public.push_tokens (
  token text primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  platform public.device_platform not null,
  updated_at timestamptz not null default now()
);

comment on table public.push_tokens is
  'FCM 등록 토큰(ERD §4). 탈퇴 시 cascade 로 즉시 지워진다. 클라이언트 읽기 권한 없음';

create index push_tokens_profile_index on public.push_tokens (profile_id);

create table public.notification_settings (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  card_arrived boolean not null default true,
  acceptance_received boolean not null default true,
  match_made boolean not null default true,
  new_message boolean not null default true,        -- 조각 5
  trust_reminder boolean not null default true,     -- 조각 5
  new_friend_review boolean not null default true,  -- 조각 6
  marketing boolean not null default false,
  marketing_consented_at timestamptz,
  -- 22시~8시 알림 보류. 단, 아침 7시 카드 도착 알림은 예외다(계획서 "실행 전 확인 사항" 6번).
  quiet_hours boolean not null default true
);

comment on table public.notification_settings is
  '알림 스위치(화면 16d). 행이 없으면 전부 기본값(마케팅만 false)으로 본다';

alter table public.push_tokens enable row level security;
alter table public.notification_settings enable row level security;

-- push_tokens: 정책 없음 = 클라이언트는 자기 토큰도 못 읽는다(ERD §2 "읽기 없음"). 등록은 FastAPI 경유.
create policy "notification settings are readable by owner"
  on public.notification_settings
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.push_tokens, public.notification_settings
  from anon, authenticated, service_role;
grant select on table public.notification_settings to authenticated;
grant select, insert, update, delete on table public.push_tokens, public.notification_settings
  to service_role;
