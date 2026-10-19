# 졸업생 인증(졸업증명서) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 학교 메일이 없는 졸업생이 졸업증명서 사진으로 인증받아, 학교 메일로 가입한 사람과 같은 상태(`university_id` · `school_email_verified_at`)로 가입을 이어 가게 한다.

**Architecture:** 가입 관문(동의 다음)에 "인증 방법 고르기"를 끼우고, 졸업생 길은 사진 신청 → 서버 글자 인식(미리 채우기 전용) → 관리자 웹 검수(사람이 발급 기관 사이트에서 번호로 진위 확인) → 승인 시 DB 함수 하나가 프로필 · 기록을 한 번에 바꾼다. 사진과 평문 값은 결정 즉시 지우고 해시만 남긴다. 서버 기능 플래그(기본 꺼짐)로 배포와 공개를 떼어 놓는다.

**Tech Stack:** FastAPI(PostgREST · Storage · Google Cloud Vision TEXT_DETECTION) · Supabase(Postgres + pgTAP) · Flutter(앱, Riverpod) · Flutter 웹(관리자). 새 의존성 0개(`pubspec.yaml` · `pyproject.toml` 수정 없음).

**Spec:** 별도 설계서 없음. 근거는 (1) 통합대장5 요청문(2026-10-19, 사용자 결정 C 방식 + 대장 결정 4 · 5) (2) 대장 추가 지시(가입 화면 "인증 방법 고르기" 두 파트) (3) 아래 0장 조사. 설계서가 없으므로 이 계획서의 판단은 모두 잠정이며 "대장 결정 필요"(10장)가 확정되면 본문을 고치지 않고 11장 "구현 편차 기록"에 덧붙인다.

---

## Global Constraints

- 사용자 지시(10-19): **운영 DB 적용 · 서버 배포 · 앱 빌드 · 스토어 업로드는 내일 아침 검토 뒤.** 이 계획서의 모든 "운영" 단계는 사용자 원문 승인 뒤에만 한다. 코드는 draft PR 까지만.
- 가입은 소셜 로그인(카카오 · 구글 · 애플) 그대로. **네이버 · 지메일 인증 코드는 넣지 않는다.**
- 글자 인식 결과는 **자동 승인에 쓰지 않는다.** 관리자 화면 미리 채우기와 중복 경고에만 쓴다.
- 이전 학교 이메일은 **`school_email_claims` · `signup_blocks` 에 쓰지 않는다**(읽기 전용 점검만). 신청자 응답은 그 메일의 선점 여부를 어떤 모양으로도 알려 주지 않는다.
- 사진 · 문서확인번호 평문 · OCR 글자 · 이전 학교 메일은 **결정(승인 · 반려 · 취소 · 만료)을 한 순간 지운다.** 남기는 것: 학교(`university_id`), 결정, 시각, 해시(`bytea`)만. 이름 · 학번 · 생년월일은 어디에도 저장하지 않는다(학번은 해시로만).
- 로그 · 디스코드 · `admin_actions` · 푸시 `data` 에 번호 · 이메일 · 학번 · OCR 글자 · 사진 경로를 쓰지 않는다. 신청 id 와 profile_id 만(COMMON §3).
- 관리자 쓰기 경로는 같은 요청 안에서 `admin_actions` 한 줄을 남기고, 기록이 실패하면 조치도 실패한다(기존 D1 규칙). `core/theme/*` · `common/widgets/*` · `pubspec.yaml` · `main.py` · `errors.py` · `settings.py` · `DESIGN.md` · `DEPLOY.md` 는 고치지 않는다(COMMON §4-1) — 필요하면 7장의 우회 방법을 쓴다. **예외: `core/router/{app_routes,auth_redirect,app_router}.dart` 는 우회할 수 없다**(새 관문 · 뒤로가기 라우팅). 대장이 이번 지시에 라우터 · 뒤로가기 반영을 명시했으므로 이를 요청으로 보되, 구현 시작 전에 대장이 허락을 한 번 확인해 주어야 한다(7장).
- SECURITY DEFINER 함수는 만들지 않는다(전부 `security invoker` + `revoke all ... from public, anon, authenticated` + `grant execute ... to service_role`). 혹시 하나라도 definer 가 필요해지면 같은 파일에 같은 revoke 를 처음부터 넣는다.
- 병렬 작업 충돌 회피: `feat/heart-task-multiphoto`(wt `feat-heart-task-multiphoto`)가 `backend/app/admin/repository.py` · `heart_tasks/*` · `tests/admin/admin_world.py` · `admin_heart_task_review` 를 고치는 중이다. 이 계획은 그 파일들을 **고치지 않고** 새 파일로만 간다. 앱 `ApiClient.sendMultipart` 와 `admin_web` `admin_api.dart` · `admin_router.dart` · `admin_section.dart` 는 양쪽이 만질 수 있어 나중에 머지하는 쪽이 합친다.
- 마이그레이션 타임스탬프는 multiphoto 의 `20261019100000` 뒤인 `20261019120000` · `20261019120100`.
- 시험 규칙: 새 비-private 클래스마다 시험(frontend/CLAUDE.md §8). PostgREST 가짜는 URL 부분 문자열이 아니라 `request.url.params` 키로 가르고, `get_settings` 오버라이드는 람다로 감싼다(메모 reference_backend_test_mock_traps).
- pgTAP(`supabase test db`)은 대장이 "DB 테스트 차례"를 준 때만(COMMON §4-1).

## Review Focus

1. **사진이 정말 사라지는가.** 승인 · 반려 직후 삭제가 실패하거나, DB 는 성공했는데 서버가 죽거나, 응답이 끊겨도 `photo_path` 가 남은 결정 행을 매시 배치가 반드시 지운다(Task 4 `test_batch_deletes_photo_of_decided_row_left_behind`). 신청 중 최대 14일 뒤에도 같다.
2. **평문이 결정 뒤 0인가.** 결정된 행에 OCR 번호 · OCR 학교 글자 · 이전 학교 메일이 있으면 DB check 가 거부한다(Task 1 `decided_row_with_plaintext_is_rejected`), 로그 · 디스코드 · `admin_actions` · 푸시 data 에 평문이 없다(Task 3 · 5 `test_logs_carry_ids_only`).
3. **남의 옛 학교 메일 선점 · 존재 노출 0.** 이전 메일이 이미 다른 계정 것이어도 신청자 응답 · 상태코드 · 문구가 같다. claims · blocks 에 쓰기 0(Task 3 `test_previous_email_never_written_and_response_is_identical`).
4. **신청 중 · 반려 직후 계정이 14일 정리 배치에 지워지지 않는다**, 탈퇴하면 신청 행 · 사진이 남지 않고, 졸업생 탈퇴 재가입 제한이 학번 해시로 걸린다(Task 1 `list_unverified_accounts_*`, Task 4 `test_withdraw_*`).
5. **옛 앱(vc11 · vc12)과 새 서버 · 플래그 꺼짐.** 선택값 null = 학교 메일, `/school-email/verify` 불변, 응답에 칸이 늘어도 옛 앱이 읽는 칸은 같다. 새 앱 + 플래그 꺼짐 = 지금 동작이고 02 는 화살표 없이 종료 안내 그대로(Task 3 `test_old_client_fields_unchanged`, Task 6 `flag_off_keeps_needs_school_email`, Task 7 `school_email_legacy_*`). 뒤로가기는 화살표 = 시스템 뒤로 = 같은 함수, 관문 화면마다 `BackExitScope` 한 겹, 스택 깊이 1(Task 6 `gate_screens_*`).

---

## 0. 조사 결과 (파일:줄 근거, 2026-10-19 main `b7a5d08c`)

### 0-1. 지금 가입 관문과 졸업생 길이 끼어들 자리

- 관문 순서: 정지 → 동의 → **학교 메일** → 학과 · 학번 → (온보딩). 서버 판정은 `GET /me/verification-status`(`backend/app/student_verification/router.py:16-37`)가 `consent` · `school_email_verified` · `has_school_info` 로 내려 준다. 앱은 `HttpVerificationGateRepository._toGateAfterConsent`(`frontend/lib/auth/model/http_verification_gate_repository.dart:30-35`)가 `school_email_verified == false` 일 때만 `needsSchoolEmail` 로 보낸다.
- 학교 메일 관문의 실제 닫힘: `require_school_email`(`student_verification/current_user.py:72-78`) = `profiles.school_email_verified_at is null` 이면 403. 온보딩 · 홈 · 매칭이 모두 쓰는 `get_verified_user_id`(`current_user.py:95-116`)가 이걸 부른다. 인증은 `POST /school-email/verify`(`school_email/router.py:191-235`)가 DB 함수 `complete_school_email_verification`(`20261008030000_create_school_email_claims.sql:78-139`)을 불러 `profiles.university_id` · `school_email_verified_at` 와 `school_email_claims`(학교 메일 HMAC 1개 = 계정 1개)를 쓰는 것으로 끝난다.
- **졸업생 승인은 같은 두 칸(`university_id` · `school_email_verified_at`)을 채우면 된다.** 그러면 `require_school_email` · 3c(학과) · 온보딩 · 매칭 후보(`university_id` 로 조인) · 홈 통계가 코드 변경 없이 학교 메일 사람과 같게 돈다. 추가로 `profiles.graduate_verified_at`(졸업생 표시용 내부 칸)과 `profiles.verification_method` 를 둔다.
- **`next_step` 은 바뀌지 않는다.** `profile_onboarding/onboarding_progress.py:5-30` 의 `next_step` 은 **관문 통과 뒤의 온보딩 단계**(basic_info → ... → avatar → complete)다. "인증 방법 고르기"는 온보딩이 아니라 **관문(`VerificationGate`)** 에 속한다 — `needsConsent` 다음, `needsSchoolEmail` 앞. 신청 중인 졸업생은 `get_verified_user_id` 가 403(SCHOOL_EMAIL_REQUIRED)으로 막아 온보딩 엔드포인트에 닿지 못한다(학교 메일 미인증과 같음). 그래서 `next_step` 판정 · 시험 · 앱 `OnboardingStep` 은 손대지 않는다.
- 두 길이 같은 진행 단계를 쓰는 법: 서버가 `school_email_verified`(= `school_email_verified_at is not null`)를 **두 길 공통의 "신분 인증 끝" 신호**로 계속 쓴다. 졸업생도 승인되면 이 값이 true → 앱 관문은 `needsSchoolInfo`(3c) → 온보딩으로 같은 길을 간다. 새로 생기는 관문 상태는 인증 전 구간(`needsVerificationMethod` · `needsGraduateApplication` · `graduateReviewing`)뿐이다.
- 14일 정리: `account/batch_router.py:24,71-74` 가 `list_unverified_accounts`(`20261018002907_exclude_admins_from_unverified_cleanup.sql:15-40`, `school_email_verified_at is null` + 14일)로 계정을 지우고, 지우기 직전 `is_still_unverified`(`account/repository.py:60-66`)로 재확인한다. **신청 중 · 반려 직후 졸업생은 이 조건에 그대로 걸려 14일 뒤 지워진다** → Task 1 · 4 가 막는다. 지울 때 비우는 버킷은 `STORAGE_BUCKETS`(`batch_router.py:32`) 4개 — 새 버킷을 추가해야 한다.
- 탈퇴: `account/router.py:43-51` 은 `school_email_claims` 의 해시를 `withdraw_account` 로 넘겨 `signup_blocks`(재가입 제한 2개월 · 정지 중이면 무기한)를 만든다. 해시가 없으면 null 이라 제한이 없다(`20261008040000_withdraw_account_without_email_hash.sql`). **졸업생은 claims 행이 없어 탈퇴하면 재가입 제한이 없다** — 정지된 졸업생이 탈퇴 후 바로 다시 가입하는 구멍이다. 해결: 승인 때 학번 해시(D5)를 받아 같은 `signup_blocks` 에 넘긴다(이름공간 접두사로 학교 메일 해시와 충돌 없음).

### 0-2. 옛 코드 — 남은 것과 지워진 것 (되살릴 수 있는 목록)

**서버에 남아 있어 그대로 쓰는 것**

| 파일 | 쓰는 것 |
| --- | --- |
| `student_verification/ocr.py` `VisionOcr.extract_text` | TEXT_DETECTION 전체 글자. 그대로 호출 |
| `student_verification/image_validation.py` | `student_id_content_type(data)` · `MAX_IMAGE_BYTES`(heart_tasks · me · onboarding 도 이미 import) |
| `core/deps.py:43` `get_vision_client_factory` | Vision 장애를 엔드포인트 안에서 잡으려고 "만드는 함수"를 주입 |
| `student_verification/current_user.py` | `reject_suspended` · `require_school_email` · `get_signed_in_user_id`(`get_caller` 뒤) |
| `student_verification/discord_notifier.py` `DiscordNotifier._send` | 실패를 삼키고 주소를 로그에 안 남기는 전송. 새 메서드 1개만 더함 |
| `student_verification/storage.py` `StudentIdStorage` | **모양만** 본뜬다(버킷 이름이 하드코딩) → 새 `GraduateCertStorage` 로 복사. `heart_tasks/storage.py:13` ponytail 주석의 "셋이 되면 합친다"는 multiphoto 머지 뒤 별도 정리(6장 이월) |
| `student_verification/retention.py` | "대기 상한 닫기 → 결정된 행의 남은 사진 지우기" 두 단계 구조와 멱등 · 예외 삼키기 규칙을 본뜬다 → 새 `graduate_verification/retention.py` |
| `cards/push.py` `notify()` · `admin/heart_task_notice.py` `send_result_notice` | 푸시 + 알림함 한 줄. `ResultNotice` 를 그대로 재사용 |

**삭제됐고 git 에서 꺼내 참고하는 것**

- 서버: `git show 42b79965^:backend/app/student_verification/router.py` — 업로드 → 시도 행 기록 → Vision(`GoogleAPIError · RuntimeError · TimeoutError · GoogleAuthError` 만 잡아 "글자 인식 실패"로 넘김) → 디스코드 → 삭제 실패 시 고아 알림(`_delete_or_report_orphan`)의 **순서와 예외 범위**(192줄). 테스트 686줄(`tests/student_verification/test_router.py`, 같은 커밋 직전)도 업로드 실패 · 행 기록 실패 때 사진 지우기 케이스의 본보기다.
- 앱: `git show fc1f66d3^:frontend/lib/auth/view/student_verification_screen.dart` 의 `_DocumentType.graduation` 안내 문구(`졸업증명서에 표기된 이름` · `이름·학교·졸업 일자가 선명하게 보여야 해요`, 178-181줄)와 대기 중 30초 폴링 · 반려 사유 배너 구조. **사진 고르기 → 압축 → 올리기 흐름은 지금 main 의 `billing/viewmodel/heart_task_submit_view_model.dart`(79줄)가 같은 모양이라 그 파일을 본보기로 쓰는 게 더 새롭다**(`pickFromGallery` 훅 · `compressToJpeg` · `discard`). 얼굴 검출(`face_detector.dart`)은 졸업증명서에 얼굴이 없어 쓰지 않는다(옛 `requireFace: false` 결정, 커밋 `299bd4b8`).
- 앱 `ImageCompressor` 는 압축본 이름 앞머리를 `student-id-` 로 그대로 둔다(`auth/model/image_compressor.dart:25`) → 졸업증명서 압축본도 `discardAll`(로그아웃 · 탈퇴)이 지운다. 그대로 재사용.

**운영에 그대로 남은 옛 자산 (건드리지 않음)**: 표 `student_verification_attempts`, 버킷 `student-id-temp`(안에 옛 학생증 사진이 남아 있을 수 있음 — 출시후_할일 1-1 에서 사용자 승인 뒤 삭제), 트리거 `on_student_verification_reviewed`, 훅 `POST /hooks/verification-reviewed`(`student_verification/review_hook.py`).

### 0-3. 옛 표 재사용 vs 새 표 — 추천: **새 표 `graduate_verification_requests` + 새 버킷 `graduate-cert-temp`**

