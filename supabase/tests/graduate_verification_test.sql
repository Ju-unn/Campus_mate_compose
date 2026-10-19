-- 졸업생 인증(졸업증명서) DB 검증: 신청 표 · 버킷 · 프로필 칸 · 승인/반려 함수 · 14일 정리 제외.
-- 마이그레이션 20261019200000_graduate_verification_tables · 20261019200100_graduate_verification_functions.
-- 기대값 기준: docs/superpowers/plans/2026-10-19-graduate-verification.md Task 1.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(70);

-- 준비 (postgres) -------------------------------------------------------------
-- 학교 U1 = ...9900, U2 = ...9901. 관리자 AD = ...9ad1. 프로필(가입 트리거가 만든다) P1~P9 = ...9601~9609.
-- P1 승인할 것 · P2 반려할 것 · P3 규칙 위반 시험(끝까지 대기) · P4 이미 학교 메일 인증됨 · P5 탈퇴
-- P6 해시 충돌 · 차단 시험 · P7 이미 승인된 사람(해시 보유) · P8 해시 유일 시험 · P9 대기 하나 규칙 시험.
insert into public.universities (id, name, region_group) values
  ('00000000-0000-0000-0000-000000009900', '졸업생테스트대학교', 'seoul'),
  ('00000000-0000-0000-0000-000000009901', '졸업생테스트대학교2', 'seoul');

insert into auth.users (id, email, raw_app_meta_data) values
  ('00000000-0000-0000-0000-000000009601', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009602', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009603', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009604', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009605', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009606', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009607', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009608', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009609', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009610', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009611', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009612', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-000000009613', null, '{"provider": "kakao", "providers": ["kakao"]}'),
  ('00000000-0000-0000-0000-00000000ad01', 'operator-grad@example.com', '{"provider": "google", "providers": ["google"]}');
insert into public.admin_users (user_id) values ('00000000-0000-0000-0000-00000000ad01');

-- P4: 학교 메일로 이미 인증됨 / P5: 탈퇴 / P7: 이미 졸업생 인증됨
update public.profiles
   set university_id = '00000000-0000-0000-0000-000000009900', school_email_verified_at = now()
 where id in ('00000000-0000-0000-0000-000000009604', '00000000-0000-0000-0000-000000009607');
update public.profiles set status = 'withdrawn', withdrawn_at = now()
 where id = '00000000-0000-0000-0000-000000009605';

-- 신청 줄(postgres 가 직접). 사진 경로는 값만 있으면 된다.
insert into public.graduate_verification_requests
  (id, profile_id, photo_path, ocr_state, ocr_document_number, ocr_school_text, previous_school_email, document_hmac) values
  ('00000000-0000-0000-0000-000000009f01', '00000000-0000-0000-0000-000000009601', '9601/9f01.jpg', 'read', 'AB12CD34', '졸업생테스트대학교', 'old@prev.ac.kr', '\x0f01'),
  ('00000000-0000-0000-0000-000000009f02', '00000000-0000-0000-0000-000000009602', '9602/9f02.jpg', 'read', 'ZZ99', '졸업생테스트대학교', 'old2@prev.ac.kr', null),
  ('00000000-0000-0000-0000-000000009f03', '00000000-0000-0000-0000-000000009603', '9603/9f03.jpg', 'nothing_found', null, null, null, null),
  ('00000000-0000-0000-0000-000000009f04', '00000000-0000-0000-0000-000000009604', '9604/9f04.jpg', 'failed', null, null, null, null),
  ('00000000-0000-0000-0000-000000009f05', '00000000-0000-0000-0000-000000009605', '9605/9f05.jpg', 'failed', null, null, null, null),
  ('00000000-0000-0000-0000-000000009f06', '00000000-0000-0000-0000-000000009606', '9606/9f06.jpg', 'read', 'REUSE99', null, null, null);

