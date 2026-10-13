-- 사용자 채널 실시간 정책 검증 — 채팅 실시간 전환 설계안(10-13) 안 A 2단계. 앱은 비공개 채널 `user:<내 profile_id>` 하나를 듣고,
-- 서버(service_role)가 REST Broadcast 로 그 채널에 쏜다. 입장 권한은 realtime.messages 의 RLS 가 정한다.
-- Realtime 은 입장할 때 role · request.jwt.claim.sub · realtime.topic 을 세션에 걸고 realtime.messages 의 시험 행이 보이는지로
-- 받기(select) 권한을 판단한다 — 정책은 행의 topic 칸이 아니라 realtime.topic() 을 보므로 여기서도 같은 설정으로 행을 읽어 본다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

-- 1. 정책의 모양 --------------------------------------------------------------

-- 보내기(insert) 정책이 생기면 앱이 남의 채널로 가짜 이벤트를 쏠 수 있다. 정책은 본인 토픽 읽기 하나뿐이어야 한다.
select results_eq(
  -- policyname · roles 는 name 형(정렬 규칙 "C")이라 기대값과 비교하려면 정렬 규칙을 맞춰야 한다.
  $$select policyname::text collate "default", cmd, roles::text collate "default"
      from pg_policies
     where schemaname = 'realtime' and tablename = 'messages'$$,
  $$values ('user_channel_read_own'::text, 'SELECT'::text, '{authenticated}'::text)$$,
  'realtime.messages 정책은 authenticated 의 본인 토픽 읽기 하나뿐이다(보내기 정책 없음)'
);

select is(
  (select relrowsecurity from pg_class where oid = 'realtime.messages'::regclass),
  true,
  'realtime.messages 는 RLS 가 켜져 있다'
);

-- 준비 (postgres) -------------------------------------------------------------
-- 사용자 A = ...c1a1, 사용자 B = ...c1b1. 정책은 auth.uid() 만 보고 테이블을 읽지 않으므로 계정 행은 필요 없다.

-- realtime.messages 는 inserted_at 하루 단위 파티션 표다(기본 파티션 없음 — 맞는 파티션이 없으면 넣기가 실패한다).
-- 파티션은 Realtime 서비스가 며칠 앞까지 만들어 두고, postgres 는 realtime 스키마에 표를 만들 권한이 없어 시험이 만들 수 없다.
-- 그래서 오늘 날짜 대신 이미 있는 파티션 중 가장 늦은 날짜로 넣는다(파티션이 하나도 없으면 아래 넣기가 오류로 멈춘다).
do $$
begin
  perform set_config('test.realtime_day', (
    select max(substring(pg_get_expr(c.relpartbound, c.oid) from 'FROM \(''([^'']+)''\)'))
      from pg_inherits i
      join pg_class c on c.oid = i.inhrelid
     where i.inhparent = 'realtime.messages'::regclass
  ), true);
end
$$;

insert into realtime.messages (topic, extension, event, payload, private, inserted_at) values
  ('user:00000000-0000-0000-0000-00000000c1a1', 'broadcast', 'message', '{}', true, current_setting('test.realtime_day')::timestamp),
  ('user:00000000-0000-0000-0000-00000000c1a1', 'presence', 'presence', '{}', true, current_setting('test.realtime_day')::timestamp);

-- 2. authenticated ------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-00000000c1a1';
set local realtime.topic to 'user:00000000-0000-0000-0000-00000000c1a1';

select results_eq(
  $$select topic, extension from realtime.messages$$,
  $$values ('user:00000000-0000-0000-0000-00000000c1a1'::text, 'broadcast'::text)$$,
  'A 는 본인 토픽 user:A 의 broadcast 를 받는다'
);

select is_empty(
  $$select 1 from realtime.messages where extension = 'presence'$$,
  'A 도 본인 토픽의 presence 는 못 받는다(broadcast 만 연다)'
);

set local request.jwt.claim.sub to '00000000-0000-0000-0000-00000000c1b1';

select is_empty(
  $$select 1 from realtime.messages$$,
  'B 는 남의 토픽 user:A 에 입장하지 못한다'
);

set local request.jwt.claim.sub to '00000000-0000-0000-0000-00000000c1a1';
set local realtime.topic to 'user:00000000-0000-0000-0000-00000000c1b1';

select is_empty(
  $$select 1 from realtime.messages$$,
  'A 는 남의 토픽 user:B 에 입장하지 못한다'
);

set local realtime.topic to 'user:00000000-0000-0000-0000-00000000c1a1';

select throws_ok(
  $$insert into realtime.messages (topic, extension, event, payload, private, inserted_at)
    values ('user:00000000-0000-0000-0000-00000000c1a1', 'broadcast', 'message', '{}', true,
            current_setting('test.realtime_day')::timestamp)$$,
  '42501', null,
  'A 는 본인 토픽에도 보내지 못한다(보내기 정책이 없어 쏘는 쪽은 서버뿐이다)'
);

-- 3. anon ---------------------------------------------------------------------

-- 정책이 role 로만 막는지 보려고 sub 와 토픽은 A 그대로 둔다(anon 키에는 원래 sub 가 없다).
set local role anon;

select is_empty(
  $$select 1 from realtime.messages$$,
  'anon 은 user:A 토픽에 입장하지 못한다'
);

select * from finish();
rollback;
