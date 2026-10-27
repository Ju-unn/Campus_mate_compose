-- 관리자 웹 매칭 현황(A9) "누가 누구에게 대화를 신청했나" 읽기 함수 admin_matching_requests 검증(상태 4종 · 커서 · 인자 검사 · 권한 · 반환 칸).
-- 마이그레이션 20261027100000_admin_matching_requests. 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
-- 다른 시험 · 시드가 남긴 줄에 흔들리지 않게 줄은 이 시험의 전용 카드 id(...d50000030cNN)로만 거른다. 시각은 모두 now() 에서 상대로 만든다(한 트랜잭션 안에서 now() 는 같은 값).
begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- 준비 (postgres) -------------------------------------------------------------
insert into public.region_group_settings (region_group) values ('d5_test');
insert into public.universities (id, name, region_group, card_opens_at) values
  ('00000000-0000-0000-0000-d50000000a01', 'D5열림대학교', 'd5_test', null),
  ('00000000-0000-0000-0000-d50000000a02', 'D5둘째대학교', 'd5_test', null);

-- 사람 6명(번호 = 끝 네 자리): 홀수 = D5열림대학교, 짝수 = D5둘째대학교. 닉네임 = 신청a · 신청b ...
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-d5000003' || lpad(i::text, 4, '0'))::uuid, 'd5r-' || i || '@example.com'
  from generate_series(1, 6) as i;
insert into public.profiles (id, university_id)
select u.id, '00000000-0000-0000-0000-d50000000a01' from auth.users u where u.email like 'd5r-%@example.com'
on conflict (id) do nothing;
update public.profiles p set
  university_id = (case when right(p.id::text, 4)::int % 2 = 1 then '00000000-0000-0000-0000-d50000000a01'
                        else '00000000-0000-0000-0000-d50000000a02' end)::uuid,
  gender = (case when right(p.id::text, 4)::int % 2 = 1 then 'male' else 'female' end)::public.gender,
  status = 'active', birth_year = 2002, height_cm = 170, nickname = '신청' || chr(96 + right(p.id::text, 4)::int)
where p.id::text like '00000000-0000-0000-0000-d5000003%';

-- 카드(주인 → 받는 사람). 번호 = 끝 두 자리.
--   c01 1→2 한 시간 전 수락 · 응답 없음 / c02 1→3 두 시간 전 수락 · 3 번이 한 시간 반 전에 수락으로 답함 /
--   c03 2→4 세 시간 전 수락 · 4 번이 두 시간 전에 거절 / c04 3→5 딱 7일 전 수락 · 응답 없음(만료 경계) /
--   c05 4→6 7일에서 한 시간 모자란 때 수락 · 응답 없음(아직 대기) / c06 5→1 네 시간 전 수락 · 응답 없음이지만 둘 사이 매칭이 30분 전에 생김 /
--   c07 6→2 거절(신청 아님) / c08 2→6 결정 없음(신청 아님) / c09 2→5 c03 과 같은 시각에 수락 · 응답 없음(같은 시각 줄의 순서).
insert into public.daily_cards (id, owner_id, target_id, source, issued_at, expires_at)
select v.id::uuid, ('00000000-0000-0000-0000-d5000003' || lpad(v.o::text, 4, '0'))::uuid,
       ('00000000-0000-0000-0000-d5000003' || lpad(v.t::text, 4, '0'))::uuid, 'daily'::public.card_source, now() - interval '8 days', now() + interval '3 days'
  from (values
    ('00000000-0000-0000-0000-d50000030c01', 1, 2), ('00000000-0000-0000-0000-d50000030c02', 1, 3),
    ('00000000-0000-0000-0000-d50000030c03', 2, 4), ('00000000-0000-0000-0000-d50000030c04', 3, 5),
    ('00000000-0000-0000-0000-d50000030c05', 4, 6), ('00000000-0000-0000-0000-d50000030c06', 5, 1),
    ('00000000-0000-0000-0000-d50000030c07', 6, 2), ('00000000-0000-0000-0000-d50000030c08', 2, 6),
    ('00000000-0000-0000-0000-d50000030c09', 2, 5)
  ) as v(id, o, t);
insert into public.card_decisions (card_id, decision, decided_at) values
  ('00000000-0000-0000-0000-d50000030c01', 'accept', now() - interval '1 hour'),
  ('00000000-0000-0000-0000-d50000030c02', 'accept', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-d50000030c03', 'accept', now() - interval '3 hours'),
  ('00000000-0000-0000-0000-d50000030c04', 'accept', now() - interval '7 days'),
  ('00000000-0000-0000-0000-d50000030c05', 'accept', now() - interval '7 days' + interval '1 hour'),
  ('00000000-0000-0000-0000-d50000030c06', 'accept', now() - interval '4 hours'),
  ('00000000-0000-0000-0000-d50000030c07', 'reject', now() - interval '1 hour'),
  ('00000000-0000-0000-0000-d50000030c09', 'accept', now() - interval '3 hours');
insert into public.acceptance_responses (card_id, responder_id, decision, decided_at) values
  ('00000000-0000-0000-0000-d50000030c02', '00000000-0000-0000-0000-d50000030003', 'accept', now() - interval '90 minutes'),
  ('00000000-0000-0000-0000-d50000030c03', '00000000-0000-0000-0000-d50000030004', 'reject', now() - interval '2 hours');
insert into public.matches (profile_a, profile_b, created_at) values
  ('00000000-0000-0000-0000-d50000030001', '00000000-0000-0000-0000-d50000030005', now() - interval '30 minutes');

-- 1. 함수 모양 (postgres) -------------------------------------------------------------
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = 'admin_matching_requests'
      and not p.prosecdef and p.proconfig = array['search_path=""']),
  1::bigint, '신청 함수가 있고 security invoker · search_path 빈 값이다(security definer 금지)'
);

