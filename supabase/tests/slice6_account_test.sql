-- 조각 6 PR 3 DB: 번호 HMAC 저장(set_phone_number 5인자) · 탈퇴(withdraw_account) · 탈퇴 계정 삭제.
-- 기대값 기준은 .superpowers/sdd/2026-09-22-slice6-safety/pr3-db-brief.md(계획서 Task B3 · B4).
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
-- 함수가 아직 없을 때도 오류로 멈추지 않고 실패로 세도록 to_regprocedure 를 쓴다.
-- 트랜잭션 하나라 now() 는 끝까지 같은 값이다 — blocked_until 을 now() 기준으로 딱 맞게 단정할 수 있다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

-- 준비 --------------------------------------------------------------------
-- PH = ...70(번호 저장), WA = ...71(active 탈퇴), WS = ...72(suspended 탈퇴),
-- WE = ...73(만료된 옛 재가입 제한 행이 있다), WI = ...74(infinity 옛 행이 있다),
-- DEL = ...75(자식 행을 잔뜩 가진 채 탈퇴 → 삭제), PT = ...76(DEL 의 상대방)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000008', '테스트대학교8', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test8.ac.kr', '00000000-0000-0000-0000-000000000008');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000070', 'a8-ph@test8.ac.kr'),
  ('00000000-0000-0000-0000-000000000071', 'a8-wa@test8.ac.kr'),
  ('00000000-0000-0000-0000-000000000072', 'a8-ws@test8.ac.kr'),
  ('00000000-0000-0000-0000-000000000073', 'a8-we@test8.ac.kr'),
  ('00000000-0000-0000-0000-000000000074', 'a8-wi@test8.ac.kr'),
  ('00000000-0000-0000-0000-000000000075', 'a8-del@test8.ac.kr'),
  ('00000000-0000-0000-0000-000000000076', 'a8-pt@test8.ac.kr');

-- on_auth_user_created 트리거가 pending 행을 이미 만든다(다른 테스트와 같은 모양).
insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000008' from auth.users
where email like 'a8-%@test8.ac.kr'
on conflict (id) do nothing;

update public.profiles set
  nickname = case id
    when '00000000-0000-0000-0000-000000000071' then '탈퇴가'
    when '00000000-0000-0000-0000-000000000072' then '탈퇴나'
    when '00000000-0000-0000-0000-000000000073' then '탈퇴다'
    when '00000000-0000-0000-0000-000000000074' then '탈퇴라'
    when '00000000-0000-0000-0000-000000000075' then '탈퇴마'
    when '00000000-0000-0000-0000-000000000076' then '상대바'
  end,
  gender = 'male', birth_year = 2002, height_cm = 175, status = 'active'
where id in (
  '00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-000000000072',
  '00000000-0000-0000-0000-000000000073', '00000000-0000-0000-0000-000000000074',
  '00000000-0000-0000-0000-000000000075', '00000000-0000-0000-0000-000000000076'
);

update public.profiles set status = 'suspended'
where id = '00000000-0000-0000-0000-000000000072';

-- set_phone_number 는 update 라 행이 먼저 있어야 한다(온보딩에서도 행을 먼저 만든다).
insert into public.profile_private (profile_id)
values ('00000000-0000-0000-0000-000000000070');

-- 예전에 탈퇴했다 재가입한 사람의 옛 행: WE 는 이미 만료, WI 는 무기한.
insert into public.signup_blocks (email_hmac, blocked_until, key_version) values
  ('\x73a1'::bytea, now() - interval '1 day', 1),
  ('\x74a1'::bytea, 'infinity', 1);

-- 1. 구조 · 권한 ---------------------------------------------------------------
select hasnt_function(
  'public', 'set_phone_number', array['uuid', 'text', 'text'],
  '옛 3인자 set_phone_number(uuid, text, text) 는 없다'
);
select has_function(
  'public', 'set_phone_number', array['uuid', 'text', 'text', 'bytea', 'smallint'],
  '새 5인자 set_phone_number(uuid, text, text, bytea, smallint) 가 있다'
);
select is(
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace and proname = 'set_phone_number'),
  1::bigint,
  'set_phone_number 는 딱 하나다(둘이면 3인자 호출이 function is not unique 로 깨진다)'
);
select has_function(
  'public', 'withdraw_account', array['uuid', 'bytea', 'smallint'],
  'withdraw_account(uuid, bytea, smallint) 가 있다'
);

