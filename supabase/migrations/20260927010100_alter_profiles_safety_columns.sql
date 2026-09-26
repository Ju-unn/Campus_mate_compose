-- 조각 6: 탈퇴 · 자동 가림 컬럼. profiles 는 authenticated 에 테이블 단위 select 가 있고(조각 0),
-- RLS 가 본인 행으로 좁힌다 — 본인은 자기 행의 이 두 칸도 읽는다(본인 행뿐이고 신고자는 드러나지 않는다).
alter table public.profiles
  add column withdrawn_at timestamptz,
  -- 결정 3: 서로 다른 세 명이 신고하면 서버가 찍는다. 카드·매칭 후보에서 빠지지만
  -- 진행 중인 채팅은 그대로다. 사람이 검토해 정지하거나 이 값을 지운다(해제).
  add column auto_hidden_at timestamptz;

-- 인덱스는 이번에 깔지 않는다(계획서 C1). 후보 쿼리 조건 중 gender <> 는 btree 로 잡히지 않고,
-- university_id 는 조인 조건이라 상수가 아니며, withdrawn_at is null 은 쿼리 where 절에 없어
-- predicate 가 맞지 않는다 — 플래너가 못 쓸 인덱스다. 백로그로 넘긴다.
alter table public.profiles
  add constraint profiles_withdrawn_pair
  check ((status = 'withdrawn') = (withdrawn_at is not null));