-- service_role(FastAPI 와 같은 역할)로 돌려야 표 권한이 모자란지 드러난다.
set local role service_role;

-- 2. 줄 · 순서 · 상태 --------------------------------------------------------------------
select results_eq(
  $$select card_id::text from public.admin_matching_requests(null, null, null, 101)
     where card_id::text like '00000000-0000-0000-0000-d50000030c%'$$,
  $$values ('00000000-0000-0000-0000-d50000030c01'), ('00000000-0000-0000-0000-d50000030c02'),
           ('00000000-0000-0000-0000-d50000030c09'), ('00000000-0000-0000-0000-d50000030c03'),
           ('00000000-0000-0000-0000-d50000030c06'), ('00000000-0000-0000-0000-d50000030c05'),
           ('00000000-0000-0000-0000-d50000030c04')$$,
  'requests list accepted cards newest first with card id tie break — 거절(c07) · 결정 없음(c08)은 신청이 아니라 빠지고, 같은 시각 c09 · c03 은 id 큰 쪽(c09)이 먼저'
);
select results_eq(
  $$select card_id::text, status from public.admin_matching_requests(null, null, null, 101)
     where card_id::text like '00000000-0000-0000-0000-d50000030c%'$$,
  $$values ('00000000-0000-0000-0000-d50000030c01', 'waiting'), ('00000000-0000-0000-0000-d50000030c02', 'accepted'),
           ('00000000-0000-0000-0000-d50000030c09', 'waiting'), ('00000000-0000-0000-0000-d50000030c03', 'rejected'),
           ('00000000-0000-0000-0000-d50000030c06', 'accepted'), ('00000000-0000-0000-0000-d50000030c05', 'waiting'),
           ('00000000-0000-0000-0000-d50000030c04', 'expired')$$,
  'requests status — 응답 없음 waiting · 수락 응답 accepted · 거절 응답 rejected · 상대 카드로 먼저 매칭된 쌍(c06)은 응답이 없어도 accepted · 딱 7일(c04)은 expired, 7일에서 한 시간 모자라면(c05) 아직 waiting'
);

-- 3. 시각 --------------------------------------------------------------------------------
select is((select requested_at from public.admin_matching_requests(null, null, null, 101)
            where card_id = '00000000-0000-0000-0000-d50000030c01'),
          now() - interval '1 hour', 'requested_at 은 수락한 시각(decided_at)이다');
select is((select responded_at from public.admin_matching_requests(null, null, null, 101)
            where card_id = '00000000-0000-0000-0000-d50000030c02'),
          now() - interval '90 minutes', 'responded_at 은 accept 응답이면 응답 시각이다');
select is((select responded_at from public.admin_matching_requests(null, null, null, 101)
            where card_id = '00000000-0000-0000-0000-d50000030c03'),
          now() - interval '2 hours', 'responded_at 은 거절 응답이면 응답 시각이다');
select is((select responded_at from public.admin_matching_requests(null, null, null, 101)
            where card_id = '00000000-0000-0000-0000-d50000030c06'),
          now() - interval '30 minutes', 'responded_at 은 응답 없이 매칭된 쌍이면 매칭이 생긴 시각이다');
select is(
  (select count(*) from public.admin_matching_requests(null, null, null, 101)
    where card_id::text like '00000000-0000-0000-0000-d50000030c%' and status in ('waiting', 'expired') and responded_at is not null),
  0::bigint, '응답 대기 · 만료는 responded_at 이 null 이다'
);

-- 4. 상태 필터 ---------------------------------------------------------------------------
select results_eq(
  $$select card_id::text from public.admin_matching_requests('waiting', null, null, 101)
     where card_id::text like '00000000-0000-0000-0000-d50000030c%'$$,
  $$values ('00000000-0000-0000-0000-d50000030c01'), ('00000000-0000-0000-0000-d50000030c09'), ('00000000-0000-0000-0000-d50000030c05')$$,
  'requests status waiting'
);
select results_eq(
  $$select card_id::text from public.admin_matching_requests('accepted', null, null, 101)
     where card_id::text like '00000000-0000-0000-0000-d50000030c%'$$,
  $$values ('00000000-0000-0000-0000-d50000030c02'), ('00000000-0000-0000-0000-d50000030c06')$$,
  'requests status accepted'
);
select results_eq(
  $$select card_id::text from public.admin_matching_requests('rejected', null, null, 101)
     where card_id::text like '00000000-0000-0000-0000-d50000030c%'$$,
  $$values ('00000000-0000-0000-0000-d50000030c03')$$,
  'requests status rejected'
);
select results_eq(
  $$select card_id::text from public.admin_matching_requests('expired', null, null, 101)
     where card_id::text like '00000000-0000-0000-0000-d50000030c%'$$,
  $$values ('00000000-0000-0000-0000-d50000030c04')$$,
  'requests status expired'
);

