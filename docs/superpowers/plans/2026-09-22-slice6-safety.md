# 조각 6: 안전 — 신고 · 차단 · 계정 삭제 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **실행 순서는 Part C(Supabase) → Part B(FastAPI) → Part A(Flutter)** 다.
> **Part C 는 파일 작성 + 로컬 스택 검증까지만 하고 클라우드 적용은 하지 않는다**(ERD 그림 · 사용자 검토 ·
> 사용자 승인 뒤 supabase 담당 세션이 적용한다).
> **Part A(앱)는 pen 시안이 확정된 뒤에 시작한다** — 아래 "화면 대조표" 가 pen 담당(erd3) 작업 지시서이고,
> 사용자 검토가 끝나야 앱 PR 을 연다.
> **사전 결정 13건은 2026-09-22 사용자 답으로 전부 확정됐다**(아래 "확정된 결정" 표). 추천과 다른 곳이
> 네 곳(3 · 4 · 7 · 9)이라 해당 Task 는 답에 맞춰 쓰여 있다.
> **새 의존성 1건 · 새 시크릿 1건 · 배포 절차 변경 1건(OIDC)이 있다.** 새 의존성은 2026-09-22
> `flutter_contacts ^2.5.0` 으로 **승인됐다**(아래 "새 의존성" 절 승인란).

**Goal:** 애플 심사 지침 1.2(신고 수단 + 24시간 조치 능력)와 구글 정책을 만족하는 **신고 · 차단 · 계정
삭제**를 만든다. 사용자가 프로필과 메시지를 신고할 수 있고, 신고하면 그 상대가 내 앞에서 사라지고,
서로 다른 세 명이 신고한 계정은 자동으로 카드에서 빠지고, 운영자가 디스코드 알림을 보고 대시보드에서
정지하거나 해제할 수 있다. 연락처(지인) 차단과 탈퇴(30일 뒤 완전 삭제 · 2개월 재가입 제한)도 이 조각이다.

**Architecture:** 새 테이블은 `reports` · `blocks` · `contact_blocks` 셋이고, 이미 있는
`signup_blocks`(조각 1a, 읽기 전용이었다)에 **쓰기 경로**가 처음 생긴다. 판정은 조각 4·5 와 같은 방식으로
**상태 컬럼을 최소로** 둔다 — 차단은 `blocks` 행 하나, 자동 가림은 `profiles.auto_hidden_at` 한 칸,
탈퇴는 `withdrawn_at` 한 칸이고 나머지는 조회 시점에 판정한다.

**차단당한 쪽은 알 수 없어야 한다**(설계 §7.2). 그래서 차단은 `matches` 에 공유 값을 쓰지 않고
**차단한 사람의 `match_participants.left_at` + `blocks` 행**으로만 처리한다 — 상대에게는 조각 5 의
"나갔어요" 와 **한 글자도 다르지 않게** 보인다. 정지(suspended)도 같은 원리인데 한 가지가 다르다:
정지는 **`left_at` 을 찍지 않고 조회 시점에 `partner_left` 로 계산**한다. 정지를 풀면 대화가 그대로
돌아와야 하기 때문이다.

**신고는 한 번에 두 가지를 한다**(결정 4) — `reports` 행을 넣고 같은 요청 안에서 `blocks` 행도 넣는다.
신고자에게 "신고했는데 아직 보인다" 는 순간이 없어야 하고, 차단 해제는 16f 에서 따로 할 수 있다.

**운영은 디스코드 + Supabase 대시보드다**(2026-09-19 결정). 관리자 페이지는 만들지 않는다. 신고가
들어오면 전용 채널에 한 줄, 서로 다른 3명이 모이면 "3건 도달 · 검토 필요" 한 줄이 더 간다.

**Tech Stack:** Postgres 17 (Supabase) + FastAPI + httpx(PostgREST · 디스코드) + **google-auth(OIDC ID
토큰 검증)** + Cloud Scheduler(**세 번째 job** + 기존 2개의 인증 방식 교체) + Flutter(Riverpod `Notifier`)
+ **`flutter_contacts` ^2.5.0(신규, 2026-09-22 승인)**.

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §2.6(탈퇴 · 재가입) ·
§2.8 · §7.2 · §7.6b(연락처 HMAC) · §13 미결 34 · 36 · 41 ①, `docs/ERD.md` §2 · §3(`profiles` ·
`profile_private`) · §5(안전 · 계정 상태) · §8(열거형) · §12 검토 5 · 9 · 10,
`frontend/docs/DESIGN.md` §9(화면 8a · 8a-2 · 8d · 14c · 14d · 14e · 14f · 16 · 16b · 16c · 16e · 16e-1 ·
16f) · §13-29 · §13-57 · §13-62, pen `C:\Users\home\OneDrive\Desktop\datingApp\design\datingApp.pen`,
메모리 `project_slice6_predecisions_2026-09-22.md` · `project_slice6_decisions_2026-09-19.md`

---

## 새 의존성 (2026-09-22 승인 완료)

**이번 조각의 새 의존성은 1건이다.** 결정 7 에서 지인(연락처) 차단을 조각 6 에 넣기로 하면서 생겼다.

| 구분 | 후보 | 버전 | 라이선스 · 게시자 | 판정 |
| --- | --- | --- | --- | --- |
| Flutter 연락처 읽기 | **`flutter_contacts`** | **^2.5.0**(2026-09 기준 최신) | MIT · quis.co(pub.dev 인증 게시자) | **추천** — 권한 요청(`requestPermission`)까지 한 패키지 안에 있어 **새 패키지가 이것 하나로 끝난다** |
| (대안) | `fast_contacts` + `permission_handler` | 6.0.0 + — | MIT · sonerik.dev | 읽기 전용이라 권한이 `READ_CONTACTS` 하나로 깔끔하지만 **패키지가 두 개**가 된다 |
| 백엔드 OIDC 검증 | `google-auth` | >=2.35 | Apache-2.0 · Google | **이미 설치돼 있다**(`google-cloud-vision` 이 끌고 온 2.58.0, `cards/push.py` 가 이미 `google.auth` 를 쓴다). `pyproject.toml` 에 **한 줄 명시만** 추가한다 — 전이 의존성에 기대는 상태를 남기지 않는다 |
| 스케줄러 | 없음 | — | — | Cloud Scheduler job 하나 추가(무료 한도 3개 중 세 번째). 패키지가 아니라 배포 설정이다 |

