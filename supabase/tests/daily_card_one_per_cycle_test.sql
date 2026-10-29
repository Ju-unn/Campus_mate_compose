-- 무료 카드는 한 사람에게 하루(서울 날짜)에 한 장 — daily_cards_one_free_per_day(2026-10-29).
-- 지급 배치의 "오늘 이미 받은 사람은 건너뜀"(cards/issuing.py, 자정 기준)과 같은 규칙을 DB 가 지킨다. 가입 뒤 첫 오늘 탭이
-- 주는 첫 카드와 그날 배치가 겹쳐도, 첫 카드 요청이 동시에 두 번 와도 두 번째 insert 는 23505 다.
-- 만료 시각으로 묶지 않는 이유: 주 중에 사다리가 오르면(주 1회 → 주 2회) 월요일 카드와 목요일 카드의 만료가 같아져
-- 정상 카드가 막힌다(검토 권고 10-29).
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

insert into public.region_group_settings (region_group) values ('cycle_test');
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-000000004001', '주기테스트대학교', 'cycle_test');

-- 4101 · 4102 = 받는 사람(남), 4103 · 4104 = 카드 상대(여)
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000' || n)::uuid, 'cy-' || n || '@cycle.ac.kr'
from unnest(array['4101','4102','4103','4104']) as n;

update public.profiles set
  university_id = '00000000-0000-0000-0000-000000004001',
  gender = (case when right(id::text, 4) in ('4101', '4102') then 'male' else 'female' end)::public.gender,
  status = 'active', birth_year = 2002, height_cm = 170, last_active_at = now(),
  nickname = 'cy' || translate(right(id::text, 2), '0123456789', 'abcdefghij')
where id in (select id from auth.users where email like '%@cycle.ac.kr');

select has_index('public', 'daily_cards', 'daily_cards_one_free_per_day',
                 '무료 카드 하루 한 장 인덱스가 있다');

-- 서울 10-29 23:00 에 한 장
insert into public.daily_cards (owner_id, target_id, source, issued_at, expires_at)
values ('00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-000000004103', 'daily',
        '2026-10-29 23:00+09', '2026-11-02 07:00+09');

select throws_ok(
  $$insert into public.daily_cards (owner_id, target_id, source, issued_at, expires_at)
    values ('00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-000000004104', 'daily',
            '2026-10-29 07:00+09', '2026-11-05 07:00+09')$$,
  '23505', null,
  '같은 사람 · 같은 서울 날짜의 무료 카드 두 번째 장은 막힌다(상대 · 만료가 달라도)');

select lives_ok(
  $$insert into public.daily_cards (owner_id, target_id, source, issued_at, expires_at)
    values ('00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-000000004104', 'daily',
            '2026-10-30 00:30+09', '2026-11-02 07:00+09')$$,
  '서울 날짜가 바뀌면(UTC 로는 같은 날이어도) 된다 — 만료가 같아도 사다리 상향 카드는 막지 않는다');

select lives_ok(
  $$insert into public.daily_cards (owner_id, target_id, source, issued_at, expires_at)
    values ('00000000-0000-0000-0000-000000004102', '00000000-0000-0000-0000-000000004103', 'daily',
            '2026-10-29 23:00+09', '2026-11-02 07:00+09')$$,
  '다른 사람은 같은 날이어도 된다');

select lives_ok(
  $$insert into public.daily_cards (owner_id, target_id, source, issued_at, expires_at)
    values ('00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-000000004104', 'purchased',
            '2026-10-29 23:30+09', null)$$,
  '산 카드(purchased)는 이 규칙 밖이다');

select is((select count(*)::int from public.daily_cards
           where owner_id = '00000000-0000-0000-0000-000000004101' and source = 'daily'),
          2, '첫 사람의 무료 카드는 날마다 하나씩 두 장');

select is((select indisunique from pg_index where indexrelid = 'public.daily_cards_one_free_per_day'::regclass),
          true, '유일 인덱스다');

select * from finish();
rollback;
