-- 1.0.7 1-1 신분: profiles.academic_status 칸과 값 제약 검증. 기대값 기준은 docs/ERD.md §3 profiles.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000001', '테스트대학교', 'seoul');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000005a0', 'status-a@test.ac.kr');

insert into public.profiles (id, university_id)
values ('00000000-0000-0000-0000-0000000005a0', '00000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

-- 1. 칸 모양 -------------------------------------------------------------------
select has_column('public', 'profiles', 'academic_status', 'profiles 에 academic_status 칸이 있다');
select col_type_is('public', 'profiles', 'academic_status', 'text', 'academic_status 는 text 다');
-- 옛 앱 · 이미 가입한 사람은 값이 없다. not null 이면 옛 앱 가입이 깨진다.
select col_is_null('public', 'profiles', 'academic_status', 'academic_status 는 null 을 허용한다');
-- 기본값이 있으면 옛 가입자도 신분이 생겨 "학교 인증" 배지가 사라진다(사용자 결정과 어긋남).
select col_hasnt_default('public', 'profiles', 'academic_status', 'academic_status 에는 기본값이 없다');

-- 2. 새 줄은 null 로 시작한다 -------------------------------------------------------
select is(
  (select academic_status from public.profiles where id = '00000000-0000-0000-0000-0000000005a0'),
  null,
  '새 프로필의 신분은 null(= 학교 인증 배지)이다'
);

-- 3. 세 값만 받는다 ------------------------------------------------------------------
select lives_ok(
  $$update public.profiles set academic_status = 'undergraduate' where id = '00000000-0000-0000-0000-0000000005a0';
    update public.profiles set academic_status = 'graduate_student' where id = '00000000-0000-0000-0000-0000000005a0';
    update public.profiles set academic_status = 'alumni' where id = '00000000-0000-0000-0000-0000000005a0'$$,
  '세 값(undergraduate · graduate_student · alumni)은 들어간다'
);

select throws_ok(
  $$update public.profiles set academic_status = 'professor' where id = '00000000-0000-0000-0000-0000000005a0'$$,
  '23514', null,
  '세 값 밖은 check 제약이 막는다'
);

select throws_ok(
  $$update public.profiles set academic_status = 'Alumni' where id = '00000000-0000-0000-0000-0000000005a0'$$,
  '23514', null,
  '대소문자가 다르면 다른 값이다'
);

select lives_ok(
  $$update public.profiles set academic_status = null where id = '00000000-0000-0000-0000-0000000005a0'$$,
  'DB 는 null 로 되돌리기를 막지 않는다(막는 곳은 서버 PATCH)'
);

select * from finish();
rollback;
