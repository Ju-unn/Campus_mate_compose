# 지인 리뷰 작성자 삭제(20e "내가 쓴 리뷰") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 리뷰를 쓴 사람이 자기 리뷰를 모아 보고 지울 수 있게 한다(설계 원안 복원, 사용자 "가" 2026-09-29).

**Architecture:** 서버에 읽기 하나(`GET /friend-reviews/written`) · 지우기 하나(`DELETE /friend-reviews/{id}`)를 더한다. 앱은 15 지인 리뷰 섹션에 줄 하나를 더하고 새 화면 20e 를 20c 모양 그대로 만든다(카드 깃발 자리에 휴지통). DB 는 바꾸지 않는다.

**Tech Stack:** FastAPI + PostgREST(서버) · Flutter/Riverpod(앱). 앞 계획서 `2026-09-28-friend-review.md` 의 모델 · 카드 · 20c 를 다시 쓴다.

---

## 결정 (통합대장 · 사용자 2026-09-29)

1. **작성자는 자기 리뷰를 지울 수 있다.** 받은 사람은 여전히 못 지우고 신고만 한다(spec §2.8 그대로).
2. **하드 삭제.** DB 변경 없음 — `friend_reviews` 에 service_role delete 권한이 이미 있다(마이그레이션 20260928040000 32줄). 신고 기록은 `reports.target_snapshot`(태그 · 한마디 · 시각)에 남고 `target_id` 는 FK 가 없어(20260927010200) 원본이 지워져도 신고가 깨지지 않는다.
3. **다시 쓰기는 막지 않는다.** unique(작성자, 받은 사람)는 행이 없어지면 풀리지만, 20b 입구가 가입 흐름 · 추천 푸시뿐이라 실제로 다시 쓸 길이 없다. 막는 칸을 따로 두지 않는다(ponytail).
4. **입구 (가)** — 15 지인 리뷰 섹션(`Cux1p`) 분홍 줄 `o9BA0` 아래 12 에 흰 줄 `tStBN` "내가 쓴 리뷰 N개" → 20e(pen `FEysN`).
5. **문구**: 확인 시트 "리뷰를 지울까요?" · 본문 "지우면 {닉네임}님 프로필에서 바로 사라지고 되돌릴 수 없어요." · "지우기"(위험) / "취소" · 토스트 "리뷰를 지웠어요"(아이콘 없음) · 20e 안내 "내가 남긴 리뷰는 언제든 지울 수 있어요. 수정은 할 수 없어요." · 빈 상태 설명 "추천으로 연결된 친구에게 / 리뷰를 남기면 여기에 모여요". 정확한 값은 pen 값표 `C:/Users/user/OneDrive/Desktop/조각6_검토/값표_20e_내가쓴리뷰.md` 가 이긴다.
6. 푸시 없음(지웠다고 받은 사람에게 알리지 않는다).
7. 로딩 · 실패 · 지우기 실패는 pen 에 없음 → PR 3 과 같은 기존 모양(대장 09-29).

## 이번에 하지 않는 것

- 리뷰 수정(결정 2 그대로, 백로그).
- 가려진(blinded) 리뷰를 작성자에게 보여 주기 — 가려진 것은 없는 것과 같다(PR 2 신고 404 와 같은 규칙).
- 받은 사람에게 "지워졌어요" 알림.

## API 계약

모두 `get_verified_caller` 뒤. 404 문구는 `errors.FRIEND_REVIEW_NOT_FOUND` 재사용(errors.py 0줄).

| 메서드 · 경로 | 응답 | 규칙 |
|---|---|---|
| `GET /friend-reviews/written` | 200 `{"reviews": [{"id", "reviewee": {"nickname", "avatar_url", "university"}, "tags", "comment", "created_at"}]}` 최신순 | 내가 쓴 것 · `status = visible` 만. 받은 사람이 정지 · 차단이어도 보인다(내 글). 탈퇴(withdrawn)면 빠진다. `reviewee_id` 는 싣지 않는다(쓸 곳 없음). ponytail: 페이지 없음 — 쓰는 수 = 추천으로 이어진 사람 수 |
| `DELETE /friend-reviews/{id}` | 204 | `reviewer_id = 나` · `status = visible` 인 행만 지운다. 지운 행이 없으면(남의 것 · 없음 · 가려짐 · 이미 지움) 전부 같은 404. 지우기는 PostgREST delete 한 번 + `Prefer: return=representation` 으로 지운 행 수를 본다 |

