-- O/X 글 댓글(2026-11-10) 1/3: 신고 대상 종류에 'poll_comment' 를 더한다.
-- enum 값은 추가한 같은 트랜잭션에서 쓸 수 없어 이 한 줄만 따로 둔다(쓰는 쪽은 20261111000200 의 admin_set_content_status).
-- 서버(safety POST /reports · admin)가 이 값을 쓰기 전에 적용한다 — 서버 배포보다 먼저.
alter type public.report_target add value if not exists 'poll_comment';
