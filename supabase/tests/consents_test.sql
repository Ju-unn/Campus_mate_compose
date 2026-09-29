-- 가입 동의 기록 표 검증. 기대값 기준은 docs/superpowers/plans/2026-09-29-signup-consent.md Task 1.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- 준비: auth.users 를 넣으면 handle_new_user_profile 트리거가 profiles 행을 만든다(rls_slice6_test.sql 과 같은 방식).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000c', '테스트대학교C', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('consent.ac.kr', '00000000-0000-0000-0000-00000000000c');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c7', 'c7@consent.ac.kr');

select has_table('public', 'user_consents', '동의 기록 표가 있다');
select enum_has_labels('public', 'consent_kind',
  array['terms', 'privacy', 'sensitive_religion', 'overseas_transfer'], '필수 4항목');
select col_is_pk('public', 'user_consents', array['profile_id', 'kind', 'version'], '같은 판을 두 번 쌓지 않는다');
select is((select relrowsecurity from pg_class where oid = 'public.user_consents'::regclass), true, 'RLS 켜짐');
select ok(not has_table_privilege('authenticated', 'public.user_consents', 'select'), '앱은 직접 못 읽는다');
select ok(not has_table_privilege('anon', 'public.user_consents', 'select'), '비로그인도 못 읽는다');
select ok(not has_table_privilege('service_role', 'public.user_consents', 'update'), '기록은 고치지 않는다');
select throws_ok(
  $$insert into public.user_consents (profile_id, kind, version)
    values ('00000000-0000-0000-0000-0000000000c7', 'terms', 'v1')$$,
  '23514', null, '판은 YYYY-MM-DD 모양만');
select fk_ok('public', 'user_consents', 'profile_id', 'public', 'profiles', 'id');

select * from finish();
rollback;
