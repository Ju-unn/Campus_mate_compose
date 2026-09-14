-- 조각 1 스키마 3/6: 학생증 사진 임시 비공개 버킷.
-- 기준 문서: docs/ERD.md §9 · §11-19
-- 초안, 클라우드 미적용.
--
-- 자동 대조가 애매하면 사람이 재검토해야 해서 검증이 끝날 때까지만 보관하고, 끝나면 FastAPI 가 즉시 지운다.
-- 검증 전에 탈퇴한 사람의 파일은 30일 보관 예외로 탈퇴 즉시 지운다(ERD §11-19).
-- profile-photos 와 같이 클라이언트용 storage.objects 정책은 두지 않는다.
-- 업로드는 FastAPI 가 발급한 서명 업로드 URL 로만 하고, 재검토 조회도 FastAPI 관리 기능으로만 한다.
-- 제한은 10MB · image/jpeg · image/png 다. 클라이언트가 업로드 전에 압축하고 JPEG 로 다시 인코딩한다(2026-09-14 사용자 결정).
-- 버킷 제한은 업로드 쪽이 신고한 content type 과 크기로만 막으므로(413 · 400), 파일 내용(매직 바이트)은 FastAPI 가 업로드 뒤 대조 전에 검사한다(조각 1 서버).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('student-id-temp', 'student-id-temp', false, 10485760, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;
