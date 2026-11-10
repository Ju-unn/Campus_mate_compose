-- 문의하기(inquiries) 검증: 권한(default deny) · check 제약 · 탈퇴 시 set null · 답변 완료 1년 정리 조건.
-- 마이그레이션 20261110200000_create_inquiries. 로컬 스택에서 `supabase test db` 로 돌린다.
-- 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

-- 준비 (postgres) -------------------------------------------------------------
-- 사람: A = …0a01(문의를 쓰는 사람), B = …0a02(탈퇴해 set null 을 보는 사람)
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-0000000000a1', '문의시험대학교', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('inq.ac.kr', '00000000-0000-0000-0000-0000000000a1');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000a01', 'inq-a@inq.ac.kr'),
  ('00000000-0000-0000-0000-000000000a02', 'inq-b@inq.ac.kr');

-- 1. 모양 · RLS · 권한 ------------------------------------------------------------
select is(
  (select relrowsecurity from pg_class where oid = 'public.inquiries'::regclass),
  true, 'inquiries 는 RLS 가 켜져 있다'
);                                                                                                   -- 1
select is(
  (select count(*) from pg_policies where tablename = 'inquiries'),
  0::bigint, 'inquiries 에는 정책이 하나도 없다(FastAPI 전용)'
);                                                                                                   -- 2
select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder) from pg_enum e
    where e.enumtypid = 'public.inquiry_reason'::regtype),
  array['account', 'payment', 'matching', 'safety', 'bug', 'other'],
  '사유 enum 은 여섯 값이다'
);                                                                                                   -- 3
select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder) from pg_enum e
    where e.enumtypid = 'public.inquiry_status'::regtype),
  array['new', 'in_progress', 'answered'],
  '상태 enum 은 세 값이다'
);                                                                                                   -- 4
select is(
  (select count(*) from pg_indexes
    where tablename = 'inquiries'
      and indexname in ('inquiries_created_at_id_index', 'inquiries_profile_id_created_at_index',
                        'inquiries_status_index')),
  3::bigint, '인덱스 세 개가 있다'
);                                                                                                   -- 5
select is(
  (select confdeltype::text from pg_constraint
    where conrelid = 'public.inquiries'::regclass and contype = 'f'),
  'n', 'profile_id FK 는 on delete set null 이다'
);                                                                                                   -- 6

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000a01", "role": "authenticated"}';

select throws_ok(
  $$select id from public.inquiries$$,
  '42501', null, 'authenticated 는 inquiries 를 select 할 수 없다(42501)'
);                                                                                                   -- 7
select throws_ok(
  $$insert into public.inquiries (profile_id, reason, body, reply_email)
    values ('00000000-0000-0000-0000-000000000a01', 'bug', '앱이 멈춰요', 'me@example.com')$$,
  '42501', null, 'authenticated 는 inquiries 에 insert 할 수 없다(42501)'
);                                                                                                   -- 8

set local role anon;
select throws_ok(
  $$select id from public.inquiries$$,
  '42501', null, 'anon 은 inquiries 를 select 할 수 없다(42501)'
);                                                                                                   -- 9

reset role;
select ok(
  has_table_privilege('service_role', 'public.inquiries', 'select, insert, update, delete')
  and not has_table_privilege('authenticated', 'public.inquiries', 'select, insert, update, delete')
  and not has_table_privilege('anon', 'public.inquiries', 'select, insert, update, delete'),
  'service_role 만 inquiries 를 읽고 쓴다'
);                                                                                                   -- 10

-- 2. 기본값 · check 제약 (service_role) -------------------------------------------
set local role service_role;