**`flutter_contacts` 를 고르면 할 일 하나가 따라온다** — 이 패키지의 매니페스트에는 `READ_CONTACTS` 와
함께 **`WRITE_CONTACTS`** 가 들어 있다. 우리는 번호를 읽기만 하므로 매니페스트 병합에서 빼야 한다:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.WRITE_CONTACTS" tools:node="remove" />
```

빼지 않으면 스토어 심사에서 "연락처 쓰기 권한을 왜 쓰느냐" 를 따로 소명해야 한다.

> **미래 유지보수:** 나중에 카메라·위치처럼 권한이 하나 더 필요해지면 그때 `permission_handler` 를
> 들이고 연락처 권한도 거기로 모은다. 지금 두 패키지를 넣어 두는 것은 안 쓰는 추상화다.

**승인란(사용자) — 2026-09-22 승인됨:**

- [x] `flutter_contacts: ^2.5.0` 을 `frontend/pubspec.yaml` 에 추가하는 것을 승인한다
- [ ] (대신 `fast_contacts` + `permission_handler` 조합을 원하면 여기에 표시) — **고르지 않음**
- [x] `google-auth>=2.35` 를 `backend/pyproject.toml` 에 명시하는 것을 승인한다(설치본은 이미 있음)

승인에 따라 **새 패키지는 `flutter_contacts` 하나로 확정**이다. 따라오는 매니페스트 한 줄
(`WRITE_CONTACTS` 제거)은 Task A3 의 첫 항목으로 넣어 뒀다 — 패키지를 넣는 커밋과 같은 커밋에서 뺀다.

---

## 확정된 결정 (2026-09-22 사용자 답)

**추천과 다른 곳은 3 · 4 · 7 · 9 네 곳이다**(굵게). 나머지 아홉은 추천대로 확정됐다.

| # | 물은 것 | 답 | 반영된 곳 |
| --- | --- | --- | --- |
| 1 | 신고 사유 | 한 벌 5개 고정 | C2 · A1 |
| 2 | 신고 대상 | DB 값 4개 미리(`profile` `message` `friend_review` `poll`), 화면은 프로필 · 메시지 둘만 | C2 · B1 · A1 |
| 3 | 자동 가림 | **같은 신고자→같은 대상 1회(unique) + 하루 10건 상한. 서로 다른 3명이면 자동 가림(카드 제외 · 새 매칭 불가, 진행 중 채팅 유지) + 디스코드 "3건 도달". 정지 · 해제는 사람이 판단** | C1 · C2 · B1 |
| 4 | 신고 시 차단 | **신고하면 자동 차단.** 설정 16f 에서 해제 가능 | B1 · A1 |
| 5 | 차단 뒤 내 대화방 | 내 목록에서 바로 사라짐(상대에게는 "나갔어요") | B2 · A2 |
| 6 | 정지 사용자 화면 | 안내 화면 + 문의 메일. **메일 주소는 미정 — 코드에는 상수 자리만** | B7 · A4 |
| 7 | 지인(연락처) 차단 | **조각 6 에 포함.** 패키지는 2026-09-22 `flutter_contacts ^2.5.0` 으로 승인 | B4 · A3 |
| 8 | 30일 삭제 · 신고 1년 삭제 · `signup_blocks` 만료 | Cloud Scheduler job 하나 추가(3/3) | B3 |
| 9 | 배치 인증 | **OIDC 로 전환하고 공유 열쇠는 폐기** | B6 |
| 10 | 14c 상대 프로필 상세 | 조각 6 에 포함 | B5 · A5 |
| 11 | 14f 저장된 카톡 아이디 | GET 하나 추가 + 14f · 16e-1 둘 다 | B5 · A6 |
| 12 | 백로그 처리 | 착수 전 정리 PR 먼저 | **완료 — #84 · #85** |
| 13 | 신고 디스코드 채널 | 별도 채널(`discord-report-webhook-url`) | B1 |

**추가 결정(2026-09-22 사용자 제안).** 정지(suspended)된 사람의 진행 중 채팅은 **상대에게 "나갔어요" 와
같게** 보인다 — 정지 사실은 상대에게도 알리지 않는다.

### 이미 결정돼 있어 다시 묻지 않는 것

- 신고 처리 = 디스코드 알림 + Supabase 대시보드 수동, **24시간 목표**. 관리자 페이지 없음(2026-09-19)
- HMAC 키 교체 = **행마다 키 버전** + 앱 자동 재동기화, 옛 키 30일 보관, 정기 교체 없음(2026-09-19)
- 탈퇴 = 즉시 숨김 · 로그인 차단 → **30일 뒤 완전 삭제**, 재가입 **2개월** 제한(탈퇴 요청 시각 기준),
  **정지 중 탈퇴는 무기한**(설계 §2.6, ERD §11-17 · §11-22)
- 보관 기간 = 신고 1년 · 실명/번호/카톡 30일 · 결제 5년(미결 21)
- **매칭 일시중지 토글은 이미 있다**(조각 4, `profiles.matching_paused` + 설정 화면). 조각 6 은
  탈퇴 확인 화면에서 **연결만** 한다

### 계획서 편차 (결정과 다르게 가는 것)

**① HMAC 키 교체 시 "앱 자동 재동기화" 는 이번 조각에서 만들지 않는다.** 2026-09-19 결정에는 키 버전과
함께 "앱 자동 재동기화" 가 같이 적혀 있지만, **정기 교체를 하지 않기로 한 것도 같은 결정**이다. 키를 바꾸는
일이 실제로 생기지 않는데 재동기화 경로를 미리 만들면, 쓰이지 않는 채로 썩는 코드가 하나 는다.
이번 조각은 **행마다 `key_version` 을 적는 것까지만** 하고 재동기화는 백로그에 둔다.

**그래서 남는 함정(키를 실제로 바꾸는 날 반드시 읽을 것):** `contact_blocks` 의 PK 는
**(`owner_id`, `contact_hmac`)** 다. 키가 바뀌면 같은 전화번호가 **다른 해시**로 계산돼 PK 가 겹치지
않는다 — 같은 사람이 같은 번호를 다시 등록하면 **버전 1 행과 버전 2 행이 둘 다 남는다.** 그 상태에서
옛 키를 버리면 버전 1 행은 대조 불가능한 쓰레기가 되고, 사용자 눈에는 해제해도 사라지지 않는 행으로
보인다. 재동기화를 만들 때는 **버전 1 행을 새 키로 다시 계산해 넣고 옛 행을 지우는 순서**여야 하고,
B4 의 "버전 1 잔량 경고" 가 그날의 알람이다.

---

## Global Constraints

1. **쓰기는 전부 FastAPI 가 `service_role` 로 한다.** 새 테이블 셋 다 클라이언트 쓰기 정책을 두지 않는다.
2. **`reports` 는 클라이언트가 읽지도 못한다.** 신고자에게조차 목록을 주지 않는다(신고 이력 화면 없음).
3. **차단당한 쪽은 알 수 없다.** 응답 어디에도 "차단됨" 을 뜻하는 값을 넣지 않는다 — 나감과 같은 모양이다.
4. **이미 적용된 마이그레이션은 고치지 않는다.** 컬럼 추가도 새 파일로 한다.
5. **enum 값 추가는 트랜잭션이 끝나야 쓸 수 있다** — `alter type ... add value 'withdrawn'` 과 그 값을
   쓰는 check · 인덱스는 **파일을 나눈다**(ERD §4 주석).
6. **원본 연락처는 서버에 올리지 않는다.** 앱이 E.164 로 정규화한 번호만 보내고 서버는 HMAC 만 저장한다.
   이름은 기기에만 둔다(ERD §5, 설계 §7.6b).
7. **문구는 한 곳(`core/errors.py` · 화면 상수)에서만 고친다.**
8. 커밋은 항목별로 쪼갠다. 표식(`Co-Authored-By` 등)은 넣지 않는다.

---

## 새 시크릿 · 배포 설정

| 이름 | 무엇 | 만드는 시점 |
| --- | --- | --- |
| `identity-hmac-key`(Secret Manager) → `IDENTITY_HMAC_KEY` | 이메일 · 연락처 · 번호 해시 공용 키. **정리 PR #85 가 이미 코드에 넣었다** | **지금**(없으면 서버가 부팅하지 않는다) |
| `discord-report-webhook-url` → `DISCORD_REPORT_WEBHOOK_URL` | 신고 전용 채널(결정 13). 기존 `discord-review-webhook-url`(학생증)과 **다른 채널** | 착수 때 사용자가 디스코드에서 생성 |
| 서비스 계정 `campus-mate-scheduler@<project>.iam.gserviceaccount.com` | Cloud Scheduler 3개 job 이 쓸 OIDC 신원 | B6 착수 때 |
| `card-batch-secret` | **폐기 대상**(결정 9) | B6 가 끝나면 버전 비활성화 → 삭제 |

---

## OIDC 전환 절차 (중간에 401 이 나지 않는 순서)

지금은 Cloud Scheduler 가 `X-Batch-Secret` 헤더에 공유 열쇠를 실어 보낸다. 열쇠가 job 설정과 서버 양쪽에
복사돼 있어서 **한쪽만 바꾸면 그 사이 배치가 전부 401** 이 된다(시크릿 v1 이 `\r` 로 오염됐을 때 겪었다).
OIDC 는 열쇠 자체를 없앤다 — 구글이 서명한 ID 토큰을 job 이 달고 오고, 서버는 공개키로 검증만 한다.

**순서(각 단계가 끝난 뒤 다음으로 간다):**

1. **서비스 계정 생성 + 권한.** `roles/run.invoker` 를 Cloud Run 서비스에 준다.
2. **서버를 "둘 다 받게" 배포한다.** `X-Batch-Secret` 이 맞거나 **또는** `Authorization: Bearer <ID 토큰>`
   이 검증되면 통과. ← **이 단계가 있어서 401 창이 없다.**
3. **job 3개를 OIDC 로 바꾼다**(`--oidc-service-account-email`, `--oidc-token-audience=<Cloud Run URL>`),
   같이 `--update-headers` 로 `X-Batch-Secret` 을 뺀다.
4. **`gcloud scheduler jobs run` 으로 3개를 수동 실행**해 200 을 확인한다. 로그에 `auth=oidc` 를 남긴다.
5. **공유 열쇠 경로를 지운다.** `settings.card_batch_secret` · `X-Batch-Secret` 분기 · 관련 테스트를 삭제하고
   배포한다.
6. **Secret Manager `card-batch-secret` 버전을 비활성화**한다. 하루 지켜보고 문제가 없으면 삭제한다.

**검증 코드(B6):**

```python
# backend/app/core/batch_auth.py
# 구글이 서명한 ID 토큰을 공개키로 검증한다. audience 는 Cloud Run 서비스 URL 이고,
# 발급자가 우리 스케줄러 서비스 계정인지까지 본다 — audience 만 보면 같은 URL 을 아는
# 다른 서비스 계정도 통과한다.
claims = await asyncio.to_thread(
    id_token.verify_oauth2_token, token, GoogleAuthRequest(), settings.batch_audience
)
if claims.get("email") != settings.batch_service_account or not claims.get("email_verified"):
    raise HTTPException(status_code=401, detail=errors.UNAUTHORIZED)
