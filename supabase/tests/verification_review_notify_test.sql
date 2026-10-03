-- 학생증 검토 결과 알림 트리거 검증(결함 A7). 마이그레이션 20261003030000_notify_verification_reviewed.sql.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다 —
-- Vault 값도 rollback 되고, pg_net 은 커밋 뒤에만 보내므로 큐에 쌓인 요청도 밖으로 나가지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- 준비: auth.users 를 넣으면 handle_new_user_profile 트리거가 profiles 행을 만든다(consents_test.sql 과 같은 방식).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000d', '테스트대학교D', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('review.ac.kr', '00000000-0000-0000-0000-00000000000d');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000d7', 'd7@review.ac.kr');

select has_extension('pg_net', 'pg_net 확장이 켜져 있다');
select has_trigger('public', 'profiles', 'on_student_verification_reviewed', '검토 결과 트리거가 있다');
select is_definer('public', 'notify_verification_reviewed', array[]::text[], 'Vault 를 읽으려고 security definer 다');
select is(
  (select proconfig from pg_proc where oid = 'public.notify_verification_reviewed()'::regprocedure),
  array['search_path=""'],
  'search_path 는 빈 값으로 고정돼 있다(advisor WARN 조치)'
);
select ok(
  not has_function_privilege('anon', 'public.notify_verification_reviewed()', 'execute')
  and not has_function_privilege('authenticated', 'public.notify_verification_reviewed()', 'execute'),
  '앱 역할은 웹훅 함수를 직접 부를 수 없다'
);

create temporary table queued_before as select count(*) as n from net.http_request_queue;

-- Vault 값이 없으면(로컬 · pgTAP) 바뀌어도 아무것도 보내지 않는다.
update public.profiles set student_verification = 'pending' where id = '00000000-0000-0000-0000-0000000000d7';
update public.profiles set student_verification = 'verified' where id = '00000000-0000-0000-0000-0000000000d7';
select is((select count(*) from net.http_request_queue), (select n from queued_before),
  'Vault 값이 없으면 요청을 쌓지 않는다');

select vault.create_secret('https://hook.invalid/hooks/verification-reviewed', 'verification_hook_url');
select vault.create_secret('test-secret', 'verification_hook_secret');

-- 검토 결과가 아닌 바뀜(none → pending · pending → pending · verified → rejected)에는 부르지 않는다.
update public.profiles set student_verification = 'none' where id = '00000000-0000-0000-0000-0000000000d7';
update public.profiles set student_verification = 'pending' where id = '00000000-0000-0000-0000-0000000000d7';
update public.profiles set student_verification = 'pending' where id = '00000000-0000-0000-0000-0000000000d7';
select is((select count(*) from net.http_request_queue), (select n from queued_before),
  'none → pending · pending → pending 은 부르지 않는다');

update public.profiles set student_verification = 'rejected' where id = '00000000-0000-0000-0000-0000000000d7';
select is((select count(*) from net.http_request_queue), (select n + 1 from queued_before),
  'pending → rejected 는 한 번 부른다');

select is(
  (select convert_from(body, 'utf8')::jsonb from net.http_request_queue order by id desc limit 1),
  '{"profile_id": "00000000-0000-0000-0000-0000000000d7"}'::jsonb,
  '본문엔 profile_id 만 — 상태는 서버가 다시 읽는다'
);
select is(
  (select headers ->> 'x-webhook-secret' from net.http_request_queue order by id desc limit 1),
  'test-secret',
  '공유 비밀을 헤더로 보낸다'
);

update public.profiles set student_verification = 'verified' where id = '00000000-0000-0000-0000-0000000000d7';
select is((select count(*) from net.http_request_queue), (select n + 1 from queued_before),
  'rejected → verified 는 검토 결과가 아니라 부르지 않는다(pending 을 거친 것만)');

select * from finish();
rollback;
