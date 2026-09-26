-- 조각 6 RLS · 권한 · 후보 필터 검증(신고 · 차단 · 지인차단 · 자동가림 · 탈퇴).
-- 기대값 기준은 docs/superpowers/plans/2026-09-22-slice6-safety.md Part C, B2 · B4.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

-- 준비 --------------------------------------------------------------------
-- A = ...60(남, 기준 사용자), CTRL = ...61(여, 대조군 후보 — 아무 조건도 안 걸려 후보로 나와야 한다),
-- BLKD = ...62(여, A 가 차단), BLKA = ...63(여, A 를 차단), HID = ...64(여, auto_hidden_at 찍힘),
-- CBTGT = ...65(여, A 가 번호를 등록해 차단), CBA = ...66(여, A 의 번호를 등록해 차단),
-- KVM = ...67(여, 키 버전이 달라 지인차단이 걸리지 않는다),
-- NULLP = ...68(여, phone_hmac 이 null 이라 A 의 지인차단이 있어도 걸리지 않는다),
-- RDEL = ...69(신고자 탈퇴 근거 확인용, onboarding 없이 pending 인 채로 둔다),
-- CBAKV = ...6a(여, A 의 번호를 등록했지만 key_version 이 A 의 실제 버전과 달라 걸리지 않는다 — KVM 의 반대 방향)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000006', '테스트대학교6', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('test6.ac.kr', '00000000-0000-0000-0000-000000000006');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000060', 'm6-a@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000061', 'm6-ctrl@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000062', 'm6-blkd@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000063', 'm6-blka@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000064', 'm6-hid@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000065', 'm6-cbtgt@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000066', 'm6-cba@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000067', 'm6-kvm@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000068', 'm6-nullp@test6.ac.kr'),
  ('00000000-0000-0000-0000-000000000069', 'm6-rdel@test6.ac.kr'),
  ('00000000-0000-0000-0000-00000000006a', 'm6-cbakv@test6.ac.kr');

insert into public.profiles (id, university_id)
select id, '00000000-0000-0000-0000-000000000006' from auth.users
where id in (
  '00000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-000000000061',
  '00000000-0000-0000-0000-000000000062', '00000000-0000-0000-0000-000000000063',
  '00000000-0000-0000-0000-000000000064', '00000000-0000-0000-0000-000000000065',
  '00000000-0000-0000-0000-000000000066', '00000000-0000-0000-0000-000000000067',
  '00000000-0000-0000-0000-000000000068', '00000000-0000-0000-0000-000000000069',
  '00000000-0000-0000-0000-00000000006a'
)
on conflict (id) do nothing;

update public.profiles set
  nickname = '가나다라', gender = 'male', status = 'active',
  interest_tags = array['카페가기'], my_traits = array['다정한'], ideal_traits = array['활발한'],
  height_cm = 180, birth_year = 2002, mbti = 'ENFP', last_active_at = now()
where id = '00000000-0000-0000-0000-000000000060';

-- 여자 9명은 닉네임만 다르고 나머지는 똑같다 — 걸러지는 이유가 조각 6 필터 하나임을 분명히 한다.
update public.profiles set nickname = '마바사아' where id = '00000000-0000-0000-0000-000000000061';
update public.profiles set nickname = '자차카타' where id = '00000000-0000-0000-0000-000000000062';
update public.profiles set nickname = '파하고나' where id = '00000000-0000-0000-0000-000000000063';
update public.profiles set nickname = '두루미새' where id = '00000000-0000-0000-0000-000000000064';
update public.profiles set nickname = '별똥별아' where id = '00000000-0000-0000-0000-000000000065';
update public.profiles set nickname = '해달별아' where id = '00000000-0000-0000-0000-000000000066';
update public.profiles set nickname = '눈보라야' where id = '00000000-0000-0000-0000-000000000067';
update public.profiles set nickname = '구름결아' where id = '00000000-0000-0000-0000-000000000068';
update public.profiles set nickname = '물결소리' where id = '00000000-0000-0000-0000-00000000006a';

update public.profiles set
  gender = 'female', status = 'active',
  interest_tags = array['카페가기'], my_traits = array['활발한'], ideal_traits = array['다정한'],
  height_cm = 165, birth_year = 2003, mbti = 'ISFJ', last_active_at = now()
where id in (
  '00000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000062',
  '00000000-0000-0000-0000-000000000063', '00000000-0000-0000-0000-000000000064',
  '00000000-0000-0000-0000-000000000065', '00000000-0000-0000-0000-000000000066',
  '00000000-0000-0000-0000-000000000067', '00000000-0000-0000-0000-000000000068',
  '00000000-0000-0000-0000-00000000006a'
);

