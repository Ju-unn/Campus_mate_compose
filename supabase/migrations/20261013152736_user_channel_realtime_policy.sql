-- 채팅 실시간 전환(설계안 10-13 안 A 2단계): 사용자 채널 `user:<내 profile_id>` 입장 권한.
-- 앱은 로그인해 앞에 있는 동안 비공개(private) 채널 하나만 듣고, 서버(FastAPI, service_role)가 메시지 · 읽음 · 새 방 이벤트를
-- REST Broadcast 로 그 채널에 쏜다. service_role 은 RLS 를 거치지 않으므로 쏘는 쪽에는 정책이 필요 없다.
-- 비공개 채널의 입장 권한은 Realtime 이 realtime.messages 의 RLS 로 판단한다(select = 받기, insert = 보내기).
-- 받기(select) 정책만 둔다. 보내기(insert) 정책을 만들면 앱이 남의 채널로 가짜 이벤트를 쏠 수 있다 — 쏘는 쪽은 서버뿐이다.
-- 조건은 토픽 이름과 auth.uid() 만 본다(테이블 조회 없음) — 입장이 가볍고, 남의 토픽은 입장 때 거부된다.
-- Realtime 은 정책을 입장 때 한 번 계산해 캐시하므로 방을 나간 사람에게 안 쏘는 것은 서버 규칙(left_at)이 맡는다.
-- 테이블 · publication · grant 는 바꾸지 않는다. security definer 함수도 없다(SUPABASE.md §5).
-- 되돌리기: drop policy if exists "user_channel_read_own" on realtime.messages;
create policy "user_channel_read_own"
  on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) = 'user:' || (select auth.uid())::text
  );