-- 이미 승인된 줄(P7) — 해시 충돌의 상대.
insert into public.graduate_verification_requests
  (id, profile_id, status, photo_path, ocr_state, university_id, document_hmac, student_hmac, decided_by, decided_at) values
  ('00000000-0000-0000-0000-000000009f07', '00000000-0000-0000-0000-000000009607', 'approved', null, 'read',
   '00000000-0000-0000-0000-000000009900', '\xd0c1', '\x5e01', '00000000-0000-0000-0000-00000000ad01', now());

-- 재가입 제한: 학번 해시 5b01 은 미래까지 막힘, 5b02 는 지난 제한.
insert into public.signup_blocks (email_hmac, blocked_until) values
  ('\x5b01', now() + interval '1 day'),
  ('\x5b02', now() - interval '1 day');

-- 1. 표 · 버킷 잠금 -----------------------------------------------------------------

select ok(
  (select relrowsecurity from pg_class where oid = 'public.graduate_verification_requests'::regclass),
  '신청 표는 RLS 가 켜져 있다'
);                                                                                                   -- 1
select is_empty(
  $$select policyname from pg_policies where schemaname = 'public' and tablename = 'graduate_verification_requests'$$,
  '정책이 0개다 — 앱은 자기 신청도 읽지 못한다(FastAPI 전용)'
);                                                                                                   -- 2
select ok(
  not has_table_privilege('anon', 'public.graduate_verification_requests', 'select')
  and not has_table_privilege('authenticated', 'public.graduate_verification_requests', 'select')
  and not has_table_privilege('authenticated', 'public.graduate_verification_requests', 'insert')
  and not has_table_privilege('authenticated', 'public.graduate_verification_requests', 'update')
  and not has_table_privilege('authenticated', 'public.graduate_verification_requests', 'delete'),
  'anon · authenticated 는 신청 표에 아무 권한도 없다'
);                                                                                                   -- 3
select ok(
  has_table_privilege('service_role', 'public.graduate_verification_requests', 'select')
  and has_table_privilege('service_role', 'public.graduate_verification_requests', 'insert')
  and has_table_privilege('service_role', 'public.graduate_verification_requests', 'update')
  and has_table_privilege('service_role', 'public.graduate_verification_requests', 'delete'),
  'service_role 은 select · insert · update · delete 를 가진다'
);                                                                                                   -- 4
select results_eq(
  $$select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'graduate-cert-temp'$$,
  $$values (false, 10485760::bigint, array['image/jpeg', 'image/png']::text[])$$,
  'graduate-cert-temp 버킷은 비공개 · 10MB · jpeg/png 다'
);                                                                                                   -- 5

-- 2. 결정된 줄에 평문이 있으면 거부 (postgres) -----------------------------------------

select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, reason, photo_path, ocr_state, previous_school_email, consented_at, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009609', 'rejected', 'unreadable', null, 'read', 'x@prev.ac.kr', now(),
            '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23514', null, '반려된 줄에 이전 학교 메일이 있으면 check 위반이다'
);                                                                                                   -- 6
select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, photo_path, ocr_state, ocr_document_number, university_id, document_hmac, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009609', 'approved', null, 'read', 'AB12CD34',
            '00000000-0000-0000-0000-000000009900', '\x0a01', '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23514', null, '승인된 줄에 OCR 번호가 있으면 check 위반이다'
);                                                                                                   -- 7
select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, reason, photo_path, ocr_state, ocr_school_text, decided_at)
    values ('00000000-0000-0000-0000-000000009609', 'cancelled', 'switched', null, 'read', '서울대학교', now())$$,
  '23514', null, '취소된 줄에 OCR 학교 글자가 있으면 check 위반이다'
);                                                                                                   -- 8
select lives_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, photo_path, ocr_state, ocr_document_number, ocr_school_text, previous_school_email)
    values ('00000000-0000-0000-0000-000000009610', '9610/a.jpg', 'read', 'AB12CD34', '서울대학교', 'x@prev.ac.kr')$$,
  '대기 중인 줄은 평문 세 칸을 가질 수 있다(관리자 화면 미리 채우기용)'
);                                                                                                   -- 9
select throws_ok(
  $$insert into public.graduate_verification_requests (profile_id, photo_path, ocr_state, previous_school_email)
    values ('00000000-0000-0000-0000-000000009611', '9611/a.jpg', 'read', repeat('a', 250) || '@b.kr')$$,
  '23514', null, '이전 학교 메일은 254자까지다'
);                                                                                                   -- 10

