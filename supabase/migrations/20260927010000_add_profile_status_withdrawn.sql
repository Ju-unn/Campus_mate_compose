-- 조각 6: 탈퇴 상태 값 추가. enum 값 추가는 같은 트랜잭션 안에서 바로 쓸 수 없어(Postgres 제약)
-- 이 값을 쓰는 다음 마이그레이션(20260927010100)과 파일을 나눈다(ERD §4).
alter type public.profile_status add value 'withdrawn';