select lives_ok(
  $$insert into public.inquiries (id, profile_id, reason, body, reply_email)
    values ('00000000-0000-0000-0000-00000000a0f1', '00000000-0000-0000-0000-000000000a01',
            'bug', '앱이 멈춰요', 'me@example.com')$$,
  '정상 문의는 저장된다'
);                                                                                                   -- 11
select is(
  (select status::text || ':' || (answered_at is null)::text || ':' || (admin_memo is null)::text
     from public.inquiries where id = '00000000-0000-0000-0000-00000000a0f1'),
  'new:true:true', '기본 상태는 new, 답변 시각 · 메모는 비어 있다'
);                                                                                                   -- 12
select throws_ok(
  $$insert into public.inquiries (reason, body, reply_email) values ('bug', '   ', 'me@example.com')$$,
  '23514', null, '공백뿐인 내용은 막는다'
);                                                                                                   -- 13
select throws_ok(
  $$insert into public.inquiries (reason, body, reply_email) values ('bug', repeat('가', 1001), 'me@example.com')$$,
  '23514', null, '1001자 내용은 막는다'
);                                                                                                   -- 14
select lives_ok(
  $$insert into public.inquiries (reason, body, reply_email) values ('other', repeat('가', 1000), 'me@example.com')$$,
  '1000자 내용은 저장된다'
);                                                                                                   -- 15
select throws_ok(
  $$insert into public.inquiries (reason, body, reply_email) values ('bug', '내용', 'no-at-sign')$$,
  '23514', null, '@ 없는 메일은 막는다'
);                                                                                                   -- 16
select throws_ok(
  $$insert into public.inquiries (reason, body, reply_email) values ('bug', '내용', E'me@example.com\nBcc: x@y.z')$$,
  '23514', null, '줄바꿈이 낀 메일(헤더 주입)은 막는다'
);                                                                                                   -- 17
select throws_ok(
  $$insert into public.inquiries (reason, body, reply_email)
    values ('bug', '내용', repeat('a', 250) || '@b.cc')$$,
  '23514', null, '254자를 넘는 메일은 막는다'
);                                                                                                   -- 18
select throws_ok(
  $$update public.inquiries set admin_memo = repeat('가', 1001) where id = '00000000-0000-0000-0000-00000000a0f1'$$,
  '23514', null, '1001자 관리자 메모는 막는다'
);                                                                                                   -- 19
select throws_ok(
  $$update public.inquiries set status = 'answered' where id = '00000000-0000-0000-0000-00000000a0f1'$$,
  '23514', null, 'answered 인데 answered_at 이 없으면 막는다'
);                                                                                                   -- 20

-- 3. 탈퇴 → set null (문의는 남는다) ------------------------------------------------
insert into public.inquiries (id, profile_id, reason, body, reply_email)
values ('00000000-0000-0000-0000-00000000a0f2', '00000000-0000-0000-0000-000000000a02',
        'account', '탈퇴 전 문의', 'b@example.com');
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-000000000a02';
select is(
  (select profile_id is null from public.inquiries where id = '00000000-0000-0000-0000-00000000a0f2'),
  true, '탈퇴하면 문의 행은 남고 profile_id 만 null 이 된다'
);                                                                                                   -- 21

-- 4. 보관 정리: 답변 완료 후 1년 (배치가 보내는 delete 조건과 같다) -----------------------
insert into public.inquiries (id, reason, body, reply_email, status, answered_at, created_at) values
  ('00000000-0000-0000-0000-00000000b001', 'bug', '오래전 답변', 'x@example.com', 'answered',
   now() - interval '400 days', now() - interval '401 days'),
  ('00000000-0000-0000-0000-00000000b002', 'bug', '최근 답변', 'x@example.com', 'answered',
   now() - interval '10 days', now() - interval '500 days'),
  ('00000000-0000-0000-0000-00000000b003', 'bug', '오래전 미답변', 'x@example.com', 'new',
   null, now() - interval '500 days');

set local role service_role;
-- 배치(delete_inquiries_before)가 보내는 조건과 같다. 문장으로 먼저 실행한 뒤 남은 행을 센다.
delete from public.inquiries where answered_at < now() - interval '365 days';
select is(
  (select count(*) from public.inquiries where id = '00000000-0000-0000-0000-00000000b001'),
  0::bigint, '답변 완료 후 1년이 지난 행만 지워진다'
);                                                                                                   -- 22
select is(
  (select count(*) from public.inquiries
    where id in ('00000000-0000-0000-0000-00000000b002', '00000000-0000-0000-0000-00000000b003')),
  2::bigint, '최근 답변과 아직 답하지 않은 오래된 문의는 남는다'
);                                                                                                   -- 23
reset role;
select is(
  (select count(*) from public.inquiries where id = '00000000-0000-0000-0000-00000000a0f1'),
  1::bigint, '새 문의는 정리에 걸리지 않는다'
);                                                                                                   -- 24

select * from finish();
rollback;