-- 3. 상태쌍 (postgres) ------------------------------------------------------------------

select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, photo_path, ocr_state, document_hmac, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009611', 'approved', null, 'read', '\x0a02',
            '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23514', null, '승인에 학교(university_id)가 없으면 check 위반이다'
);                                                                                                   -- 11
select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, photo_path, ocr_state, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009611', 'rejected', null, 'read',
            '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23514', null, '사유 없는 반려는 check 위반이다'
);                                                                                                   -- 12
select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, reason, photo_path, ocr_state, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009611', 'rejected', 'whatever', null, 'read',
            '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23514', null, '목록 밖 반려 사유는 check 위반이다'
);                                                                                                   -- 13
select throws_ok(
  $$insert into public.graduate_verification_requests (profile_id, status, photo_path, ocr_state, decided_at)
    values ('00000000-0000-0000-0000-000000009611', 'cancelled', null, 'read', now())$$,
  '23514', null, '사유 없는 취소는 check 위반이다'
);                                                                                                   -- 14
select throws_ok(
  $$insert into public.graduate_verification_requests (profile_id, photo_path, ocr_state, decided_at)
    values ('00000000-0000-0000-0000-000000009611', '9611/a.jpg', 'read', now())$$,
  '23514', null, '대기 줄에 결정 시각이 있으면 check 위반이다'
);                                                                                                   -- 15
select throws_ok(
  $$insert into public.graduate_verification_requests (profile_id, status, reason, photo_path, ocr_state, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009611', 'cancelled', 'expired', null, 'read',
            '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23514', null, '취소는 관리자가 한 결정이 아니라 decided_by 가 비어야 한다'
);                                                                                                   -- 16
select throws_ok(
  $$insert into public.graduate_verification_requests (profile_id, photo_path, ocr_state)
    values ('00000000-0000-0000-0000-000000009611', null, 'read')$$,
  '23514', null, '대기 줄에는 사진이 있어야 한다'
);                                                                                                   -- 17
select throws_ok(
  $$insert into public.graduate_verification_requests (profile_id, photo_path, ocr_state)
    values ('00000000-0000-0000-0000-000000009611', '9611/a.jpg', 'maybe')$$,
  '23514', null, '글자 인식 결과는 read · nothing_found · failed 만 받는다'
);                                                                                                   -- 18
select throws_ok(
  $$insert into public.graduate_verification_requests (profile_id, photo_path, ocr_state, university_id)
    values ('00000000-0000-0000-0000-000000009611', '9611/a.jpg', 'read', '00000000-0000-0000-0000-000000009900')$$,
  '23514', null, '대기 줄에 학교가 정해져 있으면 check 위반이다'
);                                                                                                   -- 19

-- 4. 프로필당 대기 하나 (postgres) ---------------------------------------------------------

select lives_ok(
  $$insert into public.graduate_verification_requests (id, profile_id, photo_path, ocr_state)
    values ('00000000-0000-0000-0000-000000009f09', '00000000-0000-0000-0000-000000009609', '9609/a.jpg', 'read')$$,
  'P9 의 첫 대기 줄'
);                                                                                                   -- 20
select throws_ok(
  $$insert into public.graduate_verification_requests (profile_id, photo_path, ocr_state)
    values ('00000000-0000-0000-0000-000000009609', '9609/b.jpg', 'read')$$,
  '23505', null, '같은 프로필에 대기가 둘이면 유일 인덱스 위반이다'
);                                                                                                   -- 21
update public.graduate_verification_requests
   set status = 'rejected', reason = 'unreadable', decided_by = '00000000-0000-0000-0000-00000000ad01', decided_at = now(),
       ocr_document_number = null, ocr_school_text = null, previous_school_email = null
 where id = '00000000-0000-0000-0000-000000009f09';
select lives_ok(
  $$insert into public.graduate_verification_requests (profile_id, photo_path, ocr_state)
    values ('00000000-0000-0000-0000-000000009609', '9609/c.jpg', 'read')$$,
  '앞 줄이 반려되면 같은 프로필의 새 대기 줄을 만들 수 있다'
);                                                                                                   -- 22

-- 5. 승인된 해시는 유일, 반려끼리는 같아도 된다 (postgres) ----------------------------------

insert into public.graduate_verification_requests
  (profile_id, status, photo_path, ocr_state, university_id, document_hmac, student_hmac, decided_by, decided_at)
values ('00000000-0000-0000-0000-000000009608', 'approved', null, 'read', '00000000-0000-0000-0000-000000009900',
        '\xe801', '\xe802', '00000000-0000-0000-0000-00000000ad01', now());
select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, photo_path, ocr_state, university_id, document_hmac, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009608', 'approved', null, 'read', '00000000-0000-0000-0000-000000009900',
            '\xe801', '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23505', null, '승인된 같은 문서 해시가 둘이면 유일 인덱스 위반이다'
);                                                                                                   -- 23
select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, photo_path, ocr_state, university_id, document_hmac, student_hmac, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009608', 'approved', null, 'read', '00000000-0000-0000-0000-000000009900',
            '\xe803', '\xe802', '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23505', null, '승인된 같은 학번 해시가 둘이면 유일 인덱스 위반이다'
);                                                                                                   -- 24
select lives_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, reason, photo_path, ocr_state, document_hmac, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009608', 'rejected', 'unverifiable', null, 'read', '\xe801',
            '00000000-0000-0000-0000-00000000ad01', now()),
           ('00000000-0000-0000-0000-000000009608', 'rejected', 'unverifiable', null, 'read', '\xe801',
            '00000000-0000-0000-0000-00000000ad01', now())$$,
  '반려된 줄끼리는 같은 문서 해시여도 된다(같은 서류로 다시 낸 경우)'
);                                                                                                   -- 25
select throws_ok(
  $$insert into public.graduate_verification_requests
      (profile_id, status, reason, photo_path, ocr_state, student_hmac, decided_by, decided_at)
    values ('00000000-0000-0000-0000-000000009608', 'rejected', 'unverifiable', null, 'read', '\xe899',
            '00000000-0000-0000-0000-00000000ad01', now())$$,
  '23514', null, '학번 해시는 승인된 줄에만 있을 수 있다'
);                                                                                                   -- 26

