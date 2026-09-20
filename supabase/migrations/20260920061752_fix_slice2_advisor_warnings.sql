-- Supabase 보안 advisor WARN 2건 처리(2026-09-20, 조각2 클라우드 적용 뒤 리뷰).
-- 1) 함수 3개(decrypt_phone_number·set_phone_number·grant_hearts)가 search_path 를 고정하지
--    않아 advisor 가 경고했다. 세 함수 본문은 이미 public./extensions. 로 전부 스키마 수식돼 있고
--    now() 등 내장 함수는 search_path 설정과 무관하게 항상 검색되는 pg_catalog 소속이라, 본문을
--    바꿀 필요 없이 search_path 만 빈 문자열로 고정하면 된다(Supabase 권장 조치).
-- 2) profile_avatars.source_photo_id 외래키에 인덱스가 없어 advisor 가 경고했다.

alter function public.decrypt_phone_number(uuid, text) set search_path = '';
alter function public.set_phone_number(uuid, text, text) set search_path = '';
alter function public.grant_hearts(uuid, integer, public.heart_reason, uuid) set search_path = '';

create index profile_avatars_source_photo_id_index on public.profile_avatars (source_photo_id);
