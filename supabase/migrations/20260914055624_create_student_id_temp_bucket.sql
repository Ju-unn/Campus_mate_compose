-- 조각 1 스키마 3/4: 학생증 사진 임시 비공개 버킷.
-- 기준 문서: docs/ERD.md §9 · §11-19
-- 초안(2026-09-14, 미적용). 파일 크기 · 형식 제한은 사용자 결정 전이라 넣지 않았다.
--
-- 자동 대조가 애매하면 사람이 재검토해야 해서 검증이 끝날 때까지만 보관하고, 끝나면 FastAPI 가 즉시 지운다.
-- 검증 전에 탈퇴한 사람의 파일은 30일 보관 예외로 탈퇴 즉시 지운다(ERD §11-19).
-- profile-photos 와 같이 클라이언트용 storage.objects 정책은 두지 않는다.
-- 업로드는 FastAPI 가 발급한 서명 업로드 URL 로만 하고, 재검토 조회도 FastAPI 관리 기능으로만 한다.
insert into storage.buckets (id, name, public)
values ('student-id-temp', 'student-id-temp', false)
on conflict (id) do nothing;