## 공유 파일

- 서버: 없음(`backend/app/friend_reviews/{repository,router}.py` · 테스트만).
- 앱(Part A, PR 3 #167 merge 뒤): `app_routes` 상수 1 · `app_router` GoRoute 1 · 15 `my_profile_screen` 줄 하나(나 탭 파일 — 줄 단위 허락). 줄 수는 Part A 를 쓸 때 센다.

## 파일 구조

```
backend/app/friend_reviews/repository.py   + fetch_written · delete_own
backend/app/friend_reviews/router.py       + GET /friend-reviews/written · DELETE /friend-reviews/{id}
backend/tests/friend_reviews/test_friend_reviews.py   + 테스트(아래)

(Part A — PR 3 merge 뒤)
frontend/lib/friend_review/model/…          + fetchWritten · delete, FriendReview 가 reviewee 도 읽기
frontend/lib/friend_review/viewmodel/…      + 20e 목록 · 지우기
frontend/lib/friend_review/view/written_reviews_screen.dart   20e
frontend/test/friend_review/…
```

## PR 나누기

| PR | 내용 | 조건 |
|---|---|---|
| PR 5 서버 | Task B5 | 지금(main 위). 공유 파일 0 |
| PR 6 앱 | Task A8 · A9 | PR 3 #167 merge 뒤 · PR 5 배포 뒤 ready. 15 줄은 나 탭 허락 |

---

# Part B — FastAPI

### Task B5: 내가 쓴 리뷰 읽기 · 지우기

**Files:**
- Modify: `backend/app/friend_reviews/repository.py`, `backend/app/friend_reviews/router.py`
- Test: `backend/tests/friend_reviews/test_friend_reviews.py`

**Interfaces:**
- `FriendReviewRepository.fetch_written(reviewer) -> list[dict]` — `friend_reviews?reviewer_id=eq.{me}&status=eq.visible&order=created_at.desc&select=id,tags,comment,created_at,reviewee:profiles!friend_reviews_reviewee_id_fkey(nickname,universities(name),profile_avatars(storage_path,status,created_at))`
- `FriendReviewRepository.delete_own(review_id, reviewer) -> bool` — `DELETE friend_reviews?id=eq.{id}&reviewer_id=eq.{me}&status=eq.visible`, `Prefer: return=representation`, 지운 행이 있으면 True. 부모 `_delete` 는 Prefer 를 못 받으므로 `self._client.delete(..., headers=self._with_prefer("return=representation"))` 를 이 파일 안에서 부른다(부모 postgrest.py 는 고치지 않는다).
- 라우터 `_written_item(row, supabase_url)` — `_item` 과 같은 모양, 키만 `reviewee`.

- [ ] **Step 1: 실패하는 테스트**(기존 `_wire` · `_table` 가짜 방식 그대로)

```python
def test_written_lists_my_visible_reviews_newest_first():
    # GET friend_reviews 요청 params: reviewer_id=eq.ME · status=eq.visible · order=created_at.desc,
    # select 에 friend_reviews_reviewee_id_fkey embed. 응답 키 = id · reviewee{nickname,avatar_url,university} · tags · comment · created_at
    ...

def test_written_never_carries_ids_of_people():
    # 응답 어디에도 reviewer_id · reviewee_id 가 없다
    ...

def test_written_empty_is_empty_list():
    ...

def test_delete_own_review_is_204_and_scopes_to_me_and_visible():
    # DELETE friend_reviews params: id=eq.R · reviewer_id=eq.ME · status=eq.visible, Prefer return=representation
    ...

@pytest.mark.parametrize("case", ["not_mine_or_missing", "blinded"])
def test_delete_nothing_deleted_is_404(case):
    # PostgREST 가 [] 를 돌려주면 404 detail == FRIEND_REVIEW_NOT_FOUND
    ...

def test_delete_bad_uuid_is_422():
    ...

def test_delete_sends_no_push():
    # sender 가 한 번도 불리지 않는다
    ...

def test_written_and_delete_need_verified_caller():
    # get_verified_caller override 없이 401/403 — 기존 인증 테스트 모양
    ...
```

404 테스트는 경로가 없어도 404 라 RED 가 엉뚱하게 통과한다 → `detail == FRIEND_REVIEW_NOT_FOUND` 단언 필수(PR 2 함정).

- [ ] **Step 2: 실패 확인** — `C:/Users/user/AndroidStudioProjects/campus_mate_compose/backend/.venv/Scripts/python.exe -m pytest -q tests/friend_reviews` (워크트리 backend 에서, `app.__file__` 이 이 워크트리인지 확인) → 새 테스트 FAIL
- [ ] **Step 3: 구현** — 위 Interfaces 대로. 라우트 docstring 에 결정 번호.
- [ ] **Step 4: 통과 확인** — 같은 명령 PASS, 이어서 `pytest -q` 전체 PASS
- [ ] **Step 5: 커밋 제안**: `✨ feat(friend-review): 내가 쓴 리뷰 읽기 · 지우기` / `✅ test(friend-review): 쓴 리뷰 · 삭제 테스트`

---

# Part A — Flutter(PR 3 #167 merge 뒤 · pen 값표 20e)

### Task A8: 저장소 · VM

- `FriendReviewRepository` 에 `Future<Result<List<FriendReview>>> fetchWritten()` · `Future<Result<void>> delete(String reviewId)`. `FriendReview.fromJson` 은 `reviewer` 또는 `reviewee` 중 있는 쪽을 사람으로 읽는다(모델 하나, 카드 하나).
- `FriendReviewListSource.written` 을 더해 목록 VM 을 다시 쓴다. 지우기는 목록 VM 에 `Future<String?> delete(id)` — 성공이면 그 카드를 목록에서 빼고 null, 실패면 문구.
- 테스트: 경로 · 파싱 · 성공 뒤 목록에서 빠짐 · 실패 문구 · 두 번 눌러도 한 번.

### Task A9: 20e 화면 · 15 줄 · 경로

- 값표 20e 를 받은 뒤 화면 대조표를 채운다. 20c 와 같은 뼈대: 앱바 "내가 쓴 리뷰" · 안내 상자 · 카드(깃발 자리에 trash-2 20 muted, 누름 48) · 빈 상태(20e-1) · 삭제 확인 시트(20e-2, AlertSheet) · 토스트(20e-3).
- `FriendReviewCard` 의 `onReport` 를 일반화할지(`trailing` 아이콘 + 콜백) 는 Part A 를 쓸 때 정한다 — 카드 파일 한 곳.
- 경로 `AppRoutes.friendReviewsWritten = '/friend-reviews/written'`, 15 `tStBN` 줄에서 push.
- 15 줄은 나 탭 파일 — 줄 수 세어 허락 요청.

---

## 구현 편차 기록

- **탈퇴한 받은 사람은 빠진다(검토 R1).** 탈퇴는 status=withdrawn 으로 바뀌고 행은 30일 뒤 지워진다 — 계획서 '탈퇴면 cascade 로 행이 없다' 는 틀린 전제였다. `!inner` + `reviewee.status=neq.withdrawn` + 라우터 한 겹. 정지는 계속 보인다.
- no-push 테스트는 sender 대신 `notify` 를 바꿔치고 표 집합까지 본다(계획서 Step 1 과 동등 이상).
- 지우기 응답은 `select=id` 만 받는다(검토 S4).
- 테스트는 Step 1 목록과 조금 다르다: 404 테스트는 parametrize 없이 하나(`test_delete_when_no_row_is_deleted_is_404`, 가짜가 이유를 가르지 않는다 — 검토 S1), 더한 것 두 개 `test_written_hides_withdrawn_reviewee_but_keeps_suspended`(R1) · `test_delete_postgrest_error_is_not_204`(S3). Interfaces 의 select 문자열은 R1 뒤 `!inner` · `status` 가 들어간 모양이다(repository.py `_WRITTEN_SELECT`).
- **알려진 한계(검토 R2, 사용자 결정 (가) 09-29 — 백로그 75)**: 쓰기 → 지우기를 반복하면 받은 사람에게 "새 지인 리뷰" 푸시가 매번 간다(지우면 unique 가 풀린다). API 를 직접 불러야 하고 추천으로 이어진 사이만 가능하다. DB 없이 막을 방법이 없다.

### Part A 앱(A8 · A9, PR 6, 2026-09-29)

범위(통합대장 09-29): 15 지인 리뷰 칸 `Cux1p` 전체(헤더 + 분홍 `o9BA0` → 20c + 흰 `tStBN` → 20e)를 이 PR 에 넣었다. 앞 계획서 PR 4 에는 20 → 20b · 15-4 리뷰 섹션 · redeem 푸시 훅이 남는다. 사용자 규칙(09-29) "B→A 리뷰는 한 번, 지우고 다시는 된다" 는 서버 unique + DELETE 그대로이고, 앱에 다시 쓰기 길을 새로 열지 않았다(20b 손대지 않음).

pen 과 다르게 한 곳
- 20e-1 설명(`DFs55`) · 20e-2 본문(`O7tR3q`)은 줄높이 1.55 그대로 — 두 줄 렌더 43.4(pen 46). 16f · 15d-2 와 같은 처리.
- 20e 앱바 제목 navTitle 30(pen 렌더 31) — 20c 와 같다.
- 20e-2 손잡이 모서리 · 그림자는 값표에 없어 같은 D0TvG 마스터인 15d-2 값(SheetHandle r8, `Color(0x26000000)` (0,-2) 16).

pen 에 없어 정한 곳
- 20c · 20e 공용 틀 `FriendReviewListFrame`(앱바 · 뒤로 · 안내 · 목록 · 로딩 · 실패 · 빈 상태). 빈 · 로딩 · 실패 칸은 안내 상자 뒤 16(`K2HbU` gap)부터 — 20c 빈 상태(pen 없음)도 8 내려갔다.
- 지우기 실패: 시트를 닫고 서버 문구 토스트(circle-alert 16, 20b 실패와 같음), 카드는 남긴다. **404 는 서버 문구 토스트 뒤 그 카드만 목록에서 뺀다**(다시 읽지 않는다 — 남겨 두면 다시 눌러도 404 뿐).
- 지우는 중에 시트를 닫아도 요청이 끝나면 결과 토스트(15d-2 흐름). 시트 닫는 pop 은 `ModalRoute.isCurrentOf` 일 때만(PR 3 필수 1 교훈) + 회귀 테스트. 같은 리뷰를 두 번 지우면 VM 이 진행 중인 요청을 같이 쓴다.
- 토스트 3초 · 휴지통 낭독 툴팁 "리뷰 지우기".
- 15 칸: 읽는 중 · 실패면 노트 ""(대장 결정 가, 줄 높이 84 그대로), 0개면 "받은 리뷰 0개" · "쓴 리뷰 0개". 15 는 20c · 20e 와 같은 목록 VM family 를 쥔다 — 20e 에서 지우면 15 로 돌아왔을 때 개수가 이미 줄어 있다(다시 읽지 않음).
- **검토 필수 1(09-29)**: 15 가 목록을 쥐고 있으면 VM 이 버려지지 않아 20c · 20e 를 열어도(새 리뷰 푸시 `go` 포함) 옛 목록이 남았다(PR 3 대비 회귀). `FriendReviewListFrame` 이 처음 붙을 때 `refresh()` — 목록은 둔 채 다시 읽고(깜빡임 없음), 처음 읽는 중이면 또 보내지 않고, 다시 읽다 실패하면 보던 목록을 둔다. 15 로 돌아오면 늘어난 개수도 맞는다. 회귀 테스트 + VM 테스트 3.
- **재검토 권고 1(09-29)**: 다시 읽는 중에 지우면 늦게 온 옛 목록이 지운 카드를 되살렸다(refresh 가 새로 만든 레이스). VM 이 지운 id 를 기억해(`_removed`) 읽은 목록에서 거른다 + VM 테스트 1. 20c 가 이미 떠 있을 때 새 리뷰 푸시는 다시 읽지 않는다(PR 3 과 같음, main.dart `_refreshForRoute` 몫 — 백로그).
- `FriendReview.fromJson` 은 `reviewer` 가 없으면 `reviewee` 를 사람으로 읽는다(모델 · 카드 하나). 카드 오른쪽 동작은 `onReport` · `onDelete` 중 하나.