-- HID 만 자동 가림
update public.profiles set auto_hidden_at = now()
where id = '00000000-0000-0000-0000-000000000064';

insert into public.profile_vectors (profile_id, self_survey, self_embedding, want_embedding)
select id, '[1,0,0,0,0,0,0,0]',
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector,
       ('[' || 1 || repeat(',0', 511) || ']')::extensions.vector
from public.profiles
where id in (
  '00000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-000000000061',
  '00000000-0000-0000-0000-000000000062', '00000000-0000-0000-0000-000000000063',
  '00000000-0000-0000-0000-000000000064', '00000000-0000-0000-0000-000000000065',
  '00000000-0000-0000-0000-000000000066', '00000000-0000-0000-0000-000000000067',
  '00000000-0000-0000-0000-000000000068', '00000000-0000-0000-0000-00000000006a'
);

-- 차단: A 가 BLKD 를 차단, BLKA 가 A 를 차단.
insert into public.blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-000000000062'),
  ('00000000-0000-0000-0000-000000000063', '00000000-0000-0000-0000-000000000060');

-- 신원 HMAC. A = \xaa, CBTGT(자기 번호) = \xbb, KVM(자기 번호, 키 버전 2) = \xcc.
-- BLKD · BLKA · HID · CTRL · CBA · CBAKV 는 profile_private 행 자체가 없다
-- (운영에서도 번호 인증 전이면 행이 없을 수 있다).
-- NULLP 는 행은 있고 phone_hmac 만 null 이다 — 가입은 했지만 아직 번호 인증 전인 운영 모양.
insert into public.profile_private (profile_id, phone_hmac, phone_hmac_key_version) values
  ('00000000-0000-0000-0000-000000000060', '\xaa'::bytea, 1),
  ('00000000-0000-0000-0000-000000000065', '\xbb'::bytea, 1),
  ('00000000-0000-0000-0000-000000000067', '\xcc'::bytea, 2),
  ('00000000-0000-0000-0000-000000000068', null, 1);

-- 지인 차단: A 가 CBTGT 의 번호(\xbb, 버전1)를 등록 → CBTGT 제외.
-- CBA 가 A 의 번호(\xaa, 버전1)를 등록 → CBA 제외.
-- A 가 KVM 의 번호(\xcc)를 등록하지만 버전1(=KVM 의 실제 버전2 와 다름) → KVM 은 제외되지 않는다.
-- CBAKV 가 A 의 번호(\xaa)를 등록하지만 버전2(=A 의 실제 버전1 과 다름) → CBAKV 는 제외되지 않는다
-- (CBA 의 반대 방향 — "상대가 나를 등록했지만 키버전이 다르다").
insert into public.contact_blocks (owner_id, contact_hmac, key_version) values
  ('00000000-0000-0000-0000-000000000060', '\xbb'::bytea, 1),
  ('00000000-0000-0000-0000-000000000066', '\xaa'::bytea, 1),
  ('00000000-0000-0000-0000-000000000060', '\xcc'::bytea, 1),
  ('00000000-0000-0000-0000-00000000006a', '\xaa'::bytea, 2);

-- 신고: once_per_reporter 준비 행(중복 신고 검사용) — 대상은 target_type=profile, target_id 는
-- FK 없이 임의값(신고 대상 원본 행 id 를 흉내낸다).
insert into public.reports
  (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason)
values
  ('00000000-0000-0000-0000-000000000060', 'profile',
   '00000000-0000-0000-0000-000000000090', '00000000-0000-0000-0000-000000000061',
   '{}'::jsonb, 'abuse');

-- 탈퇴 근거 확인용: RDEL 이 신고자인 행 + RDEL 이 차단자인 행.
insert into public.reports
  (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason)
values
  ('00000000-0000-0000-0000-000000000069', 'profile',
   '00000000-0000-0000-0000-000000000095', '00000000-0000-0000-0000-000000000061',
   '{}'::jsonb, 'abuse');

insert into public.blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000069', '00000000-0000-0000-0000-000000000061');

-- 1. 구조 --------------------------------------------------------------------
select enum_has_labels(
  'public', 'profile_status',
  array['pending', 'active', 'suspended', 'withdrawn'],
  'profile_status 에 withdrawn 이 더해졌다'
);

select enum_has_labels(
  'public', 'report_reason',
  array['abuse', 'sexual', 'spam', 'fake', 'other'],
  'report_reason 값은 abuse sexual spam fake other 다'
);

select enum_has_labels(
  'public', 'report_target',
  array['profile', 'message', 'friend_review', 'poll'],
  'report_target 값은 profile message friend_review poll 이다'
);

select enum_has_labels(
  'public', 'report_status',
  array['open', 'actioned', 'dismissed'],
  'report_status 값은 open actioned dismissed 다'
);

