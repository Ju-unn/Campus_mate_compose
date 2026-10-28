-- 글 정리 칸(2026-10-28 사용자 결정 "0번"): 자기소개 · "이런 사람이 좋아요" 원문을 GPT 가 정해진 칸으로 나눈 결과.
-- 모양: {"like_places": [], "dislike_places": [], "talk": null, "values": []} (backend/app/matching/facets.py).
-- FastAPI 가 글을 저장할 때 임베딩과 함께 채우고, scoring.facet_score 가 글 점수 50% 중 5% 로 쓴다.
-- null = 아직 정리 안 됨(백필 전 · 정리 실패) — 점수에서는 중립 0.5 다.
-- 테이블 단위 권한(service_role 만)이라 새 칸도 같은 권한을 받는다. 20261028100000 의 match_candidates 가 cv.* 로 읽는다.
alter table public.profile_vectors
  add column self_facets jsonb,
  add column want_facets jsonb;

comment on column public.profile_vectors.self_facets is '자기소개(bio) 원문의 글 정리 — 데이트 장소 좋아함/싫어함 · 대화 · 가치. null 은 아직 없음';
comment on column public.profile_vectors.want_facets is '"이런 사람이 좋아요"(ideal_note) 원문의 글 정리. null 은 아직 없음';