-- 6. 함수 모양 · 권한 (postgres) ---------------------------------------------------------

select has_function('public', 'admin_review_graduate_request',
  array['uuid', 'uuid', 'text', 'text', 'uuid', 'bytea', 'bytea', 'smallint', 'inet'],
  'admin_review_graduate_request(관리자, 신청, 상태, 사유, 학교, 문서해시, 학번해시, 키버전, ip) 가 있다');   -- 27
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.admin_review_graduate_request(uuid, uuid, text, text, uuid, bytea, bytea, smallint, inet)'::regprocedure),
  'security invoker · search_path 빈 값이다(SUPABASE.md §5 — security definer 금지)'
);                                                                                                   -- 28
select ok(
  has_function_privilege('service_role',
    'public.admin_review_graduate_request(uuid, uuid, text, text, uuid, bytea, bytea, smallint, inet)', 'execute')
  and not has_function_privilege('authenticated',
    'public.admin_review_graduate_request(uuid, uuid, text, text, uuid, bytea, bytea, smallint, inet)', 'execute')
  and not has_function_privilege('anon',
    'public.admin_review_graduate_request(uuid, uuid, text, text, uuid, bytea, bytea, smallint, inet)', 'execute'),
  'service_role 만 부를 수 있다'
);                                                                                                   -- 29

-- 7. 프로필 칸 (postgres) ---------------------------------------------------------------

