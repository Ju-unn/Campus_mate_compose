# SUPABASE.md — CampusMate Supabase 작업 규칙

**Supabase 작업(스키마·RLS·Storage·Auth)을 하기 전에 이 문서를 먼저 읽는다.**

`frontend/CLAUDE.md` §10.1 에서 떼어낸 문서다(2026-09-15). `frontend/CLAUDE.md` §10.1 에는 금지 규칙 요약만 남겼고, 마이그레이션 주석과 ERD 가 인용하는 "`frontend/CLAUDE.md` §10.1" 의 세부 규칙은 이 문서에 있다.

## 1. 현재 상태

Supabase **MCP 플러그인(`supabase`)이 설치·인증돼 있다.** 클라우드 프로젝트는 `campus_mate`(조직 CampusMate, Seoul) 하나뿐이다. 조각 0(테이블 4·RLS·정책 4·private 버킷 `profile-photos`·seed `universities` 20행·`university_email_domains` 20행)은 2026-09-14 사용자 승인 후 적용됐다. **조각 1(1a 이메일 인증 훅)·조각 1b(학생증 인증) 마이그레이션 클라우드 적용 완료(2026-09-20, MCP `list_migrations` 확인).** 1b 쪽 적용분: `20260914055607`(학생증 인증 컬럼)·`20260914055617`(profile_private)·`20260914055624`(student-id-temp 버킷)·`20260914061304`(student_verification_attempts)·`20260914061821`(profile-photos 버킷 제한)·`20260919181319`(student_number 컬럼) — `20260914055631`(RLS 자동 활성 execute revoke)은 이전 라운드에 이미 적용됐다. **학생증 사진 삭제 트리거 마이그레이션(`20260919181357`)은 클라우드에 올라간 적 없이 폐기·삭제됐다** — SQL 트리거로 `storage.objects` 를 지우면 메타 행만 지워지고 실제 파일은 고아로 남아, FastAPI 가 확정 직후 Storage API로 직접 지우는 방식으로 바꿨다(§7, ERD.md §9, ERD_DECISIONS.md §11-27). 조각 2 이후의 파일은 아래 "현재 상태" 와 `docs/ERD.md` 상태줄이 기준이다(이 문단은 2026-09-20 기록이라 "파일도 없다" 는 낡았다 — 2026-10-20 정정). 클라우드 쓰기(적용)는 지금도 항상 클라우드 프로젝트에 MCP 로만 한다. 로컬 스택(Docker)은 2026-09 이후 생겨 pgTAP 은 `supabase test db` 로 로컬에서 돌린다(`frontend/CLAUDE.md` §10 · `.claude/team/COMMON.md` §4 — 클라우드와 별개). **마이그레이션 24개 클라우드 적용, pgTAP 111개 통과(2026-09-20 기준).** **PR #99 로 `profile_avatars` 마이그레이션 1개 추가 적용(2026-09-25): 파일명 `20260924163241`, 원격 버전 `20260924172230`(§4 관례대로 적용 시각 기준이라 어긋난다) — `storage_path` 의 `not null` 을 빼고 `check profile_avatars_ready_has_storage_path` 로 대체했다(ERD.md §3).**

**현재 상태 (2026-10-30 문서 정리, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 저장소 `supabase/migrations/` **101개 = 운영 101개, 모두 적용**이다. 2026-10-29 문서 정리(100개) 뒤 한 개가 더 들어왔다: `20261030010000_taste_clash`(2026-10-30 운영 적용 — **새 표 `taste_words`**(글에서 뽑은 취향 단어 사전, 임베딩 512 · `storage plain`, RLS 켬 · 정책 없음, `service_role` 은 `select` · `insert` 만) + `profile_vectors` 에 `bigint[]` 칸 4개(`self_like_words` · `self_dislike_words` · `want_like_words` · `want_dislike_words`) + 함수 `taste_clash_candidates(uuid) → jsonb`(`service_role` 만 실행)). 원격 버전 값은 전달받지 못했다. 운영 승인 원문(사용자, 대장 전달): 「가 / 2. db변경 승인 / 3. erd 승인 / db적용 승인 / 5. 진행 / 6. 서버배포 승인 / 7.정리 진행」, 이어서 「db 승인 , db적용 승인 , 서버배포 승인 알아서 진행해줘」. 적용 뒤 advisor 에 새 경고는 없다(`taste_words` 의 'RLS 켬 · 정책 없음' INFO 는 서버 전용 표라는 의도다). 표 · 권한은 `docs/ERD.md` 상태줄 · §2 · §3 · §4, 서버 쪽은 `backend/DEPLOY.md` §4-18. 이 규칙은 그대로다: 클라우드 쓰기는 사용자 원문 승인을 인용한 뒤 `apply_migration` 으로만 한다(§4). 아래 두 가지는 10-29 줄에서 이어지는 지금의 사실이다. **운영 데이터 변경(마이그레이션 파일 없음, 2026-10-28 오후): 서울 학교 64곳의 `universities.card_opens_at` 을 2026-11-02 07:00 → null(열림)로 바꿨다**(사용자 원문 「현재 심사 2개다 실패여서 11월2일 이거 그냥 풀어줘 통과하면 정확한 날짜 정해서 다시 막아야할거같아」 — `execute_sql`). 저장소 `20261020110000` 은 그대로라 새 DB 는 11-02 로 닫힌 채 만들어진다. 심사 통과 뒤 날짜를 정해 다시 막아야 한다(`backend/DEPLOY.md` §4-17). **주의: 운영 DB 에는 구글 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)가 2026-10-27 00:26 KST 에 일회성 스크립트로 들어갔다(마이그레이션 파일 없음, 하네스의 "실사용자 없음" 검사를 이 한 건 한정으로 건너뛰었다고 메모에 있다). 출시 전에 사용자에게 먼저 묻고 제거하며, 그 전에는 하네스 전체 cleanup 을 돌리지 않는다**(`backend/DEPLOY.md` §4-16). 날짜별 갱신 줄은 아래 "갱신 이력" 에 그대로 있다.