select ok(
  (select exists (select 1 from unnest(proconfig) cfg where cfg = 'search_path=""')
     from pg_proc where oid = to_regprocedure('public.withdraw_account(uuid, bytea, smallint)')),
  'withdraw_account 는 search_path 가 빈 값으로 고정돼 있다'
);
select ok(
  pg_get_functiondef(to_regprocedure('public.withdraw_account(uuid, bytea, smallint)')) ~* 'for update',
  'withdraw_account 는 상태를 for update 로 읽는다(읽기와 쓰기 사이에 정지가 끼지 못한다)'
);

select isnt(
  obj_description(to_regprocedure('public.set_phone_number(uuid, text, text, bytea, smallint)'), 'pg_proc'),
  null, 'set_phone_number 5인자에 comment 가 있다'
);
select isnt(
  obj_description(to_regprocedure('public.withdraw_account(uuid, bytea, smallint)'), 'pg_proc'),
  null, 'withdraw_account 에 comment 가 있다'
);

select ok(
  has_function_privilege('service_role',
    to_regprocedure('public.set_phone_number(uuid, text, text, bytea, smallint)'), 'execute'),
  'service_role 은 set_phone_number 를 실행할 수 있다'
);
select ok(
  has_function_privilege('service_role',
    to_regprocedure('public.withdraw_account(uuid, bytea, smallint)'), 'execute'),
  'service_role 은 withdraw_account 를 실행할 수 있다'
);
select ok(
  not has_function_privilege('anon',
    to_regprocedure('public.set_phone_number(uuid, text, text, bytea, smallint)'), 'execute')
  and not has_function_privilege('anon',
    to_regprocedure('public.withdraw_account(uuid, bytea, smallint)'), 'execute')
  and not has_function_privilege('authenticated',
    to_regprocedure('public.set_phone_number(uuid, text, text, bytea, smallint)'), 'execute')
  and not has_function_privilege('authenticated',
    to_regprocedure('public.withdraw_account(uuid, bytea, smallint)'), 'execute'),
  'anon · authenticated 는 두 함수를 실행할 수 없다'
);

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000070", "role": "authenticated"}';

select throws_ok(
  $$select public.set_phone_number('00000000-0000-0000-0000-000000000070', '+821011112222', 'k')$$,
  '42501', null, 'authenticated 는 set_phone_number 를 실행할 수 없다(42501)'
);
select throws_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-000000000070', '\x70'::bytea, 1::smallint)$$,
  '42501', null, 'authenticated 는 withdraw_account 를 실행할 수 없다(42501)'
);

reset role;
reset request.jwt.claims;

-- 2. set_phone_number ------------------------------------------------------------
select lives_ok(
  $$select public.set_phone_number(
      p_profile_id => '00000000-0000-0000-0000-000000000070',
      p_phone => '+821012345678',
      p_key => 'pgtap-phone-key',
      p_phone_hmac => '\x70ab'::bytea,
      p_phone_hmac_key_version => 2::smallint)$$,
  '5인자 호출이 된다'
);
select is(
  (select phone_hmac from public.profile_private
    where profile_id = '00000000-0000-0000-0000-000000000070'),
  '\x70ab'::bytea, '5인자 호출은 phone_hmac 을 넘긴 값 그대로 저장한다'
);
select is(
  (select phone_hmac_key_version from public.profile_private
    where profile_id = '00000000-0000-0000-0000-000000000070'),
  2::smallint, '5인자 호출은 phone_hmac_key_version 을 넘긴 값 그대로 저장한다'
);
select is(
  public.decrypt_phone_number('00000000-0000-0000-0000-000000000070', 'pgtap-phone-key'),
  '+821012345678', '5인자 호출로 저장한 번호가 decrypt_phone_number 로 되돌아온다'
);

-- 운영 서버가 배포 전까지 부르는 모양: 옛 이름 붙인 인자 셋만.
select lives_ok(
  $$select public.set_phone_number(
      p_profile_id => '00000000-0000-0000-0000-000000000070',
      p_phone => '+821099998888',
      p_key => 'pgtap-phone-key')$$,
  '옛 3개 이름 인자만으로 부르는 호출도 된다'
);
select is(
  (select phone_hmac from public.profile_private
    where profile_id = '00000000-0000-0000-0000-000000000070'),
  null::bytea, '3인자 호출은 phone_hmac 을 null 로 둔다(새 번호에 옛 해시가 남지 않는다)'
);
select is(
  (select phone_hmac_key_version from public.profile_private
    where profile_id = '00000000-0000-0000-0000-000000000070'),
  1::smallint, '3인자 호출은 phone_hmac_key_version 을 1 로 둔다'
);
select is(
  public.decrypt_phone_number('00000000-0000-0000-0000-000000000070', 'pgtap-phone-key'),
  '+821099998888', '3인자 호출로 저장한 번호가 decrypt_phone_number 로 되돌아온다'
);