```

> **미래 유지보수:** job 이 네 번째로 늘어도 서버는 손대지 않는다 — 서비스 계정 하나를 그대로 쓰면 된다.
> 반대로 job 마다 권한을 나누고 싶어지면 그때 서비스 계정을 쪼개고 `email` 검사에 목록을 받는다.

---

## Cloud Scheduler 3번째 job (결정 8)

| job | 주기 | 엔드포인트 | 하는 일 |
| --- | --- | --- | --- |
| `campus-mate-daily-cards` | `0 7 * * *` | `/batch/daily-cards` | 조각 4 |
| `campus-mate-chat-gate` | `0 * * * *` | `/batch/chat-gate` | 조각 5 |
| **`campus-mate-cleanup`** | `0 4 * * *` | **`/batch/cleanup`** | ① 탈퇴 30일 경과 계정 삭제 ② 신고 **`created_at`** 1년 경과 행 삭제 ③ `signup_blocks` 만료 행 삭제 |

**pg_cron 이 아니라 FastAPI 배치인 이유:** 탈퇴 계정 삭제는 **Storage 파일(프로필 사진 · 아바타)** 도 같이
지워야 하는데, DB 안에서 도는 pg_cron 은 Storage API 를 부를 수 없다.

---

## ERD · 문서 변경 목록 (Part C 를 클라우드에 적용하기 전에 처리)

| 문서 | 무엇 | 상태 |
| --- | --- | --- |
| ERD §3 `profiles` | `withdrawn_at`(제안 → **확정**), **`auto_hidden_at` 신규**(결정 3), `status` 에 `withdrawn` 추가 | **ERD 수정 필요** |
| ERD §3 `profile_private` | `phone_hmac` 을 **실제로 채운다** + **`phone_hmac_key_version`** 신규 | **ERD 수정 필요** |
| ERD §5 `reports` | `reason` 을 5값 check 로 고정, **`reason_note`**(기타 한 줄, 200자) 신규, **unique(`reporter_id`,`target_type`,`target_id`)** 추가 | **ERD 수정 필요** |
| ERD §5 `contact_blocks` · `signup_blocks` | **`key_version`** 신규(2026-09-19 결정 "행마다 키 버전") | **ERD 수정 필요** |
| ERD §8 열거형 | `profile_status` 에 `withdrawn` · `report_target` · `report_status` 를 "제안" → 확정, **`report_reason` 신규** | **ERD 수정 필요** |
| ERD §12 검토 5 | `phone_hmac` 유니크 → **걸지 않기로 확정**(2026-09-22, 아래) | **해결로 옮김** |
| ERD §12 검토 9 · 10 | 키 교체(키 버전으로 해결) · 신고 사유 목록(결정 1로 해결) | **해결로 옮김** |
| 설계 §13 미결 36 | HMAC 키 교체 절차 → 키 버전 + 옛 키 30일 보관으로 확정 | **해결로 옮김** |
| 설계 §13 미결 41 ① ③ | 정리 PR #85 에서 처리 완료 | **해결로 옮김** |
| DESIGN §9 | 신고 시트 · 정지 안내 화면 · **말풍선 롱프레스 메뉴** 신설, 14 · 14c · 14e · 16f · 16b · **FAQ** 문구 개정(아래 대조표) | **DESIGN 수정 필요** |
| `backend/DEPLOY.md` | `IDENTITY_HMAC_KEY` · `DISCORD_REPORT_WEBHOOK_URL` · 3번째 job · OIDC 절차 | **문서 담당** |

**결정(2026-09-22 사용자 답, ERD 검토 5): `profile_private.phone_hmac` 에 유니크를 걸지 않는다.**
"한 번호 한 계정" 을 DB 로 강제하지 않는다는 뜻이다.

**받아들이는 한계:** 학교 메일을 두 개 가진 사람(예: 학부 · 대학원, 편입 전후)은 **같은 번호로 계정 둘을
동시에** 굴릴 수 있다. 그러면 한쪽이 정지되거나 탈퇴해도 다른 쪽으로 계속 쓸 수 있어 **정지 · 재가입 제한을
우회**한다. `signup_blocks` 는 메일 기준이라 이걸 막지 못한다. 이것이 유니크의 진짜 쟁점이고,
"탈퇴 뒤 30일" 은 쟁점이 아니다 — 재가입 제한이 이미 2개월이라 30일은 그 안에 들어간다.
**알려진 한계로 받아들이고 지금은 걸지 않는다.**

*미래 유지보수: 같은 번호 다계정 어뷰징이 실제로 보이면 유니크 인덱스 하나를 나중에 추가할 수 있다.
다만 그때는 이미 쌓인 중복을 사람이 먼저 정리해야 인덱스가 만들어진다 — 먼저 `phone_hmac` 중복 건수를
세어 보는 쿼리 한 줄이 시작점이다.*

---

## 파일 구조

```
supabase/migrations/
  <ts>_add_profile_status_withdrawn.sql        # enum 값만 (C1)
  <ts>_alter_profiles_safety_columns.sql       # withdrawn_at · auto_hidden_at · check (C1)
  <ts>_create_reports.sql                      # (C2)
  <ts>_create_blocks.sql                       # (C3)
  <ts>_create_contact_blocks.sql               # phone_hmac · key_version 포함 (C4)
supabase/tests/rls_slice6_test.sql             # (C5)

backend/app/safety/
  __init__.py  router.py  repository.py  reasons.py  discord.py
backend/app/account/
  __init__.py  router.py  repository.py        # 탈퇴 · 정지 안내 · 카톡 아이디 GET
backend/app/core/batch_auth.py                 # OIDC (B6)
backend/app/batch/cleanup_router.py            # 3번째 job (B3)

frontend/lib/safety/
  model/      report_repository.dart  report_reason.dart  block_repository.dart
  viewmodel/  report_view_model.dart  block_list_view_model.dart  contact_block_view_model.dart
  view/       report_sheet.dart  block_confirm_sheet.dart  block_list_screen.dart
              contact_permission_sheet.dart  contact_picker_screen.dart  contact_block_screen.dart
              suspended_screen.dart
