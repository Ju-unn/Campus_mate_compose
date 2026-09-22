-- 조각 5 RLS · 권한 검증. 기대값 기준은 docs/ERD.md §2·§4 와 설계 §2.5, 계획서 Task C2.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- 준비 --------------------------------------------------------------------
-- A = ...a0(나), B = ...b0(A 와 매칭된 상대, 둘 다 나가지 않음),
-- C = ...c0(이 매칭과 무관한 사람), D = ...d0(A 와 매칭됐지만 A 가 나간 매칭의 상대)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

-- auth.users 트리거(handle_new_user_profile)가 이메일 도메인으로 학교를 찾는다 — 없으면 가입이 막힌다.
insert into public.university_email_domains (domain, university_id)
values ('test.ac.kr', '00000000-0000-0000-0000-000000000001');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a0', 'm5-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b0', 'm5-b@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000c0', 'm5-c@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000d0', 'm5-d@test.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000001' from auth.users
on conflict (id) do nothing;

-- 매칭 두 개. profile_a < profile_b 제약 때문에 A 가 항상 앞이다.
insert into public.matches (id, profile_a, profile_b) values
  ('00000000-0000-0000-0000-000000005001',
   '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000b0'),
  ('00000000-0000-0000-0000-000000005002',
   '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000d0');

-- A↔B: 둘 다 참여 중. A↔D: A 만 나갔다(D 는 남아 있다).
insert into public.match_participants (match_id, profile_id, left_at) values
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000000a0', null),
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000000b0', null),
  ('00000000-0000-0000-0000-000000005002', '00000000-0000-0000-0000-0000000000a0', now()),
  ('00000000-0000-0000-0000-000000005002', '00000000-0000-0000-0000-0000000000d0', null);

-- A↔B 에 2건, A↔D 에 1건. A↔D 에 메시지를 남겨 두는 것이 핵심이다 —
-- 정책에서 left_at 조건을 지우면 3번이 바로 깨진다.
insert into public.messages (match_id, sender_id, kind, body) values
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000000a0', 'text', '안녕하세요'),
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000000b0', 'text', '반가워요'),
  ('00000000-0000-0000-0000-000000005002', '00000000-0000-0000-0000-0000000000a0', 'left',
   '가나다님이 채팅방을 나갔어요');

-- 1. 당사자 · 비당사자 · 나간 사람 --------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000a0", "role": "authenticated"}';

select is(
  (select count(*) from public.messages),
  2::bigint, 'A 는 참여 중인 매칭의 메시지 2건만 본다'
);

set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000c0", "role": "authenticated"}';

select is(
  (select count(*) from public.messages),
  0::bigint, '매칭과 무관한 C 는 아무 메시지도 볼 수 없다'
);

-- A 는 A↔D 매칭을 나갔다. 그 방에 메시지가 있어도 자기 대화를 더는 못 읽는다.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000a0", "role": "authenticated"}';

select is_empty(
  $$select id from public.messages
     where match_id = '00000000-0000-0000-0000-000000005002'$$,
  '나간 사람은 그 방의 메시지를 더 이상 읽지 못한다'
);

-- 같은 방을 반대편에서 본다. 상대가 나가도 남은 사람은 계속 읽는다(결정 7).
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000d0", "role": "authenticated"}';

select is(
  (select count(*) from public.messages
    where match_id = '00000000-0000-0000-0000-000000005002'),
  1::bigint, '상대가 나가도 남은 사람은 그 방의 메시지를 계속 읽는다'
);

-- 2. 쓰기는 FastAPI 전용 ------------------------------------------------------

select throws_ok(
  $$insert into public.messages (match_id, sender_id, body)
    values ('00000000-0000-0000-0000-000000005002',
            '00000000-0000-0000-0000-0000000000d0', '직접 넣기')$$,
  '42501', null, 'authenticated 는 메시지를 직접 넣을 수 없다'
);

select throws_ok(
  $$update public.messages set body = '고침'
     where match_id = '00000000-0000-0000-0000-000000005002'$$,
  '42501', null, 'authenticated 는 메시지를 고칠 수 없다'
);

select throws_ok(
  $$delete from public.messages
     where match_id = '00000000-0000-0000-0000-000000005002'$$,
  '42501', null, 'authenticated 는 메시지를 지울 수 없다'
);

reset role;
reset request.jwt.claims;

-- 3. 권한 · publication · 제약 -------------------------------------------------

select ok(
  has_table_privilege('service_role', 'public.messages', 'select')
    and has_table_privilege('service_role', 'public.messages', 'insert')
    and has_table_privilege('service_role', 'public.messages', 'update')
    and has_table_privilege('service_role', 'public.messages', 'delete'),
  'service_role 은 메시지를 읽고 쓰고 고치고 지운다(FastAPI 전용 경로)'
);

-- 앱이 새 메시지를 실시간으로 받는 유일한 통로다(결정 1). 빠지면 채팅이 조용히 멎는다.
select is(
  (select count(*) from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'),
  1::bigint, 'messages 가 supabase_realtime publication 에 들어 있다'
);

select throws_ok(
  $$insert into public.messages (match_id, sender_id, kind, body)
    values ('00000000-0000-0000-0000-000000005001',
            '00000000-0000-0000-0000-0000000000a0', 'shout', '고함')$$,
  '23514', null, '정해지지 않은 kind 는 들어가지 않는다'
);

select * from finish();
rollback;
