-- 거절 되돌리기(1.0.7 할 일 #20) — 원래 거절 시각을 남길 칸 두 개.
-- (a) 내 카드 거절을 7일 안에 다시 대화 신청: card_decisions 의 decision 이 reject → accept, decided_at 은 다시 신청 시각.
-- (b) 받은 신청에 한 거절을 7일 안에 되돌려 바로 매칭: acceptance_responses 의 decision 이 reject → accept, decided_at 은 되돌린 시각.
-- 두 경우 모두 원래 거절 시각을 rejected_at 에 옮겨 두어 관리자가 "다시 신청 · 되돌림" 건수를 셀 수 있게 한다.
-- 쓰기는 FastAPI(service_role)의 조건부 PATCH 하나뿐이다(backend/app/cards/repository.py _undo_rejection).
--
-- RLS · grant 는 바꾸지 않는다: 두 표 모두 정책 없음 + anon · authenticated 권한 없음(20260920160537) 그대로라 앱이 직접 읽지 못한다.
-- 상대에게 거절 흔적이 가지 않게 서버도 상대 쪽 읽기의 select 에 이 칸을 넣지 않는다.
-- 기본값 없는 null 칸 추가라 표를 다시 쓰지 않는다(잠금은 순간). 기존 행은 모두 null = "되돌린 적 없음".
-- 서버보다 먼저 적용한다 — 칸이 없는 DB 에 새 서버의 PATCH 가 가면 실패한다(옛 서버는 이 칸을 모른다, 뒤 호환).
-- 시험: supabase/tests/rejected_at_test.sql.

alter table public.card_decisions add column rejected_at timestamptz;

comment on column public.card_decisions.rejected_at is
  '다시 신청한 카드의 원래 거절 시각(1.0.7 #20). null 이면 다시 신청이 아니다. 관리자 통계용 — 상대 쪽 응답에 싣지 않는다';

alter table public.acceptance_responses add column rejected_at timestamptz;

comment on column public.acceptance_responses.rejected_at is
  '거절을 되돌려 수락(바로 매칭)한 받은 신청의 원래 거절 시각(1.0.7 #20). null 이면 되돌림이 아니다. 관리자 통계용 — 카드 주인 쪽 응답에 싣지 않는다';
