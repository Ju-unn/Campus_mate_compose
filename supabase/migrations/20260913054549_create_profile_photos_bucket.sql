-- 조각 0 스키마 4/4: 실사진 비공개 버킷.
-- 기준 문서: docs/ERD.md §9 · §10
--
-- 공개 버킷이면 URL 만 알아도 누구나 볼 수 있고, 크롤링당하면 사진이 통째로 유출된다.
-- 클라이언트용 storage.objects 정책은 두지 않는다.
-- 업로드는 FastAPI 가 발급한 서명 업로드 URL 로, 조회는 FastAPI 가 발급한 서명 URL 로만 한다.
-- 서명 업로드 URL 은 정책 없이 동작한다(발급에 쓰는 service key 가 RLS 를 우회한다).
insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', false)
on conflict (id) do nothing;