select has_column('public', 'profiles', 'withdrawn_at', 'profiles 에 withdrawn_at 컬럼이 있다');
select has_column('public', 'profiles', 'auto_hidden_at', 'profiles 에 auto_hidden_at 컬럼이 있다');
select has_column('public', 'profile_private', 'phone_hmac', 'profile_private 에 phone_hmac 컬럼이 있다');
select has_column('public', 'profile_private', 'phone_hmac_key_version',
  'profile_private 에 phone_hmac_key_version 컬럼이 있다');
select has_column('public', 'signup_blocks', 'key_version', 'signup_blocks 에 key_version 컬럼이 있다');
select has_column('public', 'contact_blocks', 'key_version', 'contact_blocks 에 key_version 컬럼이 있다');

-- 2. 제약 --------------------------------------------------------------------
select throws_ok(
  $$update public.profiles set status = 'withdrawn'
     where id = '00000000-0000-0000-0000-000000000061'$$,
  '23514', null, 'withdrawn 인데 withdrawn_at 이 없으면 막힌다'
);

select throws_ok(
  $$update public.profiles set withdrawn_at = now()
     where id = '00000000-0000-0000-0000-000000000061'$$,
  '23514', null, 'active 인데 withdrawn_at 이 있으면 막힌다'
);

select throws_ok(
  $$insert into public.reports
      (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason,
       status, resolved_at)
    values
      ('00000000-0000-0000-0000-000000000060', 'profile',
       '00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000061',
       '{}'::jsonb, 'abuse', 'open', now())$$,
  '23514', null, 'open 인데 resolved_at 이 있으면 막힌다'
);

select throws_ok(
  $$insert into public.reports
      (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason, status)
    values
      ('00000000-0000-0000-0000-000000000060', 'profile',
       '00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000061',
       '{}'::jsonb, 'abuse', 'actioned')$$,
  '23514', null, 'actioned 인데 resolved_at 이 없으면 막힌다'
);

select throws_ok(
  $$insert into public.reports
      (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason)
    values
      ('00000000-0000-0000-0000-000000000060', 'profile',
       '00000000-0000-0000-0000-000000000090', '00000000-0000-0000-0000-000000000061',
       '{}'::jsonb, 'spam')$$,
  '23505', null, '같은 사람이 같은 대상을 두 번 신고하지 못한다'
);

select throws_ok(
  format($$insert into public.reports
      (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason, reason_note)
    values
      ('00000000-0000-0000-0000-000000000060', 'profile',
       '00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000061',
       '{}'::jsonb, 'other', '%s')$$, repeat('x', 201)),
  '23514', null, '신고 사유 메모는 200자를 넘으면 막힌다'
);

select throws_ok(
  $$insert into public.reports
      (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason, reason_note)
    values
      ('00000000-0000-0000-0000-000000000060', 'profile',
       '00000000-0000-0000-0000-000000000094', '00000000-0000-0000-0000-000000000061',
       '{}'::jsonb, 'other', '   ')$$,
  '23514', null, '신고 사유 메모가 공백만이면 막힌다'
);

select throws_ok(
  $$insert into public.blocks (blocker_id, blocked_id)
    values ('00000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-000000000060')$$,
  '23514', null, '자기 자신은 차단할 수 없다'
);

-- 3. RLS · 권한 ----------------------------------------------------------------
select is(
  (select relrowsecurity from pg_class where oid = 'public.reports'::regclass),
  true, 'reports 는 RLS 가 켜져 있다'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.blocks'::regclass),
  true, 'blocks 는 RLS 가 켜져 있다'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.contact_blocks'::regclass),
  true, 'contact_blocks 는 RLS 가 켜져 있다'
);

select is(
  (select count(*) from pg_policies where tablename = 'reports'),
  0::bigint, 'reports 에는 정책이 하나도 없다(FastAPI 전용)'
);
select is(
  (select count(*) from pg_policies where tablename = 'blocks'),
  0::bigint, 'blocks 에는 정책이 하나도 없다(FastAPI 전용)'
);
select is(
  (select count(*) from pg_policies where tablename = 'contact_blocks'),
  0::bigint, 'contact_blocks 에는 정책이 하나도 없다(FastAPI 전용)'
);

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000060", "role": "authenticated"}';

-- grant 가 없어 0행이 아니라 42501 이다(정책이 없어도 권한이 없으면 접근 자체가 막힌다).
select throws_ok(
  $$select id from public.reports$$,
  '42501', null, 'authenticated 는 reports 를 select 할 수 없다(42501)'
);
select throws_ok(
  $$insert into public.reports
      (reporter_id, target_type, target_id, target_profile_id, target_snapshot, reason)
    values
      ('00000000-0000-0000-0000-000000000060', 'profile',
       '00000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000061',
       '{}'::jsonb, 'abuse')$$,
  '42501', null, 'authenticated 는 reports 에 insert 할 수 없다(42501)'
);