<details><summary>갱신 이력 — 2026-09-29 ~ 2026-10-29 (2026-10-20 · 10-27 · 10-29 · 10-30 문서 정리로 접었다, 내용 그대로)</summary>

**2026-10-29 갱신(문서 정리 때의 현재 상태 — 2026-10-30 에 여기로 접었다, 내용 그대로, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 저장소 `supabase/migrations/` **100개 = 운영 100개, 모두 적용**이다. 2026-10-27 문서 정리(97개) 뒤 세 개가 더 들어왔다: `20261028090000_profile_vectors_text_facets`(`profile_vectors` 에 글 정리 칸 2개, 2026-10-28 운영 적용) · `20261028100000_match_candidates_face_fields`(함수 `match_candidates` 가 후보의 얼굴상 · 인상 4칸과 글 정리 2칸을 더 돌려주고 성향 최대 거리 상수를 바꾼다, 2026-10-28 운영 적용) · `20261029090000_daily_cards_one_free_per_day`(`daily_cards` 의 부분 유일 인덱스 — 무료 카드는 한 사람에게 서울 날짜당 한 장, 2026-10-29 운영 적용, 적용 전 중복 0건 · 적용 뒤 unique · valid). 세 파일 모두 새 표를 만들지 않고, 둘째는 반환 타입을 바꾸지 않는다(`docs/ERD.md` 상태줄 · §3 · §4, 서버 쪽은 `backend/DEPLOY.md` §4-17). 원격 버전 값은 전달받지 못했다. 운영 승인 원문: 앞 두 개 「매칭 개편 마이그레이션 2개 운영 적용 승인 db승인」(메모 기록), 셋째 「db승인해줄게 완전히 막아야지」(대장 전달). 이 규칙은 그대로다: 클라우드 쓰기는 사용자 원문 승인을 인용한 뒤 `apply_migration` 으로만 한다(§4). **운영 데이터 변경(마이그레이션 파일 없음, 2026-10-28 오후): 서울 학교 64곳의 `universities.card_opens_at` 을 2026-11-02 07:00 → null(열림)로 바꿨다**(사용자 원문 「현재 심사 2개다 실패여서 11월2일 이거 그냥 풀어줘 통과하면 정확한 날짜 정해서 다시 막아야할거같아」 — `execute_sql`). 저장소 `20261020110000` 은 그대로라 새 DB 는 11-02 로 닫힌 채 만들어진다. 심사 통과 뒤 날짜를 정해 다시 막아야 한다(`backend/DEPLOY.md` §4-17). **주의: 운영 DB 에는 구글 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)가 2026-10-27 00:26 KST 에 일회성 스크립트로 들어갔다(마이그레이션 파일 없음, 하네스의 "실사용자 없음" 검사를 이 한 건 한정으로 건너뛰었다고 메모에 있다). 출시 전에 사용자에게 먼저 묻고 제거하며, 그 전에는 하네스 전체 cleanup 을 돌리지 않는다**(`backend/DEPLOY.md` §4-16). 날짜별 갱신 줄은 아래 "갱신 이력" 에 그대로 있다.

**2026-10-27 갱신(문서 정리 때의 현재 상태 — 2026-10-29 에 여기로 접었다, 내용 그대로, 대장이 이 세션에서 확인한 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 저장소 `supabase/migrations/` **97개 = 운영 97개, 모두 적용**이다. 2026-10-20 문서 정리(96개) 뒤 한 개가 더 들어왔다: `20261027100000_admin_matching_requests`(관리자 웹 매칭 현황 "누가 누구에게 대화를 신청했나" 읽기 함수, 원격 버전 `20261027053822`, 새 표 · 열 없음, `service_role` 만 실행 — `docs/ERD.md` 상태줄 · §7). 이 규칙은 그대로다: 클라우드 쓰기는 사용자 원문 승인을 인용한 뒤 `apply_migration` 으로만 한다(§4). **주의: 운영 DB 에는 구글 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)가 2026-10-27 00:26 KST 에 일회성 스크립트로 들어갔다(마이그레이션 파일 없음, 하네스의 "실사용자 없음" 검사를 이 한 건 한정으로 건너뛰었다고 메모에 있다). 출시 전에 사용자에게 먼저 묻고 제거하며, 그 전에는 하네스 전체 cleanup 을 돌리지 않는다**(`backend/DEPLOY.md` §4-16). 날짜별 갱신 줄은 아래 "갱신 이력" 에 그대로 있다.

