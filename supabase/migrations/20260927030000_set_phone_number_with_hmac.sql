-- 조각 6 지인 차단(계획서 Task B4): 번호를 저장할 때 신원 HMAC(phone_hmac)과 키 버전을 같이 쓴다.
--
-- HMAC 은 FastAPI 가 계산해 인자로 넘긴다. DB 안에서 계산하면 신원 해시 키가 Postgres 에 들어오고,
-- 그러면 대시보드에서 번호와 해시를 맞춰 볼 수 있게 된다.
--
-- 새 인자 둘에 기본값을 두는 이유: 이 파일을 클라우드에 적용한 뒤 서버를 배포하기 전까지 운영 서버가
-- 옛 3인자로 부른다. 기본값이 없으면 그 사이 온보딩 번호 저장이 실패한다. 그 사이 저장된 행은
-- phone_hmac 이 null 로 남고 백필 스크립트가 채운다.
--
-- 인자 수가 바뀌면 create or replace 로 덮이지 않고 함수가 하나 더 생긴다. 옛 3인자가 남은 채 기본값 있는
-- 5인자가 생기면 3인자 호출이 "function is not unique" 로 깨지므로, 같은 파일에서 옛 것을 먼저 지운다
-- (적용된 파일 20260920054357 · 20260920061752 는 고치지 않는다).
drop function public.set_phone_number(uuid, text, text);

create function public.set_phone_number(
  p_profile_id uuid,
  p_phone text,
  p_key text,
  p_phone_hmac bytea default null,
  p_phone_hmac_key_version smallint default 1
)
returns void
language sql
set search_path = ''
as $$
  update public.profile_private
  set phone_number = extensions.pgp_sym_encrypt(p_phone, p_key),
      phone_hmac = p_phone_hmac,
      phone_hmac_key_version = p_phone_hmac_key_version,
      updated_at = now()
  where profile_id = p_profile_id;
$$;

comment on function public.set_phone_number(uuid, text, text, bytea, smallint) is
  '번호를 pgp_sym_encrypt 로 암호화해 저장하고, FastAPI 가 계산한 신원 HMAC 과 키 버전을 같이 쓴다. FastAPI 전용';

revoke all on function public.set_phone_number(uuid, text, text, bytea, smallint) from public, anon, authenticated;
grant execute on function public.set_phone_number(uuid, text, text, bytea, smallint) to service_role;