select throws_ok(
  $$select blocker_id from public.blocks$$,
  '42501', null, 'authenticated 는 blocks 를 select 할 수 없다(42501)'
);
select throws_ok(
  $$insert into public.blocks (blocker_id, blocked_id)
    values ('00000000-0000-0000-0000-000000000060', '00000000-0000-0000-0000-000000000061')$$,
  '42501', null, 'authenticated 는 blocks 에 insert 할 수 없다(42501)'
);

select throws_ok(
  $$select owner_id from public.contact_blocks$$,
  '42501', null, 'authenticated 는 contact_blocks 를 select 할 수 없다(42501)'
);
select throws_ok(
  $$insert into public.contact_blocks (owner_id, contact_hmac)
    values ('00000000-0000-0000-0000-000000000060', '\xff'::bytea)$$,
  '42501', null, 'authenticated 는 contact_blocks 에 insert 할 수 없다(42501)'
);

select ok(
  not has_column_privilege('authenticated', 'public.profile_private', 'phone_hmac', 'select'),
  'authenticated 는 profile_private.phone_hmac 컬럼을 읽지 못한다'
);

reset role;
reset request.jwt.claims;

select ok(
  has_table_privilege('service_role', 'public.reports', 'select, insert, update, delete'),
  'service_role 은 reports 를 select·insert·update·delete 할 수 있다'
);
select ok(
  has_table_privilege('service_role', 'public.blocks', 'select, insert, update, delete'),
  'service_role 은 blocks 를 select·insert·update·delete 할 수 있다'
);
select ok(
  has_table_privilege('service_role', 'public.contact_blocks', 'select, insert, update, delete'),
  'service_role 은 contact_blocks 를 select·insert·update·delete 할 수 있다'
);

-- 4. 탈퇴 근거 ------------------------------------------------------------------
delete from auth.users where id = '00000000-0000-0000-0000-000000000069';

select is(
  (select count(*) from public.reports
    where target_id = '00000000-0000-0000-0000-000000000095'),
  1::bigint, 'RDEL 이 탈퇴해도 RDEL 이 남긴 신고 행은 남는다'
);
select is(
  (select reporter_id from public.reports
    where target_id = '00000000-0000-0000-0000-000000000095'),
  null::uuid, 'RDEL 이 탈퇴하면 그 신고의 reporter_id 는 null 이 된다'
);
select is(
  (select count(*) from public.blocks
    where blocker_id = '00000000-0000-0000-0000-000000000069'),
  0::bigint, 'RDEL 이 탈퇴하면 RDEL 이 차단자인 행은 cascade 로 사라진다'
);

-- 5. 후보 필터(match_candidates, 기준 사용자 A) ----------------------------------
select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-000000000061'),
  1::bigint, '아무 조건도 없는 대조군은 후보로 나온다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-000000000062'),
  0::bigint, 'A 가 차단한 사람은 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-000000000063'),
  0::bigint, 'A 를 차단한 사람은 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-000000000064'),
  0::bigint, 'auto_hidden_at 이 찍힌 사람은 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-000000000065'),
  0::bigint, 'A 가 등록한 번호가 후보의 phone_hmac 이면 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-000000000066'),
  0::bigint, '후보가 등록한 번호가 A 의 phone_hmac 이면 후보가 아니다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-000000000067'),
  1::bigint, 'key_version 이 다르면 지인차단으로 제외하지 않는다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-000000000068'),
  1::bigint, '후보의 phone_hmac 이 null 이면 A 의 지인차단이 있어도 제외하지 않는다'
);

select is(
  (select count(*) from public.match_candidates('00000000-0000-0000-0000-000000000060')
    where candidate_id = '00000000-0000-0000-0000-00000000006a'),
  1::bigint, '후보가 등록한 A 번호라도 key_version 이 다르면 지인차단으로 제외하지 않는다'
);

-- 6. card_issue_owners ---------------------------------------------------------
select is(
  (select count(*) from public.card_issue_owners()
    where profile_id = '00000000-0000-0000-0000-000000000064'),
  0::bigint, 'auto_hidden_at 이 찍힌 본인은 새 카드 지급 대상이 아니다'
);

select is(
  (select count(*) from public.card_issue_owners()
    where profile_id = '00000000-0000-0000-0000-000000000060'),
  1::bigint, 'auto_hidden_at 이 없는 대조군은 지급 대상이다'
);

select * from finish();
rollback;
