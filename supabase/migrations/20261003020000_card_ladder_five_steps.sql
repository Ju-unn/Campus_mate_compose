-- 결정 12(2026-10-01 사용자 표, 결함수정 B9): 지급 사다리를 3칸에서 5칸으로.
-- 남녀 중 적은 쪽 활성 인원이 50 미만 주 1회(월) · 50+ 주 2회(월 · 목) · 500+ 주 3회(월 · 수 · 금)
-- · 1,000+ 주 4회(월 · 수 · 금 · 일) · 2,000+ 매일. 요일 목록은 backend/app/cards/ladder.py 에 있고
-- 이 테이블은 기준 인원만 든다. 월요일은 모든 칸에 있다(universities_card_opens_monday_0700 과 맞물림).
alter table public.region_group_settings
  add column ladder_twice_per_week_min integer not null default 50,
  add column ladder_four_per_week_min integer not null default 1000,
  alter column ladder_three_per_week_min set default 500,
  alter column ladder_daily_min set default 2000,
  -- 맨 아래 칸이 주 1회(월)가 됐다. 요일은 배치가 매일 사다리로 덮는 결과값이라 기존 행은 두고 기본만 바꾼다.
  alter column issue_weekdays set default array[1]::smallint[];

-- 기존 행(지금은 seoul 하나)도 새 표로 — 모든 지역그룹이 같은 표다(사용자 10-01).
update public.region_group_settings
set ladder_three_per_week_min = 500, ladder_daily_min = 2000, updated_at = now();

-- 칸이 넷이라 순서 check 를 다시 건다. 같은 값은 허용한다(E2E 그룹은 전부 0, 결정 15).
alter table public.region_group_settings
  drop constraint region_group_settings_ladder_order,
  add constraint region_group_settings_ladder_order check (
    ladder_twice_per_week_min <= ladder_three_per_week_min
    and ladder_three_per_week_min <= ladder_four_per_week_min
    and ladder_four_per_week_min <= ladder_daily_min
  );