| | `student_verification_attempts` 재사용 | 새 표 (추천) |
| --- | --- | --- |
| 칸 | `file_path` · `result(verification_status)` · `reject_reason` · 시각만. OCR 번호 · 이전 메일 · 학교 선택 · 해시 · 관리자 칸이 없어 **칸을 더해야 함** | 처음부터 필요한 칸 |
| 결과 의미 | enum `verification_status`(none · pending · verified · rejected)를 쓰므로 `cancelled` 없음. enum 값은 지울 수 없음(`ERD §8`) | text + check 라 값 추가가 마이그레이션 한 줄 |
| 상태 연결 | 옛 코드는 `profiles.student_verification` 을 같이 바꾸고, 바꾸는 순간 **옛 트리거가 "학생 인증을 다시 해 주세요" 푸시**를 쏨(`retention.py:33-34` 주석이 이미 이 함정을 적어 둠) | 프로필의 옛 칸을 건드리지 않음 |
| 출시 후 정리 | 옛 학생증 표 · 버킷 · 훅은 "출시후 정리" 대상 → 졸업생 코드와 한 덩어리면 못 지움 | 옛 것은 통째로 지울 수 있음 |
| 비용 | 마이그레이션 1개 절약 | 마이그레이션 2개 + 탈퇴 · 정리 버킷 목록에 한 줄 |

버킷도 같은 이유로 새로 만든다(`student-id-temp` 에는 지금 옛 학생증이 있을 수 있고 "사용자 승인 뒤 삭제" 대기 중 — 같은 버킷을 쓰면 그 삭제 대상 목록에 졸업증명서가 섞인다).

### 0-4. 중복 가입 방지 비교 — 추천: **(가) 문서번호 해시 + (나) 학번 해시를 함께, (나)는 서류에 학번이 있을 때 입력**

| | (가) 문서확인번호 HMAC 유일 | (나) 관리자가 확인한 학번 HMAC(학교 + 학번) 유일 |
| --- | --- | --- |
| 막는 것 | **같은 증명서를 두 계정에** (사진 돌려쓰기) | **같은 사람이 새로 발급받아 두 계정에** |
| 못 막는 것 | 발급할 때마다 번호가 달라서 같은 사람이 재발급하면 통과 | 서류에 학번이 안 찍힌 학교 · 학번이 다른 편입 · 대학원 |
| 개인정보 | 번호 평문은 검수 중에만, 해시만 남김 | 학번 평문은 요청 본문으로만 거쳐 서버에서 해시, DB · 로그에 평문 0 |
| 탈퇴 재가입 | 못 막음(번호 일회성) | `signup_blocks` 에 같은 해시로 제한을 걸 수 있음(정지 중 탈퇴 무기한 포함) |
| 약점 | 약함 | 학번 공간이 작아(학교당 10^6~10^8) **서버 HMAC 키가 새면 역산 가능** — 전화번호 해시와 같은 위험 수준(`identity_hmac_key`) |

추천 근거: (가) 단독은 "한 사람 한 계정"을 못 지킨다. (나) 단독은 학번이 없는 서류에서 빈다. 둘 다 두되 **(가)는 승인 시 필수 입력**(관리자가 어차피 번호로 진위 확인을 하므로 부담 없음), **(나)는 선택 입력**(서류에 있으면). 해시 입력은 접두사로 이름공간을 나눈다(`graduate-document|...`, `graduate-student|<university_id>|...`) — 학교 메일 해시(`hash_email`)와 같은 키를 쓰되 충돌 없음. 이 결정은 10장 D5.

### 0-5. 개인정보 처리방침 · 스토어 양식 · 법률 확인 (항목만, 문구는 쓰지 않는다)

**처리방침(노션) 변경 항목**: ① 수집 항목에 "졸업증명서 사진(졸업생 인증 선택 시)" · "이전 학교 이메일(선택)" · "문서확인번호(검수 중, 해시만 보관)" ② 수집 목적(졸업생 인증 · 중복 가입 방지) ③ 보유 기간: 사진 = 결정 즉시, 신청 중 최대 14일, 평문 번호 · 이전 메일 = 결정 즉시, 해시 = 계정 존속 + 탈퇴 후 재가입 제한 기간 ④ 처리 위탁 · 국외 이전: Google Cloud Vision(글자 인식), Supabase Storage(저장 지역 확인 필요) ⑤ 관리자 열람 기록 보관(`admin_actions` 2년) ⑥ 동의 방식(별도 동의 줄, D11).
**스토어 양식 변경 항목**: Google Play "데이터 보안" — 사진(수집, 기능에 필수 아님/선택 경로), 개인 정보 > 이메일 주소(이전 학교 메일, 선택), 삭제 요청 · 보관 설명 칸, 전송 중 암호화. 나아가 지금 양식의 "민감한 정보 아님 / 사진 · 신분 문서" 칸의 답을 다시 확정. Apple "앱 개인정보" — Photos or Videos(앱 기능 · 사용자와 연결), Contact Info > Email Address, 그리고 지금 "민감한 정보" 칸 재확인. **칸의 정확한 이름 · 분류는 스토어 현재 화면을 보고 확정해야 함(확인 못 함).** 앱 심사 메모(App Review notes)에 졸업생 경로 설명 · 심사 계정 안내 추가. FAQ(`20261017130000_faq_student_id_removal.sql`로 고친 5개) 중 인증 설명 문항 갱신.
**법률 확인 목록에 추가**: (a) 졸업증명서가 고유식별정보(주민등록번호 인쇄 여부) · 민감정보에 해당하는지, 마스킹 안내 필요 여부 (b) 별도 동의 필요 여부와 방식(신청 화면 동의 줄 vs 전체 재동의 `CONSENT_VERSION` 상향 — 상향은 전 계정 재동의라 비용 큼) (c) Google Cloud Vision 처리 위탁 · 국외 이전 고지 (d) 발급 기관 사이트에서 번호로 진위 조회가 "제3자 제공"에 해당하는지(우리는 조회만 함) (e) 이전 학교 이메일을 인증 안 된 채 받아 읽기 전용 대조하는 것의 목적 범위 (f) 학번 HMAC 이 개인정보(가명처리 정보)인지, 보유 기간 (g) 관리자 열람 기록 · 접근 통제 요건 (h) 위 변조 서류 제출 시 조치 약관 문구 (i) 반려 사유 알림이 개인정보 처리 결과 통지에 해당하는지.

---

## 1. 전체 설계 요약

### 1-1. 상태 흐름

```
[동의] → (verification_method 가 null)  → 방법 고르기: 카드 2개 중 하나를 고르고(앱 안 선택만) [다음]
          ├ 학교 메일 → 02(지금 그대로) → 03 인증번호 → 3c → 온보딩
          └ 졸업증명서 → 신청 폼 → [대기] → 승인 → 3c → 온보딩
                                    └ 반려 → 사유 + 다시 신청(횟수 제한)
뒤로: 신청 폼 · 반려 · 02(선택을 거쳐 온 경우)의 앱바 화살표 = 방법 고르기. 대기 · 방법 고르기에는 화살표 없음 (1-4)
```

카드를 누르는 것은 **앱 화면 안의 선택일 뿐 서버에 쓰지 않는다.** `[다음]`(카드를 고르기 전에는 비활성)을 눌러야 `PUT /me/verification-method` 가 나간다 — 카드를 눌러 보다 앱을 닫아도 서버 값이 바뀌지 않는다.

### 1-2. 선택값 저장 위치 — 추천: **서버 칸 `profiles.verification_method`**

| | 서버 칸 (추천) | 앱 상태(SharedPreferences) |
| --- | --- | --- |
| 기기 바꿈 · 재설치 | 유지 | 사라져 방법 고르기가 다시 뜸 |
| 관문 계산 | 서버 응답만으로 `VerificationGate` 가 정해져 `HttpVerificationGateRepository` 가 순수 함수로 남음 | 앱이 로컬 값을 섞어야 해 `VerificationGateListenable` 이 복잡해짐 |
| 시험 | pytest · pgTAP 로 닫힘 | 위젯 시험에 로컬 저장소 가짜가 필요 |
| 정리 · 통계 | 서버가 "졸업생 길 선택자"를 알아 정리 배치에서 지킬 수 있음 | 서버는 신청 행이 생겨야만 앎 |
| 비용 | 칸 1개 + `PUT` 1개 | 없음 |

**옛 앱 호환**: 값 `null` = 학교 메일로 간주. 옛 앱은 `PUT` 을 모르고, `verification-status` 의 새 칸을 읽지 않고, `school_email_verified` 만 본다. `POST /school-email/verify` · `complete_school_email_verification` 은 **건드리지 않는다**(선택값이 null 이든 `graduate_certificate` 이든 학교 메일 인증은 성공한다). 그 성공은 졸업생 신청을 무효로 만들 수 있으므로 Task 4 의 배치가 "이미 인증된 계정의 대기 신청"을 `cancelled(verified_otherwise)` 로 닫고 사진을 지운다. 승인 함수도 이미 인증된 프로필이면 CM409 `already_verified`.

### 1-3. 방법 바꾸기 — 추천: **승인 전까지 서버는 언제나 허용, 앱은 화살표가 있는 화면에서만, 승인 뒤 고정**

앱의 바꾸는 길은 사용자 확정 뒤로가기 규칙(1-4)뿐이다: 02 · 신청 폼 · 반려 화면의 화살표 → `PUT {"method": null}` → 방법 고르기. 이 세 화면에는 **대기 중인 신청이 없으므로**(대기 화면에는 화살표가 없다) 앱 길에서는 신청 취소 확인 시트가 필요 없다. 서버 `PUT` 은 그래도 대기 신청이 있으면(다른 기기 · 옛 앱) 신청을 `cancelled(switched)` 로 닫고 사진을 즉시 지운다 — 안전망이다. 대기 화면에서 신청을 취소하는 길은 **pen 에 없으면 앱에 만들지 않는다**(D8). 인증 뒤에는 학교 메일 인증과 같게 변경 금지(`already_verified`).

### 1-4. 뒤로가기 규칙 (사용자 확정, 대장 전달) — 기존 온보딩 뒤로가기 규칙(#575 · #579, DESIGN.md §8.8 "온보딩 뒤로가기")과 03 인증번호(#569 `verify_code_screen.dart`)와 **같은 방식**

