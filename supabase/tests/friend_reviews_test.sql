-- 지인 리뷰 표 · 제약 · 권한 검증. 기대값: docs/superpowers/plans/2026-09-28-friend-review.md Task C1.
-- 로컬 스택에서 `supabase test db`. 트랜잭션 안에서만 돌고 rollback 한다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- 준비: R = ...90(작성자), E = ...91(받은 사람), GONE = ...92(탈퇴할 작성자)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000000009', '테스트대학교9', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('test9.ac.kr', '00000000-0000-0000-0000-000000000009');

-- on_auth_user_created 트리거가 profiles 행을 만든다.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000090', 'fr-r@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000091', 'fr-e@test9.ac.kr'),
  ('00000000-0000-0000-0000-000000000092', 'fr-gone@test9.ac.kr');

-- 1~3 표 · RLS · 권한
select has_table('public', 'friend_reviews', 'friend_reviews 표가 있다');
select ok((select relrowsecurity from pg_class where oid = 'public.friend_reviews'::regclass),
  'friend_reviews 는 RLS 가 켜져 있다');
select is_empty($$
  select grantee, privilege_type from information_schema.role_table_grants
  where table_schema = 'public' and table_name = 'friend_reviews'
    and grantee in ('anon', 'authenticated')
$$, 'anon · authenticated 는 friend_reviews 에 아무 권한이 없다');

-- 4 기본값
insert into public.friend_reviews (id, reviewer_id, reviewee_id, tags)
values ('00000000-0000-0000-0000-0000000009a0', '00000000-0000-0000-0000-000000000090',
        '00000000-0000-0000-0000-000000000091', array['약속을 잘 지켜요']);
select is((select status::text from public.friend_reviews where id = '00000000-0000-0000-0000-0000000009a0'),
  'visible', 'status 기본값은 visible 이다');

-- 5 같은 사람에게 두 번
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000090', '00000000-0000-0000-0000-000000000091', array['성실해요'])
$$, '23505', null, '같은 작성자가 같은 사람에게 두 번 쓸 수 없다');

-- 6 반대 방향은 된다(양방향 품앗이, spec §2.8)
select lives_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000090', array['성실해요'])
$$, '받은 사람이 작성자에게 거꾸로 쓰는 것은 된다');

-- 7 자기 자신
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000092', array['성실해요'])
$$, '23514', null, '자기 자신에게는 쓸 수 없다');

-- 8~9 태그 개수
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091', array[]::text[])
$$, '23514', null, '태그 0개는 안 된다');
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091',
          array['성실해요', '솔직해요', '다정해요', '차분해요'])
$$, '23514', null, '태그 4개는 안 된다');

-- 10~12 한마디
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags, comment)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091',
          array['성실해요'], repeat('가', 101))
$$, '23514', null, '한마디 101자는 안 된다');
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags, comment)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091', array['성실해요'], '')
$$, '23514', null, '빈 한마디는 null 로 넣어야 한다');
select throws_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags, comment)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091', array['성실해요'], ' 좋아요')
$$, '23514', null, '앞뒤 공백이 남은 한마디는 안 된다');

-- 13 100자는 된다
select lives_ok($$
  insert into public.friend_reviews (reviewer_id, reviewee_id, tags, comment)
  values ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091',
          array['성실해요', '솔직해요', '다정해요'], repeat('가', 100))
$$, '태그 3개 · 한마디 100자는 된다');

-- 14 인덱스
select has_index('public', 'friend_reviews', 'friend_reviews_reviewee_id_created_at_index',
  '받은 목록 인덱스가 있다');

-- 15~16 계정 삭제(탈퇴 30일 뒤)면 쓴 리뷰 · 받은 리뷰 다 사라진다(spec §2.6 FK 규칙)
insert into public.friend_reviews (reviewer_id, reviewee_id, tags)
values ('00000000-0000-0000-0000-000000000090', '00000000-0000-0000-0000-000000000092', array['성실해요']);
delete from auth.users where id = '00000000-0000-0000-0000-000000000092';
select is_empty($$
  select 1 from public.friend_reviews where reviewer_id = '00000000-0000-0000-0000-000000000092'
$$, '작성자 계정이 지워지면 그 리뷰도 지워진다');
select is_empty($$
  select 1 from public.friend_reviews where reviewee_id = '00000000-0000-0000-0000-000000000092'
$$, '받은 사람 계정이 지워지면 받은 리뷰도 지워진다');

-- 17 서버 embed 가 기대는 FK 이름 · cascade(backend/app/friend_reviews/repository.py)
select is((select count(*) from pg_constraint
           where conrelid = 'public.friend_reviews'::regclass and confdeltype = 'c'
             and conname in ('friend_reviews_reviewer_id_fkey', 'friend_reviews_reviewee_id_fkey')),
  2::bigint, 'FK 두 개는 서버가 쓰는 이름이고 on delete cascade 다');

-- 18 FastAPI 전용 — 정책 0
select policies_are('public', 'friend_reviews', array[]::name[], 'friend_reviews 에는 정책이 없다');

select * from finish();
rollback;
