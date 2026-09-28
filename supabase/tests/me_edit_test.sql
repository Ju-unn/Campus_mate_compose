-- 나 탭 편집이 기대는 DB 동작 — profile_photos 두 행의 자리 맞바꿈이 upsert 한 문장으로 통과한다
-- ((profile_id, position) 유니크가 deferred, 계획서 2026-09-27-me-edit.md 3절). 하트 쓰기 쪽은 supabase/tests/hearts_test.sql.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

-- 준비 --------------------------------------------------------------------
-- A = ...ea(사진 2장), 대학 = ...e1
-- on_auth_user_created 트리거가 도메인으로 대학을 찾으므로 도메인 행이 auth.users 보다 먼저다(다른 테스트와 같은 모양).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-0000000000e1', '편집테스트대학교', 'seoul');

insert into public.university_email_domains (domain, university_id)
values ('meedit.ac.kr', '00000000-0000-0000-0000-0000000000e1');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000ea', 'me-a@meedit.ac.kr');

insert into public.profiles (id, university_id) values
  ('00000000-0000-0000-0000-0000000000ea', '00000000-0000-0000-0000-0000000000e1')
on conflict (id) do nothing;

-- 사진 자리 맞바꿈 ----------------------------------------------------------

insert into public.profile_photos (id, profile_id, storage_path, position, is_avatar_source) values
  ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000000ea', 'ea/p0.jpg', 0, true),
  ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000000ea', 'ea/p1.jpg', 1, false);

-- PostgREST 의 on_conflict=id + merge-duplicates 가 만드는 문장과 같은 모양이다. 원본 표시는 앞서 내린 상태로 둔다
-- (원본 부분 유니크 인덱스는 즉시 검사라 PUT /me/photos 도 먼저 내린다).
update public.profile_photos set is_avatar_source = false
 where profile_id = '00000000-0000-0000-0000-0000000000ea';
select lives_ok(
  $$insert into public.profile_photos (id, profile_id, storage_path, position, is_avatar_source) values
      ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000000ea', 'ea/p0.jpg', 1, false),
      ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000000ea', 'ea/p1.jpg', 0, true)
    on conflict (id) do update
      set position = excluded.position, is_avatar_source = excluded.is_avatar_source$$,
  '두 사진의 자리 맞바꿈은 한 문장이면 통과한다(deferred 유니크)'
);
-- deferred 유니크는 커밋 때 본다. 이 파일은 rollback 으로 끝나 커밋이 없으니, 지금 검사를 당겨 와야
-- "맞바꾼 뒤의 자리가 겹치지 않는다" 가 실제로 확인된다(안 당기면 위 lives_ok 는 자리가 겹쳐도 통과한다).
select lives_ok(
  $$set constraints public.profile_photos_profile_position_unique immediate$$,
  '맞바꾼 뒤 커밋 시점 검사(자리 겹침 없음)도 통과한다'
);
select is(
  (select position::int from public.profile_photos where id = '00000000-0000-0000-0000-00000000f002'),
  0,
  '둘째 사진이 대표 자리로 왔다'
);
select is(
  (select storage_path from public.profile_photos
    where profile_id = '00000000-0000-0000-0000-0000000000ea' and is_avatar_source),
  'ea/p1.jpg',
  '원본 표시는 한 장만 남는다'
);

select * from finish();
rollback;
