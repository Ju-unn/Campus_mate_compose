-- pg_net 을 extensions 스키마로 옮긴다(advisor extension_in_public).
-- 20261003030000 의 create extension 이 스키마를 안 적어 public 에 올라갔다. pg_net 은 ALTER EXTENSION SET SCHEMA 를 지원하지 않아 drop/create 한다.
-- 함수 · 큐는 net 스키마에 그대로 생기므로 notify_verification_reviewed 의 net.http_post 본문은 손대지 않는다.
drop extension if exists pg_net;
create extension if not exists pg_net with schema extensions;
