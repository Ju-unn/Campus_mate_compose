-- FAQ 답변의 고객 문의 메일을 옛 임시 주소에서 새 주소로 바꾼다(2026-10-14 사용자 결정, 앱 상수
-- frontend/lib/common/support_email.dart 와 같은 값).
-- **초안 — 아직 어디에도 적용하지 않았다.** 운영 적용은 사용자 원문 승인 뒤(frontend/CLAUDE.md §10.1).
-- 시험: supabase/tests/faq_test.sql 16 · 17.
--
-- 첫 문구(20260929020000_create_faq.sql) 중 옛 주소가 든 답변은 safety 460 "이용이 제한됐다고 나와요." 하나다.
-- 문구는 대시보드에서도 고치므로(create_faq 36줄) 다른 답변에 옛 주소를 넣었을 수도 있어 문항을 집지 않고 옛 주소가 든 답변을 모두 고친다.
-- replace 라서 옛 주소가 없으면 아무것도 바뀌지 않는다 — 두 번 돌려도 같다.
update public.faq
set answer = replace(answer, 'appmailerl4538@gmail.com', 's26404538@gmail.com'),
    updated_at = now()
where answer like '%appmailerl4538@gmail.com%';
