# 커뮤니티 게시물 + 카테고리 설계 (할 일 19, 2026-11-24 승인)

## 왜
사용자: 「게시물도 올릴 수 있게」 · 「글만」 · 「투표와 섞어서」 · 「카테고리 … 자유, 진로, 연애」 · 「투표도 고르기」.
게시물 = 글만 · 익명 · 500자 · 제목 없음. 투표 · 게시물 모두 카테고리 필수. 옛 앱(1.0.6)은 계속 투표만 받는다.

## 하지 않는 것
게시물 하트 보상 · 사진 · 제목 · 욕설 거르기(투표와 같게 없음) · 차단 거르기(투표와 같게, 익명이라 앱이 작성자를 모름) · 앱 화면 · 관리자 웹 화면.

## 방식 (A안 채택)
`polls` 표에 `kind` · `category` 를 더해 투표와 게시물을 한 표에 담는다. 댓글 · 익명N · 하루 한도 · 신고 · 관리자 가림 · 삭제 ·
탈퇴 cascade · 댓글 푸시가 모두 `polls.id` 를 보므로 게시물에 그대로 돈다.
버린 B안(새 posts 표): 댓글 표 · 번호 표 · 함수 · 도배 막기 · 신고 enum · 관리자 가림 분기를 모두 복사해야 하고 하루 합산 한도를 두 표에서 세야 한다.

## DB (마이그레이션 하나)
- `kind text not null default 'poll' check (kind in ('poll','post'))`
- `category text not null default 'free' check (category in ('free','career','love'))` — 기존 행 · 옛 앱 투표는 기본값으로 자유
- 게시물 본문은 `question` 칸(투표의 질문 = 글 본문). 길이 check: 투표 1~80, 게시물 1~500, 앞뒤 공백 깎인 모양
- `option_a_label` · `option_b_label` not null 풀기 + check `polls_kind_options`: `case kind when 'poll' then option_a_label is not null and option_b_label is not null else option_a_label is null and option_b_label is null end` (투표면 둘 다 있고, 그 밖의 kind 는 둘 다 null)
- `poll_feed`: create or replace, where 에 `p.kind = 'poll'` 만 더함. 인자 · 반환 칸 그대로
- `cast_poll_vote`: create or replace, 있는지 확인에 `p.kind = 'poll'` → 게시물이면 CM404
- `create_poll`: 손대지 않음(옛 서버 · 되돌리기용)
- 새 `create_community_item(p_author, p_kind, p_category, p_text, p_option_a, p_option_b)`: `create_poll` 과 같은 잠금 키
  `pg_advisory_xact_lock(hashtext('create_poll'), hashtext(p_author::text))`, 같은 세는 식(polls 전체 = 투표+게시물, 한국 시간 하루 10개 → CM429). 하트 없음
- 새 `community_feed(p_viewer, p_item_id, p_before, p_before_id, p_limit, p_tab)`: 반환 id, kind, category, text, option_a_label, option_b_label,
  created_at, a_count, b_count, my_choice, is_mine, comment_count. **author_id 없음.** 가림 · 비활성 작성자 · 비활성 투표자 · 보이는 댓글 규칙은 poll_feed 와 같음.
  탭: all · popular · mine · voted · free · career · love(그 밖 빈 결과). popular = 최근 7일 + 참여 수(활성 표 + 보이는 댓글) > 0, 참여 수 → 최신 → id, 커서 없음.
- 새 함수 둘: security invoker · `set search_path = ''` · public/anon/authenticated 실행 revoke · service_role grant

## 서버
- `GET /community/feed?tab=&before=&before_id=` → `{items, has_more}`. item = `{id, kind, category, text, created_at, is_mine, comment_count, poll}`,
  `poll` = `{option_a_label, option_b_label, a_count, b_count, my_choice}` 또는 게시물이면 null. 키는 서버가 골라 담는다
