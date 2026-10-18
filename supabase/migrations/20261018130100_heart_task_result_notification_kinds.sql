-- 인증샷 결과 알림(사용자 결정 10-18 "가"): 관리자가 무료 하트 과제 인증샷을 승인 · 반려하면 푸시와 알림함 한 줄을 남긴다.
-- 새 알림 종류 둘 — heart_task_approved · heart_task_rejected — 을 알림함(notifications)과 밤 보관함(pending_pushes)이 받게 check 만 넓힌다.
-- 알림 종류는 열거형이 아니라 text + check 라서 한 문장(drop + add 가 한 번에 일어난다)으로 늘린다.
-- 서버가 이 마이그레이션보다 먼저 배포되면 알림함 insert 가 check 위반으로 조용히 실패하므로 반드시 서버 배포보다 먼저 적용한다.
-- SECURITY DEFINER 함수 · 권한 변경이 없어 revoke 는 해당 없음.
-- 시험: supabase/tests/notifications_test.sql, supabase/tests/pending_pushes_test.sql

alter table public.notifications
  drop constraint notifications_kind_check,
  add constraint notifications_kind_check check (kind in (
    'card_arrived', 'chat_request', 'match_made', 'friend_review', 'verification_result', 'night_digest',
    'heart_task_approved', 'heart_task_rejected'
  ));

alter table public.pending_pushes
  drop constraint pending_pushes_kind_check,
  add constraint pending_pushes_kind_check check (kind in (
    'acceptance_received', 'match_made', 'new_friend_review', 'verification_result',
    'heart_task_approved', 'heart_task_rejected'
  ));
