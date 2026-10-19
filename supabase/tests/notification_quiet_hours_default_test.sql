-- 방해 금지 시간 기본값 끄기 검증. 마이그레이션 20261019210000_notification_quiet_hours_default_off.sql.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

-- 준비: auth.users 를 넣으면 handle_new_user_profile 트리거가 profiles 행을 만든다(verification_review_notify_test.sql 과 같은 방식).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-0000000000e1', '테스트대학교E', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('quiet.ac.kr', '00000000-0000-0000-0000-0000000000e1');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e2', 'e2@quiet.ac.kr'),  -- 설정 행이 없는 기존 사용자
  ('00000000-0000-0000-0000-0000000000e3', 'e3@quiet.ac.kr'),  -- 이미 껐다고 저장한 기존 사용자
  ('00000000-0000-0000-0000-0000000000e4', 'e4@quiet.ac.kr');  -- 이미 켠 채 저장한 기존 사용자

-- 마이그레이션 직전의 모양을 흉내 낸다: 컬럼 기본값은 아직 켜짐.
alter table public.notification_settings alter column quiet_hours set default true;
insert into public.notification_settings (profile_id, quiet_hours) values
  ('00000000-0000-0000-0000-0000000000e3', false),
  ('00000000-0000-0000-0000-0000000000e4', true);

-- 마이그레이션 본문(채우기 + 기본값 변경)을 그대로 돌린다.
insert into public.notification_settings (profile_id, quiet_hours)
select p.id, true
from public.profiles p
where not exists (select 1 from public.notification_settings s where s.profile_id = p.id);
alter table public.notification_settings alter column quiet_hours set default false;

select is(
  (select quiet_hours from public.notification_settings where profile_id = '00000000-0000-0000-0000-0000000000e2'),
  true, '행이 없던 기존 사용자는 켜진 채 행이 채워진다(조용히 꺼지지 않는다)');
select is(
  (select quiet_hours from public.notification_settings where profile_id = '00000000-0000-0000-0000-0000000000e3'),
  false, '이미 끈 사용자의 값은 그대로다');
select is(
  (select quiet_hours from public.notification_settings where profile_id = '00000000-0000-0000-0000-0000000000e4'),
  true, '이미 켠 사용자의 값은 그대로다');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000e5', 'e5@quiet.ac.kr');
insert into public.notification_settings (profile_id, marketing) values ('00000000-0000-0000-0000-0000000000e5', true);
select is(
  (select quiet_hours from public.notification_settings where profile_id = '00000000-0000-0000-0000-0000000000e5'),
  false, '이후 가입자가 마케팅 동의 등으로 행이 생겨도 방해 금지 시간은 꺼짐이다');
select is(
  (select marketing from public.notification_settings where profile_id = '00000000-0000-0000-0000-0000000000e5'),
  true, '다른 칸은 보낸 값 그대로다');

select * from finish();
rollback;
