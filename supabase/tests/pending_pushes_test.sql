-- 밤에 보류된 알림 표 검증(결정 4 · B1). 기대값 기준은 migrations/20261003010000_create_pending_pushes.sql.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

-- 준비: auth.users 를 넣으면 handle_new_user_profile 트리거가 profiles 행을 만든다(consents_test.sql 과 같은 방식).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000d', '테스트대학교D', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('night.ac.kr', '00000000-0000-0000-0000-00000000000d');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000d1', 'd1@night.ac.kr');

select has_table('public', 'pending_pushes', '보류 알림 표가 있다');
select has_index('public', 'pending_pushes', 'pending_pushes_profile_index', '사람별로 꺼내는 인덱스');
select is((select relrowsecurity from pg_class where oid = 'public.pending_pushes'::regclass), true, 'RLS 켜짐');
select ok(not has_table_privilege('authenticated', 'public.pending_pushes', 'select'), '앱은 직접 못 읽는다');
select ok(not has_table_privilege('anon', 'public.pending_pushes', 'select'), '비로그인도 못 읽는다');
select ok(not has_table_privilege('service_role', 'public.pending_pushes', 'update'), '보류 알림은 고치지 않는다');
select ok(has_table_privilege('service_role', 'public.pending_pushes', 'delete'), '보낸 뒤 지울 수 있다');
select fk_ok('public', 'pending_pushes', 'profile_id', 'public', 'profiles', 'id');

select lives_ok(
  $$insert into public.pending_pushes (profile_id, kind, title, body, data)
    values ('00000000-0000-0000-0000-0000000000d1', 'acceptance_received', '나를 수락한 사람이 있어요',
            'A 님이 대화를 하고 싶어 해요', '{"route": "acceptances"}')$$,
  '받은 수락 알림을 보류할 수 있다');
select lives_ok(
  $$insert into public.pending_pushes (profile_id, kind, title, body)
    values ('00000000-0000-0000-0000-0000000000d1', 'verification_result', '학생증 검토가 끝났어요', 'b')$$,
  '학생증 검토 결과(A7)도 보류한다 — 조용한 시간 예외는 채팅 · 카드 도착뿐');
-- 채팅 · 카드 도착은 조용한 시간 예외라 바로 간다 — 여기 쌓이면 코드가 잘못된 것이다.
select throws_ok(
  $$insert into public.pending_pushes (profile_id, kind, title, body)
    values ('00000000-0000-0000-0000-0000000000d1', 'new_message', 't', 'b')$$,
  '23514', null, '보류하는 4종 말고는 안 받는다');
select is(
  (select data from public.pending_pushes where profile_id = '00000000-0000-0000-0000-0000000000d1' and kind = 'acceptance_received'),
  '{"route": "acceptances"}'::jsonb, '가는 화면(data)을 그대로 담는다');

-- fk_ok 는 on delete 동작을 보지 않는다 — 탈퇴 계정 삭제 때 같이 지워지는지 직접 본다.
delete from public.profiles where id = '00000000-0000-0000-0000-0000000000d1';
select is_empty(
  $$select 1 from public.pending_pushes where profile_id = '00000000-0000-0000-0000-0000000000d1'$$,
  '프로필을 지우면 보류 알림도 cascade 로 지워진다');

select * from finish();
rollback;