select throws_ok(
  $$update public.profiles set verification_method = 'naver' where id = '00000000-0000-0000-0000-000000009603'$$,
  '23514', null, 'verification_method 는 school_email · graduate_certificate 만 받는다'
);                                                                                                   -- 30
select lives_ok(
  $$update public.profiles set verification_method = 'graduate_certificate' where id = '00000000-0000-0000-0000-000000009603';
    update public.profiles set verification_method = 'school_email' where id = '00000000-0000-0000-0000-000000009603';
    update public.profiles set verification_method = null where id = '00000000-0000-0000-0000-000000009603'$$,
  'verification_method 는 두 값과 null 을 오간다'
);                                                                                                   -- 31
select throws_ok(
  $$update public.profiles set graduate_verified_at = now() where id = '00000000-0000-0000-0000-000000009603'$$,
  '23514', null, '학교 메일 인증 시각 없이 graduate_verified_at 만 채우면 check 위반이다'
);                                                                                                   -- 32

-- 8. 승인 (service_role) -------------------------------------------------------------------
-- FastAPI 와 같은 service_role 로 해야 표 권한이 모자란지 드러난다(postgres 는 무엇이든 통과한다).
set local role service_role;

select results_eq(
  $$select r->>'id', r->>'profile_id', r->>'status', r->'reason', r->>'university_id', r->>'decided_at' is not null
      from (select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01',
              '00000000-0000-0000-0000-000000009f01', 'approved', null, '00000000-0000-0000-0000-000000009900',
              '\xaa01'::bytea, '\xbb01'::bytea, 1::smallint, '203.0.113.9') as r) as call$$,
  $$values ('00000000-0000-0000-0000-000000009f01', '00000000-0000-0000-0000-000000009601', 'approved', 'null'::jsonb,
            '00000000-0000-0000-0000-000000009900', true)$$,
  '승인하면 처리 뒤 모양(id · 프로필 · 상태 · 사유 null · 학교 · 결정 시각)을 돌려준다'
);                                                                                                   -- 33
select results_eq(
  $$select university_id, school_email_verified_at is not null, graduate_verified_at is not null, verification_method
      from public.profiles where id = '00000000-0000-0000-0000-000000009601'$$,
  $$values ('00000000-0000-0000-0000-000000009900'::uuid, true, true, 'graduate_certificate')$$,
  '프로필에 학교 · 학교 메일 인증 시각 · 졸업생 인증 시각 · 방법이 채워진다 — 학교 메일 사람과 같은 상태'
);                                                                                                   -- 34
select results_eq(
  $$select status, ocr_document_number is null and ocr_school_text is null and previous_school_email is null,
           decided_by, decided_at is not null, university_id, document_hmac, student_hmac, key_version
      from public.graduate_verification_requests where id = '00000000-0000-0000-0000-000000009f01'$$,
  $$values ('approved', true, '00000000-0000-0000-0000-00000000ad01'::uuid, true,
            '00000000-0000-0000-0000-000000009900'::uuid, '\xaa01'::bytea, '\xbb01'::bytea, 1::smallint)$$,
  '신청 줄은 승인되고 평문 세 칸이 같은 update 에서 비며, 관리자가 확인한 해시로 바뀐다(옛 OCR 해시 0f01 은 덮인다)'
);                                                                                                   -- 35
select is(
  (select count(*) from public.school_email_claims where profile_id = '00000000-0000-0000-0000-000000009601'),
  0::bigint, '학교 메일 claims 는 건드리지 않는다'
);                                                                                                   -- 36
select results_eq(
  $$select action, target_type, before, after->>'status', after->>'university_id', after->>'has_student_hmac',
           after::text !~* '(aa01|bb01|0f01|AB12CD34|prev\.ac\.kr)', ip
      from public.admin_actions where target_id = '00000000-0000-0000-0000-000000009f01'$$,
  $$values ('graduate_approve', 'graduate_request', '{"status": "pending"}'::jsonb, 'approved',
            '00000000-0000-0000-0000-000000009900', 'true', true, '203.0.113.9'::inet)$$,
  '작업 기록은 한 줄 — 해시 · 번호 · 이메일이 없고 has_student_hmac 만 true/false 로 남는다'
);                                                                                                   -- 37
select is(
  (select count(*) from public.admin_actions where target_id = '00000000-0000-0000-0000-000000009f01'),
  1::bigint, '승인 한 번에 기록은 정확히 한 줄이다'
);                                                                                                   -- 38

