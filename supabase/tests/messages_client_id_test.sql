-- 1.0.7 #8 채팅 재전송 두 줄 막기: messages.client_id 와 유일 제약 검증. 기대값 기준은 docs/ERD.md §4.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- 준비 --------------------------------------------------------------------
-- A = ...a0, B = ...b0. 매칭 하나(A↔B)에 둘 다 참여 중이다.
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test.ac.kr', '00000000-0000-0000-0000-000000000001');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a0', 'cid-a@test.ac.kr'),
  ('00000000-0000-0000-0000-0000000000b0', 'cid-b@test.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000001' from auth.users
on conflict (id) do nothing;

-- profile_a < profile_b 제약 때문에 A 가 앞이다.
insert into public.matches (id, profile_a, profile_b) values
  ('00000000-0000-0000-0000-000000008001',
   '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000b0');

insert into public.match_participants (match_id, profile_id) values
  ('00000000-0000-0000-0000-000000008001', '00000000-0000-0000-0000-0000000000a0'),
  ('00000000-0000-0000-0000-000000008001', '00000000-0000-0000-0000-0000000000b0');

-- 1. 칸 모양 -------------------------------------------------------------------

select has_column('public', 'messages', 'client_id', 'messages 에 client_id 칸이 있다');

select col_type_is('public', 'messages', 'client_id', 'uuid', 'client_id 는 uuid 다');

-- 옛 앱 · 시스템 줄은 client_id 없이 들어온다. not null 이면 지금 스토어 앱의 전송이 깨진다.
select col_is_null('public', 'messages', 'client_id', 'client_id 는 null 을 허용한다');

-- 기본값이 있으면 옛 줄도 값이 생겨 "앱이 보낸 id" 라는 뜻이 흐려진다.
select col_hasnt_default('public', 'messages', 'client_id', 'client_id 에는 기본값이 없다');

-- PostgREST on_conflict 는 부분 인덱스를 못 쓴다 — 일반 유일 "제약"(contype u)이어야 하고 칸 셋이 이 순서여야 한다.
select is(
  (select array_agg(a.attname::text order by k.ord)
     from pg_constraint c
     cross join unnest(c.conkey) with ordinality as k(attnum, ord)
     join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.conrelid = 'public.messages'::regclass
      and c.conname = 'messages_client_id_unique'
      and c.contype = 'u'),
  array['match_id', 'sender_id', 'client_id'],
  'messages_client_id_unique 는 (match_id, sender_id, client_id) 일반 유일 제약이다'
);

-- 2. 같은 줄 두 번 막기 ---------------------------------------------------------

select lives_ok(
  $$insert into public.messages (match_id, sender_id, body, client_id)
    values ('00000000-0000-0000-0000-000000008001',
            '00000000-0000-0000-0000-0000000000a0', '안녕하세요',
            '00000000-0000-0000-0000-00000000c001')$$,
  'client_id 가 붙은 첫 메시지는 들어간다'
);

-- 재전송: 같은 보낸이 · 같은 방 · 같은 id 는 두 번째 줄이 되지 못한다.
select throws_ok(
  $$insert into public.messages (match_id, sender_id, body, client_id)
    values ('00000000-0000-0000-0000-000000008001',
            '00000000-0000-0000-0000-0000000000a0', '안녕하세요',
            '00000000-0000-0000-0000-00000000c001')$$,
  '23505', null, '같은 (match_id, sender_id, client_id) 두 번째 넣기는 23505 로 실패한다'
);

-- 서버가 쓸 모양(PostgREST on_conflict = 이 칸 셋 + ignore-duplicates). 부분 인덱스면 42P10 으로 깨진다.
select lives_ok(
  $$insert into public.messages (match_id, sender_id, body, client_id)
    values ('00000000-0000-0000-0000-000000008001',
            '00000000-0000-0000-0000-0000000000a0', '안녕하세요',
            '00000000-0000-0000-0000-00000000c001')
    on conflict (match_id, sender_id, client_id) do nothing$$,
  'on conflict (match_id, sender_id, client_id) do nothing 이 제약을 찾아 조용히 넘어간다'
);

select is(
  (select count(*) from public.messages
    where client_id = '00000000-0000-0000-0000-00000000c001'),
  1::bigint, '재전송을 몇 번 해도 그 client_id 줄은 하나뿐이다'
);

-- 3. 막지 말아야 할 것 ----------------------------------------------------------

-- NULL 끼리는 겹치지 않는다 — 옛 앱 말풍선과 시스템 줄은 지금처럼 몇 줄이든 들어간다.
select lives_ok(
  $$insert into public.messages (match_id, sender_id, kind, body) values
      ('00000000-0000-0000-0000-000000008001',
       '00000000-0000-0000-0000-0000000000a0', 'text', '옛 앱 말풍선'),
      ('00000000-0000-0000-0000-000000008001',
       '00000000-0000-0000-0000-0000000000a0', 'trust_accept', '카톡 공유를 수락했어요')$$,
  'client_id 가 null 인 줄은 같은 방 같은 보낸이로 여러 줄 들어간다'
);

-- 두 사람이 우연히 같은 id 를 써도 서로의 메시지를 지우지 않는다.
select lives_ok(
  $$insert into public.messages (match_id, sender_id, body, client_id)
    values ('00000000-0000-0000-0000-000000008001',
            '00000000-0000-0000-0000-0000000000b0', '반가워요',
            '00000000-0000-0000-0000-00000000c001')$$,
  '같은 client_id 라도 보낸이가 다르면 들어간다'
);

-- 4. 쓰기 권한은 그대로 FastAPI 전용 ------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000000a0", "role": "authenticated"}';

select throws_ok(
  $$insert into public.messages (match_id, sender_id, body, client_id)
    values ('00000000-0000-0000-0000-000000008001',
            '00000000-0000-0000-0000-0000000000a0', '직접 넣기',
            '00000000-0000-0000-0000-00000000c002')$$,
  '42501', null, 'authenticated 는 client_id 를 붙여도 메시지를 직접 넣을 수 없다'
);

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
