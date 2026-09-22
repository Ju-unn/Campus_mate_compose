-- 조각 6 준비(백로그 7): messages.sender_id 인덱스.
-- 탈퇴는 profiles 행을 지우고, messages.sender_id 의 on delete cascade 가 그 사람이 쓴 줄을
-- 전부 따라 지운다. 인덱스가 없으면 그 삭제가 messages 전체 스캔이라 탈퇴 한 건이 방마다 쌓인
-- 대화 전부를 훑는다 — 조각 6 탈퇴를 붙이기 전에 깔아 둔다.
-- 이미 적용된 마이그레이션은 고치지 않는다(20260922011851_create_messages.sql 는 그대로 둔다).
create index if not exists messages_sender_index on public.messages (sender_id);

comment on index public.messages_sender_index is
  '탈퇴(프로필 삭제) 때 sender_id cascade 가 타는 인덱스(백로그 7)';