(대장 메시지의 "#582 · #590 계열"은 학생증 제거 PR 이라 뒤로가기 규칙이 없다 — 실제 규칙은 위 #575 · #579 · #569 에 있어 그것을 따랐다.)

| 화면 | 앱바 화살표 | 안드로이드 시스템 뒤로 | iOS 왼쪽 가장자리 밀기 | 라우터 등록 |
| --- | --- | --- | --- | --- |
| 방법 고르기(첫 단계) | 없음 · 아래 "로그아웃" 링크 | 종료 안내 토스트(기존 `BackExitScope` 기본) | 없음 | `_ExitGuardedRoute`(래퍼가 감쌈) |
| 02 학교 메일 입력 — 선택을 거쳐 온 경우(게이트 `needsSchoolEmailChosen`) | **있음 → 방법 고르기** | 화살표와 같은 함수 | 없음 | `_PlatformRoute` + **화면이 스스로 `BackExitScope(onBack)`** (두 겹이면 종료 안내까지 뜸 — DESIGN.md §8.8 750-751줄) |
| 02 — 옛 방식(플래그 꺼짐 · 옛 서버, 게이트 `needsSchoolEmail`) | 없음(지금 그대로) | 종료 안내 | 없음 | 위와 같은 등록, `onBack` 만 null |
| 03 인증번호 | 있음 → 02 (지금 그대로) | 지금 그대로 | 없음 | 불변 |
| 졸업생 신청 폼 · 반려 변형 | **있음 → 방법 고르기** | 화살표와 같은 함수 | 없음 | `_PlatformRoute` + 화면이 스스로 `BackExitScope(onBack)` |
| 심사 대기(제출 뒤) | **없음** | 종료 안내 | 없음 | `_ExitGuardedRoute` |

- **화살표 = 시스템 뒤로 = 같은 함수** `backToMethodPicker`: ① 사진 올리는 중 · 이미 돌아가는 중이면 아무 일도 하지 않는다(화살표는 숨기지 않는다 — 온보딩 `isBusy` 규칙과 같다) ② `PUT {"method": null}` ③ 성공하면 관문을 다시 묻고 `AuthRedirect` 가 방법 고르기로 옮긴다(`context.go` 로 갈아끼움 — 03 `_backToEmail` 과 같은 패턴) ④ 실패(인터넷 없음)하면 그 자리에 머물며 짧은 안내만 띄운다. 서버 값이 `school_email`/`graduate_certificate` 인 채로 화면만 옮기면 리다이렉트가 도로 끌고 오므로, 서버 값을 먼저 비워야 한다.
- **iOS 왼쪽 가장자리 밀기는 없다**: 이 화면들은 `go`/리다이렉트로 갈아끼워 아래 화면이 없다(온보딩과 같은 이유). `push` 로 올리지 않는다 — 시험이 라우터 스택 깊이 1 을 확인한다.
- 방법 고르기 화면의 카드 선택 상태는 뷰모델(`selected`) 안에만 있다. 화살표로 돌아왔을 때 이전 선택을 미리 칠할지는 pen 이 정한다(P1).

### 1-5. 승인 한 번에 일어나는 일 (DB 함수 `admin_review_graduate_request`)

`admin_assert` → 신청 행 잠금(`pending` 아니면 CM409 `already_reviewed`) → 프로필 잠금(탈퇴면 CM409 `account_withdrawn`, 이미 인증됐으면 CM409 `already_verified`) → 승인이면 학번 해시가 `signup_blocks` 에 걸려 있으면 CM409 `rejoin_blocked` → 신청 행을 `approved`(학교 · 관리자가 확인한 번호 해시 · 학번 해시 · 시각)로 바꾸고 평문 칸 비움(같은 UPDATE) → 프로필 `university_id` · `school_email_verified_at` · `graduate_verified_at` · `verification_method` → `admin_actions` 한 줄. 해시 유일 위반은 CM409 `document_reused` · `student_reused`. 서버는 함수가 성공한 뒤에만 사진을 지우고 푸시한다.

---

## 2. 파일 목록

**새로 만든다**

| 경로 | 책임 |
| --- | --- |
| `supabase/migrations/20261019120000_graduate_verification_tables.sql` | 프로필 칸 2개 · 신청 표 · 버킷 |
| `supabase/migrations/20261019120100_graduate_verification_functions.sql` | 승인 · 반려 함수, `list_unverified_accounts` 교체 |
| `supabase/tests/graduate_verification_test.sql` | pgTAP |
| `backend/app/graduate_verification/{__init__,settings,messages,hashing,document_reader,storage,repository,retention,applicant_router}.py` | 졸업생 길 서버 본체 |
| `backend/app/admin/{graduate_review,graduate_repository,graduate_notice}.py` | 관리자 API · 읽기 전용 중복 점검 · 결과 알림 |
| `backend/tests/graduate_verification/test_*.py` · `backend/tests/admin/{graduate_world,test_admin_graduate}.py` | 시험 |
| `frontend/lib/graduate/{model,viewmodel,view}/...` | 앱 졸업생 길 |
| `admin_web/lib/graduate/*` | 검수 화면 |

**고친다**

| 경로 | 무엇을 |
| --- | --- |
| `backend/app/student_verification/router.py:16-37` | 응답 칸 추가 · `include_router(applicant_router)` 한 줄(main.py 를 안 건드리는 우회) |
| `backend/app/student_verification/schemas.py` | `VerificationStatusResponse` 칸 추가(기본값 있음) |
| `backend/app/student_verification/repository.py:17-19` | `fetch_gate_status` select 에 `verification_method,graduate_verified_at` |
| `backend/app/account/router.py:43-51,63` · `account/repository.py` | 탈퇴 때 졸업생 해시 사용 · 신청 취소 · 새 버킷 비우기 |
| `backend/app/account/batch_router.py:32,71-74` · `account/repository.py:60-66` | 새 버킷 · 신청 중 계정 제외 재확인 |
| `backend/app/chat/batch_router.py:107-115` | 매시 배치에 졸업생 사진 정리 한 줄(기존 try/except 모양) |
| `backend/app/admin/router.py` | `include_router(graduate_review.router)` 한 줄 |
| `backend/app/student_verification/discord_notifier.py` | `notify_graduate_request(request_id, profile_id)` 메서드 1개 |
| `frontend/lib/auth/model/verification_gate.dart` · `http_verification_gate_repository.dart` · `auth/view/sign_up_screen.dart`(02: 선택을 거쳐 온 경우에만 앱바 화살표 + 화면이 스스로 `BackExitScope(onBack)`, 옛 방식은 지금 그대로) · `core/push/push_route.dart` · `push_refresh.dart` | 관문 · 02 뒤로가기 · 푸시 |
| `frontend/lib/core/router/{auth_redirect,app_router,app_routes}.dart` | 새 관문 4개의 목적지 · `_isOnGate` · 경로 상수 4개 · 라우트 등록(방법 고르기 · 대기 = `_ExitGuardedRoute`, 신청 폼 = `_PlatformRoute`, **로그인(02) 등록을 `_ExitGuardedRoute` → `_PlatformRoute` 로 바꿈** — 화면이 스스로 `BackExitScope` 를 두르므로). **`core/router/*` 는 공유 파일(COMMON §4-1)이다.** 대장의 뒤로가기 · 라우터 반영 지시를 이 수정의 요청으로 보되, 구현 시작 전에 대장이 허락을 한 번 더 확인해 준다. 허락이 없으면 경로 상수는 `graduate/model/graduate_routes.dart` 에 두고 나머지는 멈춰 보고 |
| `admin_web/lib/{shell/admin_section,router/admin_router,api/admin_api}.dart` | 메뉴 1개 · 경로 · API 메서드 |

---

## 3. API 계약

### 3-1. 신청자(앱) — 모두 로그인(`get_caller`) + 정지 거절 + 동의 확인 뒤

| 경로 | 요청 | 성공 | 실패 |
| --- | --- | --- | --- |
| `GET /me/verification-status` (기존) | — | 기존 칸 불변 + 아래 표 | — |
| `PUT /me/verification-method` | JSON `{"method": "school_email" \| "graduate_certificate" \| null}` | 200 `{"verification_method": ..., "cancelled_request": bool}` | 403 `graduate_disabled`(플래그 꺼짐 + graduate 요청) · 403 정지 · 403 동의 전 · 409 `already_verified` · 401 |
| `POST /graduate-verification` | multipart `photo`(파일), `agreed`("true" 필수), `previous_school_email`(선택) | 201 `{"state":"pending","attempts_left":int}` | 400 사진 못 읽음 · 400 `previous_email_invalid`(형식만) · 400 `consent_required` · 403 `graduate_disabled` · 403 방법이 `graduate_certificate` 아님(`method_mismatch`) · 409 이미 대기 · 409 `already_verified` · 429 `attempts_exhausted` |

`verification-status` 새 칸(옛 칸은 값 · 모양 불변, 새 칸은 모두 기본값이 있어 옛 서버 응답과 호환):

| 칸 | 값 | 비고 |
| --- | --- | --- |
| `graduate_enabled` | bool | 서버 플래그. false 면 새 앱도 방법 고르기를 숨김 |
| `verification_method` | `"school_email"` \| `"graduate_certificate"` \| null | null = 아직 안 고름 |
| `graduate` | null \| `{"state":"pending"\|"rejected","reject_reason":코드\|null,"attempts_left":int,"submitted_at":ISO\|null}` | `verification_method == graduate_certificate` 이고 미인증일 때만 계산(그 밖의 사람은 추가 읽기 0회) |

반려 사유 코드(제안, 문구는 D10 확정 뒤): `unreadable` · `not_certificate` · `unverifiable` · `school_unsupported`.
`attempts_left = max(0, 3 − (만료로 닫힌 것 빼고 센 신청 수))`(상한은 D3).

### 3-2. 관리자(웹) — 모두 `get_admin_caller`(aal2 + 명단) 뒤, prefix `/admin/graduate-requests`

| 경로 | 요청 | 응답 |
| --- | --- | --- |
| `GET ""` | `status=pending\|approved\|rejected\|cancelled`(기본 pending), `limit` 1..100 | `{"items":[{id,status,reason,created_at,decided_at,attempt_no,profile_id}]}` 오래된 순 |
| `GET /{id}` | — | 아래 상세 |
| `POST /{id}/approve` | `{"university_id": uuid, "document_number": str(4..40), "student_number": str(1..20)\|null}` | 상세(결정 뒤라 사진 · 평문 없음) |
| `POST /{id}/reject` | `{"reason": 코드 4개 중 하나}` | 상세 |

상세 필드: `id, status, reason, created_at, decided_at, attempt_no, profile_id, photo_url(5분 서명 | null), ocr{state:"read"|"nothing_found"|"failed", document_number|null, school_text|null, suggested_university_ids:[uuid]}, previous_school_email|null, warnings:[{code:"school_email_in_use", profile_id, profile_status} | {code:"school_email_rejoin_blocked"} | {code:"document_seen", profile_id}], history:[{status,reason,decided_at}≤5]`. 결정된 행은 `photo_url` · `ocr` · `previous_school_email` 이 null(평문이 이미 없음). `storage_path` · 해시 · 학번은 어떤 응답에도 없다. 오류 코드 문자열(`detail`): `not_found` 404 · `already_reviewed` 409 · `already_verified` 409 · `account_withdrawn` 409 · `document_reused` 409 · `student_reused` 409 · `rejoin_blocked` 409 · 형식 422.
학교 고르기 목록은 기존 `GET /admin/universities`(`admin/stats.py:51`)를 쓴다.

---

## 4. Tasks

> 모든 Task 의 마지막 단계: 새 비-private 클래스 시험 존재 확인 → 해당 명령 재실행 → 커밋 제안 목록에 넣음(커밋은 campus-git 몫). backend pytest: 워크트리 `backend/` 에서 `C:/Users/user/AndroidStudioProjects/campus_mate_compose/backend/.venv/Scripts/python.exe -m pytest -q <경로>`; 먼저 `-c "import app; print(app.__file__)"` 로 이 워크트리를 읽는지 확인.

### Task 1: DB (마이그레이션 2개 + pgTAP)

**Files:**
- Create: `supabase/migrations/20261019120000_graduate_verification_tables.sql`, `supabase/migrations/20261019120100_graduate_verification_functions.sql`, `supabase/tests/graduate_verification_test.sql`
- Modify(권한 목록 시험): `supabase/tests/rls_slice0_test.sql`(표 목록을 세는 단언이 있으면 한 줄), `supabase/tests/social_login_test.sql` 5절은 건드리지 않고 새 시험 파일에서 `list_unverified_accounts` 를 검증

**Interfaces:**
- Produces(표): `public.graduate_verification_requests(id uuid pk default gen_random_uuid() · profile_id uuid not null → profiles on delete cascade · status text · reason text · photo_path text · ocr_state text check(read|nothing_found|failed) · ocr_document_number text · ocr_school_text text · previous_school_email text(길이 ≤254) · document_hmac bytea · student_hmac bytea · key_version smallint default 1 · university_id uuid → universities · consented_at timestamptz not null · decided_by uuid(FK 없음, admin_actions 와 같음) · decided_at · created_at default now())`.
- check: `status in (pending,approved,rejected,cancelled)`; **상태쌍**(pending: reason · decided_* · university 모두 null / approved: university · document_hmac · decided_* 있음, reason null / rejected: reason ∈ 코드 4개 + decided_* / cancelled: reason ∈ (switched,expired,verified_otherwise,account_withdrawn), decided_at 있음, decided_by null); **`status='pending' or (ocr_document_number is null and ocr_school_text is null and previous_school_email is null)`**; `student_hmac is null or status='approved'`.
- 인덱스: unique `(profile_id) where status='pending'`(`graduate_requests_one_pending_key`); unique `(document_hmac) where status='approved'`(`graduate_requests_document_approved_key`); unique `(student_hmac) where status='approved'`(`graduate_requests_student_approved_key`); `(created_at) where status='pending'`; `(profile_id, created_at desc)`.
- 프로필 칸: `verification_method text check (in school_email,graduate_certificate)`, `graduate_verified_at timestamptz`, check `graduate_verified_at is null or school_email_verified_at is not null`.
- 권한: RLS 켬 · 정책 0 · `revoke all ... from anon, authenticated, service_role` 뒤 service_role 에 select · insert · update · delete(`school_email_claims` 와 같은 관례).
- 버킷: `graduate-cert-temp` 비공개 · 10MB · jpeg/png.
- Produces(함수): `public.admin_review_graduate_request(p_admin uuid, p_request uuid, p_status text, p_reason text, p_university uuid, p_document_hmac bytea, p_student_hmac bytea, p_key_version smallint, p_ip inet) returns jsonb` `{id, profile_id, status, reason, university_id, decided_at}` — 오류: 22023(규칙 위반) · 42501(관리자 아님) · CM404 · CM409(메시지 = `already_reviewed|already_verified|account_withdrawn|document_reused|student_reused|rejoin_blocked`). `list_unverified_accounts(integer, integer)` 교체(`20261018002907` 정의 그대로 + **대기 신청이 있거나 14일 안에 결정된 신청이 있는 프로필 제외**).
- 모든 함수 `security invoker`, `set search_path = ''`, `revoke all ... from public, anon, authenticated` + `grant execute ... to service_role`.

- [ ] **Step 1: 실패하는 pgTAP 를 먼저 쓴다** (`supabase/tests/graduate_verification_test.sql`, `begin; select plan(N);` 모양은 `admin_heart_task_review_test.sql` 을 따른다). 시험과 핵심 단언:

| 시험 | 핵심 assert |
| --- | --- |
| `table_is_locked_down` | RLS 켬, `pg_policies` 0행, `has_table_privilege('anon'/'authenticated', ..., 'select')` false, service_role 4권한 true, 버킷 존재 · `public=false` · `file_size_limit=10485760` |
| `decided_row_with_plaintext_is_rejected` [RF2] | `rejected` 인데 `previous_school_email` 이 있으면 `23514`; `approved` 인데 `ocr_document_number` 가 있으면 `23514`; `pending` 은 허용 |
| `state_pairs_are_enforced` | `approved` 에 `university_id` 없음 → 23514; `rejected` 에 사유 없음 · 알 수 없는 사유 → 23514; `cancelled` 에 사유 없음 → 23514; `pending` 에 `decided_at` → 23514 |
| `one_pending_per_profile` | 같은 프로필에 pending 둘 → `23505`; 하나가 rejected 면 새 pending 허용 |
| `approved_hashes_are_unique_but_rejected_may_repeat` | 승인된 같은 `document_hmac` 둘 → 23505, 같은 `student_hmac` 둘 → 23505; rejected 끼리 같은 해시 허용 |
| `approve_sets_profile_and_clears_plaintext` | 호출 뒤 `profiles.university_id=p_university`, `school_email_verified_at is not null`, `graduate_verified_at is not null`, `verification_method='graduate_certificate'`; 신청 행 `status='approved'` · 평문 3칸 null · `decided_by=p_admin`; 반환 jsonb 에 `status:'approved'` |
| `approve_writes_one_action_without_secrets` | `admin_actions` 1줄 `action='graduate_approve'`, `target_type='graduate_request'`, `after::text` 에 hmac · 번호 · 학번 문자열 없음, `after->>'has_student_hmac'` 가 true/false |
| `reject_needs_reason_and_approve_forbids_it` | 반려 + 사유 null → 22023; 승인 + 사유 → 22023; `p_status='pending'` → 22023; 반려 뒤 프로필 불변 · 평문 null |
| `second_review_is_409` | 이미 결정된 행 → CM409 `already_reviewed`; 없는 id → CM404 |
| `non_admin_cannot_review` | `admin_users` 에 없는 id → 42501 |
| `already_verified_profile_is_409_and_nothing_changes` | 학교 메일로 이미 인증된 프로필 → CM409 `already_verified`, 신청 행 pending 그대로 |
| `withdrawn_profile_is_409` | 탈퇴 프로필 → CM409 `account_withdrawn` |
| `reused_document_or_student_is_409_and_rolls_back` | 이미 승인된 같은 해시 → CM409 `document_reused` / `student_reused`, 프로필 · 신청 모두 불변, `admin_actions` 증가 0 |
| `blocked_student_hash_is_409` | `signup_blocks` 에 같은 해시(blocked_until 미래) → CM409 `rejoin_blocked`; 과거면 통과 |
| `functions_are_not_callable_by_clients` | `has_function_privilege('anon'/'authenticated', ..., 'execute')` false, service_role true; `prosecdef` false |
| `profile_columns_checks` | `verification_method='x'` → 23514; `graduate_verified_at` 만 있고 `school_email_verified_at` 없음 → 23514 |
| `list_unverified_accounts_skips_open_and_recent_graduate_requests` [RF4] | 20일 전 가입 미인증: 대기 신청 있음 → 제외; 13일 전 반려 → 제외; 15일 전 반려 → 포함; 신청 없음 → 포함; 관리자 제외 유지 |

- [ ] **Step 2: 실패 확인** — `supabase test db`(대장의 "DB 테스트 차례"에서만). Expected: 새 파일 전부 FAIL(`relation ... does not exist`), 기존 파일은 PASS.
- [ ] **Step 3: 마이그레이션 2개를 쓴다.** 구현 메모: 승인 함수는 `unique_violation` 을 `exception when unique_violation` 블록에서 `get stacked diagnostics v_constraint = constraint_name` 으로 읽어 위 이름에 따라 CM409 메시지를 나눈다(예외 블록은 부분 롤백이므로 `admin_actions` 삽입은 예외 블록 밖 성공 경로에서만). 프로필은 `for update` 로 잠근 뒤 `school_email_verified_at is not null` 확인. `admin_actions` 의 `after` 는 `jsonb_strip_nulls(status, university_id, reason, has_student_hmac)`. 파일 머리에 "서버가 마이그레이션보다 먼저 배포되면 PATCH 가 칸 없음으로 실패하므로 DB 먼저"를 적는다.
- [ ] **Step 4: 통과 확인** — `supabase test db` Expected: 전체 PASS(기존 ~1000개 + 새 N개), 보고에 docker 비정상 컨테이너 한 줄.
- [ ] **Step 5: 커밋 제안** — "✨ feat(db): 졸업생 인증 신청 표 · 버킷 · 프로필 칸" / "✨ feat(db): 졸업생 승인 · 반려 함수와 14일 정리 제외" / "✅ test(db): 졸업생 인증 pgTAP".

### Task 2: 서버 순수 모듈 (해시 · 판독 · 저장소)

**Files:** Create `backend/app/graduate_verification/{__init__,settings,messages,hashing,document_reader,storage,repository}.py`, `backend/tests/graduate_verification/{__init__,test_hashing,test_document_reader,test_storage,test_repository,test_settings}.py`

**Interfaces:**
- `settings.py`: `class GraduateSettings(BaseSettings)`(`AdminWebSettings` 모양, env `GRADUATE_VERIFICATION_ENABLED`, **기본 False**) · `graduate_enabled() -> bool`. `settings.py`(공유)는 고치지 않는다.
- `messages.py`: 문구 상수(`PREVIOUS_EMAIL_INVALID` · `CONSENT_REQUIRED` · `GRADUATE_DISABLED` · `METHOD_MISMATCH` · `ATTEMPTS_EXHAUSTED` · 반려 사유 코드 집합 `REJECT_REASONS`, 취소 사유 집합). `core/errors.py` 는 공유라 고치지 않는다(합치기는 대장 허락 시).
- `hashing.py`: `normalize_document_number(raw: str) -> str | None`(공백 · 하이픈 제거, 영문 대문자, 영숫자 4~40자 아니면 None) · `hash_document_number(secret: str, number: str) -> bytes` · `normalize_student_number(raw: str) -> str | None` · `hash_student_number(secret: str, university_id: str, student_number: str) -> bytes`. 입력 접두사 `graduate-document|` · `graduate-student|` 로 `hash_email` 과 이름공간을 나눈다. 반환을 DB 에 넘길 때는 기존 `bytea_literal`(`signup_policy.py:37`).
- `document_reader.py`: `class CertificateReading(NamedTuple): document_number: str | None; school_names: tuple[str, ...]` · `read_certificate(text: str, university_names: Sequence[str]) -> CertificateReading`. 번호는 라벨(`문서확인번호` · `확인번호` · `발급번호`) 뒤 같은 줄 또는 다음 한 줄의 영숫자 덩어리를 `normalize_document_number` 로 정리. 학교는 공백 제거 · 소문자 정규화한 글자 포함 여부(`matching.py:_normalize` 와 같은 규칙, 그 비공개 함수는 import 하지 않고 복사).
- `storage.py`: `class GraduateCertStorage(storage_url, service_role_key, client)` — `upload(profile_id: UUID, request_id: UUID, data: bytes, content_type: str) -> str`(경로 `{profile_id}/{request_id}.jpg|png`), `delete(path: str) -> bool`(404 = True, 예외 삼킴), `list_paths() -> list[str]`, `create_signed_url(path: str, expires_in: int) -> str`. 상수 `BUCKET = "graduate-cert-temp"`.
- `repository.py`: `class GraduateRequestRepository(PostgrestRepository)`:
  `insert_pending(*, request_id: UUID, profile_id: UUID, photo_path: str, ocr_state: str, ocr_document_number: str | None, ocr_school_text: str | None, previous_school_email: str | None, document_hmac: bytes | None, key_version: int) -> None`
  `fetch_latest(profile_id) -> dict | None` · `fetch_pending(profile_id) -> dict | None` · `count_attempts(profile_id) -> int`(`cancelled+expired` 제외)
  `cancel_pending(profile_id, reason: str, now) -> dict | None`(한 PATCH 로 `status=cancelled`, 사유, `decided_at`, 평문 3칸 null — 돌려주는 행에 `photo_path`)
  `clear_photo_path(request_id) -> None`
  `fetch_pending_older_than(cutoff, limit) -> list[dict]` · `fetch_decided_with_photo(limit) -> list[dict]`
  `fetch_method(profile_id) -> str | None` · `set_method(profile_id, method: str | None) -> None`
  `fetch_university_names() -> list[dict]`(id · name)

- [ ] **Step 1: 실패하는 시험을 쓴다.**

| 시험 | 핵심 assert |
| --- | --- |
| `test_hashing_is_domain_separated` | 같은 문자열 `"1234"` 를 `hash_email` · `hash_document_number` · `hash_student_number` 로 해시하면 셋이 모두 다르다; 키가 다르면 다르다; 길이 32 |
| `test_document_number_variants_hash_the_same` | `"1234-5678 9012-3456"` · `"1234567890123456"` · 소문자 영문 섞인 값이 같은 정규화 · 같은 해시; `"12"`(너무 짧음) · 한글 섞임 → `None` |
| `test_student_hash_depends_on_university` | 같은 학번 · 다른 `university_id` → 다른 해시; 앞뒤 공백 · 소문자 → 같은 해시 |
| `test_reader_takes_number_after_label_on_same_or_next_line` | `"문서확인번호 : 1234-5678-9012-3456"` · `"문서확인번호\n1234 5678 9012 3456"` → `"1234567890123456"`; 라벨 없음 → None |
| `test_reader_never_takes_a_number_from_unrelated_digits` | 전화 · 날짜(`2024.02.20`) 만 있는 글 → None |
| `test_reader_finds_school_names_contained_ignoring_spaces` | `"서 울 대 학 교"` 와 이름 목록 `["서울대학교","서울과학기술대학교"]` → `("서울대학교",)`; 부분 겹침(`"서울대학교"` ⊂ `"서울대학교사범대"`)은 둘 다 반환하지 않고 가장 긴 일치만 |
| `test_reader_on_empty_text` | `""` → `CertificateReading(None, ())` |
| `test_storage_upload_path_and_extension` | `{profile}/{request}.png`(PNG 일 때) · `.jpg`; 요청 헤더 `Content-Type` 은 판정값 |
| `test_storage_delete_treats_404_as_deleted_and_swallows_network_errors` | 404 → True, 500 → False, `httpx.ConnectError` → False |
| `test_storage_signed_url_is_absolute` | 상대 경로 응답 앞에 storage_url 이 붙음 |
| `test_repository_uses_param_keys` | 가짜가 `request.url.params` 키로 가름(`profile_id` ≠ `id`); `count_attempts` 가 `reason=neq.expired` 를 거는 대신 서버에서 센 값 검증 |
| `test_cancel_pending_nulls_plaintext_in_one_patch` | PATCH 본문에 `ocr_document_number`·`ocr_school_text`·`previous_school_email` 이 `None`, 필터에 `status=eq.pending` |
| `test_graduate_enabled_defaults_off` | env 없음 → False; `GRADUATE_VERIFICATION_ENABLED=true` → True |

- [ ] **Step 2: 실패 확인** — `... -m pytest -q backend/tests/graduate_verification` Expected: ImportError/Collection 실패(모듈 없음).
- [ ] **Step 3: 구현.** `read_certificate` 의 번호 정규식과 "가장 긴 일치만"이 알고리즘이라 시험이 결정한다. 나머지는 시그니처대로.
- [ ] **Step 4: 통과 확인** — 같은 명령 Expected: 위 시험 전부 PASS, 기존 `tests/student_verification` 도 PASS.
- [ ] **Step 5: 커밋 제안** — "✨ feat(graduate): 해시 · 서류 판독 · 저장소 · 설정" / "✅ test(graduate): 위 시험".

### Task 3: 서버 신청자 API (방법 고르기 · 신청 · 상태 칸)

**Files:** Create `backend/app/graduate_verification/applicant_router.py`, `backend/tests/graduate_verification/{test_method_router,test_apply_router,test_status_fields}.py`; Modify `student_verification/{router,schemas,repository}.py`, `student_verification/discord_notifier.py`

**Interfaces:**
- Consumes: Task 2 의 `GraduateRequestRepository` · `GraduateCertStorage` · `read_certificate` · `hash_document_number` · `graduate_enabled`; 기존 `get_caller` · `reject_suspended` · `require_current_consent` · `get_vision_client_factory` · `student_id_content_type` · `VisionOcr`.
- Produces: `applicant_router.router`(경로 3-1), `VerificationStatusResponse` 새 칸(`graduate_enabled: bool = False`, `verification_method: Literal[...] | None = None`, `graduate: GraduateState | None = None`), `DiscordNotifier.notify_graduate_request(request_id: UUID, profile_id: UUID) -> None`.

- [ ] **Step 1: 실패하는 시험.** (`graduate_world.py` 같은 가짜 PostgREST 를 시험 파일 안에 둔다 — `admin_world.py` 는 건드리지 않는다.)

| 시험 | 핵심 assert |
| --- | --- |
| `test_old_client_fields_unchanged` [RF5] | 새 칸이 있어도 `status=="verified"` · `reject_reason is None` · `school_email_verified` · `has_school_info` · `consent` 값이 예전 시험(`test_router.py`)과 같고, 플래그 꺼짐 + method null → `graduate_enabled false` |
| `test_status_reads_graduate_state_only_for_graduate_method_unverified` | method=school_email 인 사람 · 인증 끝난 사람 → `graduate_requests` 읽기 호출 0회; graduate 선택자만 1회 |
| `test_status_graduate_pending_and_rejected_shapes` | pending → `{"state":"pending","reject_reason":null,"attempts_left":2}`; rejected(`unreadable`) → `reject_reason:"unreadable"` |
| `test_put_method_requires_login_consent_and_not_suspended` | 정지 → 403 + `X-Account-Status: suspended`; 동의 전 → 동의 403; 탈퇴 → 401 |
| `test_put_method_sets_and_clears_value` | `graduate_certificate` · `school_email` · `null` 각각 `profiles.verification_method` PATCH |
| `test_put_method_rejects_verified_person` | `school_email_verified_at` 있음 → 409 `already_verified`, PATCH 0회 |
| `test_put_graduate_when_flag_off_is_403` [RF5] | 플래그 꺼짐 → 403 `graduate_disabled`, `school_email`/`null` 은 허용 |
| `test_switching_away_cancels_pending_request_and_deletes_photo` | 대기 신청이 있으면 `cancel_pending(…, "switched")` → 스토리지 DELETE → `clear_photo_path`; 응답 `cancelled_request:true`; 삭제가 실패해도 200 이고 `photo_path` 는 남음 |
| `test_apply_happy_path_runs_ocr_stores_hint_and_notifies_discord` | 201; 업로드 경로 `{profile}/{request}.jpg`; `insert_pending` 이 OCR 번호 · 학교 글자 · 번호 해시를 받음; 디스코드 한 번(본문에 profile_id · request_id 만) |
| `test_apply_validates_before_uploading` | 사진 아님 · 10MB 초과 → 400 이고 업로드 0회; `agreed` 없음 → 400 `consent_required`; method 가 graduate 아님 → 403 `method_mismatch`; 이미 pending → 409; 인증됨 → 409; 시도 3회 소진 → 429 |
| `test_apply_survives_vision_failure` | Vision 이 `GoogleAPIError`/`RuntimeError`/`TimeoutError`/`GoogleAuthError` → 201, `ocr_state="failed"`, 번호 null; **그 밖의 예외(우리 버그)는 500 으로 올라간다** |
| `test_apply_rolls_back_photo_when_row_write_fails` | `insert_pending` 이 실패하면 방금 올린 사진을 지우고 원래 오류를 올림 |
| `test_previous_email_never_written_and_response_is_identical` [RF3] | 이전 메일이 이미 claims 에 있든 없든 응답 상태 · 본문 · 호출한 PostgREST 경로가 같다(claims · signup_blocks 에는 읽기 · 쓰기 호출 0회; 제출 시점에는 중복 점검 자체를 하지 않는다); 형식 틀리면 400 `previous_email_invalid`, `+` 별칭 · 도메인은 검사하지 않는다 |
| `test_logs_carry_ids_only` [RF2] | 성공 · Vision 실패 · 삭제 실패 경로의 `caplog` 에 번호 · 이메일 · OCR 글자 · 사진 경로가 없음 |
| `test_double_submit_race_is_409` | `insert_pending` 이 `one_pending_key` 23505 를 받으면 사진을 지우고 409 |

- [ ] **Step 2: 실패 확인** — Expected: FAIL(라우트 없음 404, 새 칸 없음).
- [ ] **Step 3: 구현.** 시그니처: `async def put_verification_method(body: MethodBody, caller: Caller = Depends(get_caller)) -> dict`, `async def apply(photo: UploadFile = File(), agreed: bool = Form(), previous_school_email: str | None = Form(default=None), caller: Caller = Depends(get_caller), make_vision_client = Depends(get_vision_client_factory)) -> dict`. 관문 순서는 정지 → 동의 → 플래그 → 방법 → 인증됨 → 대기 중 → 시도 횟수 → 사진. 사진은 `photo.read(MAX_IMAGE_BYTES + 1)`. 번호 해시는 OCR 값이 있을 때만(검수 때 관리자 값으로 교체). `student_verification/router.py` 에 `router.include_router(applicant_router)` 한 줄. `fetch_gate_status` select 에 두 칸 추가.
- [ ] **Step 4: 통과 확인** — `pytest -q backend/tests/graduate_verification backend/tests/student_verification` Expected: PASS.
- [ ] **Step 5: 커밋 제안** — "✨ feat(graduate): 인증 방법 선택 API와 상태 응답 칸" / "✨ feat(graduate): 졸업증명서 신청 API" / "✅ test(graduate): 신청자 API".

### Task 4: 서버 생명주기 (정리 · 탈퇴 · 만료 배치)

**Files:** Create `backend/app/graduate_verification/retention.py`, `backend/tests/graduate_verification/{test_retention,test_lifecycle}.py`; Modify `backend/app/account/{router,batch_router,repository}.py`, `backend/app/chat/batch_router.py`

**Interfaces:**
- Produces: `retention.PENDING_LIMIT = timedelta(days=14)`(D16) · `async def purge_graduate_photos(repo: GraduateRequestRepository, storage: GraduateCertStorage, now: datetime) -> dict[str, int]`(`{"photos_deleted":n,"pending_expired":n,"verified_cancelled":n}`, 멱등 · 예외를 내지 않음) · `AccountRepository.fetch_graduate_claim(profile_id) -> dict | None`(`{"student_hmac","key_version"}`) · `AccountRepository.has_open_graduate_request(profile_id) -> bool`.
- 배치 순서(`retention.py` 의 옛 구조와 같다): ① 14일 지난 pending → `cancelled(expired)` + 평문 null ② 이미 인증된 프로필의 pending → `cancelled(verified_otherwise)` ③ 결정된(approved · rejected · cancelled) 행의 `photo_path` 가 남았으면 스토리지 삭제 후 `clear_photo_path` ④ 버킷에 남은 파일 중 신청 행이 없는 것은 **건드리지 않는다**(방금 올려 기록 전일 수 있음 — 옛 retention 과 같은 규칙).

- [ ] **Step 1: 실패하는 시험.**

| 시험 | 핵심 assert |
| --- | --- |
| `test_pending_for_13_days_is_kept_14_days_expires` | 14일 → `cancelled/expired`, 평문 null, 사진 삭제 |
| `test_batch_deletes_photo_of_decided_row_left_behind` [RF1] | 승인 · 반려 · 취소 행에 `photo_path` 가 남아 있으면 삭제 후 null; 삭제 실패는 다음 시각이 다시 시도하고 한 사람 실패가 다음 사람을 막지 않는다 |
| `test_pending_of_verified_profile_is_cancelled` | 학교 메일로 인증된 프로필의 pending → `verified_otherwise` + 사진 삭제 |
| `test_purge_is_idempotent_and_never_raises` | 두 번 돌리면 0건; 목록 조회 실패 · 저장소 장애에도 예외 없음 |
| `test_purge_logs_ids_only` [RF2] | `caplog` 에 사진 경로 · 번호 없음 |
| `test_hourly_chat_gate_batch_runs_graduate_purge_and_survives_its_failure` | `/batch/chat-gate` 응답에 `graduate_photos_deleted` 등 추가, 졸업생 정리가 터져도 응답 200 · 앞 결과 유지(옛 학생증 정리와 같은 방어선) |
| `test_cleanup_keeps_accounts_with_open_graduate_request` [RF4] | `run_cleanup` 이 미인증 14일 후보 중 대기 신청이 있는 계정을 `still_due` 재확인에서 건너뜀(`skipped_accounts` 증가) |
| `test_cleanup_empties_the_graduate_bucket_too` | `STORAGE_BUCKETS` 에 `graduate-cert-temp` 포함, `empty_folder` 호출 5개 버킷 |
| `test_withdraw_cancels_open_request_and_empties_bucket` [RF4] | 대기 신청이 `cancelled(account_withdrawn)` + 평문 null, 버킷 폴더 비움 |
| `test_withdraw_of_graduate_passes_student_hash_to_signup_blocks` [RF4] | claims 가 없고 졸업생 승인 행의 `student_hmac` 이 있으면 `withdraw_account(p_email_hmac=그 해시)`; 해시가 없으면 null(제한 없음, 기존 동작); claims 가 있으면 claims 우선 |
| `test_withdraw_reading_graduate_claim_failure_is_503` | 읽기 실패는 학교 메일 claims 와 같이 503 으로 멈춤(null 로 탈퇴시켜 제한을 잃지 않는다) |

- [ ] **Step 2: 실패 확인** — Expected: FAIL.
- [ ] **Step 3: 구현.** `is_still_unverified` 는 `school_email_verified_at is null` 에 더해 `has_open_graduate_request` 가 false 일 때만 True(SQL 후보 목록과 지우기 직전 재확인 둘 다 막는다). `run_cleanup` 의 14일 후보는 Task 1 의 SQL 이 이미 거른다 — 재확인은 경쟁 방어.
- [ ] **Step 4: 통과 확인** — `pytest -q backend/tests/graduate_verification backend/tests/account backend/tests/chat` Expected: PASS.
- [ ] **Step 5: 커밋 제안** — "✨ feat(graduate): 만료 · 남은 사진 정리 배치" / "🐛 fix(account): 신청 중 졸업생을 14일 정리에서 지키고 탈퇴 때 신청을 닫는다" / "✅ test(graduate): 생명주기".

### Task 5: 서버 관리자 API + 결과 알림 + 읽기 전용 중복 점검

**Files:** Create `backend/app/admin/{graduate_review,graduate_repository,graduate_notice}.py`, `backend/tests/admin/{graduate_world,test_admin_graduate}.py`; Modify `backend/app/admin/router.py`(한 줄)

**Interfaces:**
- Consumes: Task 2 저장소 · 해시 · 스토리지; 기존 `get_admin_caller` · `AdminRepository.record_action`(쓰지 않음 — DB 함수가 기록) · `FcmSender` · `get_sender` · `get_now` · `request_ip` · `send_result_notice`(`admin/heart_task_notice.py:52`) · `ResultNotice` · `SignupPolicy.find_university_id` · `hash_email`.
- Produces: 경로 3-2. `graduate_notice.result_notice(status: str, reason: str | None) -> ResultNotice` — `kind="verification_result"`(기존 알림 종류 재사용: 마이그레이션 · 앱 enum 변경 0, D15), `data={"route":"graduate_verification","state":status[,"reason":reason]}`. `graduate_repository.GraduateAdminRepository(PostgrestRepository)`: `list_requests(status, limit) -> list[dict]` · `fetch_request(id) -> dict | None` · `review(...) -> dict`(RPC 호출, CM404/CM409/22023/42501 을 HTTPException 으로) · `find_claim_owner(email_hmac: bytes) -> dict | None`(`school_email_claims` **읽기만**, profile_id · status) · `find_block(email_hmac) -> bool` · `find_approved_with_document(document_hmac, exclude_profile) -> str | None` · `fetch_history(profile_id) -> list[dict]`.
- 푸시 문구는 D13 확정 전 제안값(승인: "졸업생 인증이 끝났어요" / "학과 정보를 입력하고 시작해 보세요", 반려: "졸업생 인증이 반려됐어요" / "{사유} · 다시 신청해 주세요").

- [ ] **Step 1: 실패하는 시험.**

| 시험 | 핵심 assert |
| --- | --- |
| `test_every_graduate_route_is_behind_the_admin_gate` | 기존 `test_admin_heart_tasks.py:58` 과 같은 표(비로그인 401 · aal1 403 mfa_required · 비관리자 403 not_admin) |
| `test_list_is_oldest_first_and_has_no_photo_or_plaintext` | 한 번의 읽기, 응답에 `photo_url` · `ocr` · 이메일 없음 |
| `test_detail_has_five_minute_signed_url_and_no_raw_path_or_hash` | `photo_url` 있음, 응답 문자열에 `storage_path` · hmac 값 없음; 서명 실패 → `photo_url` null(500 아님) |
| `test_detail_prefills_ocr_and_suggests_universities_from_text_and_email_domain` | OCR 학교 글자와 이전 메일 도메인이 가리키는 `university_id` 가 `suggested_university_ids` 에 들어감(중복 제거) |
| `test_warning_school_email_in_use_is_read_only` [RF3] | 이전 메일 HMAC 이 claims 에 있으면 `warnings` 에 `school_email_in_use`(profile_id · profile_status); claims · signup_blocks 로 나간 호출은 **GET 만** |
| `test_warning_rejoin_blocked_and_document_seen` | blocks 에 있으면 `school_email_rejoin_blocked`; 다른 프로필의 승인 행과 같은 번호 해시면 `document_seen` |
| `test_approve_hashes_admin_values_and_calls_rpc_once` | RPC 본문에 `p_document_hmac` · `p_student_hmac`(있을 때)가 `bytea_literal` 해시, 평문 번호 · 학번이 본문 어디에도 없음; 학번이 없으면 `p_student_hmac` null |
| `test_approve_validates_input_before_rpc` | `document_number` 가 정규화 후 None → 422, RPC 0회; `student_number` 빈 문자열 → 422 |
| `test_approve_then_deletes_photo_pushes_and_returns_decided_detail` | 순서: RPC 성공 → 스토리지 DELETE → `clear_photo_path` → 푸시 → 응답; 응답에 `photo_url` null |
| `test_photo_delete_failure_does_not_flip_the_decision` [RF1] | 삭제가 실패해도 200, `photo_path` 남음(배치가 지움), 로그에 request id 만 |
| `test_reject_with_each_reason_pushes_reason_code` | 4개 코드 각각 200 + 푸시 data `reason`; 목록 밖 코드 → 422, RPC 0회 |
| `test_409_codes_map_from_db_messages` | `already_reviewed` · `already_verified` · `account_withdrawn` · `document_reused` · `student_reused` · `rejoin_blocked` 가 그대로 `detail` 로; 푸시 0회 |
| `test_notice_failure_never_flips_the_decision` | 푸시 시간 초과 · FCM 실패 → 200(기존 `heart_task_notice` 규칙) |
| `test_notice_data_never_carries_photo_email_number_or_nickname` [RF2] | data 키 집합 == {route, state, reason} |
| `test_logs_carry_ids_only` [RF2] | 승인 · 반려 · 경고 계산 경로의 `caplog` |
| `test_admin_route_names_avoid_forbidden_words` | 기존 `test_admin_route_names.py` 가 새 경로에도 통과 |

- [ ] **Step 2: 실패 확인** — Expected: FAIL(404).
- [ ] **Step 3: 구현.** 순서는 `heart_task_review._review`(`admin/heart_task_review.py:90-101`)와 같다: 줄 읽기(없으면 404) → RPC → 사진 삭제 → 알림 → 응답. 이전 메일은 `hash_email(settings.identity_hmac_key, normalize_email(...))` 로 해시해 조회만 한다. 디스코드 · 로그에 해시 · 번호 없음.
- [ ] **Step 4: 통과 확인** — `pytest -q backend/tests/admin backend/tests/graduate_verification` Expected: PASS.
- [ ] **Step 5: 커밋 제안** — "✨ feat(admin): 졸업생 신청 검수 API" / "✨ feat(admin): 결과 푸시와 읽기 전용 중복 경고" / "✅ test(admin): 졸업생 검수".

### Task 6: 앱 로직 (관문 · 저장소 · 뷰모델 · 뒤로가기 · 라우터)

**Files:** Create `frontend/lib/graduate/model/{verification_method,graduate_request_state,previous_school_email,graduate_verification_repository,http_graduate_verification_repository,graduate_verification_repository_provider}.dart`, `frontend/lib/graduate/viewmodel/{verification_method_view_model,verification_method_ui_state,graduate_application_view_model,graduate_application_ui_state,method_back_view_model}.dart`, 대응 `frontend/test/graduate/**`; Modify 2장 표의 앱 파일들(`core/router/*` 는 대장 허락 확인 뒤).

**Interfaces:**
- `enum VerificationMethod { schoolEmail, graduateCertificate }`(`wire` = 서버 문자열) · `sealed class GraduateRequestState`(`GraduatePending(attemptsLeft, submittedAt)` · `GraduateRejected(reason: GraduateRejectReason, attemptsLeft)`) · `enum GraduateRejectReason { unreadable, notCertificate, unverifiable, schoolUnsupported }`(`tryParse`; 문구는 D10 확정 전 자리표시 — pen 문구표 대기).
- `PreviousSchoolEmail`(값 객체, `tryParse(String) -> PreviousSchoolEmail?`, 형식만, 빈 입력 = 값 없음, `toRequestValue()`).
- `abstract interface class GraduateVerificationRepository { Future<Result<void>> chooseMethod(VerificationMethod? method); Future<Result<GraduateRequestState>> submit(File photo, PreviousSchoolEmail? previousEmail); }` · `HttpGraduateVerificationRepository(ApiClient)`(`PUT /me/verification-method` · `ApiClient.sendMultipart('/graduate-verification', {'agreed':'true', if previous ...}, photo.path)`).
- 방법 고르기 뷰모델 `VerificationMethodViewModel`(UiState: `selected: VerificationMethod?` · `isSubmitting` · `errorMessage`): `select(VerificationMethod)` 는 **앱 상태만 바꾼다**(서버 호출 0) · `canGoNext` = 고른 카드가 있고 보내는 중이 아님 · `next()` = `chooseMethod(selected)` → 성공하면 `verificationGateListenable.refresh()`.
- 뒤로 함수 `VoidCallback? methodBack(WidgetRef ref, {required bool isBusy})`(`profile/view/onboarding_back.dart` 와 같은 모양): 화살표 · 시스템 뒤로에 **같은 함수**를 준다. `isBusy`(사진 올리는 중)면 `() {}`, 아니면 `MethodBackViewModel.goBack()` — `_leaving` 중복 누름 방지, `chooseMethod(null)` → 성공 시 관문 새로 묻기, 실패 시 오류 상태(화면이 짧은 안내를 띄움).
- `VerificationGate` 에 `needsVerificationMethod` · `needsSchoolEmailChosen`(**선택 화면을 거쳐 온 02** — 앱바 화살표 판별용) · `needsGraduateApplication` · `graduateReviewing` 추가. 서버 `graduate_enabled`/칸이 없으면 늘 옛 값 `needsSchoolEmail`. `_toGateAfterConsent` 규칙(`school_email_verified == false` 일 때): `graduate_enabled != true` → `needsSchoolEmail`; `graduate.state == 'pending'` → `graduateReviewing`; method `graduate_certificate` 또는 `graduate.state=='rejected'` → `needsGraduateApplication`; method `school_email` → `needsSchoolEmailChosen`; method null → `needsVerificationMethod`.
- `AuthRedirect._gateTarget`: `needsVerificationMethod` → 방법 고르기 경로, `needsSchoolEmail`/`needsSchoolEmailChosen` → `AppRoutes.login`, `needsGraduateApplication` → 신청 경로, `graduateReviewing` → 대기 경로. `_isOnGate`: 두 `needsSchoolEmail*` 모두 `verifyCode` 를 같은 관문으로 본다. 졸업생 3개 경로는 관문 값이 바뀌면(승인 · 취소 · 반려) 서로 밀려난다. 푸시 `route == 'graduate_verification'` → `refreshForPush` 가 관문 새로 묻기, `PushRoute.resolve` 는 null.
- 02 `SignUpScreen`: 게이트 값을 읽어 `needsSchoolEmailChosen` 이면 앱바 화살표 + `BackExitScope(onBack: methodBack)`, `needsSchoolEmail` 이면 앱바 없음 + `BackExitScope(onBack: null)`(종료 안내, 지금과 같은 동작). 라우터 등록은 `_ExitGuardedRoute` → `_PlatformRoute`.

- [ ] **Step 1: 실패하는 시험.**

| 시험 | 핵심 assert |
| --- | --- |
| `gate: flag_off_keeps_needs_school_email` [RF5] | `school_email_verified:false` + `graduate_enabled:false`(또는 칸 없음 — 옛 서버) → `needsSchoolEmail` |
| `gate: method_value_picks_the_gate` | flag on: method null → `needsVerificationMethod`; `school_email` → `needsSchoolEmailChosen`; `graduate_certificate` → `needsGraduateApplication`; `graduate.state=pending` → `graduateReviewing`; `rejected` → `needsGraduateApplication` |
| `gate: verified_person_ignores_graduate_fields` | `school_email_verified:true` + 아무 졸업생 칸 → 예전과 같은 `needsSchoolInfo`/`complete` |
| `auth_redirect: new_gates_target_their_routes_and_block_others` | 각 게이트에서 홈 경로로 가면 해당 화면으로 리다이렉트; `needsSchoolEmailChosen` 에서 `verifyCode` 허용; 신청 → 대기 이동 허용; 지나간 게이트 화면은 리다이렉트로 밀려남 |
| `previous_school_email_test` | 빈 → 값 없음(null 허용), `a@b.ac.kr` OK, `a@`/공백 포함 → null |
| `http_repo: choose_method_sends_put_with_wire_value_and_null` | 본문 `{"method":"graduate_certificate"}` / `{"method":null}` |
| `http_repo: submit_sends_photo_agreed_and_optional_email_only_when_present` | 필드 `agreed=true`, 이메일 없으면 필드 자체 없음 |
| `http_repo: maps_server_errors` | 429 `attempts_exhausted` · 409 · 400 이 각각 구분되는 `Failure` |
| `method_vm: selecting_a_card_never_calls_the_server` | `select` 를 여러 번 불러도 `chooseMethod` 0회; `canGoNext` 는 카드를 고르기 전 false |
| `method_vm: next_sends_the_selected_method_then_refreshes_gate` | `next()` → `chooseMethod(selected)` 한 번 → `refresh()` 한 번; 실패 → 오류 문구 · 관문 불변 · 선택 유지; 보내는 중 `next()` 연타 → 한 번만 |
| `method_back_vm: back_clears_server_value_then_refreshes_gate` | `goBack()` → `chooseMethod(null)` 한 번 → 성공 시 `refresh()`; 실패 → 오류 상태, `refresh` 0회(그 자리에 머묾) |
| `method_back_vm: double_tap_goes_back_once_and_busy_is_a_noop` | 연타 → `chooseMethod(null)` 1회; `methodBack(isBusy:true)` 는 호출 0회 |
| `application_vm: needs_photo_and_consent_to_submit` | 사진 없음 · 동의 안 함 → `canSubmit` false |
| `application_vm: compresses_then_uploads_then_discards_copy` | `compressToJpeg` → 제출 → `discard`(성공 · 실패 모두); 압축 실패 → "사진을 다시 확인해 주세요" |
| `application_vm: attempts_exhausted_shows_contact_state` | 429 → 재신청 불가 상태(문의 안내) |
| `push_route: graduate_verification_resolves_to_null_and_refreshes_gate` | `PushRoute.resolve({'route':'graduate_verification'})` null, `refreshForPush` 가 관문 갱신 호출 |
| `app_router: gate_screens_have_exactly_one_back_exit_layer` [뒤로가기] | 방법 고르기 · 대기 · 신청 폼 · 02 각각 `find.byType(BackExitScope)` == 1(두 겹이면 같은 뒤로에 종료 안내까지 뜬다) |
| `app_router: gate_screens_are_a_single_page_with_no_edge_swipe` [뒤로가기] | 위 네 화면 + 03 에서 `Navigator.canPop()` false, 선택 → 다음 → 화살표 왕복 뒤에도 스택 깊이 1(`push` 가 아니라 `go`) — iOS 왼쪽 가장자리 밀기를 받을 아래 화면이 없다 |

- [ ] **Step 2: 실패 확인** — `cd frontend && flutter test test/graduate test/auth test/core/router test/core/push` Expected: FAIL(컴파일 오류 → 새 심볼 없음).
- [ ] **Step 3: 구현.** MVVM · 생활체조: 새 `model/` 클래스는 인스턴스 변수 2개 이하 · getter 노출 없이 행위 메서드. UiState 는 예외. 사진 고르기 훅은 `HeartTaskSubmitViewModel.pickFromGallery` 와 같은 모양. `core/router/*` 수정은 대장 허락 확인 뒤(2장 표). 뒤로 함수는 `profile/view/onboarding_back.dart` · 03 `_backToEmail` 의 패턴을 따른다.
- [ ] **Step 4: 통과 확인** — 위 명령 PASS, 이어서 `flutter analyze` exit 0. 전체 `flutter test` 는 대장의 "전체 테스트 차례"에서(메모 feedback_full_flutter_test_turn).
- [ ] **Step 5: 커밋 제안** — "✨ feat(auth): 관문에 인증 방법 · 졸업생 단계를 더한다" / "✨ feat(graduate): 신청 저장소와 뷰모델" / "✨ feat(router): 방법 고르기 · 졸업생 경로와 02 뒤로가기" / "✅ test(graduate): 관문 · 라우팅 · 뒤로가기 · 뷰모델".

### Task 7: 앱 화면 (campus-ui 몫 — **pen 값표가 오기 전에는 시작하지 않는다**)

**Files:** Create `frontend/lib/graduate/view/{verification_method_screen,graduate_application_screen,graduate_waiting_screen,method_back_app_bar}.dart` + 위젯 시험; Modify `frontend/lib/auth/view/sign_up_screen.dart`(02 앱바 화살표 변형 · 화면이 스스로 `BackExitScope`), `core/router/app_router.dart`(라우트 3개 등록 · 02 등록 교체 — 허락 확인 뒤)

**pen 값 필요 (노드 id 와 함께 받아야 시작 — 메모 feedback_pen_values_need_node_id; 대장 말로는 `CampusMate_문서\디자인_pen\졸업생_인증\` 에 같은 구조로 만드는 중):**

| # | 요소 | 필요한 값 |
| --- | --- | --- |
| P1 | 인증 방법 고르기: 카드 2개(학교 메일 · 졸업증명서) 선택 전 · 선택됨 상태, [다음] 비활성 · 활성, 제목 · 보조 문구, 하단 로그아웃, **앱바 없음 확인**, 돌아왔을 때 이전 선택을 미리 칠하는지 | 노드 id, 크기 · 간격 · 라운드 · 아이콘 · 문구 |
| P2 | 신청 폼: **앱바 뒤로 화살표**, 안내 문구, 사진 칸(빈 · 선택됨), 이전 학교 메일 입력(선택), 동의 줄, CTA, 오류 줄 | 노드 id, 값 전부, 앱바 값(03 `_BackAppBar` 와 같은지), 사진 칸 Ink 규칙(COMMON §4-2) |
| P3 | 대기 화면: **앱바 없음 확인**, 일러스트/아이콘, 문구, 로그아웃. 신청 취소 링크가 있는지(없으면 만들지 않음, D8) | 노드 id, 심사 기한 문구(D6) |
| P4 | 반려 변형: **앱바 뒤로 화살표**, 사유 4개 문구, 다시 신청 CTA, 횟수 소진 상태(문의) | 노드 id, 문구(D10) |
| P5 | **02 앱바 변형**(대장: "선택 화면을 거쳐 온 경우 뒤로 화살표 — pen 변형 추가됨"): 02 는 지금 앱바가 없다(DESIGN.md §8.8) → 변형 02 의 앱바 높이 · 화살표 위치 · 본문이 내려가는 양 | 노드 id(기존 02 `emHNY` 와 변형 둘 다) |
| P6 | (조건부) 대기 중 신청 취소 확인 시트 — P3 에 링크가 있을 때만 | 노드 id 또는 "없음" 확정 |
| P7 | 알림함 행: 기존 `verificationResult` 아이콘 재사용 가능한지 | 노드 id 또는 "재사용" 확정 |

- [ ] **Step 1: 위젯 시험(실패)** — 화면별 + 뒤로가기:

| 시험 | 핵심 assert |
| --- | --- |
| `method_screen: card_tap_selects_and_next_is_disabled_until_then` | 카드 탭 → 선택 표시, [다음] 비활성 → 활성; 탭만으로 저장소 호출 0회; [다음] → `chooseMethod` |
| `method_screen: has_no_back_arrow_and_shows_logout` | `find.byTooltip(onboardingBackLabel)` 없음, 로그아웃 링크 있음 |
| `method_screen: android_back_shows_exit_hint_then_exits` | 첫 시스템 뒤로 → "한 번 더 누르면 종료돼요" 토스트, 2초 안 두 번째 → 종료(`back_exit_scope_test.dart` 의 가짜 사용) |
| `school_email_chosen: arrow_and_system_back_do_the_same_single_thing` | 02(`needsSchoolEmailChosen`): 화살표 탭과 시스템 뒤로 각각 `chooseMethod(null)` 정확히 1회, 종료 안내 토스트 없음; 실패하면 02 에 머묾 + 안내 |
| `school_email_legacy: no_arrow_and_back_shows_exit_hint` [RF5] | 02(`needsSchoolEmail`): 화살표 없음, 시스템 뒤로 = 종료 안내, 지금 시험(`sign_up_screen_test`)이 그대로 통과 |
| `verify_code: back_still_goes_to_email_screen` | 03 → 02 동작 불변 |
| `application_screen: arrow_and_system_back_go_to_method_picker` | 신청 폼 · 반려 변형 모두 같은 함수 1회; 사진 올리는 중에는 화살표 탭이 호출 0회(화살표는 보임) |
| `application_screen: photo_tile_tap_calls_hook_and_email_is_optional` | 사진 칸 탭 → 훅; 이메일 비어도 CTA 활성(사진 + 동의가 있으면) |
| `application_screen: rejected_variant_shows_reason_and_exhausted_state` | 사유 코드별 문구, 횟수 소진 시 CTA 대신 문의 안내 |
| `waiting_screen: no_arrow_system_back_shows_exit_hint_and_cannot_pop` | 화살표 없음, 시스템 뒤로 = 종료 안내, `Navigator.canPop()` false |
| `waiting_screen: polls_gate_every_30s_and_on_resume` | 30초마다 · 앱 재개 시 `refresh()`; 화면을 떠나면 타이머 해제 |
| `all_gate_screens: respect_reduced_motion_and_large_text` | `disableAnimations` 존중, 글자 확대에서 넘침 없음 |
| `ink_surface_sweep` 갱신 | 새 탭 위젯(카드 · 사진 칸)이 칸 크기의 Material 위에 그려짐(`test/common/ink_surface_sweep_test.dart`) |

- [ ] **Step 2: 실패 확인** — `flutter test test/graduate/view test/auth/view` Expected: FAIL.
- [ ] **Step 3: 구현** — 토큰만(`AppColors` · `AppSpacing` …), `AppButton` 공용, 하드코딩 문자열 금지(상수), 탭 위젯은 `Material(type: transparency)` 로 감싼다. 화면 PR 은 pen 대조표(요소 / pen 값(노드 id) / 앱 값 파일:줄)를 리뷰어에게 넘긴다.
- [ ] **Step 4: 통과 확인** — `flutter test test/graduate test/auth test/core` + `flutter analyze` exit 0.
- [ ] **Step 5: 커밋 제안** — "💄 ui(graduate): 인증 방법 고르기" / "💄 ui(graduate): 신청 폼 · 반려 · 대기 화면" / "💄 ui(auth): 02 앱바 뒤로 화살표 변형".

### Task 8: 관리자 웹 (로직 = campus-coder, 화면 = campus-ui · **pen A-졸업생 검수 시안 대기**)

**Files:** Create `admin_web/lib/graduate/{graduate_item,graduate_review_controller,graduate_review_screen,certificate_viewer}.dart` + `admin_web/test/graduate/*`; Modify `admin_web/lib/api/admin_api.dart`, `router/admin_router.dart`, `shell/admin_section.dart`

**Interfaces:**
- `admin_api.dart`: `listGraduateRequests(status) -> Future<List<GraduateItem>>` · `fetchGraduateRequest(id) -> Future<GraduateDetail>` · `approveGraduate(id, {universityId, documentNumber, studentNumber}) -> Future<void>` · `rejectGraduate(id, GraduateRejectReason) -> Future<void>`.
- `AdminSection.graduates('/graduates', '졸업생 인증', LucideIcons.graduationCap)`(인증샷 검수 다음 자리 제안; 아이콘은 pen 확정에 따름).
- 화면(기존 `HeartTaskReviewScreen` 모양): 왼쪽 대기 목록, 가운데 사진 크게(`ProofPhotoViewer` 의 확대 · 회전 재사용 가능 여부는 구현 때 확인), 오른쪽 폼 = 읽어 둔 문서확인번호(수정 가능, 승인 필수) · OCR 학교 글자 · 이전 학교 메일 · **경고 줄**(`warnings`) · 학교 고르기(제안 미리 선택, 기존 `GET /admin/universities`) · 학번(선택) · [승인] [반려 ▾ 사유 4개]. 승인 · 반려 후 다음 건 자동 선택, 409 코드별 안내(`already_reviewed` · `document_reused` · `student_reused` · `rejoin_blocked` · `already_verified` · `account_withdrawn`).
- 학번 · 번호 입력값은 컨트롤러 메모리에만 두고 로그 · 오류 메시지에 싣지 않으며, 결정 뒤 비운다.

pen 값 필요: A-졸업생 검수 화면 전체(노드 id), 경고 줄 3종 표현, 반려 사유 드롭다운.

- [ ] **Step 1: 실패하는 시험** — `graduate_item_test`(JSON 파싱: 결정된 행의 `photo_url`/`ocr` null 허용), `graduate_review_controller_test`(승인 전 문서번호 비어 있으면 승인 불가 · OCR 값 미리 채움 · 제안 학교 미리 선택 · 처리 후 다음 건 · 409 별 상태 · 입력 평문이 상태 `toString` 에 안 나옴), `graduate_review_screen_test`(경고 줄 렌더, 단축키 규칙은 인증샷 화면과 같은지), `admin_api_graduate_test`(경로 · 본문 키 이름 정확).
- [ ] **Step 2: 실패 확인** — `cd admin_web && flutter test test/graduate` Expected: FAIL.
- [ ] **Step 3: 구현** — 컨트롤러는 `HeartTaskReviewController` 모양. 다듬기 단계(웹 화면 조각마다 campus-ui 가 ui-ux-pro-max 등으로 한 번 더 손봄 — 대장 10-18 지시)는 화면 커밋 뒤.
- [ ] **Step 4: 통과 확인** — `flutter test` + `flutter analyze`(admin_web) exit 0.
- [ ] **Step 5: 커밋 제안** — "✨ feat(admin-web): 졸업생 신청 API 클라이언트와 컨트롤러" / "💄 ui(admin-web): 졸업생 검수 화면".

---

## 5. 커밋 분할 제안 (전체 PR 은 나누는 걸 추천: ① DB+서버 ② 앱 ③ 관리자 웹)

1. ✨ feat(db): 졸업생 인증 표 · 버킷 · 프로필 칸
2. ✨ feat(db): 졸업생 승인 · 반려 함수와 14일 정리 제외 (+ pgTAP)
3. ✨ feat(graduate): 해시 · 서류 판독 · 저장소 · 설정 (+ 시험)
4. ✨ feat(graduate): 인증 방법 선택 · 신청 API와 상태 칸 (+ 시험)
5. ✨ feat(graduate): 만료 · 정리 · 탈퇴 연동 (+ 시험)
6. ✨ feat(admin): 졸업생 검수 API · 결과 푸시 · 중복 경고 (+ 시험)
7. ✨ feat(auth): 앱 관문 · 저장소 · 뷰모델 (+ 시험)
8. 💄 ui(graduate): 앱 화면 3개 + 02 앱바 화살표 변형
9. ✨ feat(admin-web): 졸업생 검수 로직 · 화면
10. 📝 docs(plan): 구현 편차 기록

## 6. 이월(이번에 하지 않는 것) · 영향 알림

- `heart_tasks/storage.py` · `student_verification/storage.py` · `graduate_verification/storage.py` 세 버킷 클래스 합치기 — multiphoto 머지 뒤 별도 정리(ponytail 주석 약속).
- 사용자 상세(W3)에 "인증 방법"(졸업생 표시) 보이기, 학번 중복의 약한 대조(`profiles.student_number` 자가 입력값), 관리자 "일괄 처리" — 필요해지면.
- 옛 학생증 표 · 버킷 · 훅 · 트리거 삭제는 출시후_할일 1-1 그대로(이 계획과 독립).
- **영향받는 공용 코드**: 앱 `VerificationGate` 를 쓰는 곳 전부(`verification_gate_listenable`, `auth_redirect`, `main.dart` 관문 소비처, `refreshUnreadForPush` 의 `gate != complete` 비교는 불변); `sign_up_screen.dart`(02, 선택을 거쳐 온 경우에만 앱바 화살표 · 화면이 스스로 `BackExitScope`), `core/router/app_router.dart`(02 등록이 `_ExitGuardedRoute` → `_PlatformRoute`). 공용 위젯(`common/widgets/**`) · 테마 변경은 계획에 없음 — 새 화면은 기존 `AppButton` 등만 쓴다.
- **E2E 하네스(`e2e/` · `frontend/integration_test`)**: 새 앱의 모든 신규 가입 흐름이 02 앞에 "방법 고르기"(카드 하나 탭 + [다음]) 한 번을 지난다 → 계정 공장 · E-GATE 계열 가설을 고치는 별도 PR 필요(이 계획 밖, 앱 머지 전에 대장 확인).
- 문서 갱신(campus-docs 몫, 코드 머지 뒤): `docs/ERD.md`(새 표 · 칸 · 버킷), `ERD_DECISIONS.md`(D5 · D8), `frontend/CLAUDE.md` §2 인증 행, `backend/DEPLOY.md`(플래그 · 마이그레이션 번호), `DESIGN.md` §9 화면 목록.

## 7. 공유 파일 우회 정리

| 필요 | 공유 파일 | 이 계획의 우회 |
| --- | --- | --- |
| 라우터 등록 | `backend/app/main.py` | `student_verification/router.py` 안에서 `include_router` (admin 이 `/admin` 하나만 알게 한 것과 같은 방식) |
| 오류 문구 | `backend/app/core/errors.py` | `graduate_verification/messages.py` 에 모듈 지역 상수 — 합치기는 대장 허락 시 |
| 설정 | `backend/app/settings.py` | `GraduateSettings`(`AdminWebSettings` 와 같은 별도 클래스) |
| 앱 경로 · 리다이렉트 · 라우트 등록 | `core/router/{app_routes,auth_redirect,app_router}.dart` | **대장 허락 필요**(2장 표). 우회 불가 — 관문 목적지는 `AuthRedirect` 가 정한다. 허락 전에는 Task 6 의 이 부분만 멈추고 나머지(모델 · 뷰모델 · 저장소)는 진행 |

## 8. 배포 순서 (모든 단계는 사용자 원문 승인 뒤, 10-19 지시로 내일 아침 검토 뒤)

1. PR(서버 · DB)을 draft 로 올려 독립 검토 PASS. pgTAP 전체 PASS(대장 DB 테스트 차례).
2. **운영 DB**: 마이그레이션 2개를 `campus-supabase` 가 MCP 로 적용(승인 문장 인용 필요). multiphoto 의 `20261019100000` 이 먼저 적용되면 번호 순서가 맞다. 서버가 DB 보다 먼저 나가면 PATCH 가 칸 없음으로 실패 → 반드시 DB 먼저.
3. 서버 PR 머지 → **서버 배포(플래그 꺼짐)**. 확인: `/health` 200, 무인증 401, `GET /me/verification-status` 가 `graduate_enabled:false`, ERROR 로그 0, 매시 배치 응답에 `graduate_*` 키.
4. 관리자 웹 PR 머지(머지하면 Vercel 이 자동 배포한다 — 서버 뒤에). 관리자 계정으로 빈 목록 확인.
5. 앱 PR 머지 → 새 빌드(안드로이드 AAB · TestFlight). 처리방침 · 스토어 양식 변경(0-5)을 **빌드를 제출하기 전에** 반영.
6. 시험 계정으로 졸업생 길 end-to-end(플래그 켜는 `gcloud run services update --update-env-vars GRADUATE_VERIFICATION_ENABLED=true` 도 별도 승인), 사진 삭제 확인(버킷 비어 있음), 문제 없으면 공개.
7. 롤백: 플래그를 끄면 새 앱도 옛 관문으로 돌아간다(서버 응답 `graduate_enabled:false`). 서버 리비전 롤백 시 안전 하한(00063 → 최신 안전 하한) 규칙은 `DEPLOY.md` 를 따른다 — 이 기능은 새 앱이 나간 뒤 옛 서버로 롤백하면 새 앱의 `PUT` 이 404 이므로 **새 앱 출시 뒤에는 서버 하한을 이 기능 포함 리비전으로 올릴 것**.

## 9. 일정 근거 (출시 11/2, 앱 제출 10/28)

오늘 10-19, 제출까지 9일(주말 포함). 이 기능은 Task 1~5 서버 · DB, Task 6~8 앱 · 웹, 그리고 **pen 값(진행 중) · 처리방침 · 스토어 양식 · 법률 확인(시작 전) · E2E 하네스 수정 · 독립 검토 · 운영 적용**이 줄줄이 걸린다. 서버 · DB · 관리자 웹은 병렬로 약 3~4일에 가능하지만 앱 화면은 pen 값표가 오는 날부터 시작이고, 법률 확인 결과(별도 동의 방식)가 신청 화면 구조를 바꿀 수 있다. 또 10-17 에 "학생증 제거 + 개인정보 양식 완화"를 막 끝낸 직후라, 제출 직전에 사진 수집 기능을 다시 넣으면 양식 재작성과 심사 재제출 위험이 같이 온다. 추천은 D1 의 (나).

## 10. 대장 결정 필요 (추천 포함, 추측 금지)

| # | 결정 | 선택지 | 추천과 근거 |
| --- | --- | --- | --- |
| D1 | **출시 시점** | (가) 10/28 제출 빌드에 포함 (나) 출시 후 약 1주(11/9 전후) 업데이트 (다) 코드는 10/28 빌드에 넣되 서버 플래그를 꺼 둠 | **(나)**. 9장: 제출까지 9일에 pen · 법률 · 양식 · E2E 가 겹치고, 직전에 양식을 줄인 방향과 반대라 심사 위험. 단 서버 · DB · 관리자 웹은 지금부터 만들어 둘 수 있다. (다)는 스토어 양식의 "수집" 신고와 어긋날 수 있어 법률 확인 뒤에만 |
| D2 | **졸업생 표시를 다른 사람에게 보일지** | (가) 안 보임, 내부 칸만 (나) 프로필 · 카드에 표시 | **(가)**. 요청문 7항 "같은 상태" + 카드 응답 · pen · 매칭 점수 영향 변경 없음. 필요해지면 `graduate_verified_at` 으로 나중에 켠다 |
| D3 | **반려 뒤 재신청 횟수** | 무제한 / 3회 / 5회 | **3회**(만료로 닫힌 것 제외). 사진 업로드 · 글자 인식 비용과 관리자 부담을 막고, 소진되면 지원 이메일 안내(FAQ 에 이미 있음). 값은 서버 상수 한 줄 |
| D4 | **신청 중 앱 화면** | (가) 전용 대기 화면(관문, **앱바 화살표 없음 · 시스템 뒤로 = 종료 안내** — 사용자 확정 규칙, 로그아웃, 30초 폴링 + 푸시로 새로고침) (나) 대기를 방법 고르기 화면 위 배너로 | **(가)**. 03(인증번호)과 같은 관문 모양이라 `AuthRedirect` 규칙이 같다. pen P3 필요 |
| D5 | **중복 가입 방지** | (가) 문서번호 해시 (나) 학번 해시 (가+나) | **(가)+(나) 병행**, (나)는 서류에 학번이 있을 때 선택 입력. 0-4 표. 학번 해시는 탈퇴 재가입 제한에도 사용 |
| D6 | **심사 기한 약속 문구** | "당일" / "1~2일" / 약속 안 함 | 앱 문구는 **"보통 1~2일 안에 알려 드려요"**(운영자 1명), 시스템 상한 14일 뒤 자동 취소 + 사진 삭제. "당일"은 약속하지 않는다 |
| D7 | **방법 선택 저장 위치** | 서버 칸 / 앱 상태 | **서버 칸**(1-2 표) |
| D8 | **방법 바꾸기** | 한 번 고르면 고정 / 승인 전까지 허용(화살표 길) / 대기 중 신청 취소 링크까지 | **승인 전까지 허용 — 사용자가 확정한 화살표 길(02 · 신청 폼 · 반려 → 방법 고르기)로만.** 승인 뒤 고정. **대기 화면에서 신청을 취소하고 바꾸는 길은 사용자 확정 규칙("대기는 뒤로가기 없음")과 pen 에 없으므로 만들지 않는다** — 잘못 낸 사람은 결정(또는 14일 자동 취소)을 기다리거나 로그아웃한다. 필요해지면 후속. 대장이 사용자에게 "잘못 낸 신청을 스스로 취소할 길이 필요한지" 한 번 확인해 주세요 |
| D9 | **서류 번호 승인 시 필수 여부** | 필수 / 선택 | **필수**(관리자가 번호로 진위를 확인하므로 부담 없고, 해시가 비면 재사용 방지가 사라짐) |
| D10 | **반려 사유 4개와 문구** | `unreadable`(사진이 흐려요/잘려요) · `not_certificate`(졸업증명서가 아니에요) · `unverifiable`(발급 기관에서 확인되지 않아요) · `school_unsupported`(아직 지원하지 않는 학교예요) / 다른 구성 | 이 4개 코드 추천, **문구는 대장이 확정**(앱 · 푸시 · 관리자 웹 세 곳이 같은 글자로) |
| D11 | **별도 동의 방식** | (가) 02-c 전체 재동의(`CONSENT_VERSION` 상향) (나) 신청 화면 동의 줄 + 신청 행 `consented_at` (다) 방침만 | **(나)**, 법률 확인 (b) 결과로 확정. (가)는 전 계정 재동의라 비용 큼 |
| D12 | **사진 보관 상한(신청 중)** | 7 / 14 / 30일 | **14일**(옛 학생증은 30일). 지나면 자동 취소 + 사진 삭제 |
| D13 | **푸시 문구** | 3장 제안값 | 대장 확정(기존 인증샷 푸시처럼 pen `푸시_문구_표` 에 올리는 것도 방법) |
| D14 | **서버 기능 플래그 기본값** | 꺼짐 / 켜짐 | **꺼짐**(배포와 공개를 분리, 롤백이 환경변수 한 줄) — 켜는 것은 별도 승인 |
| D15 | **알림 종류** | 기존 `verification_result` 재사용 / 새 종류 2개 | **재사용**(check 마이그레이션 · 앱 enum 변경 0, 옛 앱도 이미 아는 종류). 단 `push.py` 가 이 종류를 안드로이드 tag/`apns-collapse-id` 로 한 장에 합치므로 결과가 두 번 연속 오면 마지막 것만 보임 — 허용 가능 |
| D16 | **학교 후보 미리 선택 범위** | OCR 학교 글자 + 이전 메일 도메인 둘 다 / 하나만 | 둘 다(관리자는 최종 선택만 함) |

## 11. 확인하지 못한 것 · 구현 편차 기록

**확인하지 못한 것**
- 실제 졸업증명서의 문서확인번호 모양(발급 시스템별로 다름)과 학번이 인쇄되는지 — 실서류 샘플이 없다. Task 2 판독 시험은 합성 글자로만 돈다. 구현 전에 대장이 서로 다른 학교 증명서 3~5장(개인정보 가린 사본)을 주면 정규식 시험 케이스로 추가.
- Vision 글자 인식의 정확도(번호 한 글자 오인 시 관리자 입력 칸에서 고침 — 설계 반영됨).
- 법률 확인 결과, 스토어 양식 칸의 현재 이름 · 분류, Supabase Storage 저장 지역.
- 운영 DB 현재 상태(클라우드 호출 금지라 읽지 않음): 마이그레이션 번호 충돌 여부, 버킷 `student-id-temp` 안 파일 수.
- pen 값 전부(P1~P7, 웹 시안) — `CampusMate_문서\디자인_pen\졸업생_인증\` 진행 중.
- multiphoto 브랜치와의 실제 머지 충돌(`sendMultipart` · `admin_api.dart` · `admin_router.dart`).

**구현 편차 기록 (구현 중 계획서와 달라진 점을 여기에만 덧붙인다 — 본문은 고치지 않는다)**

**2026-10-19 Task 1~5 (DB · 서버) 구현 편차** — 대장 결정 D2~D16 추천 확정 + D1 뒤집힘(출시 전 구현) 반영.

1. 마이그레이션 번호: `20261019120000 · 120100` → `20261019200000_graduate_verification_tables.sql` · `20261019200100_graduate_verification_functions.sql`(대장 지시: 인증샷 여러 장 코더가 `20261019100000` 을 쓰는 중이라 `200000` 이후).
2. `consented_at` 은 `not null default now()` — 신청은 동의 줄을 누른 뒤에만 들어오므로 기본값이 곧 동의 시각이다(서버가 따로 보내지 않는다).
3. 신청 표 check 가 계획보다 두 개 많다: 대기 줄은 `photo_path` 가 있어야 하고(`graduate_requests_state_pairs`), `ocr_state` 는 `read | nothing_found | failed` 로 고정. 또 `case when` 안의 `reason in (...)` 은 사유가 비면 null 이라 check 를 그냥 통과하므로 `reason is not null` 을 같이 둔다(시험 12 · 14 가 잡았다).
4. 승인 함수에서 `already_reviewed` 의 unique 위반 폴백: 알 수 없는 제약 이름이면 `already_reviewed`(CM409) 로 보낸다. 반려에도 `already_verified` · `account_withdrawn` 검사가 적용된다(계획 1-5 문장 그대로).
5. `list_unverified_accounts` 의 "14일 안에 결정된 신청" 기준은 고정 14가 아니라 인자 `p_older_than_days` 와 같은 기간이다(배치는 14 를 넘긴다).
6. 서버 저장소: `GraduateRequestRepository` 의 `fetch_latest` · `fetch_pending` · `count_attempts` 는 만들지 않고 `fetch_history`(읽기 한 번, 최근 순) + 순수 함수 `attempts_used(history)` 로 합쳤다 — 상태 응답이 "졸업생 선택자만 읽기 1회"이어야 해서. `fetch_pending_of_verified(limit)` 를 더했다(이미 학교 메일로 통과한 사람의 대기 신청 닫기). `GraduateCertStorage.list_paths` 는 만들지 않았다(버킷에 남은 파일 중 신청 행 없는 것은 건드리지 않는 규칙이라 쓸 곳이 없다).
7. 신청 API · 관리자 API 오류 응답은 `{"detail": 문구, "code": 코드}`(인앱결제와 같은 모양, 앱은 code 로 가른다). 정지 · 동의 전 403 과 탈퇴 401 은 기존 관문의 모양 그대로.
8. 신청 순서: 글자 인식(Vision) → 사진 올리기 → 행 쓰기. 계획의 "업로드 → 인식" 순서를 뒤집었다 — 인식이 우리 버그로 500 이 되어도 지울 사진이 없다. 행 쓰기 실패 · 유일 인덱스 충돌(409)은 방금 올린 사진을 지운다. `ocr_school_text` 에는 OCR 원문이 아니라 학교 이름 목록과 맞은 이름만(" / " 로 이음) 저장한다.
9. 관리자 중복 경고의 재가입 제한 점검은 새 메서드 대신 기존 `SignupPolicy.is_blocked` · `find_university_id` 를 재사용(읽기 전용). `find_block` 은 만들지 않았다.
10. 관리자 목록 `attempt_no` 는 PostgREST 임베드(`profile:profiles(all_requests:graduate_verification_requests(id,created_at))`)로 읽기 한 번에 센다.
11. 시험 파일 이름: 폴더에 `__init__.py` 가 없어 같은 이름이 충돌하므로 `test_repository/test_storage/test_settings/test_retention` → `test_graduate_*` 로, 관리자 가짜는 `tests/admin/graduate_world.py` → `graduate_admin_world.py`(신청자 쪽 가짜와 이름 충돌 방지). 기존 시험 중 "응답이 정확히 이 딕셔너리" 를 확인하던 5곳(`student_verification/test_router.py` · `test_repository.py`, `chat/test_chat_batch.py`, `notifications/test_retention.py`)은 새 칸을 허용하도록 고쳤다 — 옛 앱이 읽는 다섯 칸의 값 · 이름은 그대로 확인한다.
12. 배치 응답 키: `/batch/chat-gate` 에 `graduate_photos_deleted` · `graduate_pending_expired` · `graduate_verified_cancelled` 가 더해졌다(옛 학생증 키는 그대로).
13. 탈퇴: 단계 이름 `graduate_request`(대기 신청 닫기 + 사진 삭제) · `graduate_files`(폴더 비우기)가 best-effort 뒤 단계에 더해졌다. 재가입 제한 해시는 학교 메일 claims 가 먼저, 없으면 졸업생 학번 해시, 둘 다 없으면 null. 읽기 실패는 둘 다 503.
14. pgTAP: 로컬 DB 를 `supabase db reset` 할 수 없어(자동 모드가 막음) 같은 컨테이너에 마이그레이션 2개 + 시험 파일을 한 트랜잭션으로 흘려 넣고 롤백하는 방식으로 돌렸다(70/70). 공식 `supabase test db` 전체 재실행은 DB 차례를 쥔 쪽에서 `db reset` 뒤 필요.
15. 독립 검토 반영(10-19): 신청 줄 쓰기 실패 뒤 방금 올린 사진 삭제도 실패하면 `DiscordNotifier.notify_graduate_orphaned_file`(계정 id 만, 졸업생 버킷 문구 — 학생증 문구인 기존 `notify_orphaned_file` 은 쓰지 않음)로 알린다. `set_method` 쓰기에 `school_email_verified_at`/`graduate_verified_at` 이 비어 있는 조건을 붙였다. 호출처 없는 `fetch_method` 는 지웠다. **알려진 좁은 틈(고치지 않음)**: ① 업로드는 됐는데 응답이 끊겨 서버가 죽는 등으로 신청 줄이 없는 사진은 매시 배치가 신청 줄을 보고 고르므로 못 찾는다(탈퇴·14일 정리의 폴더 비우기가 마지막 방어선) ② 탈퇴와 관리자 승인이 거의 같은 순간 겹치는 좁은 틈(독립 검토 사소2) — 고치지 않고 기록만 한다.


**2026-10-19 Task 6 (앱 로직) 구현 편차** — 화면(Task 7)과 라우트 등록은 하지 않았다.

1. 관문 판정을 `_toGateAfterConsent`(저장소 안 private)에서 **`VerificationGate.fromStatus(Map)` 정적 순수 함수**로 옮겼다(`auth/model/verification_gate.dart`). `HttpVerificationGateRepository` 는 한 줄 위임이다. 판정표 시험을 네트워크 없이 돌리려는 것이고, 규칙은 계획 그대로다(플래그 `!= true` → `needsSchoolEmail`, 대기 → `graduateReviewing`, 반려 또는 방법 졸업증명서 → `needsGraduateApplication`, 방법 학교 메일 → `needsSchoolEmailChosen`, 방법 없음 → `needsVerificationMethod`). 인증을 마친 사람(`school_email_verified != false`)은 졸업생 칸을 읽지 않는다.
2. 저장소 인터페이스에 **`fetchState() -> Result<GraduateRequestState?>`** 를 더했다. 계획의 `chooseMethod` · `submit` 만으로는 신청 폼(반려 변형)이 사유 · 남은 횟수를 알 길이 없어서다(관문 값은 enum 이라 칸을 못 싣는다). `GET /me/verification-status` 의 `graduate` 칸만 읽는다.
3. `GraduateRejected.reason` 은 nullable(`GraduateRejectReason?`) — 서버가 모르는 사유 코드를 주거나 null 을 줘도 반려는 반려로 읽는다. `GraduateRejected.isExhausted()`(남은 횟수 0)를 더했다. `GraduatePending.submittedAt` 도 nullable.
4. 429 `attempts_exhausted` 는 새 `Failure` 클래스를 만들지 않았다. `failure.dart` 의 `Failure` 는 sealed 라 같은 파일을 고쳐야 해서, 이 엔드포인트의 429 가 신청 횟수 소진 하나뿐인 점(서버 `applicant_router.py` 확인)을 근거로 `RateLimitedFailure` 를 그대로 쓰고 뷰모델이 `isExhausted` 로 바꾼다(인증샷 `HeartTaskSubmitViewModel` 과 같은 방식). 서버가 이 엔드포인트에 다른 429(전역 한도 등)를 더하면 이 판단을 다시 봐야 한다.
5. 신청 뷰모델은 서버가 `already_pending` · `already_verified`(다른 기기가 먼저 냄 · 그새 인증됨)로 거절하면 문구를 보이고 **관문을 다시 묻는다**(폼에 갇히지 않게). 방법 고르기 `next()` · 뒤로가기 실패에는 계획대로 관문을 건드리지 않는다.
6. 경로 상수는 **3개**(`verificationMethod` `/verification-method` · `graduateApplication` `/graduate/application` · `graduateWaiting` `/graduate/waiting`)다 — 계획의 "4개"는 화면 3개 + 02 의 변형을 센 것으로 보고 02 는 기존 `login` 을 쓴다. `AuthRedirect` 는 `needsSchoolEmail`/`needsSchoolEmailChosen` 을 `login` 으로, 두 쪽 모두 `verifyCode` 를 같은 관문으로 본다. 세 새 경로는 `_isBeforeHome` 에 들어 있어 인증을 마친 사람은 홈으로 밀려난다.
7. **하지 않은 것(Task 7)**: `app_router.dart` 의 라우트 3개 등록 · 02 등록 `_ExitGuardedRoute` → `_PlatformRoute` 교체 · `sign_up_screen.dart` 앱바 화살표 · 계획 Task 6 표의 `app_router: gate_screens_*`(BackExitScope 한 겹 · 스택 깊이 1) 시험 2개 — 모두 화면 클래스가 있어야 해서 Task 7 로 넘긴다. 서버 플래그가 켜진 채로 라우트 3개가 등록되기 전에는 새 관문에서 go_router 가 경로를 못 찾는다(플래그 꺼짐이면 새 관문이 나오지 않아 영향 없음).
8. `methodBack(WidgetRef, {required bool isBusy})` 는 `graduate/view/method_back.dart` 에 두었고 **항상 non-null** 함수를 돌려준다(계획의 `VoidCallback?` 보다 좁다 — 졸업생 길의 뒤로는 늘 있다). 뷰모델 상태 `MethodBackUiState{isLeaving, errorMessage}`.
9. 푸시: `refreshForPush` 의 `graduate_verification` 가지가 `verificationGateListenableProvider.refresh()` 만 부르고 `PushRoute.resolve` 는 (기존 `_ => null` 로) null 이다. **발견**: 푸시 토큰 등록은 `main.dart:_startPushWhenGateOpens`(관문 `complete` 일 때만)와 `_startPush`(세션 변화 때)가 하는데, `_startPush` 는 세션이 바뀔 때 관문과 무관하게 불리고 서버 `POST /cards/push-tokens` 도 `_wire_signed_in`(학교 메일 관문 앞에서도 열림)이라 대기 중 졸업생도 토큰을 등록할 수 있다 — 다만 `refreshOnResume`(앱 재개 갱신)은 관문 `complete` 에서만 돌아서 **대기 화면의 30초 폴링 · 앱 재개 갱신은 Task 7 의 화면이 직접 `refresh()` 해야 한다**(계획 Task 7 시험 `waiting_screen: polls_gate_every_30s_and_on_resume` 가 이미 요구).
16. 후속(10-19, 대장 확정): 반려 사유 문구(D10)를 "사진이 잘 안 보여요" / "졸업증명서가 아니에요" / "확인할 수 없는 번호예요" / "아직 지원하지 않는 학교예요" 로 바꿨다(`admin/graduate_notice.py` 한 곳, 푸시 본문 형식 그대로). 관리자 목록·상세에 `nickname` · `university_name`(없으면 null, 탈퇴한 계정이면 둘 다 null, 결정된 줄에도 표시)을 더했다 — 기존 신청 줄 읽기의 `profile:profiles(status,nickname,universities(name),all_requests:…)` 임베드에 칸만 더해 쿼리가 늘지 않는다.


**2026-10-19 Task 7 (앱 화면) 구현 편차** — 화면 5종(방법 고르기 · 신청 폼 · 대기 · 02 변형)과 라우트 등록. pen 값표 `디자인_pen\졸업생_인증\값표.md` 와 PNG 가 기준이고, 값표에 없어 앱이 정한 것은 전부 아래에 적는다(pen 수정 대기).

1. **파일**: `graduate/view/{verification_method_screen,graduate_application_screen,graduate_photo_slot,graduate_reject_alert,graduate_waiting_screen,method_back_app_bar,gate_toast}.dart`. 화면 4종이 스스로 `BackExitScope` 를 한 겹 두른다 — 라우터가 두르면 두 겹이 된다(Task 6 표 `gate_screens_*` 시험 2개를 `test/core/router/graduate_gate_screens_router_test.dart` 에 맞췄다).
2. **값표에 없어 임의로 정한 것 (pen 수정 필요)**:
   - **사진 칸 빈 · 채움**: 값표는 "채워진 1장"의 자리 표시 하나뿐이다. 빈 칸 = 같은 칸(104×104 · `#EBEBEB` · 모서리 14 · `image` 28 `#929292`)에서 삭제 X 만 없음, 채움 = 사진을 cover 로 채우고 오른쪽 위 삭제 X(28, 위치 x72 y4, 누르는 넓이 44). 칸을 누르면 갤러리, 고른 뒤에는 바꾸기. 개수 글자는 "0/1장" ↔ "1/1장".
   - **개인정보 동의 줄**(D11 (나)): 02-g 에 줄이 없는데 뷰모델이 `agreed` 를 요구해 공용 `ConsentRow`("필수" 뱃지)를 안내 줄과 [제출하기] 사이에 넣었다. 문구 "졸업증명서 사진을 확인에 쓰는 것에 동의해요"(대장 확정). 그래서 [제출하기]는 pen 보다 약 64px 아래다.
   - **이전 학교 메일 형식 오류 문구**: "이전 학교 메일 형식을 다시 확인해 주세요"(서버 `PREVIOUS_EMAIL_INVALID` 와 같은 글자, `LabeledField` 오류 줄).
   - **횟수 소진 화면**(시안 없음): 폼 대신 제목 "신청 횟수를 모두 썼어요" · 설명 "졸업증명서로는 더 신청할 수 없어요. 아래 메일로 문의해 주세요." · 문의 메일 카드(정지 안내 `JCWwK` 와 같은 칸 모양). 앱바 화살표는 남겨 학교 메일 길로 돌아갈 수 있다.
   - **사유가 알 수 없는 값(null)일 때 반려 알림 제목**: "졸업증명서 확인이 반려됐어요"(접두 "반려 사유: " 없음).
   - **반려 알림 캡션 두 종**(대장 결정): 평소 "졸업증명서 사진을 다시 올려 주세요 · 남은 신청 {n}번"(한 줄, 알림 높이 pen 64.67 그대로), `school_unsupported` 는 "뒤로 가서 학교 이메일로 인증할 수도 있어요 · 남은 신청 {n}번"(두 줄로 접혀 알림이 18 높다). 알림 두 줄 사이 간격 2 는 PNG 실측(18b-2 는 4).
   - **반려 사유 4번째** "아직 지원하지 않는 학교예요": 값표에 없어 같은 틀로 추가(D10 확정 문구).
   - **실패 토스트**: 경고 아이콘 16 + 글자(Toast `I8UOWm` 형태, 시간은 SnackBar 기본).
   - **낭독 라벨**: 사진 칸 "졸업증명서 사진 추가"/"졸업증명서 사진 바꾸기", 삭제 X "사진 빼기", 방법 카드는 버튼 · 선택됨(그림은 읽지 않음).
   - **대기 화면 로그아웃 링크**(대장 결정): 값표엔 단추가 없으나 심사 중 계정을 바꿀 길이 없어 02-0 의 `LogoutTextButton` 을 맨 아래 16 에 더했다. 내용은 위 64 를 같이 비워 pen 가운데 자리 그대로다.
   - **방법 카드 선택 표식**(대장 결정): 선택된 카드 안쪽 오른쪽 20 · 위 20 에 `circle-check` 20 primary(색만으로 전하지 않으려고). 제목 오른쪽을 28 비워 글자 확대에도 겹치지 않는다.
   - **앱바 3D 물음표(02-0 Trailing 24) 미구현**: 값표는 Leading · 제목이 꺼지고 Trailing 에 3D 물음표 24 가 있다고 하나 PNG 에는 아무것도 안 보이고 누르면 무엇을 하는지(도움말인지) 값표에 없다. 뜻이 정해지지 않은 단추를 만들지 않고 앱바 자리 56 만 빈 채로 둔다.
3. **[다음] 버튼**(대장 승인): pen `itG98` 은 02 프레임 복사(모서리 8 · 18/700)라 마스터가 아니다. 02 · 03 과 같이 공용 `AppButton`(52 · 모서리 14 · 16/700)을 쓴다.
4. **줄높이**: pen "normal" 은 속성이 없어 PNG 실측으로 맞췄다 — 16px 설명 렌더 22, 방법 카드 제목 22 · 설명 줄 간격 22(카드 높이 118 = 20+22+12+44+20), 사진 라벨 렌더 19.6. 공용 `LabeledField`(라벨 16.8) · `HintLine`(21.7)은 고치지 않아 pen 보다 각각 2~3px 위아래로 어긋날 수 있다.
5. **공용 · 기존 파일 변경과 이유**:
   - `core/router/app_router.dart`(사용자 승인 범위): 라우트 3개 등록, 02 를 `_ExitGuardedRoute` → `_PlatformRoute`. 02 의 변형 판별(`hasMethodPicker`)은 라우트 빌드 때 한 번이 아니라 `refreshListenable`(관문 알림)마다 다시 정한다 — 02 에 머무는 동안 서버 플래그가 꺼져 관문이 `needsSchoolEmail` 로 바뀌면 화살표가 사라진다(독립 검토 권고4). 시험 `02 변형은 관문을 따라간다`.
   - `core/theme/app_icons.dart`: `AppIcons.image`(Lucide `image`) 한 줄. DESIGN.md §5.3 표 갱신은 공유 문서라 하지 않았다.
   - `core/router/verification_gate_listenable.dart`: `refresh()` 가 `Future<void>` → `Future<bool>`(답을 받았으면 true). 반환값을 안 쓰는 기존 호출은 그대로다. 졸업생 뒤로가기가 "서버 값은 비웠는데 관문을 다시 묻지 못함"을 알리려고(독립 검토 사소3) 읽는다.
   - `graduate/viewmodel/graduate_application_view_model.dart`(Task 6 로직): ① `removePhoto()` 추가(pen 삭제 X). ② 사진 사본 정리(독립 검토 사소1): **고르는 즉시 압축**하고 image_picker 가 만든 원본 사본을 바로 지운다. 압축본은 올리기 성공 · 사진 빼기/바꾸기 · 화면을 떠날 때(뒤로가기 · 취소) 지우고, 올리기가 실패하면 그대로 둬 다시 보낸다(종전 "제출 때 압축 · 성공 실패 모두 삭제" 에서 바뀜). 임시 폴더 밖 파일은 건드리지 않는다(갤러리 원본 보호; iOS 는 image_picker 가 `tmp`, path_provider 가 `Caches` 라 둘 다 본다). 로그아웃 · 탈퇴는 기존 `ImageCompressor.discardAll`(압축본 이름 `student-id-`)이 쓸어 간다 — 공용 `ImageCompressor` 는 바꾸지 않았다(학생증 · 프로필 사진 동작 불변). **알려진 틈**: 고르는 중 · 압축 중 앱이 죽으면 원본 사본이 캐시에 남는다(OS 가 비운다).
   - `auth/view/sign_up_screen.dart`: `hasMethodPicker` 인자와 `BackExitScope` 추가(옛 길은 그대로 — 기존 시험 불변).
6. **뒤로가기 실패 안내**(독립 검토 사소3): `MethodBackViewModel` 이 서버 값 비우기에 성공한 뒤 관문 재조회가 실패하면 기존 실패 토스트와 같은 문구("네트워크 연결을 확인해 주세요")를 한 번 남긴다. 재조회 실패는 원인을 주지 않아 네트워크 문구로 한다.
7. **발견 — 반려된 뒤 신청 폼의 화살표는 아무 곳으로도 가지 못한다**: `VerificationGate.fromStatus` 가 `graduate.state == 'rejected'` 를 방법 값보다 먼저 보므로 `PUT /me/verification-method {null}` 이 성공해도 관문이 `needsGraduateApplication` 그대로라 화면이 안 옮겨진다(반려 사람이 학교 메일 길로 바꾸려 해도 못 감). 고치지 않았다(Task 6 판정표). 고치려면 방법이 비었으면(null) 반려여도 `needsVerificationMethod` 로 보내는 한 줄이 필요하다 — 대장 결정 필요.
8. **시험 수치**: pen 대조 시험은 각 화면 시험 파일에 있다(`test/graduate/view/*_test.dart`). 글자 1.3 · 2.0 배 오버플로 없음, 터치 영역 44 이상, 낭독 라벨, 동작 줄이기 `pumpAndSettle`, 눌림 효과 Material 크기(COMMON §4-2, `ink_surface_sweep_test` 에 새 화면 4개 추가).

**2026-10-19 Task 8 (관리자 웹) 구현 편차** — 대장 전달 요약. 화면 값은 pen `A10 졸업생 검수 pIuL0`. (아래는 대장이 전한 요약을 그대로 옮긴 것이다 — 이 창은 관리자 웹 코드를 읽지 않았다.)

1. 검수 큐 항목 이름은 "닉네임 + 학교 · n분 전"이다. 닉네임 · 학교를 못 읽으면(탈퇴 등) "n번째 신청"으로 폴백한다.
2. 큐 위 칩 2종("중복 경고" · "이전 메일 있음")은 이번 출시에서 뺐다(전체 칩만).
3. 반려 사유는 D10 4개 문구이고, 관리자 웹 상수와 서버 `backend/app/admin/graduate_notice.py` 의 `REASON_TEXT` 를 글자 단위로 대조하는 시험을 둔다.
4. 입력 칸 2개(문서확인번호 · 학교 확인)와 번호 정규화 안내 문구, 승인 · 반려 확인 대화상자, 409 오류 6종 문구는 값표에 없어 앱이 정했다(pen 수정 필요).
5. 학교 후보 첫 항목을 미리 선택해 둔다. 학교 목록을 못 받으면 승인 단추가 잠긴다.
6. 공용 `AdminSelect` 에 크기 인자를 더했고 A3 의 공개 이름을 바꿨다(동작 불변).
7. 신청자의 닉네임이 있어도 사용자 상세로 가는 링크는 두지 않았다.


**2026-10-19 머지 · 운영 반영 기록 (문서 정리 라운드, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다)**

1. PR #615 가 main(`fc430713`)에 머지됐다. 마이그레이션은 위 편차 1 의 번호 그대로 `20261019200000` · `20261019200100` 이다. 운영 DB 에 인증샷 `20261019100000`, 이 두 파일, 저녁 알림 `20261019210000` 네 개가 적용돼 **운영 93개 = 저장소 93개**다(원격 버전은 적용 시각 `20261019055736` · `055756` · `055818` · `055824` — 파일과의 짝은 받지 못했다).
2. 서버 리비전 흐름(대장이 조회로 확인): `00086-7zf` → `00087-9qj`(DB 4개 적용 직후 배포, 스위치 꺼짐) → `00088-gh5`(**졸업생 스위치 `GRADUATE_VERIFICATION_ENABLED=true` 켬**, 사용자 직접 승인 "졸업생 스위치 켜기 승인") → `00089-fpm`(#617 원본대조번호 읽기 + #619 약관 판 2026-10-19). 현재 운영 `00089-fpm`, env 27(시크릿 11), 스위치 켜짐, 운영 마이그레이션 93개, /health 200 · 무인증 401 · ERROR 로그 0. **코드 기본값은 꺼짐, 운영은 10-19 켬**이다. 켠 근거는 공개 출시 전이라 앱 사용자가 테스터뿐이고 사용자가 시험하려고 켜는 것을 직접 승인한 것이다. 처리방침(노션)은 10-19 졸업증명서 · 학생증 정리를 반영 완료, 이용약관도 반영 완료. 스토어 개인정보 양식 · 법률 확인 · 실제 졸업증명서 판독 검증은 공개 출시 전까지 남았다(8장 6단계, `backend/DEPLOY.md` §4-14).
3. 관리자 웹(A10 졸업생 검수 · "졸업생" 메뉴 세 번째)은 Vercel 자동 배포로 나갔다. 스위치를 켠 10-19 `00088-gh5` 부터 졸업생 API 를 쓸 수 있다.
4. 10장 결정 확정: D1 은 대장 추천 (나)(출시 후)가 아니라 **사용자 결정으로 출시 전 포함**으로 뒤집혔다. D1 · D5 는 설계 기본값, **D8(대기 화면에서 신청 스스로 취소)은 출시 후**로 확정됐다(할 일 17차 0-2). 하트 스토어 대기 목록 시안도 출시 후.
5. 8장 7단계(롤백) 보강: 서버 안전 하한은 이 계획의 "최신 안전 하한"이 아니라 인증샷 마이그레이션(`20261019100000`)까지 고려해 **`00087`** 이다(그 아래로 내리면 인증샷 제출 · 관리자 사진 보기가 깨진다). 스위치를 켠 운영에서 `00087` 이전으로 되돌리면 새 앱의 `PUT /me/verification-method` 가 404 다.
6. **아직 닫히지 않은 것**: ① 실제 졸업증명서 샘플로 번호 판독 검증(11장 첫 항목) ② 법률 확인 · 처리방침 · 스토어 양식(0-5) ③ Task 7 편차 7(반려된 뒤 신청 폼 화살표) — **대장이 서버 코드로 확인: 실서버에서는 발생하지 않는다**(`student_verification/router.py` 가 방법이 `graduate_certificate` 이고 미인증일 때만 `graduate` 칸을 계산하므로 `PUT {method:null}` 뒤 `graduate` 가 null 이 되어 관문이 방법 고르기로 간다. 편차 7 의 시험은 가짜 응답 조합). 실기기 확인이 남았다 ④ 앱 빌드: TestFlight 21(6개 PR) · 22(#617 ~ #620 포함 main `db166fdc`, 진행 중), 안드로이드 vc13 은 이미 사용된 번호라 vc14, vc15(진행 중).
7. 결정 배경 · 면접용 설명은 `docs/decisions/2026-10-19-graduate-verification-decision.md`, DB 는 `docs/ERD.md` §3, 서버 운영은 `backend/DEPLOY.md` §4-14, 화면은 `frontend/docs/DESIGN.md` §9 02-0 ~ 02-g-4 로 옮겼다.