-- 3. withdraw_account ------------------------------------------------------------
-- active → withdrawn, 재가입 제한 2개월
select lives_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-000000000071', '\x71a1'::bytea, 2::smallint)$$,
  'active 사용자를 탈퇴시킬 수 있다'
);
select is(
  (select status::text from public.profiles where id = '00000000-0000-0000-0000-000000000071'),
  'withdrawn', '탈퇴하면 status 가 withdrawn 이 된다'
);
select is(
  (select withdrawn_at from public.profiles where id = '00000000-0000-0000-0000-000000000071'),
  now(), '탈퇴하면 withdrawn_at 이 지금으로 찍힌다'
);
select is(
  (select count(*) from public.signup_blocks where email_hmac = '\x71a1'::bytea),
  1::bigint, '탈퇴하면 재가입 제한 행이 하나 생긴다'
);
select is(
  (select blocked_until from public.signup_blocks where email_hmac = '\x71a1'::bytea),
  now() + interval '2 months', 'active 에서 탈퇴하면 재가입 제한은 2개월이다'
);
select is(
  (select key_version from public.signup_blocks where email_hmac = '\x71a1'::bytea),
  2::smallint, '재가입 제한 행의 key_version 은 넘긴 값 그대로다'
);

-- 두 번째 호출은 아무것도 안 한다: 앞 결과를 눈에 띄는 값으로 바꿔 두고, 다시 불러도 그대로인지 본다.
update public.signup_blocks set blocked_until = now() + interval '1 day'
where email_hmac = '\x71a1'::bytea;
update public.profiles set withdrawn_at = now() - interval '1 day'
where id = '00000000-0000-0000-0000-000000000071' and status = 'withdrawn';

select lives_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-000000000071', '\x71a1'::bytea, 3::smallint)$$,
  '이미 탈퇴한 사람을 다시 불러도 오류가 나지 않는다'
);
select is(
  (select blocked_until from public.signup_blocks where email_hmac = '\x71a1'::bytea),
  now() + interval '1 day', '두 번째 호출은 blocked_until 을 바꾸지 않는다'
);
select is(
  (select key_version from public.signup_blocks where email_hmac = '\x71a1'::bytea),
  2::smallint, '두 번째 호출은 key_version 을 바꾸지 않는다'
);
select is(
  (select withdrawn_at from public.profiles where id = '00000000-0000-0000-0000-000000000071'),
  now() - interval '1 day', '두 번째 호출은 withdrawn_at 을 바꾸지 않는다'
);

select lives_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-000000000071', '\x71a2'::bytea, 2::smallint)$$,
  '이미 탈퇴한 사람을 다른 해시로 다시 불러도 오류가 나지 않는다'
);
select is(
  (select count(*) from public.signup_blocks where email_hmac in ('\x71a1'::bytea, '\x71a2'::bytea)),
  1::bigint, '이미 탈퇴한 사람은 몇 번을 불러도 재가입 제한 행이 1개다'
);

-- suspended → 무기한
select lives_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-000000000072', '\x72a1'::bytea, 1::smallint)$$,
  '정지 중인 사용자를 탈퇴시킬 수 있다'
);
select is(
  (select blocked_until from public.signup_blocks where email_hmac = '\x72a1'::bytea),
  'infinity'::timestamptz, '정지 중에 탈퇴하면 재가입 제한은 무기한이다'
);

-- 만료된 옛 행은 새 값으로 올라가고, 무기한 행은 줄지 않는다.
select lives_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-000000000073', '\x73a1'::bytea, 2::smallint)$$,
  '만료된 옛 재가입 제한 행이 있어도 탈퇴할 수 있다'
);
select is(
  (select blocked_until from public.signup_blocks where email_hmac = '\x73a1'::bytea),
  now() + interval '2 months', '만료된 옛 행은 지금부터 2개월로 올라간다'
);
select is(
  (select key_version from public.signup_blocks where email_hmac = '\x73a1'::bytea),
  2::smallint, '만료된 옛 행의 key_version 은 새 값으로 바뀐다'
);

select lives_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-000000000074', '\x74a1'::bytea, 1::smallint)$$,
  '무기한 옛 재가입 제한 행이 있어도 탈퇴할 수 있다'
);
select is(
  (select blocked_until from public.signup_blocks where email_hmac = '\x74a1'::bytea),
  'infinity'::timestamptz, '무기한 옛 행은 2개월로 줄지 않는다'
);

