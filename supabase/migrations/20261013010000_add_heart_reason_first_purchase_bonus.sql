-- 인앱결제 첫 구매 보너스(2026-10-13 사용자 확정, 하트_상품_첫구매보너스_안 §4)의 원장 사유.
-- enum 값 추가는 같은 트랜잭션에서 바로 쓸 수 없어(Postgres 제약) 쓰는 마이그레이션(20261013010100_billing_purchases)과
-- 파일을 나눈다(20260927010000 과 같은 이유). 구매 지급은 기존 'purchase', 환불 회수는 기존 'refund' 를 쓴다.
alter type public.heart_reason add value 'first_purchase_bonus';
