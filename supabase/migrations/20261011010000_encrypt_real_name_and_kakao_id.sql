-- 실명(real_name) · 카카오톡 아이디(kakao_id) 암호화 1단계(M1). 전화번호와 같은 방식(pgp_sym_encrypt)이고
-- 키도 같은 PHONE_ENCRYPTION_KEY 를 쓴다. 키는 FastAPI Secret Manager 전용, DB 에 저장하지 않는다.
--
-- 순서: M1(이 파일: 새 열 + 함수) → 서버가 옛 열과 새 열에 이중 쓰기 → backfill 로 옛 행 채움 →
-- 서버 읽기를 새 열로 전환 → M2(옛 평문 열 real_name · kakao_id 삭제, backfill 함수 삭제, 별도 PR).
-- 그래서 이 파일은 옛 열을 건드리지 않는다.
--
-- 새 열은 authenticated 에 grant 하지 않는다(20260914055617 의 "이후 조각에서 컬럼을 추가해도 authenticated
-- 에는 grant 하지 않는다"). 읽기는 service_role 이 decrypt_profile_private 로만 한다.
--
-- 함수는 전화번호 함수처럼 security invoker 다(SUPABASE.md §5). 호출자가 service_role 이라 이미 테이블
-- 권한이 있고 우회가 필요 없다. 모두 search_path 를 빈 값으로 고정한다.
--
-- 키가 null · 빈 문자열이면 예외를 낸다. pgp_sym_encrypt / pgp_sym_decrypt 는 입력이 null 이면 조용히
-- null 을 돌려주므로, 가드가 없으면 서버 설정 실수 한 번에 암호문이 null 로 덮이거나 복호화가 전부
-- null 로 보인다.

alter table public.profile_private
  add column real_name_enc bytea,
  add column kakao_id_enc bytea;

comment on column public.profile_private.real_name_enc is
  'extensions.pgp_sym_encrypt(평문, 키) 암호문. 키는 FastAPI Secret Manager 전용, DB 에 저장하지 않는다. real_name 의 후속 열(M2 에서 옛 열 삭제)';
comment on column public.profile_private.kakao_id_enc is
  'extensions.pgp_sym_encrypt(평문, 키) 암호문. 키는 FastAPI Secret Manager 전용, DB 에 저장하지 않는다. kakao_id 의 후속 열(M2 에서 옛 열 삭제)';

-- 실명 저장. profile_private 행이 아직 없을 수 있어 upsert 다(가입 직후 첫 쓰기가 실명이다).
-- 빈 문자열은 암호화하지 않고 암호문을 null 로 비운다(null 과 같은 뜻 — 암호화한 빈 값을 남기지 않는다).
create function public.set_real_name(p_profile uuid, p_real_name text, p_key text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(p_key, '') = '' then
    raise exception 'encryption key is required' using errcode = '22023';
  end if;

  insert into public.profile_private (profile_id, real_name_enc)
  values (p_profile, extensions.pgp_sym_encrypt(nullif(p_real_name, ''), p_key))
  on conflict (profile_id) do update
    set real_name_enc = excluded.real_name_enc,
        updated_at = now();
end;
$$;

comment on function public.set_real_name(uuid, text, text) is
  '실명을 pgp_sym_encrypt 로 암호화해 real_name_enc 에 쓴다. 행이 없으면 만든다(upsert). 빈 문자열은 null 로 저장한다. FastAPI 전용';

-- 카카오 아이디 저장. update 전용이라 행이 없으면 0행이 바뀐다(서버가 ensure_private_row 로 행을 먼저 보장한다).
-- 빈 문자열은 암호문 null.
create function public.set_kakao_id(p_profile uuid, p_kakao_id text, p_key text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(p_key, '') = '' then
    raise exception 'encryption key is required' using errcode = '22023';
  end if;

  update public.profile_private
  set kakao_id_enc = extensions.pgp_sym_encrypt(nullif(p_kakao_id, ''), p_key),
      updated_at = now()
  where profile_id = p_profile;
end;
$$;

comment on function public.set_kakao_id(uuid, text, text) is
  '카카오 아이디를 pgp_sym_encrypt 로 암호화해 kakao_id_enc 에 쓴다. 행이 없으면 아무것도 하지 않는다. 빈 문자열은 null 로 저장한다. FastAPI 전용';

-- 복호화 조회. 행이 없으면 0행, 행은 있고 암호문이 null 이면 값이 null 인 1행이다.
-- 전화번호 함수(decrypt_phone_number)는 스칼라라 "행 없음"과 "값 null" 이 둘 다 null 이지만, 이쪽은 둘을
-- 구분한다. 서버(PostgREST 목록 응답)는 빈 목록이면 행 없음, 첫 원소의 값이 null 이면 미입력으로 읽는다.
-- 틀린 키면 pgcrypto 가 오류(39000 Wrong key or corrupt data)를 낸다. 일반 API 응답 경로에서 남에게
-- 보이는 값에는 쓰지 않는다(본인 · 관리자 조회에서만).
create function public.decrypt_profile_private(p_profile uuid, p_key text)
returns table (real_name text, kakao_id text)
language plpgsql
stable
set search_path = ''
as $$
begin
  if coalesce(p_key, '') = '' then
    raise exception 'encryption key is required' using errcode = '22023';
  end if;

  return query
  select extensions.pgp_sym_decrypt(pp.real_name_enc, p_key),
         extensions.pgp_sym_decrypt(pp.kakao_id_enc, p_key)
  from public.profile_private pp
  where pp.profile_id = p_profile;
end;
$$;

comment on function public.decrypt_profile_private(uuid, text) is
  '실명 · 카카오 아이디 암호문을 복호화해 (real_name, kakao_id) 로 돌려준다. 행이 없으면 0행, 암호문이 null 이면 그 값만 null. 틀린 키는 오류. FastAPI 전용';

-- 임시 함수(M2 에서 삭제). 옛 평문 열 값을 암호문 열로 옮긴다. 암호문이 이미 있는 열은 덮지 않아
-- 이중 쓰기로 먼저 들어간 새 값을 지키고, 몇 번을 돌려도 같은 결과다. 열마다 따로 판단한다.
-- 평문이 null · 빈 문자열이면 암호문도 null 로 둔다. 서버 백필 스크립트가 행마다(또는 profile 목록을 돌며) 부른다.
create function public.backfill_profile_private_encryption(p_profile uuid, p_key text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(p_key, '') = '' then
    raise exception 'encryption key is required' using errcode = '22023';
  end if;

  update public.profile_private
  set real_name_enc = extensions.pgp_sym_encrypt(real_name, p_key)
  where profile_id = p_profile
    and real_name_enc is null
    and nullif(real_name, '') is not null;

  update public.profile_private
  set kakao_id_enc = extensions.pgp_sym_encrypt(kakao_id, p_key)
  where profile_id = p_profile
    and kakao_id_enc is null
    and nullif(kakao_id, '') is not null;
end;
$$;

comment on function public.backfill_profile_private_encryption(uuid, text) is
  '임시(M2 에서 삭제). 평문 real_name · kakao_id 를 암호문 열로 옮긴다. 암호문이 이미 있는 열은 덮지 않는다. FastAPI 백필 전용';

revoke all on function public.set_real_name(uuid, text, text) from public, anon, authenticated;
revoke all on function public.set_kakao_id(uuid, text, text) from public, anon, authenticated;
revoke all on function public.decrypt_profile_private(uuid, text) from public, anon, authenticated;
revoke all on function public.backfill_profile_private_encryption(uuid, text) from public, anon, authenticated;

grant execute on function public.set_real_name(uuid, text, text) to service_role;
grant execute on function public.set_kakao_id(uuid, text, text) to service_role;
grant execute on function public.decrypt_profile_private(uuid, text) to service_role;
grant execute on function public.backfill_profile_private_encryption(uuid, text) to service_role;

-- 적용 뒤 확인할 것(supabase 세션 몫, 이 파일 자체는 실행하지 않는다):
-- 1. pg_stat_statements · 로그에 pgp_sym_encrypt / pgp_sym_decrypt 호출의 key 인자가 `$1` 같은 자리표시자로만
--    보이는지 확인한다(전화번호 함수 20260920043638 의 확인 항목과 같은 위험). PostgREST 는 RPC 인자를 JSON 바디로
--    받아 함수에 바인딩하므로 보통 문제없지만, 로그 설정이 인자 값을 남기는지(log_statement, auto_explain) 본다.
-- 2. FastAPI 는 키를 RPC 의 JSON 바디 인자로만 넘기고 URL 쿼리스트링에는 넣지 않는다.
-- 3. 대시보드에서 손으로 복호화가 필요하면 `select * from public.decrypt_profile_private('<profile_id>', '<키>');`
--    키를 SQL 창에 붙여넣는 행위가 감사 대상이므로 실행 전후로 사유를 운영 기록에 남긴다.