-- 9. 반려 (service_role) ---------------------------------------------------------------------

select results_eq(
  $$select r->>'status', r->>'reason', r->'university_id'
      from (select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01',
              '00000000-0000-0000-0000-000000009f02', 'rejected', 'not_certificate', null, null, null, 1::smallint, null) as r) as call$$,
  $$values ('rejected', 'not_certificate', 'null'::jsonb)$$,
  '반려하면 상태 · 사유를 돌려준다'
);                                                                                                   -- 39
select results_eq(
  $$select status, reason, ocr_document_number is null and ocr_school_text is null and previous_school_email is null,
           university_id is null, decided_at is not null
      from public.graduate_verification_requests where id = '00000000-0000-0000-0000-000000009f02'$$,
  $$values ('rejected', 'not_certificate', true, true, true)$$,
  '반려된 줄도 평문이 비고 학교는 정해지지 않는다'
);                                                                                                   -- 40
select results_eq(
  $$select university_id is null, school_email_verified_at is null, graduate_verified_at is null
      from public.profiles where id = '00000000-0000-0000-0000-000000009602'$$,
  $$values (true, true, true)$$,
  '반려는 프로필을 바꾸지 않는다'
);                                                                                                   -- 41
select results_eq(
  $$select action, after::text from public.admin_actions where target_id = '00000000-0000-0000-0000-000000009f02'$$,
  $$values ('graduate_reject', '{"reason": "not_certificate", "status": "rejected"}')$$,
  '반려 기록에는 사유(고르는 값)와 상태만 실린다'
);                                                                                                   -- 42

-- 10. 규칙 위반 (service_role) — 모두 P3 의 R3 에 대고, R3 는 끝까지 대기여야 한다 --------------------

select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'rejected', null, null, null, null, 1::smallint, null)$$,
  '22023', null, '사유 없는 반려는 22023(서버 422)'
);                                                                                                   -- 43
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'rejected', 'whatever', null, null, null, 1::smallint, null)$$,
  '22023', null, '목록 밖 사유는 22023'
);                                                                                                   -- 44
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'approved', 'unreadable', '00000000-0000-0000-0000-000000009900', '\xcc01'::bytea, null, 1::smallint, null)$$,
  '22023', null, '승인에 사유를 붙이면 22023'
);                                                                                                   -- 45
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'approved', null, null, '\xcc01'::bytea, null, 1::smallint, null)$$,
  '22023', null, '학교 없는 승인은 22023'
);                                                                                                   -- 46
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'approved', null, '00000000-0000-0000-0000-000000009900', null, null, 1::smallint, null)$$,
  '22023', null, '문서 해시 없는 승인은 22023(D9 — 번호는 승인 때 필수)'
);                                                                                                   -- 47
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'rejected', 'unreadable', null, '\xcc01'::bytea, null, 1::smallint, null)$$,
  '22023', null, '반려에 해시를 붙이면 22023'
);                                                                                                   -- 48
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'pending', null, null, null, null, 1::smallint, null)$$,
  '22023', null, '"대기" 로 검수하는 것은 22023'
);                                                                                                   -- 49
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      null, null, null, null, null, 1::smallint, null)$$,
  '22023', null, '상태가 비면 22023'
);                                                                                                   -- 50
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'approved', null, '00000000-0000-0000-0000-0000000099ff', '\xcc01'::bytea, null, 1::smallint, null)$$,
  '23503', null, '없는 학교로 승인하면 FK 위반 23503(서버 422)'
);                                                                                                   -- 51
select results_eq(
  $$select status, university_id is null, reason is null from public.graduate_verification_requests
     where id = '00000000-0000-0000-0000-000000009f03'$$,
  $$values ('pending', true, true)$$,
  '위 실패들 뒤에도 R3 는 대기 그대로다'
);                                                                                                   -- 52

-- 11. 이미 결정됨 · 없음 · 관리자 아님 --------------------------------------------------------------