frontend/lib/account/view/withdraw_screen.dart # 16c 1차 · 최종
frontend/lib/profile/view/partner_profile_screen.dart # 14c
```

---

## Part C: Supabase 마이그레이션 (파일 작성 + 로컬 검증까지, 클라우드 적용 금지)

### Task C1: 계정 상태 컬럼

- [ ] `alter type public.profile_status add value 'withdrawn';` **한 줄짜리 파일 하나**
- [ ] 다음 파일에서 컬럼을 추가한다

```sql
alter table public.profiles
  add column withdrawn_at timestamptz,
  -- 결정 3: 서로 다른 세 명이 신고하면 서버가 찍는다. 카드·매칭 후보에서 빠지지만
  -- 진행 중인 채팅은 그대로다. 사람이 검토해 정지하거나 이 값을 지운다(해제).
  add column auto_hidden_at timestamptz;

alter table public.profiles
  add constraint profiles_withdrawn_pair
  check ((status = 'withdrawn') = (withdrawn_at is not null));
```

> **인덱스는 이번에 깔지 않는다.** 후보 쿼리 조건 중 `gender <>` 는 btree 로 잡히지 않고,
> `university_id` 는 조인 조건이라 상수가 아니며, `withdrawn_at is null` 은 쿼리 where 절에 없어
> predicate 가 맞지 않는다 — 플래너가 못 쓸 인덱스다. 백로그로 넘긴다.

- [ ] `profile_private` 에 `phone_hmac bytea` · `phone_hmac_key_version smallint not null default 1` 추가
- [ ] `signup_blocks` 에 `key_version smallint not null default 1` 추가

> **미래 유지보수:** `auto_hidden_at` 을 컬럼으로 두는 이유는 카드 배치가 매번 `reports` 를 세지 않게
> 하려는 것이다. 신고 3건 규칙이 바뀌면 컬럼은 그대로 두고 **찍는 쪽 조건만** 고친다.

### Task C2: `reports`

- [ ] `report_target`(`profile` `message` `friend_review` `poll`) · `report_status`(`open` `actioned`
      `dismissed`) · **`report_reason`**(`abuse` `sexual` `spam` `fake` `other`) enum 생성
- [ ] 표 생성

```sql
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  -- 신고자가 탈퇴해도 근거는 남는다(설계 §2.6 FK 규칙의 예외).
  reporter_id uuid references public.profiles (id) on delete set null,
  target_type public.report_target not null,
  -- FK 를 걸지 않는다. 신고 대상 행(메시지·리뷰·글)이 지워져도 신고는 남아야 한다.
  target_id uuid not null,
  target_profile_id uuid references public.profiles (id) on delete set null,
  -- 원본이 사라져도 24시간 조치 근거가 남아야 한다(애플 1.2, ERD §5).
  target_snapshot jsonb not null,
  reason public.report_reason not null,
  reason_note text check (reason_note is null or char_length(btrim(reason_note)) between 1 and 200),
  status public.report_status not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint reports_status_pair check ((status = 'open') = (resolved_at is null)),
  -- 결정 3: 같은 사람이 같은 대상을 두 번 신고하지 못한다. "3명" 을 세는 기준이기도 하다.
  constraint reports_once_per_reporter unique (reporter_id, target_type, target_id)
);
```

- [ ] `target_profile_id` 인덱스(3명 세기 · 대시보드 조회), **`created_at` 인덱스**(1년 정리 배치 —
      기준이 `resolved_at` 이 아닌 이유는 B3 참고)
- [ ] RLS 켜고 **정책 0개**(default deny), `service_role` 만 grant

> `target_profile_id` 를 따로 두는 이유: 메시지를 신고해도 "누가 신고당했는가" 를 조인 없이 세야 한다.
> *미래 유지보수: 신고 대상이 커뮤니티 글까지 늘어도 이 컬럼 하나로 계속 센다.*

### Task C3: `blocks`

- [ ] `blocker_id` + `blocked_id` 복합 PK, 둘 다 `on delete cascade`, `created_at`(16f 차단일)
- [ ] `check (blocker_id <> blocked_id)`
- [ ] `blocked_id` 인덱스 — 카드 후보에서 **양방향**으로 빼야 한다
- [ ] RLS: **읽기도 주지 않는다**(16f 목록은 FastAPI 가 준다). `service_role` 만

### Task C4: `contact_blocks`

- [ ] `owner_id` + `contact_hmac bytea` 복합 PK, `id uuid unique default gen_random_uuid()`(기기 이름과
      짝지을 키 — ERD §5), `key_version smallint not null default 1`, `created_at`
- [ ] `contact_hmac` 인덱스(매칭 후보 대조용)
- [ ] RLS default deny + `service_role`

### Task C5: pgTAP (`rls_slice6_test.sql`)

- [ ] 세 표 모두 **`authenticated` 가 select 0행 · insert 42501**
- [ ] `reports_once_per_reporter` 가 두 번째 신고를 23505 로 막는다
- [ ] `reports_status_pair` · `profiles_withdrawn_pair` check 가 어긋난 조합을 23514 로 막는다
- [ ] `blocks` 자기 자신 차단이 23514
- [ ] `service_role` 은 셋 다 CRUD 가능
- [ ] 로컬에서 `supabase db reset` → `supabase test db` 로 확인(**클라우드 적용 금지**)

---

## Part B: FastAPI

### Task B1: 신고 (`backend/app/safety/`)

- [ ] `POST /reports` — 본문 `{target_type, target_id, reason, reason_note?}`
- [ ] 사유 5개는 `reasons.py` 한 곳에 둔다(앱과 문구를 맞춘다)

| 값 | 화면 문구 |
| --- | --- |
| `abuse` | 욕설 · 비방 · 혐오 표현 |
| `sexual` | 성적 불쾌감을 주는 내용 |
| `spam` | 광고 · 스팸 · 외부 유도 |
| `fake` | 사칭 · 허위 프로필 |
| `other` | 기타(한 줄 입력) |

- [ ] **처리 순서**: ① 대상 존재 확인 + **접근 권한 — 지금 또는 과거에 매칭이 있던 상대만 신고할 수
      있다**(`match_participants` 에 둘이 같이 있던 방이 하나라도 있어야 한다. 방이 없어도 200 이라
      이걸 안 막으면 아무나 셋이 모여 임의의 프로필을 가릴 수 있다) → ② 하루 10건 상한 확인(24시간 창, 넘으면 **429**)
      → ③ `target_snapshot` 구성(프로필이면 닉네임 · 사진 URL · 자기소개, **메시지면 본문 · 보낸 시각 ·
      말풍선 id** — A1 의 말풍선 롱프레스 진입점이 보내는 `message_id` 가 `target_id` 다)
      → ④ **차단 먼저**(결정 4, B2 의 함수를 그대로 부른다) → ⑤ `reports` INSERT(중복이면 **409**
      "이미 신고한 사용자예요") → ⑥ 디스코드 한 줄 → ⑦ 서로 다른 신고자 수를 세어 **3 이상이면**
      `auto_hidden_at` 을 찍고 디스코드에 "3건 도달 · 검토 필요" 를 한 줄 더
- [ ] **④ 와 ⑤ 의 순서가 중요하다.** 둘은 PostgREST 호출 두 번이라 한 트랜잭션이 아니다. 신고를 먼저
      넣으면 차단이 409(`CHAT_CLOSED`) · 404 로 넘어졌을 때 **신고만 남고 차단은 안 된 상태**로 갇히고,
      사용자가 다시 신고해도 `reports_once_per_reporter` 409 라 영영 차단할 방법이 없다. 차단이 멱등
      (B2, 이미 차단이면 200)이라 먼저 해도 두 번 해도 안전하다. 반대로 차단만 되고 신고가 실패하면
      **앱이 시트를 안 닫고 다시 보낸다**(A1) — 차단 뒤에는 방 · 14c · 카드가 다 사라져 신고 진입점이
      없어지므로, "나중에 다시 신고하면 된다" 는 성립하지 않는다
- [ ] **이미 닫힌 방(나갔거나 상대가 나간 방)을 신고 · 차단할 때**: 방 상태를 보지 않고 `blocks` 행만
      세우고 **200**. `match_participants` 가 이미 `left_at` 이면 그 단계를 건너뛴다 — 차단은 방이 아니라
      사람에 거는 것이라 방이 닫혔다고 실패하면 14c(프로필)에서 온 차단이 막힌다. 단 ① 의 접근 권한은
      그대로다(한 번도 매칭된 적 없는 상대는 **403**)
- [ ] 디스코드 실패가 신고 실패가 되지 않게 한다(조각 1b 의 `discord_notifier` 와 같은 방식)
- [ ] 디스코드 한 줄에 **번호만 싣는다** — `report_id` · `target_profile_id` · 사유 코드 · 누적 건수까지.
      **`target_snapshot` · 메시지 본문 · 사진 URL 은 싣지 않는다**(2026-09-19 결정). 운영자는 링크를 보고
      대시보드에서 본다 — 채널에 본문이 흐르면 신고 내용이 웹훅 히스토리에 영구히 남는다
- [ ] 테스트: 409 · 429 · 스냅샷 내용 · 차단 행이 같이 생기는가 · 3번째 신고에서만 가림 · 디스코드 2건
      · **`reports` INSERT 가 실패해도 차단은 남아 있다** · **디스코드 본문에 스냅샷이 없다**
      · 닫힌 방(과거 매칭)의 상대를 신고해도 200 · **한 번도 매칭된 적 없는 상대는 403**

> **미래 유지보수:** "3명" 과 "하루 10건" 은 `reasons.py` 옆 상수 두 개다. 숫자를 바꿔도 다른 코드는 그대로다.

### Task B2: 차단 · 차단 목록 (16f)

- [ ] `POST /blocks/{profile_id}` — `blocks` INSERT + **내 `match_participants.left_at`** 찍기(조각 5 의
      나가기와 같은 함수) + 상대에게는 나감 시스템 줄. 이미 차단돼 있으면 **200 으로 그냥 성공**(재시도
      안전 — 조각 5 "이미 나간 방" 과 같은 판단)
- [ ] **이미 닫힌 방이어도 200.** `blocks` 행만 세우고 방 단계는 건너뛴다. B1 이 이 함수를
      먼저 부르기 때문에(위 필수 순서) 여기가 방 상태로 실패하면 신고 전체가 막힌다
- [ ] `GET /blocks` — 닉네임 · 차단일. **아바타는 준다, 실사진은 주지 않는다**
- [ ] `DELETE /blocks/{profile_id}` — 해제. **대화는 복구하지 않는다**(16f 문구 그대로)
- [ ] 카드 후보 쿼리(조각 4)와 매칭 후보 쿼리(조각 3)에 **양방향 제외**와 **`auto_hidden_at is null`**
      을 **같은 마이그레이션에서 함께** 넣는다 — C1 이 만들고 B1 ⑦ 이 찍는 값인데 읽는 곳이 없으면
      자동 가림이 아무 일도 하지 않는다
- [ ] 테스트: 차단 뒤 내 목록에서 방이 빠진다 · 상대 목록에는 남고 `partner_left` 가 켜진다 ·
      해제해도 방은 안 돌아온다 · 카드 후보에서 양방향으로 빠진다 ·
      **`auto_hidden_at` 이 찍힌 사람은 카드 후보에서 빠진다**

### Task B3: 탈퇴 · 정리 배치

- [ ] `POST /account/withdraw` — 순서: `status='withdrawn'` + `withdrawn_at=now()` → `signup_blocks`
      INSERT(`blocked_until = now() + 2개월`, **정지 중이었으면 `infinity`**) → `push_tokens` 삭제 →
      `student-id-temp` 파일 삭제 → 세션 무효화
- [ ] 로그인 게이트(`current_user`)에서 `withdrawn` 은 **401 + 탈퇴 안내 문구**
- [ ] `POST /batch/cleanup` — ① `withdrawn_at < now() - 30일` 인 프로필: Storage 사진 삭제 후 행 삭제
      (FK cascade 가 나머지를 정리한다) ② **`created_at < now() - 1년`** 인 신고 삭제 ③ `blocked_until` 이
      지난 `signup_blocks` 삭제(`infinity` 는 남긴다)
- [ ] ② 의 기준은 **`resolved_at` 이 아니라 `created_at`** 이다 — 보관 1년은 "신고가 들어온 날" 기준이고,
      `open` 인 신고는 `resolved_at` 이 NULL 이라(`reports_status_pair`) `resolved_at` 으로 세면 처리되지
      않은 신고가 영원히 남는다. C2 의 인덱스도 `resolved_at` 이 아니라 **`created_at`** 에 건다
- [ ] 배치는 **건수를 세어 응답**한다(조각 4·5 와 같은 모양) — 재실행해도 안전해야 한다
- [ ] 테스트: 29일은 안 지우고 31일은 지운다 · `infinity` 행은 남는다 · 재실행해도 건수가 늘지 않는다

> **미래 유지보수:** 30일 · 1년 · 2개월은 상수 세 개다. 법무 검토(미결 21)에서 기간이 바뀌면 여기만 고친다.

### Task B4: 지인(연락처) 차단

- [ ] `POST /contact-blocks` — 본문 `{numbers: ["+8210...", ...]}`(E.164). 서버가 HMAC 계산 후 저장,
      응답은 `[{id, contact_hmac 없음}]`. **원본도 해시도 클라이언트에 돌려주지 않는다**
- [ ] `GET /contact-blocks` — `[{id, created_at}]` 만(이름은 기기에 있다)
- [ ] `DELETE /contact-blocks/{id}`
- [ ] **`phone_hmac` 채우기 — 경로 확정.** 지금 번호는 `set_phone_number(p_profile_id, p_phone, p_key)`
      RPC 가 `pgp_sym_encrypt` 로 넣는다(조각 2). **FastAPI 가 HMAC 을 계산해 RPC 인자로 넘기고**, RPC 를
      **새 마이그레이션 파일에서 `phone_hmac` · `phone_hmac_key_version` 까지 쓰는 버전으로 교체**한다
      (인자가 늘어 시그니처가 바뀌므로 옛 시그니처를 `drop function` 하고 새로 만든다. 적용된 파일은
      고치지 않는다 — 제약 4). **키는 FastAPI 에만 있다** — DB 안에서 HMAC 을 계산하면 신원 해시 키가
      Postgres 에 들어가고, 그러면 대시보드에서 번호와 해시를 맞춰 볼 수 있게 된다
- [ ] 기존 사용자 백필은 `/batch/cleanup` 이 아니라 **한 번 쓰고 버리는 스크립트**로 돈다 —
      FastAPI 가 `decrypt_phone_number` 로 풀고 해시를 채운다(암호문이라 DB 혼자서는 못 한다)
- [ ] 매칭 후보에서 제외: `contact_blocks.contact_hmac = 상대.phone_hmac` **양방향**(내가 등록한 지인도,
      나를 등록한 사람도 서로 안 보인다)
- [ ] 키 버전: 계산할 때 현재 키 버전을 같이 적는다. 대조는 **같은 버전끼리만** 한다

> **미래 유지보수:** 키를 바꾸면 새 행만 버전 2 로 쌓이고 옛 행은 옛 키로 계속 대조된다. 옛 키를 30일 뒤
> 버릴 때 남은 버전 1 행이 있으면 지인 차단이 조용히 풀리므로, 정리 배치에 **버전 1 잔량 경고**를 한 줄 남긴다.

### Task B5: 14c 상대 프로필 상세 · 카톡 아이디 GET

- [ ] `GET /profiles/{profile_id}` — **매칭 상대일 때만**. 게이트 통과 전이면 아바타 · 닉네임 · 태그까지,
      통과 후면 실사진 · 카카오톡 아이디까지. 차단 · 탈퇴 · 정지 상대면 **404**
- [ ] `GET /account/kakao-id` — 내 것(백로그 17, 14f 시트와 16e-1 이 같이 쓴다)
- [ ] 테스트: 매칭이 아닌 사람은 404 · 게이트 전후로 응답 키가 달라진다 · 정지 상대는 404

### Task B6: 배치 인증 OIDC 전환 (결정 9)

- [ ] `core/batch_auth.py` 신설 — 위 "OIDC 전환 절차" 의 검증 코드
- [ ] **2단계(둘 다 받기)를 먼저 배포**하고, job 3개를 바꾼 뒤, 마지막 커밋에서 공유 열쇠 경로를 지운다
- [ ] `settings.card_batch_secret` · `X-Batch-Secret` 분기 · 관련 테스트 삭제
- [ ] 테스트: 토큰 없음 401 · audience 불일치 401 · 다른 서비스 계정 401 · 정상 200

### Task B7: 정지(suspended) 처리

- [ ] 게이트에서 `suspended` 는 **403 + 정지 안내 코드**를 준다(로그인 자체는 살려 둔다 — 안내 화면을
      띄워야 하고 문의 메일을 보여야 한다)
- [ ] 채팅 조회에서 **상대가 `suspended` 면 `partner_left` 를 켠다**(추가 결정). `left_at` 은 찍지 않는다
- [ ] 카드 · 매칭 후보에서 제외
- [ ] **정지를 보는 곳은 조회만이 아니다.** 아래 세 경로도 같은 판정을 탄다 — 하나라도 빠지면 정지된
      사람이 계속 말을 걸거나, 정지 중에 방이 자동으로 닫혀 "풀면 그대로 돌아온다" 가 깨진다
      - 메시지 보내기(`POST /chat/{match_id}/messages`) — 보내는 쪽이 정지면 403, **상대가 정지면
        조각 5 의 "상대가 나갔어요" 와 같은 409**(정지 사실을 알리지 않는다)
      - 게이트 배치(`/batch/chat-gate` — 24h 리마인드 · 48h 종료) — **어느 한쪽이 정지면 그 방을
        건너뛴다.** 정지 중에 시간이 흘러 방이 종료되면 해제해도 대화가 돌아오지 않는다
      - 푸시 발송(새 메시지 · 카드 · 매칭) — 정지 계정에는 보내지 않는다
- [ ] 테스트: 정지 계정의 모든 API 403 · 상대 방은 "나갔어요" 와 같은 응답 · 정지를 풀면 그대로 돌아온다
      · **정지 중에는 게이트 배치가 그 방의 시계를 건드리지 않는다** · 정지 상대에게 보내기는 409

> **미래 유지보수:** 정지를 `left_at` 으로 구현하면 해제가 불가능해진다. 조회 시점 판정이라 대시보드에서
> `status` 한 칸만 되돌리면 끝이다.

### Task B8: 배포 문서 (`backend/DEPLOY.md`)

- [ ] `IDENTITY_HMAC_KEY` · `DISCORD_REPORT_WEBHOOK_URL` 을 `--set-secrets` 줄에 추가
- [ ] 3번째 job 생성 명령, OIDC 6단계, 공유 열쇠 폐기 절차

---

## Part A: Flutter (**pen 확정 뒤 착수**)

### Task A1: 신고 시트 (신규 화면)

- [ ] 사유 5개 라디오 + 기타일 때만 한 줄 입력(200자) + "신고하기"
- [ ] 신고 뒤 안내: "신고했어요. 이 사용자는 차단되어 서로에게 보이지 않아요."(결정 4 를 숨기지 않고 알린다)
- [ ] 409 → "이미 신고한 사용자예요", 429 → "오늘은 더 신고할 수 없어요"
- [ ] **409 · 429 가 아닌 실패는 시트를 닫지 않고 "다시 시도" 를 띄운다** — 같은 요청을 그대로 다시
      보낸다(B1 ④ 차단이 멱등이라 두 번 가도 안전하다). 시트를 닫아 버리면 차단은 됐는데 신고는 안 된
      상태로 남고, 방 · 14c · 카드가 모두 사라져 다시 신고할 진입점이 없다
- [ ] 진입점 3곳: 채팅방 앱바 메뉴(프로필 신고) · 14c 하단 액션 행(프로필 신고) ·
      **말풍선 롱프레스 → "이 메시지 신고"**(메시지 신고). 결정 2 가 정한 화면 진입점은 프로필 · 메시지
      둘인데 메시지 쪽이 빠져 있었다. 롱프레스는 `target_type='message'` 에 그 말풍선의 `id` 를
      `target_id` 로 보낸다 — B1 ③ 이 그 id 로 본문 · 보낸 시각을 스냅샷에 담는다
- [ ] **내가 보낸 말풍선에는 신고 메뉴를 띄우지 않는다**(자기 신고)

### Task A2: 차단 · 16f 차단 목록

- [ ] 14e 확인 시트 → `POST /blocks` → **방을 목록에서 없애고 대화 목록으로**
- [ ] 16f: 닉네임 + 차단일 + 해제 버튼 + 해제 확인 시트 + 빈 상태 + 연락처 차단 안내 한 줄

### Task A3: 지인 차단 (8a → 8d → 16b)

- [ ] `flutter_contacts: ^2.5.0` 을 `pubspec.yaml` 에 넣고, **같은 커밋에서**
      `android/app/src/main/AndroidManifest.xml` 에 `WRITE_CONTACTS` 제거 한 줄
      (`tools:node="remove"`, 위 "새 의존성" 절의 스니펫)을 넣는다 — 패키지만 먼저 들어가면
      그 사이에 만든 빌드에 쓰기 권한이 그대로 붙는다
- [ ] 8a 권한 안내 시트 → 패키지 권한 요청 → 거부면 8a-2
- [ ] 8d 연락처 선택(검색 · 다중 선택 · 카운트 CTA), 번호를 **E.164 로 정규화해서** 전송
- [ ] 16b 관리: 기기에 저장한 이름과 서버 `id` 를 짝지어 표시, 이름이 없으면 "이전에 차단한 연락처"
- [ ] 이름은 **기기 저장소에만** 둔다(ERD §5)

### Task A4: 탈퇴(16c) · 정지 안내 화면

- [ ] 16c 1차: 삭제 항목 안내 + **"매칭만 잠시 멈추기"(이미 있는 토글로 보낸다)** + "영구 삭제"
- [ ] 16c 최종: 재가입 2개월 안내 + "정말 영구 삭제"
- [ ] 정지 안내 화면(신규): 사유 요약 + 문의 메일 **상수 자리**(`supportEmail = '' // 사용자 확정 전`)
      + 로그아웃. 403 정지 코드를 받으면 어느 화면에서든 여기로 보낸다
