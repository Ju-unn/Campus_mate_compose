-- 조각 6: 차단. 차단당한 쪽은 알 수 없어야 한다(설계 §7.2) — 클라이언트는 읽지도 못한다.
-- 16f 목록은 FastAPI 가 준다.
create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(), -- 16f 차단일
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);

comment on table public.blocks is
  '차단. FastAPI 전용, 클라이언트 접근 없음(설계 §7.2) — 차단당한 쪽은 알 수 없어야 한다';

-- 카드·매칭 후보에서 양방향으로 빼는 쿼리가 이 인덱스를 탄다(blocked_id 쪽 조회).
-- 탈퇴 cascade(blocked_id 쪽 행 삭제)도 이 인덱스를 탄다.
create index blocks_blocked_id_index on public.blocks (blocked_id);

alter table public.blocks enable row level security;

revoke all on table public.blocks from anon, authenticated, service_role;
grant select, insert, update, delete on table public.blocks to service_role;
