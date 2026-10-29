-- 무료 카드는 한 사람에게 하루(서울 날짜)에 한 장(2026-10-29 사용자 결정 "완전히 막아야지").
--
-- 가입 뒤 처음 오늘 탭을 열면 서버가 지급일을 기다리지 않고 무료 카드 한 장을 준다(backend cards/issuing.py
-- issue_first_card). 지급 배치는 원래 "오늘(자정 KST 뒤) 이미 받은 사람은 건너뜀" 규칙이 있는데, 배치가 대상 목록을 읽은 뒤
-- 앱이 첫 카드를 주거나 첫 카드 요청이 동시에 두 번 오면 서버 확인만으로는 틈이 남는다. 그 같은 규칙을 DB 가 지킨다 —
-- 두 번째 insert 는 23505 이고, 서버는 그것을 "이미 받았다"로 읽고 넘어간다(cards/repository.py DailyCardConflict).
--
-- 만료 시각(expires_at)으로 묶지 않는 이유: 주 중에 사다리가 오르면(주 1회 → 주 2회) 월요일 카드와 목요일 카드의 만료가
-- 같은 다음 월요일이 되어, 월요일 카드를 이미 정한 사람의 목요일 정상 카드가 막힌다(검토 권고 10-29).
--
-- 산 카드(purchased)는 이 규칙 밖이다. 날짜는 서울 기준이다(배치 · 관리자 통계와 같다). timestamptz 를 고정 시간대로
-- 바꾸는 식이라 immutable 이다.
-- 운영 확인(2026-10-29, 읽기 SQL): 같은 사람 · 같은 서울 날짜 무료 카드 2장 이상 0건이라 만들 때 실패하지 않는다.
create unique index daily_cards_one_free_per_day
  on public.daily_cards (owner_id, ((issued_at at time zone 'Asia/Seoul')::date))
  where source = 'daily';

comment on index public.daily_cards_one_free_per_day is
  '무료 카드는 한 사람에게 하루(서울 날짜)에 한 장 — 첫 카드 동시 요청 · 배치 겹침 방지(2026-10-29)';