- [ ] **`core/http/http_send.dart` 의 `_classify` 에 403(정지) · 401(탈퇴) 분기를 넣고**
      `common/failure.dart` 에 `SuspendedFailure` · `WithdrawnFailure` 를 더한다. 지금은 4xx 가 전부
      `ServerRejectedFailure(detail 문자열)` 로 뭉쳐서, 화면이 "정지" 를 문자열 비교로만 알아낼 수 있다
      — 서버 문구를 한 글자 고치면 정지 화면으로 못 보낸다. 401 은 이미 `SessionExpiredFailure` 가
      있으니 **본문 코드로 세션 만료와 탈퇴를 가른다**(만료는 재로그인, 탈퇴는 안내 문구)
- [ ] 테스트: 403 → `SuspendedFailure` · 401+탈퇴 코드 → `WithdrawnFailure` · 401 만 있으면 기존대로

### Task A5: 14c 상대 프로필 상세

- [ ] 14b "상대 프로필 보기" 버튼을 살린다(조각 5 에서 비워 뒀다)
- [ ] 하단 액션 행 "신고하기 · 차단하기"

### Task A6: 14f 시트 · 16e-1 카톡 아이디

- [ ] 14f 시트에 "저장된 카카오톡 아이디 · 변경"(백로그 17) 붙이기
- [ ] 16e-1 전용 화면(설정 → 계정 → 카카오톡 아이디)