select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f01',
      'approved', null, '00000000-0000-0000-0000-000000009900', '\xaa09'::bytea, null, 1::smallint, null)$$,
  'CM409', 'already_reviewed', '승인한 건을 다시 승인하면 CM409 already_reviewed'
);                                                                                                   -- 53
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f02',
      'rejected', 'unreadable', null, null, null, 1::smallint, null)$$,
  'CM409', 'already_reviewed', '반려한 건을 다시 반려해도 CM409 already_reviewed'
);                                                                                                   -- 54
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009fee',
      'rejected', 'unreadable', null, null, null, 1::smallint, null)$$,
  'CM404', null, '없는 신청은 CM404(서버 404)'
);                                                                                                   -- 55
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-000000009603', '00000000-0000-0000-0000-000000009f03',
      'rejected', 'unreadable', null, null, null, 1::smallint, null)$$,
  '42501', 'not admin', '명단에 없는 id(신청자 본인)로는 검수하지 않는다 — admin_assert 가 42501'
);                                                                                                   -- 56
select throws_ok(
  $$select public.admin_review_graduate_request(null, '00000000-0000-0000-0000-000000009f03',
      'rejected', 'unreadable', null, null, null, 1::smallint, null)$$,
  '42501', 'not admin', '관리자 id 없이는 검수할 수 없다'
);                                                                                                   -- 57

-- 12. 이미 인증된 사람 · 탈퇴한 사람 -------------------------------------------------------------------

select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f04',
      'approved', null, '00000000-0000-0000-0000-000000009900', '\xaa04'::bytea, null, 1::smallint, null)$$,
  'CM409', 'already_verified', '학교 메일로 이미 인증된 프로필은 CM409 already_verified'
);                                                                                                   -- 58
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f05',
      'rejected', 'unreadable', null, null, null, 1::smallint, null)$$,
  'CM409', 'account_withdrawn', '탈퇴한 프로필은 CM409 account_withdrawn'
);                                                                                                   -- 59
select results_eq(
  $$select r.status, p.university_id, p.graduate_verified_at is null
      from public.graduate_verification_requests r join public.profiles p on p.id = r.profile_id
     where r.id in ('00000000-0000-0000-0000-000000009f04', '00000000-0000-0000-0000-000000009f05') order by r.id$$,
  $$values ('pending', '00000000-0000-0000-0000-000000009900'::uuid, true), ('pending', null::uuid, true)$$,
  '두 경우 모두 신청 줄은 대기 그대로고 프로필도 그대로다'
);                                                                                                   -- 60

-- 13. 해시 충돌 · 재가입 제한 ------------------------------------------------------------------------------

select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f06',
      'approved', null, '00000000-0000-0000-0000-000000009900', '\xd0c1'::bytea, null, 1::smallint, null)$$,
  'CM409', 'document_reused', '이미 승인된 문서 해시는 CM409 document_reused'
);                                                                                                   -- 61
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f06',
      'approved', null, '00000000-0000-0000-0000-000000009900', '\xd0c2'::bytea, '\x5e01'::bytea, 1::smallint, null)$$,
  'CM409', 'student_reused', '이미 승인된 학번 해시는 CM409 student_reused'
);                                                                                                   -- 62
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f06',
      'approved', null, '00000000-0000-0000-0000-000000009900', '\xd0c3'::bytea, '\x5b01'::bytea, 1::smallint, null)$$,
  'CM409', 'rejoin_blocked', '재가입 제한 중인 학번 해시는 CM409 rejoin_blocked'
);                                                                                                   -- 63
select results_eq(
  $$select r.status, r.document_hmac is null, p.school_email_verified_at is null, p.verification_method is null,
           (select count(*) from public.admin_actions where target_id = r.id::text)
      from public.graduate_verification_requests r join public.profiles p on p.id = r.profile_id
     where r.id = '00000000-0000-0000-0000-000000009f06'$$,
  $$values ('pending', true, true, true, 0::bigint)$$,
  '세 실패 뒤 신청 · 프로필이 그대로고 작업 기록도 늘지 않는다(통째로 되돌아간다)'
);                                                                                                   -- 64
select results_eq(
  $$select r->>'status' from (select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01',
      '00000000-0000-0000-0000-000000009f06', 'approved', null, '00000000-0000-0000-0000-000000009900',
      '\xd0c3'::bytea, '\x5b02'::bytea, 1::smallint, null) as r) as call$$,
  $$values ('approved')$$,
  '지난 재가입 제한(blocked_until 이 과거)은 통과한다'
);                                                                                                   -- 65

