# 커뮤니티 공지사항 설계 (할 일 21, 2026-11-24 승인)

## 왜
사용자: 「공지사항 배너 … 7일이내 new 배지 … 서버에서 이미지 올릴 수 있거나 글 작성 … 댓글 가능」 · 「따로 화면」.
공지 = 운영자 글(앱은 "CampusMate 운영자" 로 그림), 제목 · 본문 · 그림 1장(선택). 피드 맨 위 띠 = 가장 최근 보이는 공지, 7일 안이면 NEW.

## 하지 않는 것
공지 수정(작성 · 삭제 · 가림만) · 운영자 답글 · 새 공지 푸시 · 관리자 웹 화면 · 앱 화면.

## 방식
19 의 polls 표(kind · category) 위에 kind='notice' 로 얹는다. 댓글 · 익명N · 댓글 한도 · 신고 · 관리자 가림이 polls.id 기준이라 그대로 쓴다.
버린 안: 새 notices 표(댓글 표 · 함수 · 도배 막기 복사). 브랜치는 feat/community-posts 위에 이어서.

## DB (19 다음 마이그레이션 하나)
- kind check 에 'notice' 추가
- author_id not null 풀기 + check `(kind = 'notice') = (author_id is null)`. 누가 썼는지는 admin_actions
- `title text` — 공지만 1~40자(앞뒤 공백 깎인 모양), 공지 아니면 null. check 로 못박음
- `image_path text` — 공지만, 선택. 공지 아니면 null
- 공지 본문 = question 칸, 1~2000자(19 의 길이 check 를 kind 별로 넓힘). 선택지 null(19 check 그대로 맞음). category 는 기본값 free, 쓰지 않음
- `add_poll_comment` · `poll_comments_page`: 현재 정의(spam guard 판 20261112090000, poll_comments_page 는 20261111000200) 그대로 복사 + 글 확인을
  "kind='notice' 이거나 작성자 active" 로. 익명N 판단 `p_author <> v_poll_author` → `p_author is distinct from v_poll_author`.
  공지 댓글 is_post_author=false, can_delete = 내 댓글만. 푸시용 poll_author_id 는 null(서버가 null 이면 푸시 안 함)
- `create_community_item`(19): kind='notice' 거절
- 새 `notice_list(p_viewer, p_notice_id, p_before, p_before_id, p_limit)`: 가리지 않은 공지 최신순 + (created_at,id) 커서. id · title · text · image_path · created_at · comment_count. 작성자 칸 없음
- 새 `admin_create_notice(p_admin, p_id, p_title, p_body, p_image_path, p_ip)` · `admin_delete_notice(p_admin, p_id, p_reason, p_ip)` → admin_assert + admin_actions(`notice_create` · `notice_delete`). delete 는 지운 image_path 를 돌려줌. admin_set_content_status 와 같은 틀
- 관리자 공지 목록용 `admin_notice_list`(가린 것 포함, status 칸) 또는 서버 PostgREST 직접 읽기 — 작은 쪽으로
- 공개 버킷 `community-notices`: public true · file_size_limit 2MB · allowed_mime_types ['image/jpeg'] · storage.objects 정책 0
- 새 함수 전부 security invoker · search_path '' · public/anon/authenticated revoke · service_role grant

## 서버
앱(get_verified_caller):
- `GET /community/notices?before=&before_id=` → `{items:[{id, title, text, image_url|null, created_at, is_new, comment_count}], has_more}`. is_new = 서버 시계 7일 안. 쪽 크기 20
- `GET /community/items/{id}` 가 공지도: kind "notice" + `title` · `image_url` 칸(투표 · 게시물은 null). 가린 공지 404
- 댓글 길 그대로(19 /community/items/{id}/comments). 공지 댓글은 푸시 없음(글쓴이 null)
- 신고 target 'poll' 그대로. 공지면 작성자 active · 본인 검사 건너뛰고 target_profile_id null, 스냅샷 kind · title · question
- 사용자 DELETE 공지 → 404(주인 없음)
- 앱 글쓰기 요청 모델(POST /community/posts · /community/polls)은 `extra="forbid"` → kind · title · image 칸 넣으면 422
- 새 문구: errors.py `COMMUNITY_NOTICE_NOT_FOUND = "공지를 찾을 수 없어요"`(11-24 사용자 확정)
관리자(get_admin_caller):
- `GET /admin/notices` (가린 것 포함, 커서) · `POST /admin/notices` multipart(title · body · image 선택) → 201 `{id}` · `DELETE /admin/notices/{id}` body `{reason}`
- 그림 오류는 기계용 detail: `image_type`(형식) · `image_too_large`(10MB 넘음). 글자는 관리자 웹 쪽
- 가림은 기존 moderation polls 길 그대로