---

## 화면 대조표 (pen 작업 지시서 — 담당: erd3)

파일: **`C:\Users\home\OneDrive\Desktop\datingApp\design\datingApp.pen`**(pencil MCP 로만 읽는다).
master 세션은 **읽기만** 했고 수정하지 않았다.

| 화면 | pen 노드 | 판정 | 무엇을 그려야 하는가 |
| --- | --- | --- | --- |
| **신고 시트**(사유 5개) | **없음** | **새로 그림** | `GrabHandle` → "무엇을 신고할까요?" → 라디오 5개(욕설·비방·혐오 / 성적 불쾌감 / 광고·스팸 / 사칭·허위 / 기타) → 기타 선택 시 한 줄 입력(200자 카운터) → `button-danger`("신고하기") / `button-text`("취소") → 완료 토스트 "신고했어요. 이 사용자는 차단되어 서로에게 보이지 않아요." **14e 와 같은 시트 골격**을 복사해 쓰면 된다 |
| **정지 안내 화면** | **없음** | **새로 그림** | 전체 화면(앱바 없음). 아이콘 + "이용이 제한된 계정이에요" + 설명(신고 누적 검토 결과) + 문의 메일 행(**주소는 자리만**, 값은 사용자가 나중에) + `button-text`("로그아웃"). 하단 내비 없음 |
| 14 채팅방 | `ioKLk` | **수정 필요** | 앱바 `⋯` 메뉴에 **"신고하기" · "차단하기"** 추가(지금은 "채팅방 나가기" 하나뿐). 메뉴 펼친 상태 한 장이 필요하다 |
| 14 채팅방(말풍선 롱프레스) | **없음** | **새로 그림** | **상대 말풍선을 길게 누르면 뜨는 작은 시트/메뉴 한 장** — 행 하나("이 메시지 신고"). 결정 2 의 "메시지 신고" 진입점이 여기다. 누르면 신고 시트가 그 말풍선을 대상으로 열린다(선택된 말풍선은 살짝 강조). **내 말풍선에는 뜨지 않는다** |
| 14 채팅방(끊김 배너) | 없음(Notice `WQIrY` 재사용) | 참고 | 정리 PR #85 에서 "연결이 끊겼어요 / 다시 시도" 배너가 생겼다. 기존 **Notice(`WQIrY`)** 를 그대로 써서 **새로 그릴 것은 없다**(`teNRJ` 는 Alert 이다 — 노드 이름을 헷갈리지 말 것) |
| 14b 신뢰 확인 후 | `albnG` | **수정 필요** | "상대 프로필 보기" 버튼이 이제 실제로 14c 로 간다(조각 5 에서 비워 둔 자리) |
| 14c 상대 프로필 상세 | `VTX3D` | **수정 필요** | 하단 액션 행이 "신고하기 · 차단하기" 로 이미 그려져 있다 — **신고하기 탭 → 신고 시트** 연결선만 없다. 앱바(`WpvDL`)는 그대로 |
| 14d 상대 지인 리뷰 전체 | `FXNL4` | 있음(변경 없음) | 지인 리뷰 조각에서 쓴다. 조각 6 은 건드리지 않는다 |
| 14e 상대 차단 확인 | `aCTy1` | **수정 필요** | 문구가 결정 5 와 어긋난다. 현재 "대화가 종료되고, 서로의 카드에 다시 나타나지 않아요" → **"이 대화는 내 목록에서 사라지고, 서로의 카드에 다시 나타나지 않아요. 상대에게는 대화를 나갔다고 표시돼요."** 로. "설정 > 차단 목록에서 해제할 수 있어요" 는 유지 |
| 14f 신뢰 확인 시트 | `p0XJA6` | **수정 필요** | "저장된 카카오톡 아이디 · 변경"(→16e-1) 행 추가(백로그 17). 나머지는 그대로 |
| 14g · 14h 배너 | `SJWl0` · `KGjJx` | 있음(변경 없음) | — |
| 16 설정 | `lMDpY` | 있음(변경 없음) | 행 4개(계정 · 알림 · 차단 목록 · 연락처 차단)와 탈퇴 버튼이 이미 있다 |
| 16b 연락처 차단 관리 | `fkjEh`(빈 상태 `Gp5my`, 해제 시트 `AA8T7`) | **수정 필요** | 이름을 모르는 행("이전에 차단한 연락처") 상태를 한 줄 추가 — 앱 재설치·기기 교체 때 실제로 이렇게 보인다(ERD §5) |
| 16c 탈퇴 1차 · 최종 | `rAitU` · `hleae` | 있음(변경 없음) | "매칭만 잠시 멈추기 → 일시중지" 가 이미 그려져 있다. 그대로 구현한다 |
| 16e 계정 | `i3WGAa` | 있음(변경 없음) | "연락처 공개 정보 → 카카오톡 아이디" 행이 이미 있다 |
| 16e-1 카톡 아이디 변경 | `bWrnD` | 있음(변경 없음) | 저장된 값을 서버에서 읽어 채운다(B5 의 GET) |
| 16f 차단 목록 | `Oby6v`(카드 `JULLG`, 해제 시트 `FzXZ4`) | **수정 필요** | ① **신고해서 생긴 차단도 같은 목록에 섞인다** — 행에 사유를 적지 않는다(적으면 해제 화면이 신고 이력이 된다). 카드 캡션을 "차단한 날짜" 로 통일 ② 빈 상태 한 장이 없다 ③ **문구가 14e 와 같은 문제다** — 화면 안내의 "진행 중이던 대화도 종료돼요" → **"차단하면 그 대화는 내 목록에서 사라져요"**, 해제 시트(`FzXZ4`)의 "종료된 대화는 복구되지 않아요" → **"사라진 대화는 돌아오지 않아요"**. 상대에게는 "나갔어요" 로 보인다는 사실과 말을 맞춘다 |
| 8a 연락처 권한 안내 | `KgX8O` | 있음(변경 없음) | 문구 "전화번호는 암호화해 대조에만 쓰고 원본은 저장하지 않아요" 는 사실과 맞다(§7.6b) |
| 8a-2 권한 거부 | `M9ovbi` | 있음(변경 없음) | — |
| 8b 지인 차단 소개 · 8c 전화번호 입력 | `B25TL5` · `z64ze` | **미사용(그대로 둠)** | DESIGN §9 8d 주석대로 체인에서 빠진 화면이다. **되살리지 않는다** |
| 8d 차단할 연락처 선택 | `bWKuJ` | **수정 필요** | 하단에 "번호는 암호화해 대조에만 쓰고 원본은 저장하지 않아요" 한 줄 고정(권한 화면을 지나 여기서 실제로 고르는 순간에 다시 보여야 한다) |
| FAQ(도움말) | 질문 `CgWrI` · 답변 `mfNt8` | **수정 필요** | "신고하면 어떻게 되나요?" 의 **답변이 카드 구매 설명으로 붙어 있다**(복사 흔적). 조각 6 내용으로 바꾼다: "신고한 사용자는 바로 차단돼 서로에게 보이지 않아요. 접수된 신고는 24시간 안에 확인하고, 필요하면 이용을 제한해요. 차단은 설정 > 차단 목록에서 해제할 수 있어요." |
| 9. 유저플로우 | `dJJM2` · `mO35F`(07 프로필·설정) · `cknsr`(08 도움말·계정 삭제) | **수정 필요** | 아래 플로우 4개를 레인에 잇는다 |

