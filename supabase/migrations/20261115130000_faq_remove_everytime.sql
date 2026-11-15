-- FAQ 무료 하트 두 답변에서 에브리타임 홍보를 뺀다(2026-11-15 사용자 결정 「무료로 모으기 "에브리타임 홍보" 지우자
-- -> 에타 올리면 서비스 홍보물 정지 대상」, 적용 범위 「서버 · DB 도 같이」). 서버 GET /heart-tasks 목록과 제출도 함께 뺐다.
-- 데이터만 고친다 — enum heart_task · 한도 함수 · heart_task_submissions 는 이미 낸 제출을 위해 그대로 둔다.
-- 시험: supabase/tests/faq_test.sql 18 · 24 · 25.
--
-- 1) heart_payment 120: 에브리타임 구절만 뺀다. 운영 글("커뮤니티 투표는 하루 첫 투표에 …")과 저장소 시드 글
--    ("커뮤니티 투표에 참여하면 하루 한 번 …")이 다르지만 빼는 구절은 둘 다 같다. replace 라 두 번 돌려도 같다.
update public.faq
set answer = replace(answer, '에브리타임 홍보 글 인증은 월 1회 40하트, ', ''),
    updated_at = now()
where category = 'heart_payment'
  and question = '하트를 무료로 얻는 방법이 있나요?'
  and answer like '%에브리타임 홍보 글 인증은 월 1회 40하트, %';

-- 2) heart_payment 130: 운영 글과 저장소 시드 글이 달라(운영은 대시보드에서 고친 글) 구절 치환 대신 답 전체를 새 글로 둔다.
--    단톡방 기준은 앱 18b 캡션과 같은 "3명 이상이 있는 단톡방"(2026-10-16 확정 — 옛 FAQ 의 "5명 이상 · 학교 단톡방"은 어긋나 있었다).
--    에브리타임이 든 글만 바꾸므로 두 번 돌려도 같다.
update public.faq
set answer = '단톡방 공유 화면을 캡처해 올리면 운영팀이 확인한 뒤 하트를 드려요. 확인은 보통 영업일 1~2일 걸려요. '
             || '3명 이상이 있는 단톡방에 공유한 글과 단톡방 인원 수가 보이게 찍어 주세요. '
             || '기준에 맞지 않거나 이미 쓴 캡처면 반려되는데, 사유를 확인하고 다시 찍어 올리면 돼요.',
    updated_at = now()
where category = 'heart_payment'
  and question = '무료 하트 인증은 어떻게 하고, 반려되면 어떻게 하나요?'
  and answer like '%에브리타임%';