## 그림 처리 (서버)
입력 최대 10MB(MAX+1 바이트만 읽기) → 매직 바이트 jpeg/png/webp(webp = `RIFF????WEBP`)만, 그 밖 422 image_type →
Pillow 로 열기(Image.MAX_IMAGE_PIXELS 상한, 깨진 파일 · 폭탄 422 image_type) → 열린 형식이 매직 바이트와 같은지 →
exif_transpose → 투명이면 흰 바탕 합성 → RGB → 긴 변 1600px 넘으면 줄이기 → JPEG(quality 80, 대장 11-24 「80 안팎」) 다시 저장(EXIF 없음) →
경로 `{notice_id}.jpg`, content-type image/jpeg 서버 지정. 순서: id → 그림 올리기 → admin_create_notice(실패면 그림 지움).
삭제: admin_delete_notice → 그림 지우기(실패는 로그만). image_url = `{supabase_url}/storage/v1/object/public/community-notices/{image_path}`(홈 배너와 같음).
Storage 클래스는 기존 heart_tasks/storage.py 모양(이미 셋이면 ponytail 주석대로 합칠지 판단).

## 배포 순서
DB → 서버 → 관리자 웹 → 1.0.7 앱.

## 시험 (보안담당 21 기준 1~5)
- pgTAP `supabase/tests/community_notices_test.sql`: author null ⇔ notice check · title/본문 길이 · 일반 글에 title/image 거절 · create_community_item notice 거절 ·
  poll_feed · community_feed(모든 탭) 에 공지 없음 · notice_list 가림 제외 · 커서 · 공지 댓글 익명N 1,2 · 공지 댓글 한도/가림 ·
  admin_create/delete_notice 비관리자 거절 · admin_actions 기록 · 버킷 public · mime · 크기, storage.objects 에 이 버킷 정책 0 · 함수 권한
- pytest: 관리자 길 3개 401(토큰 없음) · 403(일반 사용자 · mfa) · 그림 jpeg/png/webp 통과, svg · gif · html · 11MB · 깨진 파일 거절 ·
  저장 바이트에 EXIF 없음 · 긴 변 1600 · 경로/content-type 서버 결정 · 올린 뒤 DB 실패면 그림 지움 · 앱 요청 extra forbid 422 ·
  GET /community/notices 키 집합(작성자 없음) · is_new 7일 경계 · 공지 댓글 푸시 안 감 · 공지 신고 target_profile_id null

## 구현 편차 기록 (2026-11-24 코더)

설계 본문은 고치지 않았다. 설계가 비워 둔 곳을 정한 것과 설계와 다르게 한 것만 적는다.

