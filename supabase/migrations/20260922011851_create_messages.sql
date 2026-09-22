-- 조각 5: 매칭된 두 사람의 1:1 대화(설계 §2.5, ERD §4). 텍스트만 저장한다(§13-13).
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,

  -- 결정 7·10: 사람이 쓰지 않은 줄이 섞인다. text 는 말풍선, 나머지는 시스템 줄로 그린다.
  -- 새 종류가 생기면 값을 늘린다 — 테이블을 나누지 않는다.
  kind text not null default 'text'
    check (kind in ('text', 'left', 'trust_accept')),

  body text not null,
  created_at timestamptz not null default now(),

  -- 길이 상한은 서버(pydantic)와 DB 양쪽에 둔다. 빈 문자열·공백만 있는 메시지는 막는다.
  constraint messages_body_length check (char_length(btrim(body)) between 1 and 1000)
);

comment on table public.messages is
  '매칭 대화의 메시지(ERD §4). 쓰기는 FastAPI 전용, 읽기는 참여 중인 당사자만';
comment on column public.messages.kind is
  'text=사람이 쓴 말풍선 / left=나감 / trust_accept=한쪽 수락. sender_id 는 그 일을 한 사람';

-- 방을 열면 "이 매칭의 최근 50건"을 시간 역순으로 읽는다. 목록 화면의 마지막 메시지도 같은 인덱스를 탄다.
create index messages_match_created_index on public.messages (match_id, created_at desc);

alter table public.messages enable row level security;

-- 참여 중인 매칭의 메시지만. 채팅방을 나간 사람(left_at)은 자기 대화도 더 못 읽는다.
-- 조건은 읽는 사람 본인의 행에만 걸리므로, 상대가 나가도 남은 사람은 계속 읽는다(결정 7).
create policy "messages are readable by active participants"
  on public.messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.match_participants mp
      where mp.match_id = messages.match_id
        and mp.profile_id = (select auth.uid())
        and mp.left_at is null
    )
  );

revoke all on table public.messages from anon, authenticated, service_role;
grant select on table public.messages to authenticated;
grant select, insert, update, delete on table public.messages to service_role;

-- 앱이 INSERT 만 구독한다(결정 1). 구독에도 위 RLS 가 그대로 걸린다.
alter publication supabase_realtime add table public.messages;
