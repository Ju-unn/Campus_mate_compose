-- 조각 2: 본인 전화번호(04-1, 필수) · 카카오톡 아이디(04-1b, 필수). 둘 다 profile_private 로 분리한다
-- (민감 값, ERD §3). 전화번호는 원본을 그대로 저장하되 컬럼 암호화(at-rest, 설계 §7.6b)한다.
-- 기준 문서: docs/ERD.md §3, 설계 §7.6b

create extension if not exists pgcrypto with schema extensions;

alter table public.profile_private
  add column phone_number bytea,
  add column kakao_id text;

comment on column public.profile_private.phone_number is
  'extensions.pgp_sym_encrypt(평문, 키) 암호문. 키는 FastAPI Secret Manager 전용, DB 에 저장하지 않는다';

-- 관리자 조회 전용 복호화 함수. security definer 를 안 쓴다(SUPABASE.md §5) — 호출자가 service_role 이므로
-- 이미 profile_private select 권한이 있고, 별도 권한 우회가 필요 없다. 일반 API 응답 경로에서는 절대 호출하지
-- 않는다(계획서 Part B Task B-encryption 참고) — 이 함수를 부르는 코드는 관리자 조회 엔드포인트 하나뿐이어야
-- 한다.
create or replace function public.decrypt_phone_number(p_profile_id uuid, p_key text)
returns text
language sql
stable
as $$
  select extensions.pgp_sym_decrypt(phone_number, p_key)
  from public.profile_private
  where profile_id = p_profile_id;
$$;

revoke all on function public.decrypt_phone_number(uuid, text) from public, anon, authenticated;
grant execute on function public.decrypt_phone_number(uuid, text) to service_role;

-- 적용 뒤 확인할 것(supabase 세션 몫, 이 파일 자체는 실행하지 않는다):
-- 1. Supabase 대시보드 Database > Query Performance(pg_stat_statements) 에서 이 함수·
--    pgp_sym_encrypt 호출이 찍힌 행을 열어 key 인자가 `$1`(파라미터 자리표시자)로만 보이는지 확인한다
--    (pg_stat_statements 는 기본적으로 리터럴 값을 정규화해 지우지만, PostgREST 가 파라미터 바인딩 없이
--    문자열을 그대로 SQL 에 이어붙이면 키가 그대로 남을 수 있어 확인이 필요하다).
-- 2. FastAPI 쪽은 키를 PostgREST RPC 호출의 JSON 바디 인자로만 넘기고, URL 쿼리스트링에는 절대 넣지 않는다
--    (URL 은 웹서버 접근 로그에 그대로 남는다) — Part B Task B-encryption 코드 리뷰에서 확인.
-- 3. Supabase 대시보드에서 손으로 복호화가 필요하면(신고·수사 협조): SQL Editor 에서
--    `select public.decrypt_phone_number('<profile_id>', '<Secret Manager 에서 복사한 키>');` 를 실행한다.
--    키를 대시보드 SQL 창에 붙여넣는 행위 자체가 감사 대상이므로, 실행 전후로 사유를 운영 기록에 남긴다.