**2026-10-20 갱신(문서 정리 때의 현재 상태 — 2026-10-27 에 여기로 접었다, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 저장소 `supabase/migrations/` **96개 = 운영 96개, 모두 적용**이다. 2026-10-19 문서 정리(93개) 뒤 세 개가 더 들어왔다: `20261019220000_admin_billing_returned_accounts`(관리자 결제 "환불이 잦은 계정" 읽기 함수) · `20261020100000_faq_support_email_change`(FAQ 문의 메일 교체, 데이터만) · `20261020110000_close_seoul_schools_until_cohort_open`(서울 학교 64곳 `card_opens_at = 2026-11-02 07:00 KST`, 시험 학교 `region_group = 'e2e'` 1곳은 열린 채, 데이터만). 세 파일 모두 표 · 열을 바꾸지 않는다(`docs/ERD.md` 상태줄 · §3 · §7). 원격 버전은 파일 이름이 아니라 적용 시각이다(§4 관례). 이 규칙은 그대로다: 클라우드 쓰기는 사용자 원문 승인을 인용한 뒤 `apply_migration` 으로만 한다(§4). 날짜별 갱신 줄은 아래 "갱신 이력" 에 그대로 있다.

**2026-09-29 문서 정리 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 저장소 `supabase/migrations/` 는 **52개**다. 그 사이 조각 2 ~ 5 · 아바타 비동기 · 홈 집계 · 조각 6(신고 · 차단 · 지인 차단 · 탈퇴) · 커뮤니티 · 추천 · `grant_hearts` 음수 · 무료 하트 인증 · 지인 리뷰 · 코호트 · 가입 동의 · FAQ 가 운영에 적용됐고, **마지막 적용은 `create_faq`(운영 기록 `20260929054505`), 그 앞 `create_user_consents`(`20260929051356`)** 이다. 위 "조각 2 이후는 파일도 없다" · "로컬 스택(Docker)은 없다" · "마이그레이션 24개" 는 2026-09-20 기록으로 남긴다 — 지금은 로컬 스택(Docker)에서 `supabase db reset` · `supabase test db` 로 먼저 검증하고, 모든 작업 폴더가 같은 로컬 DB 를 쓰므로 한 번에 한 작업만 돌린다. 적용 순서가 서버 배포와 얽힌 기능(조각 6 PR 3 · 무료 하트 · 코호트 · 가입 동의)의 순서는 `backend/DEPLOY.md` §4-4 · §4-5 가 기준이다. 적용은 여전히 **ERD 그림 → 사용자 검토 → 사용자 승인** 뒤에만 한다.

**2026-10-12 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 저장소 · 운영 모두 **67개**, 마지막 적용은 `20261011010000_encrypt_real_name_and_kakao_id`(실명 · 카톡 암호화 M1, §8). 그 앞은 소셜 로그인 4개(`20261008010000` ~ `040000`) · 카드 선정 · 유료 카드 · 알림함 5개(`20261010010000` ~ `050000`)다(`docs/ERD.md` 상태줄).

**2026-10-12 저녁 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 운영 **68개** — 마지막은 M2 `drop_plaintext_real_name_and_kakao_id`(파일 `20261012010000`, 운영 기록 버전 `20261012070722` — §4 관례대로 파일 이름과 원격 버전이 다르다, 정상). M2 는 `profile_private` 의 평문 `real_name` · `kakao_id` 열과 함수 `backfill_profile_private_encryption` 을 지웠다(§8). **운영 적용은 끝났고 파일은 DB PR #476(draft) merge 대기**라 저장소 main 은 아직 67개다 — #476 이 merge 되면 저장소도 68개가 된다. 실행 기록 · 롤백 주의는 `backend/DEPLOY.md` §4-4.

**2026-10-14 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 저장소 · 운영 모두 **71개**다(위 M2 파일은 PR #476 merge 로 저장소에도 들어왔다). 그 뒤 세 파일: `20261013010000_add_heart_reason_first_purchase_bonus` · `20261013010100_billing_purchases`(인앱결제 `purchases` 표 · `grant_store_purchase` · `refund_store_purchase`, PR #498) · **`20261013152736_user_channel_realtime_policy`(마지막 적용, 원격 버전 `20261013154505`, PR #512)** — 채팅 실시간 사용자 채널의 `realtime.messages` 받기 정책 `user_channel_read_own` 하나다(테이블 · publication · grant 변경 없음, `docs/ERD.md` §2). Realtime 설정 "Allow public access" 는 끄지 않았다(방 채널 `messages:<match_id>` 가 public 이다). 적용 순서는 `backend/DEPLOY.md` §4-8 · §4-9.

**2026-10-14 밤 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** 저장소 · 운영 모두 **72개**다. 새 파일 **`20261014120000_faq_avatar_regen_cost_20`(마지막 적용, 원격 버전 `20261014080438`, PR #523)** — 스키마 변경 없이 `faq` 답변 두 곳의 아바타 다시 만들기 값 숫자만 10 → 20 으로 바꾸는 `update ... replace` 다(두 번 돌려도 같다. 5회 실패 보상 10하트 구절은 그대로). 원격 버전이 파일 이름 타임스탬프와 다른 것은 §4 관례(`apply_migration` 이 적용 시각을 버전으로 찍는다)대로 정상이다 — 이번에는 원격 버전(08:04 UTC)이 파일 이름(12:00)보다 **이른 시각**이지만, 앞 적용분(`20261013154505`)보다는 늦어 원격 순서는 맞다. 대조는 늘 `name` 으로 한다. 시험은 `supabase/tests/faq_test.sql` 14 · 15. 파일 머리말의 "초안 — 아직 어디에도 적용하지 않았다" 는 쓸 때의 문장이다(운영 적용은 위 대장 전달 값).

**2026-10-15 갱신(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다).** **운영 73개 · 저장소 74개**로 갈린다. 운영의 마지막 적용은 **`20261014130000_faq_support_email`(PR #533)** — 스키마 변경 없이 `faq` 답변의 옛 문의 메일을 새 주소(앱 상수 `frontend/lib/common/support_email.dart` 와 같은 값)로 바꾸는 `update ... replace` 다(옛 주소가 없으면 아무것도 안 바뀐다, 두 번 돌려도 같다. 시험 `supabase/tests/faq_test.sql` 16 · 17). 원격 버전 값은 받지 못했다. **저장소 74번째 `20261015120000_poll_feed_tabs`(PR #540)는 운영 미적용**이다 — 커뮤니티 탭 줄용으로 함수 `poll_feed` 에 `p_tab` 칸을 더한다(`drop` 뒤 다시 만들기, 표 · 데이터 변경 없음 — `docs/ERD.md` §7). 옛 서버도 기본값 `'all'` 로 그대로 돌므로 **DB → 서버 → 앱 순서**로 내보낸다(`backend/DEPLOY.md` §5). 적용은 위 관문(사용자 원문 승인) 그대로다.

**2026-10-17 갱신(이 문서 담당이 저장소를 셌다 · 운영 값은 대장 전달 값 — 클라우드를 조회하지 않았다).** **저장소 `supabase/migrations/` 76개**(main `fccc5e2d`). 위 10-15 줄의 `20261015120000_poll_feed_tabs` 는 2026-10-15 밤 운영에 적용돼 운영 74개가 됐다(`backend/DEPLOY.md` §5 10-15 밤 줄). 새 두 파일(무료 하트 조정, 2026-10-16 사용자 확정 · PR #570 · #573)은 둘 다 표 · 열을 바꾸지 않는다:
- `20261016144525_poll_vote_reward_5_cap_15` — `poll_vote_reward_due` · `cast_poll_vote` 를 `create or replace` 로 다시 만들어 하루 첫 투표 5하트 · 주 상한 15(종전 10 · 30)로 바꾼다. 이름 · 인자 · 반환형 · `security invoker` · `search_path ''` · 권한 그대로(파일 끝에 revoke · grant 를 다시 적었다). 시험 `supabase/tests/community_polls_test.sql` · `heart_tasks_test.sql`. **2026-10-16 운영에 적용됐다**(대장 전달 값 — 사용자 승인 문장 뒤 MCP `apply_migration`). 파일 머리말의 "초안 — 아직 어디에도 적용하지 않았다" 는 쓸 때의 문장이다 — SQL 파일은 고치지 않는다(10-14 `faq_avatar_regen_cost_20` 줄과 같은 관례)
- `20261016144530_faq_free_heart_amounts` — `faq` "하트를 무료로 얻는 방법이 있나요?" 답의 숫자(에브리타임 40 · 투표 5 · 주 15)와 "학교 단톡방" → "단톡방" 을 `update … replace` 로 바꾼다(두 번 돌려도 같다). 저장소 시드는 "하루 한 번 10하트" 인데 운영 실제 문구는 "하루 첫 투표에 10하트" 라 두 표기를 모두 바꾸게 PR #573 이 고쳤다. **운영에 적용됐다**(사용자 승인 "db적용부터 승인할게" 뒤 `apply_migration`). 대장 전달 값은 2026-10-16 적용이고 파일 머리말은 "2026-10-17 운영에 적용했다" 라 날짜가 하루 다르다(파일은 고치지 않는다). 원격 버전 값은 받지 못했다. 시험 `supabase/tests/faq_test.sql` 18 · 19
- 그래서 **운영 76개 = 저장소 76개, 모두 적용**이다(대장 전달 값, 2026-10-17 확인). 이 두 파일과 짝인 서버(에브리타임 40 · 투표 표시 5)는 2026-10-17 리비전 `00083-pwx` 로 배포됐다(`backend/DEPLOY.md` §4-13)

**2026-10-19 갱신(이 문서 담당이 저장소를 셌다 · 운영 값은 대장 전달 값 — 클라우드를 조회하지 않았다).** **저장소 `supabase/migrations/` 93개**(main `fc430713`)이고 **운영도 93개 = 모두 적용**이다. 76번째 뒤 17개의 내용은 `docs/ERD.md` 상태줄(2026-10-19)에 있다. 적용 묶음은 둘이다:
- **2026-10-17 ~ 18 밤(운영 76 → 89)**: `20261017120000_create_unknown_email_domain_attempts` · `20261017130000_faq_student_id_removal`(FAQ 5문항, 데이터만) · 관리자 웹 11개(`20261018002858` ~ `20261018150000`, `admin_users` · `admin_actions` · 관리자 조치 함수 · 통계 함수 · 기본 아바타 유일 인덱스 · 알림 종류 check). 서버 `00086-7zf` 와 같이 나갔다(`backend/DEPLOY.md` §5).
- **2026-10-19(운영 89 → 93)**: `20261019100000_heart_task_multi_photos`(인증샷 여러 장) · `20261019200000_graduate_verification_tables` · `20261019200100_graduate_verification_functions`(졸업생 인증) · `20261019210000_notification_quiet_hours_default_off`(저녁 알림 기본값). **원격 기록 버전은 파일 이름이 아니라 적용 시각이다 — `20261019055736` · `20261019055756` · `20261019055818` · `20261019055824`**(§4 관례대로 정상, 파일과의 짝은 받지 못했다). 서버 `00087-9qj`(이후 `00088-gh5` 스위치 켬, `00089-fpm`)와 같이 나갔고 순서는 DB → 서버 → 관리자 웹 → 앱이다(`backend/DEPLOY.md` §4-14). **되돌릴 수 없는 변경**: `20261019100000` 이 `heart_task_submissions.storage_path` 를 지우고 `submit_heart_task` 인자를 바꿔 서버를 `00087` 아래로 내리면 인증샷 제출 · 관리자 사진 보기가 깨진다.
- 졸업생 인증 마이그레이션의 SQL 은 `security definer` 를 쓰지 않고(§5) 함수마다 `public · anon · authenticated` 실행을 걷고 `service_role` 에만 준다. 새 비공개 버킷 `graduate-cert-temp` 가 `storage.buckets` insert 로 만들어졌다(§7 학생증 사진 보관 규칙과 같은 관례 — 클라이언트 Storage 정책 없음).

</details>

## 2. 시작할 때

- 스키마·RLS·Storage·Auth 를 건드리기 전에 `supabase:supabase` 스킬(보안 체크리스트)과 `supabase:supabase-postgres-best-practices` 스킬을 로드한다
- 현재 상태는 추측하지 않고 MCP `list_tables` · `list_extensions` · `list_migrations` 로 확인한다

## 3. 키·식별자 취급

- 프로젝트 URL · project ref · anon/publishable 키 · `service_role` 키 · DB 비밀번호는 **문서·코드·커밋·PR 에 쓰지 않는다.** 필요할 때 MCP `get_project_url` · `get_publishable_keys` 로 조회하고, 앱에는 `--dart-define` 으로 주입한다 (`frontend/CLAUDE.md` §11)
- `service_role` 키는 FastAPI 서버 전용이다. Flutter 쪽 코드·설정에는 절대 두지 않는다

## 4. 스키마 변경 = 마이그레이션 파일

- **`supabase/` 는 저장소 루트에 있다, `frontend/` 안이 아니다**(2026-09-13 사용자 결정). 모든 스키마 변경은 `supabase/migrations/<timestamp>_<name>.sql` 로 저장소에 남긴다 (설계 문서 §5.4). 대시보드·`execute_sql` 로 DDL 을 손으로 실행하지 않는다
- 파일 이름은 `supabase migration new <name>` 으로 만든다(저장소 루트에서 실행). 직접 지어내지 않는다
- 클라우드 적용은 MCP `apply_migration` 에 **그 파일 내용을 그대로** 넘긴다(2026-09-14 사용자 결정, ERD §12-33). `apply_migration` 은 원격 버전을 적용 시각으로 찍어 파일명과 다르므로 `supabase db push`·`migration list` 는 `migration repair` 없이는 쓸 수 없고, repair 도 클라우드 쓰기라 사용자 승인이 필요하다. 클라우드 쓰기는 매번 사용자가 직접 승인한 뒤에만 한다.
- **클라우드 마이그레이션 적용 절차 (2026-09-20 정책으로 고정).** 클라우드 마이그레이션은 MCP `apply_migration` 으로만 적용한다(사용자 승인 후). `supabase db push` · `migration repair` · `db pull` 은 쓰지 않는다 — 원격 `version` 이 적용 시각으로 기록돼 로컬 파일명과 다르기 때문이다(`name` 은 1:1 일치). 적용 전에는 `list_migrations` 의 `name` 과 로컬 파일 `name` 을 대조해 아직 적용되지 않은 파일만 적용한다. 로컬 검증은 `supabase db reset` + `supabase test db` 로 한다
- 적용 직후 MCP `get_advisors`(security · performance)를 돌려 경고를 0 으로 만든다
- 프로덕션 DB 에서 `execute_sql` 은 **읽기 전용 조회**에만 쓴다

## 5. RLS 체크리스트 (정책 SQL 을 쓸 때마다)

테이블별 실제 접근 표는 `docs/ERD.md` §2 가 기준이다.

- `public` 스키마의 모든 테이블은 RLS 를 켠다
- 정책은 `to authenticated` + `using ((select auth.uid()) = user_id)` 꼴. `auth.uid()` 는 항상 `(select …)` 로 감싼다
- `auth.role()` 은 쓰지 않는다(deprecated). `to authenticated` 만으로는 인가가 아니다 — **소유자 조건을 반드시 붙인다.** 예외는 공개 참조 테이블 4개뿐이다: `universities`·`university_email_domains`·`region_group_settings`·`faq`. 이 중 `anon` 까지 여는 건 앞의 2개(`universities`·`university_email_domains`)뿐이고, 나머지 둘은 `authenticated` 전체까지만 연다(ERD.md §2)
- UPDATE 정책은 `using` + `with check` 둘 다 쓴다. UPDATE 는 SELECT 정책이 있어야 동작한다
- `user_metadata` 로 권한을 판단하지 않는다(사용자가 수정 가능). 권한 데이터는 `app_metadata`
- `security definer` 함수는 쓰지 않는다(권한 오류 우회용 금지). 뷰는 `with (security_invoker = true)`
- **클라이언트 쓰기 정책은 두지 않는다.** 쓰기는 전부 FastAPI가 `service_role`로 한다(2026-09-13 확정, ERD.md §11-8). `anon`·`authenticated`에는 INSERT·UPDATE·DELETE 권한 자체를 주지 않는다(42501로 끝난다)
- **grant는 RLS와 같은 마이그레이션에 둔다.** 새 테이블에 `anon`·`authenticated` 권한이 자동으로 붙는지는 프로젝트 설정마다 달라 믿지 않는다 — 테이블마다 `revoke all ... from anon, authenticated, service_role` 뒤에 ERD.md §2 표대로 `anon`·`authenticated`에는 필요한 `select`만 주고, `service_role`에는 `select`·`insert`·`update`·`delete`를 모두 준다. `service_role`까지 revoke하는 이유는 자동 grant 여부(프로젝트 설정·적용 시점)와 상관없이 결과를 같게 만들기 위해서다
- **클라이언트 Storage 정책은 두지 않는다.** 업로드·조회는 FastAPI가 발급하는 서명 업로드 URL·서명 URL로만 한다(2026-09-13 확정, ERD.md §9·§11-8)
- RLS 테스트는 pgTAP (`supabase/tests/*.sql`) — 다른 사용자로 조회 시 0행뿐 아니라, `anon`·`authenticated`·`service_role`·`PUBLIC`의 테이블·컬럼 권한(ACL), Storage 버킷·정책, 탈퇴 cascade까지 표대로 맞는지 검사한다. 기대값 기준은 ERD.md §2 (`frontend/CLAUDE.md` §8)
- **`realtime.messages`(Supabase 내장 Realtime 표)에 정책을 둘 때(2026-10-13, `20261013152736`)** — 위 "`public` 스키마" 규칙의 바깥이다
  - 정책은 마이그레이션(`postgres` 역할)으로 만들 수 있다. 표 · publication · grant 는 Supabase 가 관리하므로 건드리지 않는다
  - 토픽은 행의 `topic` 칸이 아니라 **`(select realtime.topic())`** 로 본다(Realtime 이 입장 때 세션에 건다). `auth.uid()` 처럼 `(select …)` 로 감싼다. 받기(`for select`)만 두고 **보내기(`for insert`) 정책은 만들지 않는다**(쏘는 쪽은 서버 `service_role` 뿐 — RLS 를 거치지 않는다)
  - 정책은 **입장 때 한 번 계산돼 연결 동안 캐시된다** — 방을 나간 사람처럼 "입장 뒤 바뀌는 권한" 을 정책으로 막을 수 없다. 서버가 쏘지 않는 것으로 막는다
  - **pgTAP**: `realtime.messages` 는 `inserted_at` **하루 단위 파티션 표**이고 기본 파티션이 없다(맞는 파티션이 없으면 넣기가 실패). 파티션은 Realtime 서비스가 며칠 앞까지 만들고 `postgres` 는 `realtime` 스키마에 표를 만들 권한이 없어 시험이 만들 수 없다 — 그래서 시험 행은 오늘 날짜가 아니라 **이미 있는 파티션 가운데 가장 늦은 날짜**로 넣는다(`supabase/tests/user_channel_realtime_policy_test.sql`, 파티션이 하나도 없으면 오류로 멈춘다). 받기 판정은 Realtime 과 같은 설정(`role` · `request.jwt.claim.sub` · `realtime.topic`)을 세션에 걸고 시험 행이 보이는지로 본다. 알려진 사소: 한 시험이 표 전체를 읽어 로컬에 다른 행이 있으면 거짓 FAIL 이 날 수 있다(후속으로 `where topic` 조건)

## 6. pgvector

- 조각 0 첫 마이그레이션(`20260913054542`) 맨 앞에서 `create extension if not exists vector with schema extensions;` 로 켰고, 2026-09-14 클라우드에 적용됐다. 대시보드에서 손으로 켜지 않는다. 조각 3 벡터 컬럼의 타입 주의는 `docs/ERD.md` §3

## 7. 학생증 재검토 — 대시보드 수동 확정

> **2026-10-19 표시: 이 절은 더는 쓰지 않는다(기록으로 남긴다).** 학생증 단계가 2026-10-17 사용자 결정으로 없어져(서버 PR #582 · 앱 PR #583) 새 학생증 재검토는 생기지 않는다. 졸업생 인증의 검수는 대시보드가 아니라 **관리자 웹 "졸업생" 화면**에서 하고(결정 즉시 사진 삭제 — 손으로 지울 일이 없다), 절차는 `backend/DEPLOY.md` §4-14 · `docs/decisions/2026-10-19-graduate-verification-decision.md` 에 있다. 옛 `student-id-temp` 파일 삭제는 사용자 승인 대기다.

자동 대조(OCR)가 애매하거나 실패하면 담당자가 Supabase 대시보드에서 학생증 사진을 직접 열어 육안으로 재검토한다(설계 §7.3). 자동 확정과 다르게 이 경로는 FastAPI를 거치지 않으므로, 사람이 손으로 아래 순서를 그대로 따라야 한다 — 순서를 바꾸면 안 되는 이유는 자동 경로와 같다: `student_verification_attempts` 를 먼저 확정하고 남에게 보이는 `profiles` 를 나중에 바꾼다(§11-27, 2026-09-20 결정).

1. **`student_verification_attempts`** 에서 해당 제출 행을 찾아 `result` 를 `verified` 또는 `rejected` 로 바꾸고, `reviewed_at` 을 지금 시각으로 채운다. `rejected` 면 `reject_reason` 도 채운다(본인에게 재검토 결과로 내려간다)
2. 같은 `profile_id` 의 **`profiles.student_verification`** 을 1번과 같은 값으로 바꾼다(자동 경로와 같은 순서 — attempts 먼저, profiles 나중)
3. ~~**`student-id-temp` 버킷에서 해당 파일을 Storage UI 로 손으로 지운다.**~~ **2026-10-11 사용자 결정으로 개정(PR #463)** — 종전 "대시보드 수동 확정은 자동 삭제 경로를 타지 않으므로 손으로 지운다". 지금은 **손으로 지우지 않는다.** 2번 저장으로 `profiles` 가 `pending` → `verified`/`rejected` 로 바뀌면 DB 트리거(`on_student_verification_reviewed`, `20261003030000`)가 FastAPI `/hooks/verification-reviewed` 를 부르고, 훅이 알림을 보내기 전에 그 사람의 **가장 최근 제출**을 읽어 `result` 가 `pending` 이 아니면 사진을 지운다(`app/student_verification/review_hook.py`). 훅이 못 지웠으면 매시 `chat-gate` 배치가 "검토가 끝났는데 버킷에 남은 사진"을 찾아 지운다(`backend/DEPLOY.md` §4-1). **그래서 1 → 2 순서가 그대로 중요하다** — `profiles` 를 먼저 바꾸면 훅이 읽는 시도가 아직 `pending` 이라 사진을 안 지운다(1번을 저장한 뒤 다음 정각 배치가 지운다)

**검토 대기 상한 30일(2026-10-11 사용자 결정, PR #463).** 제출하고 30일이 지나도 `pending` 인 시도는 매시 배치가 1 · 2 를 대신한다 — `student_verification_attempts` 를 `rejected` · `reject_reason` "검토 기한이 지나 사진을 삭제했어요. 학생증을 다시 올려 주세요" · `reviewed_at` 으로 닫고, 그 시도가 최근 제출이면 `profiles.student_verification` 도 `pending` 일 때만 `rejected` 로 바꾼 뒤 사진을 지운다. 사람이 이미 확정한 행은 건드리지 않는다. 그 사이 사람이 직접 검토하려면 30일 안에 위 1 · 2 를 끝낸다.

## 8. 실명 · 카카오톡 아이디 암호화 (2026-10-11, M1 `20261011010000` · PR #461 · #464 · #467 · 2026-10-12 M2 `20261012010000` · PR #474 · #476)

`profile_private.real_name` · `kakao_id` 를 전화번호(`phone_number`, `20260920043638`)와 같은 방식으로 암호화한다. 적용 · 백필 순서와 운영 기록은 `backend/DEPLOY.md` §4-4 가 기준이다.

**지금 상태(2026-10-12 M2 운영 적용 뒤)**: 평문 열 `real_name` · `kakao_id` 는 없다 — 실명 · 카톡 아이디는 암호문 `real_name_enc` · `kakao_id_enc` 에만 있다. 남은 함수는 `set_real_name` · `set_kakao_id` · `decrypt_profile_private` **셋**(`service_role` 전용)이다. `authenticated` 의 컬럼 grant 는 `profile_id` 하나만 남았다(`select (real_name)` 은 열과 함께 사라졌다). M2 파일은 DB PR #476 merge 대기(운영에는 적용됨). 아래 M1 때 쓴 서술 중 "함수 4개" · "이중 쓰기 기간" · "M2 는 아직" 은 2026-10-12 개정으로 바뀌었다(줄마다 표시).

- **새 열**: `real_name_enc` · `kakao_id_enc` — `bytea`, `extensions.pgp_sym_encrypt(평문, 키)` 암호문. 키는 전화번호와 **같은** `PHONE_ENCRYPTION_KEY`(FastAPI Secret Manager 전용, DB 에 두지 않는다). `authenticated` 에는 grant 하지 않는다(`20260914055617` 의 "이후 조각에서 컬럼을 추가해도 authenticated 에는 grant 하지 않는다"). 빈 문자열은 암호화하지 않고 null 로 둔다
- **함수 4개(2026-10-12 M2 뒤 3개)** — 모두 security invoker · `search_path = ''` · `public` · `anon` · `authenticated` 실행 회수 · **`service_role` 만 실행**. 키가 null · 빈 문자열이면 22023 오류(pgcrypto 는 null 키에 조용히 null 을 돌려줘 암호문이 덮이거나 복호화가 전부 null 로 보이기 때문)
  - `set_real_name(p_profile uuid, p_real_name text, p_key text) returns void` — upsert(행이 없으면 만든다. 가입 뒤 첫 쓰기가 실명이다)
  - `set_kakao_id(p_profile uuid, p_kakao_id text, p_key text) returns void` — update 전용(행이 없으면 0행. 서버가 `ensure_private_row` 로 먼저 보장한다)
  - `decrypt_profile_private(p_profile uuid, p_key text) returns table (real_name text, kakao_id text)` — 행이 없으면 0행, 암호문이 null 이면 그 값만 null. 틀린 키는 39000 오류. 본인 · 관리자 조회에만 쓴다
  - `backfill_profile_private_encryption(p_profile uuid, p_key text) returns void` — **임시, M2 에서 삭제.** 평문을 암호문 열로 옮기되 암호문이 이미 있는 열은 덮지 않는다(멱등). **2026-10-12 M2 로 운영에서 삭제됐다** — 이 함수를 부르던 일회용 스크립트 `backend/scripts/backfill_encrypt_profile_private.py` 는 죽은 코드다
- **키는 RPC 의 JSON 바디로만 넘긴다** — URL 쿼리스트링에 넣으면 웹서버 접근 로그에 남는다(전화번호와 같은 2026-09-20 승인 조건, `app/profile_onboarding/encryption.py`)
- **읽기 · 쓰기 규칙(2026-10-12 개정, PR #474 · 리비전 `00063` — 종전 "이중 쓰기 기간" 서술은 바로 아래에 기록으로 남긴다)**: **복호화 전용, 실패는 오류다.** 쓰기는 암호화 RPC(`set_real_name` · `set_kakao_id`) 하나뿐이고 실패하면 요청이 실패한다(삼키지 않는다). 읽기는 `core/postgrest.py` `_read_private` 한 곳이 `decrypt_profile_private` 로만 하고, 온보딩 진행 판단(`kakao_id_set`)도 같은 복호화 값을 본다. **복호화가 실패하면 None 으로 삼키지 않고 예외로 올린다** — None 이면 "아직 안 냈다" 로 보여 이미 낸 사람을 입력 화면으로 되돌리거나 상대에게 아이디가 없는 것처럼 보이기 때문이다. 복호화 실패 로그에는 `profile_id` · 상태 코드만 남긴다(예외 문구에 주소가 들어 있어 쓰지 않는다)
- ~~**서버(이중 쓰기 기간)**: 쓰기는 평문 열 + 암호문 열 둘 다(암호문 쓰기 실패는 요청을 실패시키지 않고 경고 로그만 — 백필이 메운다). 값을 내려주는 읽기(16e 계정 · 내 카톡 조회 · 채팅 신뢰 확인의 상대 카톡)는 `core/postgrest.py` `_read_private` 가 **복호화 값을 먼저 쓰고, 비었거나 복호화가 실패하면 평문 열로 폴백**한다. 온보딩 진행 판단(`kakao_id_set`, `profile_onboarding/repository.py`)만 반대로 평문을 먼저 보고 비었을 때 복호화로 확인한다. 로그에는 필드 이름 · profile_id · 예외 종류만 남긴다~~ (2026-10-11 ~ 10-12 리비전 `00059` ~ `00062` 의 동작 — 기록)
- ~~**M2(옛 평문 열 · 백필 함수 삭제)는 아직이다.**~~ **M2 는 2026-10-12 운영에 적용됐다**(파일 `20261012010000`, 운영 기록 버전 `20261012070722`, 파일은 DB PR #476 merge 대기). 순서는 계획대로 하네스 수정 → 평문 쓰기 · 폴백 읽기를 뺀 서버(`00063`) 배포 → 사용자 승인 → 적용이었고, 적용 뒤 `vacuum full public.profile_private` 를 돌렸다. 되돌릴 수 없고 사용자가 되살릴 백업도 없다(`backend/DEPLOY.md` §4-4 "M2 실행 기록")
- **적용 뒤 확인할 것 — 키 로그 노출**: `pg_stat_statements` · Postgres 로그에 `pgp_sym_encrypt` / `pgp_sym_decrypt` 의 키 인자가 `$1` 같은 자리표시자로만 보이는지, `log_statement` · `auto_explain` 이 인자 값을 남기지 않는지 본다(M1 머리말 1번). ~~점검 결과는 아직 기록이 없다~~ **점검 결과(2026-10-12, 대장 전달 값)**: `pg_stat_statements` 의 RPC 문장은 본문이 파라미터라 키가 평문으로 남지 않았고, 운영 `log_statement` 는 `ddl` 이다
- **대시보드에서 손으로 복호화해야 할 때**: `select * from public.decrypt_profile_private('<profile_id>', '<키>');` — 키를 SQL 창에 붙여넣는 일 자체가 감사 대상이라 실행 전후로 사유를 운영 기록에 남긴다(M1 머리말 3번). 평소 원칙은 그대로 "운영자는 `profile_private` 를 FastAPI 관리 기능으로만 본다"(ERD_DECISIONS §11-18)