### 유저 플로우 (erd3 가 화살표로 이을 순서)

**① 신고 → 자동 차단**

```
14 채팅방(⋯ 메뉴) ─ "신고하기" ─→ [신고 시트] ─ 사유 선택 → 신고하기 ─→ 토스트("신고했어요…")
                                                           └→ 13 대화 목록(그 방이 사라진 상태)
14 채팅방(상대 말풍선 롱프레스) ─→ [메시지 메뉴] ─ "이 메시지 신고" ─→ [신고 시트] (같은 시트, 대상만 메시지)
14c 상대 프로필 상세 ─ "신고하기" ─→ [신고 시트] (같은 시트)
```

**② 차단 → 해제**

```
14c ─ "차단하기" ─→ 14e 차단 확인 시트 ─ "차단" ─→ 13 대화 목록(방 사라짐)
16 설정 ─ "차단 목록" ─→ 16f ─ "해제" ─→ 해제 확인 시트 ─→ 16f(행 사라짐, 대화는 안 돌아옴)
```

**③ 지인 차단**

```
16 설정 ─ "연락처 차단" ─→ (최초) 8a 권한 안내 ─ 허용 ─→ OS 권한 팝업 ─→ 8d 선택 ─ "차단하기" ─→ 16b
                          └ 거부/나중에 ─→ 8a-2
                        (재진입·권한 있음) ─→ 16b ─ "+ 추가" ─→ 8d
```