-- 5. 커서 --------------------------------------------------------------------------------
select results_eq(
  $$select card_id::text from public.admin_matching_requests(null, now() - interval '3 hours',
      '00000000-0000-0000-0000-d50000030c09', 101) where card_id::text like '00000000-0000-0000-0000-d50000030c%'$$,
  $$values ('00000000-0000-0000-0000-d50000030c03'), ('00000000-0000-0000-0000-d50000030c06'),
           ('00000000-0000-0000-0000-d50000030c05'), ('00000000-0000-0000-0000-d50000030c04')$$,
  'requests cursor returns only older rows — c09 다음 쪽은 같은 시각의 c03 부터, 겹치지 않는다'
);
select results_eq(
  $$select card_id::text from public.admin_matching_requests('waiting', now() - interval '3 hours',
      '00000000-0000-0000-0000-d50000030c09', 101) where card_id::text like '00000000-0000-0000-0000-d50000030c%'$$,
  $$values ('00000000-0000-0000-0000-d50000030c05')$$,
  'requests cursor and status filter work together'
);
select throws_ok(
  $$select * from public.admin_matching_requests(null, now(), null, 10)$$, '22023', null, 'requests cursor needs both parts (시각만)');
select throws_ok(
  $$select * from public.admin_matching_requests(null, null, '00000000-0000-0000-0000-d50000030c03', 10)$$, '22023', null,
  'requests cursor needs both parts (id 만)');

-- 6. 사람 · 칸 ---------------------------------------------------------------------------
select results_eq(
  $$select requester_id::text, requester_nickname, requester_university, target_id::text, target_nickname, target_university
      from public.admin_matching_requests(null, null, null, 101) where card_id = '00000000-0000-0000-0000-d50000030c01'$$,
  $$values ('00000000-0000-0000-0000-d50000030001', '신청a', 'D5열림대학교', '00000000-0000-0000-0000-d50000030002', '신청b', 'D5둘째대학교')$$,
  'requests show who asked whom with nicknames and university names — 신청한 사람(주인)과 받은 사람(대상)이 바뀌지 않는다'
);
select results_eq(
  $$select pg_get_function_result('public.admin_matching_requests(text,timestamptz,uuid,integer)'::regprocedure)$$,
  $$values ('TABLE(card_id uuid, requested_at timestamp with time zone, status text, responded_at timestamp with time zone, requester_id uuid, requester_nickname text, requester_university text, target_id uuid, target_nickname text, target_university text)')$$,
  'requests result columns are exactly the allowed list — 사진 · 카톡 아이디 · 대화 · 전화 칸이 슬쩍 더해지면 이 시험이 떨어진다'
);

-- 7. 인자 검사 ---------------------------------------------------------------------------
select is((select count(*) from public.admin_matching_requests(null, null, null, 1)), 1::bigint, 'requests limit 1 gives one row');
select throws_ok($$select * from public.admin_matching_requests(null, null, null, 0)$$, '22023', null, 'requests rejects limit 0');
select throws_ok($$select * from public.admin_matching_requests(null, null, null, 102)$$, '22023', null, 'requests rejects limit 102');
select throws_ok($$select * from public.admin_matching_requests(null, null, null, null)$$, '22023', null, 'requests rejects null limit');
select throws_ok($$select * from public.admin_matching_requests('ended', null, null, 10)$$, '22023', null, 'requests rejects an unknown status');
select throws_ok($$select * from public.admin_matching_requests('matched', null, null, 10)$$, '22023', null, 'requests rejects a pairs-style status');
select throws_ok($$select * from public.admin_matching_requests('waiting,expired', null, null, 10)$$, '22023', null, 'requests rejects a list of statuses');
select throws_ok($$select * from public.admin_matching_requests('', null, null, 10)$$, '22023', null, 'requests rejects an empty status');

-- 8. service_role 만 부른다 ---------------------------------------------------------------
reset role;
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = 'admin_matching_requests'
      and has_function_privilege('service_role', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')),
  1::bigint, 'service_role 만 부를 수 있다 — anon · authenticated(그리고 public)는 실행 권한이 없다'
);
set local role authenticated;
select throws_ok($$select * from public.admin_matching_requests(null, null, null, 10)$$, '42501', null, 'authenticated 는 admin_matching_requests 를 부를 수 없다');
reset role;
set local role anon;
select throws_ok($$select * from public.admin_matching_requests(null, null, null, 10)$$, '42501', null, 'anon 은 admin_matching_requests 를 부를 수 없다');
reset role;

select * from finish();
rollback;
