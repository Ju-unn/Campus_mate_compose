-- FAQ 답변의 고객 문의 메일을 s26404538@gmail.com 에서 appmailerl4538@gmail.com 으로 바꾼다(2026-10-20 사용자 결정, 앱 상수
-- frontend/lib/common/support_email.dart 와 같은 값). 앞선 20261014130000_faq_support_email.sql 과 같은 방식이다.
-- **초안 — 아직 어디에도 적용하지 않았다.** 운영 적용은 사용자 원문 승인 뒤(frontend/CLAUDE.md §10.1).
-- 시험: supabase/tests/faq_test.sql 16 · 17.
--
-- 문항을 집지 않고 옛 주소가 든 답변을 모두 고친다(safety "이용이 제한됐다고 나와요." 외에 대시보드에서 넣은 문구까지).
-- replace 라서 옛 주소가 없으면(이미 새 주소면) 아무것도 바뀌지 않는다 — 두 번 돌려도 같다.
update public.faq
set answer = replace(answer, 's26404538@gmail.com', 'appmailerl4538@gmail.com'),
    updated_at = now()
where answer like '%s26404538@gmail.com%';
