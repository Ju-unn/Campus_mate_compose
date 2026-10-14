-- 아바타 다시 만들기 값 10 → 20하트(2026-10-14 사용자 피드백 6). 서버 상수 AVATAR_REGEN_HEARTS 와 같이 간다.
-- **초안 — 아직 어디에도 적용하지 않았다.** 운영 적용은 사용자 원문 승인 뒤(frontend/CLAUDE.md §10.1).
-- 시험: supabase/tests/faq_test.sql 14 · 15.
--
-- FAQ 문구는 원래 대시보드에서 고친다(20260929020000_create_faq.sql 36줄). 그래도 파일로 두는 이유는 로컬 db reset 과
-- 새 환경이 같은 문구를 갖게 하려는 것이다. 바꾸는 것은 "다시 만들기 값" 숫자 두 곳뿐이고, 같은 줄의
-- "5번 연속 실패하면 … 10하트를 드려요"(보상 하트, 서버 FALLBACK_COMPENSATION_HEARTS)는 따로 정한 값이라 그대로 둔다.
-- replace 라서 대시보드에서 이미 문구를 바꿨으면(옛 구절이 없으면) 아무것도 바뀌지 않는다 — 두 번 돌려도 같다.
update public.faq
set answer = replace(answer, '그다음부터 10하트예요', '그다음부터 20하트예요'),
    updated_at = now()
where category = 'heart_payment'
  and question = '하트는 어디에 쓰나요?'
  and answer like '%그다음부터 10하트예요%';

update public.faq
set answer = replace(answer, '그다음부터는 10하트예요', '그다음부터는 20하트예요'),
    updated_at = now()
where category = 'photo_profile'
  and question = '아바타를 다시 만들 수 있나요?'
  and answer like '%그다음부터는 10하트예요%';