1. **그림 경로 check 를 더 좁혔다.** `polls_notice_image` 는 "공지만 · 선택" 에 더해 값이 `{id}.jpg` 하나뿐이다(임의 URL · 남의 경로가 DB 에 들어가지 못하게, 보안 기준 21-4). 그래서 서버는 id 를 먼저 정하고 그 id 로 그림을 올린 뒤 `admin_create_notice(p_id …)` 를 부른다(설계 순서 그대로).
2. **작업 기록의 `target_type` 은 `notice`** 로 했다(설계는 동작 이름만 정함). `notice_create` 의 after = 제목 · 그림 경로, `notice_delete` 의 before = 제목 · 그림 경로 · reason = 사유.
3. **관리자 목록은 DB 함수 없이 서버가 PostgREST 로 `polls?kind=eq.notice` 를 읽는다**(설계가 고르게 한 두 안 중 작은 쪽). 공지 목록용 부분 인덱스 `polls_notice_created_id_index` 를 더했다.
4. **상세 404 문구를 가르려고 읽기 한 번을 더한다.** `GET /community/items/{id}` 가 `community_feed` 에서 못 찾으면 `polls?select=kind` 를 읽어 공지일 때만 `notice_list` 를 부른다. 가린 공지 = 404 "공지를 찾을 수 없어요"(`COMMUNITY_NOTICE_NOT_FOUND`), 그 밖 = 그대로 "글을 찾을 수 없어요". 상세의 공지는 `category` null · `is_mine` false · `poll` null 이고, `title` · `image_url` 은 상세에만 붙였다(피드 줄 `/community/feed` 는 19 모양 그대로).
5. **Storage**: 같은 모양 클래스가 이미 넷(heart_tasks · student_verification · graduate_verification · profile_onboarding)이라 다섯째를 베끼지 않고 버킷 이름을 받는 `app/core/storage.py` `BucketStorage` 를 새로 두어 공지가 쓴다. 넷은 경로 규칙 · 서명 URL · 시험 가짜가 저마다 달라 이번에 옮기지 않았다(큰 리팩터 금지) — 그 기능을 고칠 때 하나씩 옮긴다(파일 머리 ponytail 주석).
6. **그림 화소 상한은 전역 `Image.MAX_IMAGE_PIXELS` 를 바꾸지 않고** 열린 그림의 머리 크기로 직접 본다(4천만 화소, 넘으면 `image_type`). 전역 값은 face_framing · paid_preview 도 쓴다. 검사 · 다시 저장은 `app/community/notice_image.py` 한 모듈이고, 그림 풀기는 `asyncio.to_thread` 로 이벤트 루프 밖에서 한다.
7. **신고**: 공지 댓글 신고도 되게 `fetch_comment_for_report` 의 글 임베드에 `kind` 를 더했다(공지면 글쓴이 active 검사를 건너뛴다 — 공지 글 신고와 같은 `_poll_shown`). 공지 글 신고는 `target_profile_id` 가 null 이라 신고자 세기를 부르지 않고 0명으로 디스코드에 보낸다.
8. **관리자 작성 요청은 multipart 칸마다 `Form()`** 으로 받는다(pydantic 폼 모델 + `File` 을 같이 쓰면 FastAPI 가 모델을 `form` 칸 아래로 감싸 422 가 난다). 제목은 한 줄 칸(SafeLine), 본문은 19 의 `body_text(2000)`. 지우기 응답은 200 `{id}`.
9. **19 시험 세 곳을 고쳤다**: `test_community_items.py` 상세 칸 집합에 `title` · `image_url` 을 더하고 가짜에 `GET /polls`(kind 읽기)를 넣었다 · `test_report_poll_comment.py` 의 임베드 select 기대값에 `kind` 를 넣고 가짜 글 줄에 `kind` 를 채웠다.
10. 19 pgTAP `community_posts_test.sql` 의 "kind 는 poll · post 둘뿐이다"(작성자 있는 notice insert)는 이 마이그레이션 뒤에도 23514 로 통과한다(이유가 kind check 가 아니라 `polls_notice_author`) — 설명 글은 손대지 않았다.
11. 21 이 새로 더한 옛 앱(1.0.6) 호환 코드는 없다. `extra="forbid"` 는 1.0.6 이 보내는 세 칸을 그대로 통과시킨다(시험 `test_the_1_0_6_poll_request_shape_still_passes`).
12. (검토 하-1 반영) 공지 신고의 디스코드 줄은 대상 칸에 `None` 대신 "운영자 공지"(`safety/router.py` `NOTICE_TARGET_LABEL`, 운영자만 보는 알림 글)를 싣는다. 형식("대상: …")은 그대로다. 신고자 세기를 부르지 않는 것을 시험으로 고정했다.
13. (검토 하-2 반영) 관리자 공지 작성에서 DB 가 오류로 답했을 때(`HTTPException` · `httpx.HTTPStatusError`)만 올린 그림을 지운다. 시간 초과 · 끊김(`httpx.TransportError`)은 결과를 모르니 그림을 남기고 로그만 남긴다(공지가 들어갔다면 그림을 지우면 깨진 주소가 된다).
14. (검토 하-4 반영) (시각, id) 커서 짝 검사를 `app/core/cursor.py` `check_cursor` 하나로 옮겼다. 커뮤니티 피드는 인기 탭 규칙만 더한 `_check_feed_cursor`, 댓글 · 공지 목록 · 관리자 공지 목록은 `check_cursor` 를 그대로 쓴다. 동작은 같다.