-- 프로필이 없으면 아무것도 안 한다.
select lives_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-00000000007f', '\x7fa1'::bytea, 1::smallint)$$,
  '없는 프로필로 불러도 오류가 나지 않는다'
);
select is(
  (select count(*) from public.signup_blocks where email_hmac = '\x7fa1'::bytea),
  0::bigint, '없는 프로필로 부르면 재가입 제한 행을 만들지 않는다'
);

-- 4. 탈퇴 계정 삭제(정리 배치의 전제) --------------------------------------------------
-- DEL(...75) 에게 profiles · auth.users 를 가리키는 main 의 표마다 자식 행을 만든다. PT(...76) 는 상대방.
insert into public.profile_private (profile_id, phone_hmac, phone_hmac_key_version)
values ('00000000-0000-0000-0000-000000000075', '\x75bb'::bytea, 1);

insert into public.profile_photos (id, profile_id, storage_path, position)
values ('00000000-0000-0000-0000-0000000075f0', '00000000-0000-0000-0000-000000000075',
        'profile-photos/75/0.jpg', 0);

insert into public.profile_avatars (profile_id, source_photo_id, storage_path, status)
values ('00000000-0000-0000-0000-000000000075', '00000000-0000-0000-0000-0000000075f0',
        'avatars/75/1.png', 'ready');

insert into public.student_verification_attempts (profile_id, file_path, result)
values ('00000000-0000-0000-0000-000000000075', 'student-id-temp/75/1.jpg', 'pending');

insert into public.survey_answers (profile_id, axis, value)
values ('00000000-0000-0000-0000-000000000075', 1, 0.5);

insert into public.entitlements (profile_id, heart_balance)
values ('00000000-0000-0000-0000-000000000075', 10);

insert into public.heart_transactions (profile_id, amount, reason)
values ('00000000-0000-0000-0000-000000000075', 10, 'promo');

insert into public.profile_vectors (profile_id)
values ('00000000-0000-0000-0000-000000000075');

-- 카드: DEL 이 받은 카드(대상 PT)와 PT 가 받은 카드(대상 DEL), 각각에 결정 · 수락 응답.
insert into public.daily_cards (id, owner_id, target_id, source, expires_at) values
  ('00000000-0000-0000-0000-0000000075c1', '00000000-0000-0000-0000-000000000075',
   '00000000-0000-0000-0000-000000000076', 'daily', now() + interval '1 day'),
  ('00000000-0000-0000-0000-0000000076c1', '00000000-0000-0000-0000-000000000076',
   '00000000-0000-0000-0000-000000000075', 'daily', now() + interval '1 day');

insert into public.card_decisions (card_id, decision) values
  ('00000000-0000-0000-0000-0000000075c1', 'accept'),
  ('00000000-0000-0000-0000-0000000076c1', 'accept');

insert into public.acceptance_responses (card_id, responder_id, decision) values
  ('00000000-0000-0000-0000-0000000075c1', '00000000-0000-0000-0000-000000000076', 'accept'),
  ('00000000-0000-0000-0000-0000000076c1', '00000000-0000-0000-0000-000000000075', 'accept');

-- 매칭 · 채팅방 · 메시지(양쪽이 한 통씩)
insert into public.matches (id, profile_a, profile_b)
values ('00000000-0000-0000-0000-0000000075a0', '00000000-0000-0000-0000-000000000075',
        '00000000-0000-0000-0000-000000000076');

insert into public.match_participants (match_id, profile_id) values
  ('00000000-0000-0000-0000-0000000075a0', '00000000-0000-0000-0000-000000000075'),
  ('00000000-0000-0000-0000-0000000075a0', '00000000-0000-0000-0000-000000000076');

insert into public.messages (match_id, sender_id, body) values
  ('00000000-0000-0000-0000-0000000075a0', '00000000-0000-0000-0000-000000000075', 'DEL 이 보낸 말'),
  ('00000000-0000-0000-0000-0000000075a0', '00000000-0000-0000-0000-000000000076', 'PT 가 보낸 말');

insert into public.push_tokens (token, profile_id, platform)
values ('pgtap-token-75', '00000000-0000-0000-0000-000000000075', 'android');

insert into public.notification_settings (profile_id)
values ('00000000-0000-0000-0000-000000000075');

-- 차단 양쪽 · 지인 차단
insert into public.blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000075', '00000000-0000-0000-0000-000000000076'),
  ('00000000-0000-0000-0000-000000000076', '00000000-0000-0000-0000-000000000075');

insert into public.contact_blocks (owner_id, contact_hmac, key_version)
values ('00000000-0000-0000-0000-000000000075', '\x75cc'::bytea, 1);

