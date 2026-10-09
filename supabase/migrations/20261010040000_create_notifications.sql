-- 알림함(설계 §8): 푸시와 별개로 앱 안 알림 목록에 쌓는 기록. 푸시를 못 받았거나 껐어도 여기서 다시 볼 수 있다.
-- kind 는 열거형이 아니라 text + check 다 — 새 종류는 check 를 바꾸는 마이그레이션 한 줄로 늘린다(pending_pushes 와 같다).
-- 90일 보관 정리는 서버 배치 몫이라 여기서 만들지 않는다.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in (
    'card_arrived', 'chat_request', 'match_made', 'friend_review', 'verification_result', 'night_digest'
  )),
  title text not null,
  body text not null,
  -- 눌렀을 때 가는 화면 같은 값(푸시 data 와 같은 모양)
  data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  read_at timestamptz
);

comment on table public.notifications is
  '앱 안 알림함(설계 §8). 안 읽은 개수 · 목록은 FastAPI 가 service_role 로 읽어 내려준다';

-- 안 읽은 알림 개수 · 빨간 점
create index notifications_unread_index on public.notifications (profile_id) where read_at is null;
-- 최근순 목록
create index notifications_profile_created_index on public.notifications (profile_id, created_at desc);

-- RLS: 정책 없음 = 클라이언트는 직접 읽지 못한다.
alter table public.notifications enable row level security;

revoke all on table public.notifications from anon, authenticated, service_role;
grant select, insert, update, delete on table public.notifications to service_role;