- `GET /community/items/{id}` → `{item}`(없음 · 가림 404)
- `POST /community/posts {category, body}` → 201 `{id}`. body: SafeText 여러 줄 · strip · 1~500 · 보이는 글자 필수. category 세 값만(그 밖 422)
- `DELETE /community/items/{id}` · `GET/POST /community/items/{id}/comments` → 기존 처리 함수에 경로만 더 붙임
- 옛 길: `GET /community/polls` · `/community/polls/{id}` 투표만, 모양 그대로. `POST /community/polls` 에 `category` 선택 칸(없으면 free, 그 밖 422) → `create_community_item` 사용
- 신고: target_type `poll` 그대로. 게시물이면 스냅샷에 kind · category 추가(선택지 null)
- 새 문구(11-24 사용자 확정, errors.py 새 상수 · 기존 문구 그대로): `COMMUNITY_ITEM_NOT_FOUND` "글을 찾을 수 없어요" ·
  `COMMUNITY_DAILY_LIMIT` "오늘은 글을 더 올릴 수 없어요"(새 길 공통) · 댓글 푸시 제목 "내 글에 새 댓글이 달렸어요"(새 길로 단 댓글, 투표 · 게시물 공통.
  옛 길로 단 댓글은 "내 질문에 새 댓글이 달렸어요" 그대로)

## 배포 순서
DB → 서버 → 1.0.7 앱. 서버를 되돌려도 옛 poll_feed 가 게시물을 거른다.

## 시험 (보안담당 19 기준 1~5)
- pgTAP `supabase/tests/community_posts_test.sql`: 칸 check · 기존 행 free · poll_feed 가 어떤 탭/p_poll_id 로도 게시물을 안 줌 · 게시물 투표 CM404 ·
  투표 5 + 게시물 5 뒤 11번째 CM429(둘 다) · 탭 7개 · 인기 순서(표+댓글) · 가림 글이 모든 탭 · 상세 · 댓글에서 0행 · 가림 글 커서로도 안 나옴 ·
  반환 칸에 author_id 없음 · anon/authenticated 실행 거부 · 게시물 댓글 · 익명N 동작
- pytest: 새 길 · 입력 검사(500자 · 제어 문자 · 빈 글 · 0폭만 · 카테고리) · 응답 키 집합 고정(작성자 칸 없음) · 남의 글 삭제 404 ·
  **옛 GET /community/polls 응답 키 · 타입 고정** · 옛 POST category 없으면 free

## 구현 편차 기록 (2026-11-24, 코더)
- `create_poll`: 설계는 "손대지 않음" 이었으나 대장 전달 사용자 규칙(공통 코드는 한 곳)에 따라 인자 · 반환 · 권한 그대로 몸통만 `create_community_item(p_author, 'poll', 'free', …)` 에 넘긴다. 하루 합산 한도의 잠금 · 세는 식이 한 곳에만 있다.
- 댓글 푸시 제목: 설계는 "게시물 댓글 푸시 제목" 이었으나 사용자 확정으로 **새 길(`/community/items/{id}/comments`)로 단 댓글은 투표 · 게시물 모두** "내 글에 새 댓글이 달렸어요", 옛 길은 "내 질문에 새 댓글이 달렸어요" 그대로. 길은 처리 함수의 경로 틀(`route.path`)로 가른다(`router._wording`).
- 본문 검사 한 곳: 투표 질문 · 게시물 본문 · 댓글이 `core/text.py` `body_text(max_length)` 를 같이 쓴다. 그래서 옛 투표 질문 길이도 앞뒤 공백을 깎은 뒤 잰다(앞뒤 공백 포함 81자 이상이던 질문이 이제 통과 — 저장 값은 늘 80자 이하).
- 투표하기 길은 새로 만들지 않았다(설계에 없음). 새 앱도 `POST /community/polls/{id}/votes` 를 부르고 응답은 옛 카드 모양이다.
