-- 조각 2 리뷰(2026-09-20 필수 4): AI 자기소개 초안 본문을 저장한다.
-- 지금까지는 생성 시각(bio_draft_generated_at)만 남겨서, 06-2b 를 다시 열면 "이미 만들었다"는
-- 것만 알 뿐 만든 글은 어디에도 없었다 — 사용자는 빈 칸을 보게 된다.
-- 본문을 함께 남기면 재호출 때 OpenAI 를 다시 부르지 않고 저장본을 그대로 돌려줄 수 있다.
-- 기준 문서: docs/ERD.md §3, 설계 §13-71(초안 생성은 최초 1회)

alter table public.profiles
  add column bio_draft text;

comment on column public.profiles.bio_draft is 'AI 자기소개 초안 본문, 재조회용(1회 제한은 bio_draft_generated_at 이 센다)';
