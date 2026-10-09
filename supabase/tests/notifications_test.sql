-- 알림함 표(notifications) 검증 — 수익모델 재설계 01 §8. 푸시와 별개로 앱 안 알림함에 쌓는 기록이다.
-- 종류는 열거형이 아니라 text + check 라서 새 종류는 check 를 바꾸는 마이그레이션 한 줄로 늘린다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000041a1', 'nt@noti.ac.kr');

select has_table('public', 'notifications', '알림함 표가 있다');
select fk_ok('public', 'notifications', 'profile_id', 'public', 'profiles', 'id');
select has_index('public', 'notifications', 'notifications_unread_index', '안 읽은 것만 훑는 부분 인덱스');
select has_index('public', 'notifications', 'notifications_profile_created_index', '사람별 최근순 인덱스');
select is(
  (select indpred is not null from pg_index where indexrelid = 'public.notifications_unread_index'::regclass),
  true, '안 읽은 인덱스는 부분 인덱스다(where read_at is null)'
);
select is((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass), true, 'RLS 켜짐');
select is((select count(*) from pg_policies where schemaname = 'public' and tablename = 'notifications'), 0::bigint, '정책 없음 = 클라이언트가 직접 읽지 못한다(서버가 내려준다)');
select ok(
  not has_table_privilege('authenticated', 'public.notifications', 'select')
  and not has_table_privilege('anon', 'public.notifications', 'select')
  and not has_table_privilege('authenticated', 'public.notifications', 'insert')
  and not has_table_privilege('anon', 'public.notifications', 'insert'),
  'anon · authenticated 는 읽지도 쓰지도 못한다'
);
select ok(has_table_privilege('service_role', 'public.notifications', 'select, insert, update, delete'), 'service_role 은 읽고 · 쓰고 · 읽음 표시하고 · 지울 수 있다');

select lives_ok(
  $$insert into public.notifications (profile_id, kind, title, body, data)
    values ('00000000-0000-0000-0000-0000000041a1', 'card_arrived', '오늘의 카드가 도착했어요', '확인해 보세요', '{"route": "cards"}')$$,
  '카드 도착 알림을 쌓을 수 있다'
);

select lives_ok(
  $$insert into public.notifications (profile_id, kind, title, body)
    select '00000000-0000-0000-0000-0000000041a1', k, 't', 'b'
    from unnest(array['chat_request', 'match_made', 'friend_review', 'verification_result', 'night_digest']) k$$,
  '나머지 다섯 종류도 모두 받는다'
);

select throws_ok(
  $$insert into public.notifications (profile_id, kind, title, body)
    values ('00000000-0000-0000-0000-0000000041a1', 'card_arrive', 't', 'b')$$,
  '23514', null, '종류 오타는 check 가 막는다'
);

select is(
  (select data from public.notifications where kind = 'match_made'), '{}'::jsonb, 'data 의 기본값은 빈 객체다'
);

select is(
  (select read_at from public.notifications where kind = 'match_made'), null, '새 알림은 안 읽음(read_at null)이다'
);

select is(
  (select created_at is not null from public.notifications where kind = 'match_made'), true, 'created_at 이 자동으로 찍힌다'
);

select throws_ok(
  $$insert into public.notifications (profile_id, kind, title, body)
    values ('00000000-0000-0000-0000-0000000041a1', 'card_arrived', null, 'b')$$,
  '23502', null, '제목은 필수다'
);

delete from public.profiles where id = '00000000-0000-0000-0000-0000000041a1';
select is_empty(
  $$select 1 from public.notifications where profile_id = '00000000-0000-0000-0000-0000000041a1'$$,
  '프로필을 지우면 알림함도 cascade 로 지워진다'
);

select * from finish();
rollback;