**④ 탈퇴 · 정지**

```
16 설정 ─ "탈퇴하기" ─→ 16c 1차 ─ "매칭만 잠시 멈추기" ─→ 16 설정(토글 OFF)
                              └ "영구 삭제" ─→ 16c 최종 ─ "정말 영구 삭제" ─→ 02 로그인(탈퇴 안내)
(정지된 계정) 로그인 ─→ [정지 안내 화면] ─ "로그아웃" ─→ 02 로그인
```

**pen 에 없는 세 장(신고 시트 · 정지 안내 화면 · 말풍선 롱프레스 메뉴)은 새로 그리고, 나머지
"수정 필요" 는 기존 노드를 고친다.** master 세션은 pen 을
그리지 않는다 — 이 표가 erd3 의 작업 지시서이고, 사용자 검토가 끝나야 Part A 를 시작한다.

---

## 스토어 권한 사유 문구 초안 (연락처)

**Google Play — 데이터 세이프티 / 권한 선언**

> CampusMate는 사용자가 아는 사람(지인)과 서로 추천되지 않도록, 사용자가 직접 고른 연락처의 전화번호만
> 읽습니다. 선택한 번호는 기기에서 국제 표준 형식으로 바꾼 뒤 **되돌릴 수 없는 해시(HMAC)로 변환해
> 전송**하며, 원본 전화번호·이름·이메일은 서버에 저장하지 않습니다. 연락처 데이터는 광고·분석·제3자
> 공유에 사용하지 않고, 사용자가 차단을 해제하면 해당 해시는 즉시 삭제됩니다. 쓰기 권한
> (`WRITE_CONTACTS`)은 사용하지 않으며 매니페스트에서 제거했습니다.

**iOS — `NSContactsUsageDescription`(Info.plist, 한 문장)**

> 아는 사람과 서로 추천되지 않도록, 직접 고른 연락처의 전화번호만 확인하는 데 사용해요. 번호는 암호화해
> 대조에만 쓰고 원본은 저장하지 않아요.

**앱 안 문구(8a 권한 안내)는 이미 pen 에 있는 문장을 그대로 쓴다** — 세 곳의 말이 서로 다르면 심사에서
가장 먼저 걸린다.

---

## PR 분할 (base 는 항상 main, stacked 금지)

| # | PR | 내용 | 겹치는 파일 |
| --- | --- | --- | --- |
| 1 | **DB** | C1~C5(마이그레이션 5개 + pgTAP) | 없음 |
| 2 | **서버 · 안전** | B1 신고 · B2 차단 · B5 14c/카톡 GET · B7 정지 | `backend/` |
| 3 | **서버 · 계정** | B3 탈퇴 · 정리 배치 · B4 지인 차단 | `backend/`(2 merge 뒤 시작) |
| 4 | **배포 · OIDC** | B6 · B8 — 절차가 있어 **되돌리기 쉬워야** 한다. 단독 PR | `backend/app/core/batch_auth.py` · `DEPLOY.md` |
| 5 | **앱 · 안전** | A1 신고 · A2 차단/16f · A5 14c | `frontend/` |
| 6 | **앱 · 계정** | A3 지인 차단 · A4 탈퇴/정지 · A6 14f/16e-1 | `frontend/`(5 merge 뒤) |

커밋은 항목별로 쪼갠다(모델 / 저장소 / 화면 / 테스트). **PR 5·6 은 pen 확정 뒤에 연다.**

---

## 테스트 전략

| 층 | 무엇을 | 어떻게 | Task |
| --- | --- | --- | --- |
| DB | 세 표 RLS(0행 · 42501) · unique · check | pgTAP | C5 |
| 서버 · 신고 | 중복 409 · 상한 429 · 스냅샷 · 차단 동반 · 3건에서만 가림 · 디스코드 2건 | `TestClient` + `MockTransport` | B1 |
| 서버 · 차단 | 내 방만 사라짐 · 상대는 `partner_left` · 해제해도 복구 없음 · 카드 양방향 제외 | 같음 | B2 |
| 서버 · 탈퇴 | `signup_blocks` 기간 · 정지 중 탈퇴는 `infinity` · 토큰 삭제 · 재로그인 401 | 같음 | B3 |
| 서버 · 배치 | 29일/31일 경계 · `infinity` 잔존 · 재실행 멱등 | 같음 | B3 |
| 서버 · 지인 | HMAC 저장 · 원본 미저장 · 키 버전 대조 · 양방향 제외 | 같음 | B4 |
| 서버 · OIDC | 토큰 없음/audience 불일치/다른 SA 401 · 정상 200 · **전환 중에는 옛 헤더도 200** | 같음 | B6 |
| 서버 · 정지 | 모든 API 403 · 상대 방 표시 · 해제 시 복구 | 같음 | B7 |
| 앱 · 저장소 | URL · 바디 · 4xx 문구 | `MockClient` | A1~A6 |
| 앱 · ViewModel | 사유 선택 · 기타 입력 필수 · 상한 문구 · 차단 뒤 목록 갱신 | `ProviderContainer` | A1~A4 |
| 앱 · 화면 | 시트 구성 · 정지 화면 분기 · 16f 빈 상태 · 8d 다중 선택 | `testWidgets` | A1~A6 |

**연락처 패키지는 인터페이스 뒤에 숨긴다**(`ContactSource`) — 조각 4 의 `PushMessaging`, 조각 5 의
`MessageStream` 과 같은 경계다. 테스트는 가짜 연락처 목록을 끼우고 실제 권한을 부르지 않는다.

**기준선(정리 PR #84 · #85 merge 후):** pytest **276** · flutter test **392** · pgTAP **144**(Files=6) ·
마이그레이션 **31**. 조각 6 이 끝나면 네 숫자가 모두 늘어야 하고, **줄어든 항목이 있으면 무언가 깨진 것이다.**

---

## 백로그 (이번 조각에서 하지 않는다)

- **관리자 페이지** — 대시보드 + 디스코드로 운영한다(2026-09-19 결정). 신고가 하루 수십 건이 되면 그때
- **자동 조치(정지 자동화)** — 3건 자동 가림까지만. 정지는 사람이 판단한다
- **신고 이력 화면 · 처리 결과 알림** — 신고자에게 결과를 알리지 않는다
- **커뮤니티 글 · 지인 리뷰 신고 화면** — DB 값(`poll` · `friend_review`)만 미리 만들어 둔다(결정 2)
- **`phone_hmac` 유니크("한 번호 한 계정")** — 2026-09-22 걸지 않기로 확정. 같은 번호 다계정은
  알려진 한계로 둔다(위 ERD 변경 목록 아래 설명)
- **카드 후보 인덱스** — `profiles_active_pool_index` 는 C1 에서 뺐다. 구현 뒤 `explain analyze` 를 보고
  필요하면 `(university_id, last_active_at desc) where status = 'active' and not matching_paused
  and auto_hidden_at is null` 로 만든다
- **차단 목록 페이징** — 수십 건까지는 한 번에 준다
- **연락처 자동 재동기화** — 지금은 8d 에서 다시 고를 때만 갱신한다
- **HMAC 키 교체 시 앱 자동 재동기화** — 위 "계획서 편차 ①"(정기 교체를 하지 않으므로 미룬다)
- 조각 5 백로그 8 · 9(메시지 길이 pgTAP · 커서 인덱스), 11~16, 20~22 는 그대로 남아 있다
