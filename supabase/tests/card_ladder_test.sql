-- 지급 사다리 5칸(결정 12, 마이그레이션 20261003020000): 기준 칸 넷 · 기본값 · 기존 행 값 · 순서 check.
-- 요일 판정은 backend/tests/cards/test_ladder.py 가 본다. 여기는 테이블이 그 재료를 바르게 드는지만 본다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

-- 1. 새 칸 ------------------------------------------------------------------
select has_column('public', 'region_group_settings', 'ladder_twice_per_week_min', '주 2회 기준 칸이 있다');
select has_column('public', 'region_group_settings', 'ladder_four_per_week_min', '주 4회 기준 칸이 있다');

-- 2. 새 지역그룹은 사용자 표대로 시작한다 ----------------------------------------
insert into public.region_group_settings (region_group) values ('ladder_test');

select row_eq(
  $$select issue_weekdays, ladder_twice_per_week_min, ladder_three_per_week_min,
           ladder_four_per_week_min, ladder_daily_min
    from public.region_group_settings where region_group = 'ladder_test'$$,
  row(array[1]::smallint[], 50, 500, 1000, 2000),
  '새 행 기본값: 주 1회(월) · 50 · 500 · 1000 · 2000'
);

-- 3. 기존 행도 새 표로 바뀌었다 ---------------------------------------------------
select row_eq(
  $$select ladder_twice_per_week_min, ladder_three_per_week_min,
           ladder_four_per_week_min, ladder_daily_min
    from public.region_group_settings where region_group = 'seoul'$$,
  row(50, 500, 1000, 2000),
  'seoul 행: 200 · 500 이던 기준이 50 · 500 · 1000 · 2000 으로'
);

-- 4. 순서 check -----------------------------------------------------------------
select throws_ok(
  $$update public.region_group_settings set ladder_twice_per_week_min = 501
    where region_group = 'ladder_test'$$,
  '23514', null,
  '주 2회 기준이 주 3회 기준보다 크면 막힌다'
);

select throws_ok(
  $$update public.region_group_settings set ladder_four_per_week_min = 2001
    where region_group = 'ladder_test'$$,
  '23514', null,
  '주 4회 기준이 매일 기준보다 크면 막힌다'
);

select lives_ok(
  $$insert into public.region_group_settings (region_group, ladder_twice_per_week_min,
      ladder_three_per_week_min, ladder_four_per_week_min, ladder_daily_min)
    values ('ladder_zero', 0, 0, 0, 0)$$,
  '기준을 전부 0 으로 둘 수 있다(E2E 그룹 = 매일 지급)'
);

select * from finish();
rollback;
