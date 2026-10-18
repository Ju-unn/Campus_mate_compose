-- 기본 아바타(5회 실패 보상) 행은 한 사람에 한 줄 — 보상 하트 10 이 두 번 나가는 경쟁을 DB 가 막는다(10-18 보안 점검).
-- 워커의 5번째 실패(profile_onboarding/tasks_router.py)와 POST 의 5회 보상(profile_onboarding/router.py)이 겹치면 두 길 모두
-- 기본 아바타 행을 넣고 하트를 줬다. 이제 두 번째 insert 는 23505 로 튕기고 서버(avatars.apply_fallback_avatar)는 하트를 건너뛴다.
--
-- 적용 전 확인(대장): 이미 한 사람에게 기본 아바타 행이 둘 이상이면 인덱스 생성이 실패한다. 이 마이그레이션은 기존 데이터를
-- 고치지 않는다 — 운영에서 아래가 0행인지 먼저 본다(0행이 아니면 적용하지 말고 그 profile_id 를 사람이 정리).
--   select profile_id, count(*) from public.profile_avatars where is_fallback group by profile_id having count(*) > 1;
--
-- 되돌리기: drop index if exists public.profile_avatars_one_fallback;
create unique index profile_avatars_one_fallback
  on public.profile_avatars (profile_id)
  where is_fallback;
