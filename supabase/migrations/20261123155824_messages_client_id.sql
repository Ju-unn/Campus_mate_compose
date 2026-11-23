-- 1.0.7 #8 채팅 재전송 두 줄 막기(ERD §4, backend/DEPLOY.md §4-35).
-- 앱이 메시지마다 고유 id(client_id)를 붙여 보낸다. 응답을 못 받아 같은 id 로 다시 보내면
-- 서버가 on conflict 로 한 번만 저장하고 기존 줄을 돌려준다.

-- 제약을 짓는 동안 표를 잠근다. 긴 트랜잭션 뒤에 줄 서서 채팅 읽기 · 쓰기를 같이 세우지 않게 5초 안에 못 잡으면 실패한다
-- (선례 20261012010000). 실패하면 다시 적용하면 된다.
set local lock_timeout = '5s';

alter table public.messages add column client_id uuid;

comment on column public.messages.client_id is
  '앱이 메시지마다 붙이는 고유 id. 같은 보낸이가 같은 방에 같은 id 로 다시 보내면 서버가 한 번만 저장한다. 옛 앱 · 시스템 줄(left · trust_accept)은 null';

-- 부분 인덱스가 아니라 일반 유일 제약이다 — PostgREST on_conflict 는 부분 인덱스를 찾지 못한다(42P10).
-- NULL 끼리는 겹치지 않으므로 옛 앱 줄 · 시스템 줄은 그대로 들어간다.
-- sender_id 를 넣는 이유: 상대가 내 client_id 를 읽을 수 있어도(참여자 select) 상대 글과 엮이지 않게.
-- 기존 줄은 새 칸이 전부 null 이라 제약 만들기가 실패하지 않는다. 인덱스를 짓는 동안 표가 잠깐 잠긴다.
alter table public.messages
  add constraint messages_client_id_unique unique (match_id, sender_id, client_id);

-- RLS · grant · publication 은 바꾸지 않는다(쓰기는 지금처럼 service_role 만).
