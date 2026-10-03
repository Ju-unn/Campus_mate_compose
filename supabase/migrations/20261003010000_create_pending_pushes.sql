-- 밤에 보류된 알림(결정 4 · B1, 사용자 결정 2026-10-01). 기준 문서: docs/ERD.md §4 pending_pushes
-- 조용한 시간(22~08시)에 걸린 받은 수락 · 매칭 · 지인 리뷰 · 학생증 검토 결과(A7) 알림을 버리지 않고 여기 쌓는다(app/cards/push.py notify).
-- 매시 chat-gate 배치가 조용하지 않은 시각에 사람 × 가는 화면(data.route)으로 묶어 보내고 지운다.
-- 채팅 · 카드 도착은 조용한 시간 예외라 여기 안 온다. trust_reminder 는 보낼 시각을 08시로 미뤄 두어 안 온다.
create table public.pending_pushes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('acceptance_received', 'match_made', 'new_friend_review', 'verification_result')),
  -- 원래 알림 그대로. 한 건뿐이면 이대로 보내고, 여러 건이면 묶음 문구로 바꾼다.
  title text not null,
  body text not null,
  data jsonb not null default '{}',
  created_at timestamptz not null default now()
);

comment on table public.pending_pushes is
  '조용한 시간에 보류된 알림(결정 4). FastAPI 전용 — 매시 chat-gate 배치가 08~21시에 묶어 보내고 지운다';

create index pending_pushes_profile_index on public.pending_pushes (profile_id);

alter table public.pending_pushes enable row level security;

-- push_tokens 와 같은 규칙: 정책 없음 = 클라이언트는 자기 행도 못 읽는다. 보낸 행은 지울 뿐 고치지 않는다.
revoke all on table public.pending_pushes from anon, authenticated, service_role;
grant select, insert, delete on table public.pending_pushes to service_role;