-- 14. 기록이 실패하면 조치도 없던 일 (service_role) ----------------------------------------------------------
reset role;
revoke insert on public.admin_actions from service_role;
set local role service_role;
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-000000009f03',
      'rejected', 'unreadable', null, null, null, 1::smallint, null)$$,
  '42501', null, '기록을 남기지 못하면 검수할 수 없다(기록 insert 가 막는다)'
);                                                                                                   -- 66
reset role;
grant insert on public.admin_actions to service_role;
select is(
  (select status from public.graduate_verification_requests where id = '00000000-0000-0000-0000-000000009f03'),
  'pending', '기록 실패로 반려가 되돌아가 R3 는 여전히 대기다'
);                                                                                                   -- 67

-- 15. 앱 역할은 함수를 부를 수 없다 ------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009603", "role": "authenticated"}';
select throws_ok(
  $$select public.admin_review_graduate_request('00000000-0000-0000-0000-000000009603', '00000000-0000-0000-0000-000000009f03',
      'rejected', 'unreadable', null, null, null, 1::smallint, null)$$,
  '42501', null, 'authenticated 는 부를 수 없다'
);                                                                                                   -- 68
reset role;
reset request.jwt.claims;

-- 16. list_unverified_accounts: 대기 · 최근 결정 신청이 있는 계정은 정리에서 뺀다 ---------------------------------
-- P10 = 대기 있음, P11 = 13일 전 반려, P12 = 15일 전 반려, P13 = 신청 없음. 모두 20일 전 가입한 인증 전 계정.
-- 관리자(AD)도 20일 전 가입으로 두고 여전히 빠지는지 본다.
update public.profiles set created_at = now() - interval '20 days'
 where id in ('00000000-0000-0000-0000-000000009610', '00000000-0000-0000-0000-000000009611',
              '00000000-0000-0000-0000-000000009612', '00000000-0000-0000-0000-000000009613',
              '00000000-0000-0000-0000-00000000ad01');
insert into public.graduate_verification_requests
  (profile_id, status, reason, photo_path, ocr_state, decided_by, decided_at) values
  ('00000000-0000-0000-0000-000000009611', 'rejected', 'unreadable', null, 'read',
   '00000000-0000-0000-0000-00000000ad01', now() - interval '13 days'),
  ('00000000-0000-0000-0000-000000009612', 'rejected', 'unreadable', null, 'read',
   '00000000-0000-0000-0000-00000000ad01', now() - interval '15 days');
set local role service_role;
select results_eq(
  $$select id from public.list_unverified_accounts(14, 1000)
     where id in ('00000000-0000-0000-0000-000000009610', '00000000-0000-0000-0000-000000009611',
                  '00000000-0000-0000-0000-000000009612', '00000000-0000-0000-0000-000000009613',
                  '00000000-0000-0000-0000-00000000ad01')
     order by id$$,
  $$values ('00000000-0000-0000-0000-000000009612'::uuid), ('00000000-0000-0000-0000-000000009613'::uuid)$$,
  '대기 중(P10) · 13일 전 반려(P11)는 빠지고, 15일 전 반려(P12) · 신청 없음(P13)은 나온다. 관리자는 여전히 빠진다'
);                                                                                                   -- 69
select ok(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.list_unverified_accounts(integer, integer)'::regprocedure)
  and not has_function_privilege('authenticated', 'public.list_unverified_accounts(integer, integer)', 'execute')
  and not has_function_privilege('anon', 'public.list_unverified_accounts(integer, integer)', 'execute')
  and has_function_privilege('service_role', 'public.list_unverified_accounts(integer, integer)', 'execute'),
  'list_unverified_accounts 는 교체 뒤에도 security invoker · service_role 전용이다'
);                                                                                                   -- 70
reset role;

select * from finish();
rollback;
