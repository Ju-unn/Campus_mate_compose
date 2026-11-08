-- FAQ 두 답변을 졸업증명서 인증(2026-10-19 운영 스위치 켬, backend/DEPLOY.md §4-14)에 맞춘다(2026-11-08 사용자 「1 db적용해줘」).
-- 앞선 20261017130000_faq_student_id_removal.sql 이 "졸업증명서는 받지 않아요" 로 썼는데, 지금은 학교 메일이 없는 졸업생이
-- 졸업증명서로 인증한다(앱 인증 방법 화면 graduateMethodCertificateBody 와 같은 뜻).
-- 시험: supabase/tests/faq_test.sql 20 · 21.
--
-- replace 라서 옛 문장이 없으면(이미 고쳤으면) 아무것도 바뀌지 않는다 — 두 번 돌려도 같다.
update public.faq
set answer = replace(answer,
                     '졸업생도 학교 메일을 쓸 수 있으면 가입할 수 있어요.',
                     '졸업생도 가입할 수 있어요. 학교 메일이 있으면 메일로, 없으면 졸업증명서로 인증해요.'),
    updated_at = now()
where category = 'account'
  and answer like '%졸업생도 학교 메일을 쓸 수 있으면 가입할 수 있어요.%';

update public.faq
set answer = replace(answer,
                     '학생증이나 졸업증명서는 받지 않아요.',
                     '졸업해서 학교 메일이 없으면 졸업증명서로 인증할 수 있어요. 확인에 시간이 걸릴 수 있어요. 학생증은 받지 않아요.'),
    updated_at = now()
where category = 'account'
  and answer like '%학생증이나 졸업증명서는 받지 않아요.%';
