-- FAQ 표 · 첫 36행 · 권한 검증. 기대값: docs/superpowers/plans/2026-09-29-faq.md Task D1.
-- 로컬 스택에서 `supabase test db`. 트랜잭션 안에서만 돌고 rollback 한다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

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

-- 14~15 아바타 다시 만들기 값 20하트(20261014120000, 사용자 피드백 6). 보상 하트 10 구절은 그대로다.
select ok((select answer like '%그다음부터 20하트예요%' from public.faq where question = '하트는 어디에 쓰나요?'),
  '하트 쓰는 곳 답변의 다시 만들기 값은 20하트다');
select ok((select answer like '%그다음부터는 20하트예요%' and answer like '%10하트를 드려요%'
           from public.faq where question = '아바타를 다시 만들 수 있나요?'),
  '아바타 다시 만들기 답변은 20하트이고, 5번 실패 보상 10하트 구절은 그대로다');

-- 16~17 고객 문의 메일 교체(20261014130000 → 20261020100000, 앱 상수 frontend/lib/common/support_email.dart).
select is_empty($$select id from public.faq where answer like '%s26404538@gmail.com%'$$,
  '옛 문의 메일이 든 답변이 없다');
select ok((select answer like '%appmailerl4538@gmail.com 으로 가입한 학교 메일 주소와 함께%'
           from public.faq where question = '이용이 제한됐다고 나와요.'),
  '이용 제한 답변은 새 문의 메일을 안내한다');

-- 18~19 무료 하트 값(2026-10-16 사용자 확정 "무료하트조정 확정"): 에브리타임 40 · 투표 5 / 주 15, 단톡방 25 · 친구 50 은 그대로.
select is((select answer from public.faq where question = '하트를 무료로 얻는 방법이 있나요?'),
  '네. 설정 → 무료로 하트 모으기에서 받을 수 있어요. 친구의 추천 코드를 넣으면 나와 친구가 각각 50하트를 받고, '
  || '에브리타임 홍보 글 인증은 월 1회 40하트, 단톡방 공유 인증은 월 3회 25하트씩이에요. '
  || '커뮤니티 투표에 참여하면 하루 한 번 5하트, 한 주에 최대 15하트를 받아요.',
  '무료 하트 답변은 에브리타임 40 · 단톡방 25 · 투표 하루 5 / 주 15 · 친구 50 이고 "학교 단톡방" 이 아니다');
select is_empty(
  $$select id from public.faq
     where answer like '%월 1회 50하트%' or answer like '%하루 한 번 10하트%' or answer like '%최대 30하트%'
        or answer like '%학교 단톡방%'$$,
  '옛 무료 하트 값(에브리타임 50 · 투표 10 / 30) · "학교 단톡방" 이 든 답변이 없다');

select * from finish();
rollback;
