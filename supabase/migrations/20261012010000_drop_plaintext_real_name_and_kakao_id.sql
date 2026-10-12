-- 실명(real_name) · 카카오톡 아이디(kakao_id) 암호화 2단계(M2): 옛 평문 열 2개와 임시 백필 함수를 지운다.
-- M1(20261011010000) 의 암호문 열 real_name_enc · kakao_id_enc 가 유일한 저장소가 된다.
--
-- ■ 되돌릴 수 없다. 지운 평문은 백업 복원 말고는 되살릴 길이 없다(롤백 마이그레이션 없음).
--
-- ■ 적용 선행조건 — 넷 다 확인한 뒤에만 적용한다.
--   1. 평문 열을 쓰지 않는 서버가 운영에 배포됐다(평문 쓰기 · 평문 폴백 읽기 제거판). 옛 서버가 하나라도 돌고 있으면
--      실명 · 카톡 저장과 읽기가 42703(열 없음)으로 실패한다.
--   2. E2E 하네스가 통과했다(하네스는 암호화 RPC 로만 읽고 쓴다, e2e/fake_private.py).
--   3. 백필이 끝났다 — 1 의 새 서버를 배포하기 직전에 scripts.backfill_encrypt_profile_private 를 다시 돌려
--      종료 코드 0(mismatch 0)을 봤다(backend/DEPLOY.md). Cloud Run 과 같은 PHONE_ENCRYPTION_KEY 버전으로 돌린다 —
--      다르면 검사가 오류로 멈추거나, mismatch 0 이어도 백필이 채운 암호문을 서버가 못 읽는다.
--      새 서버 배포 뒤에는 다시 돌리지 않는다. 새 서버는 평문 열을 고치지 않아서, 사용자가 바꾼 값은 거짓 불일치
--      (종료 코드 1)로 보이고, 빈 값으로 지운 카톡 아이디는 run() 이 남은 평문으로 다시 채워 되살린다.
--      아래 안전장치가 "평문은 있는데 암호문이 빈 행" 을 한 번 더 세서, 하나라도 있으면 아무것도 지우지 않고 멈춘다.
--      새 서버 배포 뒤 여기서 멈췄다면 백필로 메우지 말고 보고한다(빈 값으로 지운 카톡 아이디 행일 수 있다).
--      (복호화 값 = 평문 인지는 키가 DB 밖에 있어 여기서 못 본다 — 그건 3 의 mismatch 0 이 맡는다.)
--   4. 적용 직전 백업(PITR 또는 대시보드 백업)이 있는지 확인했다.
--
-- ■ 적용 뒤 정리: drop column 은 평문을 디스크에서 바로 지우지 않는다(기존 행 안에 남는다). 적용 뒤 따로
--   `vacuum full public.profile_private;` 를 돌려 표를 다시 쓴다(트랜잭션 안에서는 못 돌아 이 파일에 넣지 않았다).
--   그래도 적용 전 백업 · PITR · WAL 에는 평문이 남아 보관 기간이 지나야 사라진다.
--
-- 잠금 · 안전장치 · 삭제는 do 블록 하나(= 한 문장 = 한 트랜잭션)에 둔다. 실행기가 파일을 트랜잭션으로 감싸든 문장마다
-- 따로 돌리든(로컬 CLI 는 문장마다 따로 돌린다 — 블록 밖 `lock table` 은 25P01 로 거부됐다) 검사와 삭제가 쪼개지지 않는다.
-- 표를 먼저 잠가 검사와 삭제 사이에 평문만 든 행이 끼어들지 못하게 한다. 잠금은 오래 기다리지 않는다(lock_timeout 5초) —
-- 긴 트랜잭션 뒤에 줄 서서 표 전체 읽기를 막지 않게 하고, 못 잡으면 아무것도 안 바뀐 채 실패하니 다시 적용하면 된다.
--
-- 이 열을 참조하는 다른 DB 객체: 뷰 · 트리거 · 인덱스 · 정책은 없다(정책은 profile_id 만 본다). authenticated 의
-- 컬럼 grant `select (real_name)` 와 열 comment 는 열과 함께 사라진다. 남은 함수 set_real_name · set_kakao_id ·
-- decrypt_profile_private 는 암호문 열만 쓴다. drop column 은 cascade 없이 둔다 — 모르는 의존이 있으면 조용히 같이
-- 지우지 않고 오류로 멈춘다.

do $$
declare
  v_unfilled bigint;
begin
  perform set_config('lock_timeout', '5s', true);
  lock table public.profile_private in access exclusive mode;

  -- 빈 문자열 평문은 백필도 암호화하지 않았다(M1 backfill — null 과 같은 뜻) — 잃을 값이 아니라 세지 않는다.
  select count(*) into v_unfilled
  from public.profile_private
  where (nullif(real_name, '') is not null and real_name_enc is null)
     or (nullif(kakao_id, '') is not null and kakao_id_enc is null);

  -- 건수만 싣는다(profile_id · 값은 로그에 남기지 않는다).
  if v_unfilled > 0 then
    raise exception 'profile_private 에 암호문 없이 평문만 있는 행이 %개 있다 — 백필을 먼저 끝내야 한다', v_unfilled;
  end if;

  alter table public.profile_private
    drop column real_name,
    drop column kakao_id;

  -- 평문 열이 없어 더는 할 일이 없다(M1 의 임시 함수). 서버 코드는 부르지 않는다 — 일회용 스크립트만 불렀다.
  drop function public.backfill_profile_private_encryption(uuid, text);
end;
$$;

comment on table public.profile_private is
  '민감 정보. 앱(authenticated)은 본인 행의 profile_id 만 읽고, 값은 FastAPI(service_role)만 다룬다';
comment on column public.profile_private.real_name_enc is
  '실명 암호문 extensions.pgp_sym_encrypt(평문, 키). 키는 FastAPI Secret Manager 전용, DB 에 저장하지 않는다. 쓰기 set_real_name, 읽기 decrypt_profile_private';
comment on column public.profile_private.kakao_id_enc is
  '카카오톡 아이디 암호문 extensions.pgp_sym_encrypt(평문, 키). 키는 FastAPI Secret Manager 전용, DB 에 저장하지 않는다. 쓰기 set_kakao_id, 읽기 decrypt_profile_private';
