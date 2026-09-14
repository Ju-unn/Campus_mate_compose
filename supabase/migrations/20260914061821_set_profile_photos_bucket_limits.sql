-- 조각 1 스키마 6/6: 조각 0 버킷 profile-photos 에 파일 크기 · 형식 제한 추가.
-- 기준 문서: docs/ERD.md §9
-- 초안, 클라우드 미적용.
--
-- 조각 0 버킷에 제한을 추가한다(2026-09-14 사용자 결정, #6).
-- 조각 0 파일(20260913054549)은 이미 클라우드에 올라가 있어 고치지 않고 여기서 update 한다.
-- student-id-temp 와 같이 10MB · image/jpeg · image/png 다. 클라이언트가 업로드 전에 압축하고 JPEG 로 다시 인코딩한다.
-- 버킷 제한은 업로드 쪽이 신고한 content type 과 크기로만 막으므로(413 · 400), 파일 내용(매직 바이트)은 FastAPI 가 검사한다.
update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array['image/jpeg', 'image/png']
 where id = 'profile-photos';