-- 신고: DEL 이 신고자인 행, DEL 이 대상인 행
insert into public.reports
  (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason)
values
  ('00000000-0000-0000-0000-000000000075', 'profile',
   '00000000-0000-0000-0000-0000000075e1', '00000000-0000-0000-0000-000000000076',
   '{}'::jsonb, 'abuse'),
  ('00000000-0000-0000-0000-000000000076', 'profile',
   '00000000-0000-0000-0000-0000000075e2', '00000000-0000-0000-0000-000000000075',
   '{}'::jsonb, 'spam');

-- 커뮤니티: DEL 의 글에 PT 가 투표, PT 의 글에 DEL 이 투표
insert into public.polls (id, author_id, question) values
  ('00000000-0000-0000-0000-0000000075b1', '00000000-0000-0000-0000-000000000075', 'DEL 의 질문'),
  ('00000000-0000-0000-0000-0000000076b1', '00000000-0000-0000-0000-000000000076', 'PT 의 질문');

insert into public.poll_votes (poll_id, voter_id, choice) values
  ('00000000-0000-0000-0000-0000000075b1', '00000000-0000-0000-0000-000000000076', 'a'),
  ('00000000-0000-0000-0000-0000000076b1', '00000000-0000-0000-0000-000000000075', 'b');

select lives_ok(
  $$select public.withdraw_account('00000000-0000-0000-0000-000000000075', '\x75a1'::bytea, 1::smallint)$$,
  '자식 행이 많은 사용자도 탈퇴할 수 있다'
);

select lives_ok(
  $$delete from auth.users where id = '00000000-0000-0000-0000-000000000075'$$,
  '탈퇴한 사용자의 auth.users 행을 지우는 것이 어떤 FK 에도 막히지 않는다'
);

select is(
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000000075'),
  0::bigint, 'auth.users 를 지우면 profiles 행도 사라진다'
);

select is(
  (select
      (select count(*) from public.profile_private where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.profile_photos where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.profile_avatars where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.student_verification_attempts where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.survey_answers where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.entitlements where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.heart_transactions where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.profile_vectors where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.daily_cards where '00000000-0000-0000-0000-000000000075' in (owner_id, target_id))
    + (select count(*) from public.acceptance_responses where responder_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.push_tokens where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.notification_settings where profile_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.blocks where '00000000-0000-0000-0000-000000000075' in (blocker_id, blocked_id))
    + (select count(*) from public.contact_blocks where owner_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.polls where author_id = '00000000-0000-0000-0000-000000000075')
    + (select count(*) from public.poll_votes where voter_id = '00000000-0000-0000-0000-000000000075')),
  0::bigint, '탈퇴한 사용자의 자식 행은 cascade 로 전부 사라진다'
);

select is(
  (select count(*) from public.reports
    where target_id in ('00000000-0000-0000-0000-0000000075e1', '00000000-0000-0000-0000-0000000075e2')),
  2::bigint, '탈퇴한 사용자가 신고자 · 대상인 신고 행은 남는다'
);
select is(
  (select reporter_id from public.reports where target_id = '00000000-0000-0000-0000-0000000075e1'),
  null::uuid, '탈퇴한 사용자가 신고자인 행은 reporter_id 가 null 이 된다'
);
select is(
  (select target_profile_id from public.reports where target_id = '00000000-0000-0000-0000-0000000075e2'),
  null::uuid, '탈퇴한 사용자가 대상인 행은 target_profile_id 가 null 이 된다'
);

select is(
  (select count(*) from public.signup_blocks where email_hmac = '\x75a1'::bytea),
  1::bigint, 'auth.users 를 지워도 그 사람의 재가입 제한 행은 남는다'
);

-- 상대방 쪽: 현재 FK 동작을 그대로 고정한다(보고서 FK 표 참고).
select is(
  (select
      (select count(*) from public.matches where id = '00000000-0000-0000-0000-0000000075a0')
    + (select count(*) from public.match_participants where profile_id = '00000000-0000-0000-0000-000000000076')
    + (select count(*) from public.messages where sender_id = '00000000-0000-0000-0000-000000000076')),
  0::bigint, '현재 동작: 매칭이 cascade 로 지워져 상대방의 채팅방 · 상대방이 보낸 메시지도 사라진다'
);
select is(
  (select count(*) from public.polls where author_id = '00000000-0000-0000-0000-000000000076'),
  1::bigint, '상대방이 쓴 투표 글은 남는다(탈퇴한 사람의 표만 빠진다)'
);

select * from finish();
rollback;
