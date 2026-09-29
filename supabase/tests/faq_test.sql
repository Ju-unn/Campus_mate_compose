-- FAQ 표 · 첫 36행 · 권한 검증. 기대값: docs/superpowers/plans/2026-09-29-faq.md Task D1.
-- 로컬 스택에서 `supabase test db`. 트랜잭션 안에서만 돌고 rollback 한다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

-- 1~3 표 · RLS · enum
select has_table('public', 'faq', 'faq 표가 있다');
select ok((select relrowsecurity from pg_class where oid = 'public.faq'::regclass), 'faq 는 RLS 가 켜져 있다');
select enum_has_labels('public', 'faq_category',
  array['card_matching', 'heart_payment', 'photo_profile', 'friend_review', 'safety', 'account'],
  'faq_category 는 DESIGN §8.13 묶음 6개를 이 순서로 가진다');

-- 4~8 첫 문구(FAQ_초안.md 09-29)
select is((select count(*) from public.faq), 36::bigint, '첫 문구는 36개다');
select results_eq(
  -- 출력 열 이름을 category 로 두면 order by 가 글자순(text)으로 붙는다 — enum 순서로 세우려고 이름을 바꾼다.
  $$select category::text as name, count(*) from public.faq group by category order by category$$,
  $$values ('card_matching', 7::bigint), ('heart_payment', 5), ('photo_profile', 6),
           ('friend_review', 4), ('safety', 6), ('account', 8)$$,
  '묶음별 개수가 초안과 같다');
select is_empty(
  $$select id from public.faq where btrim(question) = '' or btrim(answer) = ''$$,
  '빈 질문 · 빈 답변이 없다');
select is_empty(
  $$select sort_order from public.faq group by sort_order having count(*) > 1$$,
  '첫 36행의 sort_order 는 겹치지 않는다');
select is((select question from public.faq order by sort_order limit 1), '카드는 언제 오나요?',
  '맨 앞 문항은 카드는 언제 오나요? 다');

-- 9~12 로그인한 사용자: 전부 읽고, 못 쓴다(ERD §2)
set local role authenticated;
select is((select count(*) from public.faq), 36::bigint, 'authenticated 는 36행을 모두 읽는다');
select throws_ok(
  $$insert into public.faq (category, question, answer, sort_order) values ('account', 'q', 'a', 999)$$,
  '42501', null, 'authenticated 는 faq 에 쓸 수 없다');
select throws_ok($$update public.faq set answer = 'x'$$, '42501', null, 'authenticated 는 faq 를 고칠 수 없다');
select throws_ok($$delete from public.faq$$, '42501', null, 'authenticated 는 faq 를 지울 수 없다');

-- 13 로그인 전: 못 읽는다
set local role anon;
select throws_ok($$select 1 from public.faq$$, '42501', null, 'anon 은 faq 를 읽을 수 없다');
reset role;

select * from finish();
rollback;
