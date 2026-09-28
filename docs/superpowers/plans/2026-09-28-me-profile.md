# 화면 15 개편 — 15 내 프로필 · 15-4 남이 보는 내 프로필 · 15-5 프로필 편집 · 15b 아바타 다시 만들기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> 앞 계획서 `2026-09-27-me-edit.md` 의 뒤를 잇는다. 그 계획서의 서버(Part S) · DB(Part D) · 앱 PR 2(A1 ~ A5, #151)는
> 그대로 쓰고, **화면 15 의 모양과 입구 자리만 이 계획서가 바꾼다**(사용자가 15 새 디자인을 확정, 대장 배정 09-28).
> 15b 시트 · 15-2 · 15-3 의 값과 규칙(옛 A8, 옛 4절 15b 표, C4 · C5 · C7 · C8 · D6 · T2)은 옛 계획서 그대로이고,
> 입구만 히어로 안 `R5Quru` 로 옮긴다.
> **pen 값표 대기:** 대장이 campus-pen 으로 한 번에 뽑아 준다(목록 = 4절 "값표 대기" 칸). 값이 오면 4절을 채운 뒤
> 그 칸을 쓰는 Task 를 시작한다. 값이 필요 없는 Task(S1 · A9 · A10)는 먼저 한다.

**Goal:** 화면 15 를 새 디자인(`nkFJV`)으로 바꾼다 — 큰 아바타 히어로(`l8p6X`, 안에 "다시 만들기 · 10" → 15b), 입구
두 줄("남이 보는 내 프로필 카드" → 15-4, "프로필 편집" → 15-5). 15 에 있던 실사진 · 기본 정보 · 선호 조건 · 자기소개는
새 화면 15-5(`rrJ27`)로 옮기고, 15-4(`gnEwq`)는 상대가 보는 내 카드를 미리 보여 준다. 15d(PR 3-2) · 15e(PR 4) 입구는
그동안 "곧 열려요" 를 띄운다. 지인 리뷰 부분(15 `Cux1p` · 15-4 리뷰 섹션)은 채팅탭 지인 리뷰 PR 4 몫이다.

**Architecture:** 15-4 카드는 10b · 14c 가 같이 쓰는 `ProfileCard`(`matching/view/card_detail_screen.dart`)를 슬롯
없이 그대로 쓴다 — 실사진 · 카톡 · 신고 줄이 없는 모양이 `kpIeX` 와 같다. 값은 새 `GET /me/card-preview`(서버 PR,
S1)가 10b · 14c 와 같은 몸통 함수 `profile_detail()` 로 만든다. 15-5 는 `myProfileProvider` 를 그대로 본다 — 편집
화면(15c · 태그 · 06-1)은 저장 뒤 invalidate 하고 `pop` 하므로, 15-5 에서 열면 15-5 로 돌아와 새 값을 그린다(코드
변경 없음). 15b 는 옛 A8 그대로(뷰모델 `regenerate()` · 시트 · 15-2/15-3 토스트).

**Tech Stack:** FastAPI + httpx · Flutter(Riverpod 3 `FutureProvider` · `Notifier`, go_router). **새 의존성 없음.**

**Spec:** `frontend/docs/DESIGN.md` §9 15 · §6(그림자 — 대장 결정으로 ProfileEntryRow 에도, 문서는 조각 끝 정리 때)
· §8.10(하트) · §10(터치 48) · §11.2(글자 배율), 옛 계획서 `2026-09-27-me-edit.md`(2-3 · 4절 15b 표 · A8), pen
`datingApp.pen` aDKIa "4. 프로필·설정" > hmkR3, 유저플로우 ksN0R > mO35F "07 · 프로필과 설정".

---

## 1. 결정

| # | 무엇 | 답 | 누가·언제 | 반영 |
| --- | --- | --- | --- | --- |
| N1 | 15 새 디자인 | `nkFJV`: 앱바 → 히어로 → 입구 두 줄(gap 12) → 지인 리뷰 섹션 → 내비. 자기소개 · 실사진 · 기본 정보 · 선호 조건 · "프로필 수정" 버튼은 15 에서 빠진다(15-5 로) | 사용자 확정 · 대장 배정 09-28 | A12 · A14 |
| N2 | 15-4 데이터 | 새 `GET /me/card-preview`(me/router.py). cards `profile_detail()` import 재사용, DB 변경 0. **수락 뒤 공개 값(실사진 · 카톡 아이디)이 절대 안 들어가는 것을 테스트로 고정.** main 에서 뜬 작은 서버 PR 로 먼저(지금 배포 묶음에 태운다) | 대장 결정 1 09-28 | S1 · A9 |
| N3 | 지인 리뷰 부분 | **(가)** 15 `Cux1p`(분홍 줄 `o9BA0` "친구들이 본 나" → 20c) · 15-4 리뷰 섹션 · 깃발 숨김은 채팅탭 지인 리뷰 PR 4 가 넣는다(개수 · 20c · 리뷰 카드가 전부 그쪽 코드). PR 3 은 자리만 주석으로 남긴다 | 대장 결정 2 09-28 | A13 · A14 |
| N4 | 15d | PR 3 에서 빼고 **PR 3-2**(옛 A7 그대로, 입구만 15-5 `A8LX2`). 그동안 15-5 "수정 ›" · "교체"(→ 15e, PR 4)는 "곧 열려요". PR 3 · 3-2 · 4 는 가깝게 잇는다 | 대장 결정 3 09-28 | A12 |
| N5 | ProfileEntryRow 모양 | 바탕 #FFFFFF + **`AppElevation.card` 두 겹 그대로**, radius 14, 높이 84, 아이콘 원 `zdZqS` #F7F7F7. `app_elevation.dart` 주석에 적용 대상 한 줄(DESIGN §6 "그림자는 요약 카드만" 이 바뀜 — 문서는 조각 끝) | 사용자 결정 · 대장 09-28 | A11 |
| N6 | 15-4 신고 깃발 | 앱 미리보기에서는 숨기거나 못 누르게 | 대장 09-28 | N3 에 따라 지인 리뷰 PR 4 |
| N7 | 히어로 "다시 만들기 · 10" | pen 높이 34 → **코드 누름 영역 44**. 학교 글자는 한 줄 말줄임 | 대장 09-28 | A14 · A8 |
| N8 | 저장 뒤 돌아오는 곳 | 15d · 15e · 15c(와 태그 · 06-1)에서 저장하면 **15-5** 로 돌아온다(옛 U4 "15 로" 를 바꿈) | 대장 09-28 | A12(코드 변경 없음 — `pop`) |
| N9 | pen 에 없는 상태 | 15 · 15-4 · 15-5 로딩 · 실패 = 지금 화면 15 모양(가운데 로딩 / "잠시 뒤 다시 시도해 주세요" + "다시 시도"). 아바타 없음 = 히어로 같은 크기 surface-soft 빈 칸(옛 15 와 같은 규칙) | 나 탭 판단(기존 패턴) | A12 · A13 · A14 |

## 2. API — `GET /me/card-preview` (새로, 서버 PR `feat/me-card-preview`)

응답 = 10b `GET /cards/{card_id}` 에서 `card_id` 만 뺀 몸통(`profile_detail()` 그대로):

```jsonc
{
  "profile": {"profile_id": "<uuid>", "nickname": "하늘", "age": 24, "university": "서울대학교",
              "major": "컴퓨터공학과", "avatar_url": "<공개 URL 또는 null>"},
  "survey": [0.1, 0.2, 0.3, 0.4, 0.0, 0.6, 0.7, 0.8, 0.9],   // 9축, 답 없는 축 0
  "animal_type": "fox", "impression_type": "kind", "religion": "none", "is_smoker": false,
  "interests": [...], "my_traits": [...], "ideal_traits": [...],
  "height_cm": 178, "mbti": "ENFP", "student_number": "22", "bio": "...", "ideal_note": "..."
}
```

- 관문 `get_verified_caller`(다른 `/me/...` 와 같다). 요청은 가드 뒤 `profiles` 1번 + `survey_answers` 1번.
- 실사진 · 카톡 아이디 · 전화 · 실명은 select 에도 응답에도 없다. 14c 의 `revealed_contact` 를 부르지 않는다.
- 앱은 `CardDetail.fromJson({...json, 'card_id': profile_id})` 로 읽는다(14c 가 `match_id` 를 넣는 것과 같은 모양).
- 배포 순서: 서버 PR merge · 배포가 앱 PR 3 ready 보다 먼저다. 옛 앱은 이 경로를 안 부른다.

## 3. 화면 흐름

```
15 내 프로필 nkFJV ── 톱니 C7teyl ──────────────▶ 16 설정
   ├─ 히어로 R5Quru "다시 만들기 · 10" ─────────▶ 15b 시트 aGaPA → 15-2 p3BJ38 / 15-3 LbGpP
   ├─ k3r5C "남이 보는 내 프로필 카드" ─────────▶ 15-4 gnEwq (/me/preview)
   ├─ sC8BR "프로필 편집" ──────────────────────▶ 15-5 rrJ27 (/me/manage)
   │                                                ├─ Rn3AC "교체" ─────▶ "곧 열려요"(PR 4 에서 15e)
   │                                                ├─ A8LX2 "수정 ›" ───▶ "곧 열려요"(PR 3-2 에서 15d)
   │                                                ├─ J0ZhR6 선호 줄 ───▶ 06-1 편집 (/me/ideal-conditions)
   │                                                └─ jVQAw "자기소개 · 태그" ▶ 15c (/me/edit)
   └─ Cux1p "친구들이 본 나" ────────────────────▶ 20c (채팅탭 지인 리뷰 PR 4)
```

## 4. 화면 대조표

pen 값은 대장이 campus-pen 으로 뽑아 주는 값표가 기준이다. 아래 "값표 대기" 칸은 그 값이 오면 채우고, 채운 뒤에
그 칸의 Task 를 시작한다. 지금 적힌 값은 대장 배정문(09-28)에 있던 것이다.

**15 내 프로필 `nkFJV`(360×922)** — `lib/me/view/my_profile_screen.dart` · `lib/me/view/profile_hero.dart`

| 요소 | pen 값 | 노드 id | 위젯 | Task |
| --- | --- | --- | --- | --- |
| 앱바 | YTDwe "내 프로필", 톱니 → 16. 값표 대기(옛 `ffOFL` 과 같은지) | `hwVQB` / `YTDwe` / `C7teyl` | 지금 `AppBar` 그대로 | A14 |
| 히어로 자리 | 값표 대기(여백) | `nrcYh` | `_ProfileContent` 의 첫 칸 | A14 |
| ProfileHero | 328×360. 모서리 · 그림 채움 값표 대기. "AI 아바타" 배지 없음 | `l8p6X`(인스턴스 `exlt1`) | `ProfileHero` | A14 |
| 스크림 | 값표 대기(그라데이션 색 · 멈춤점 · 위치) | `gyzqh` | `ProfileHero` 안 `DecoratedBox` | A14 |
| 위 줄 칩 | "상대에게 이렇게 보여요" 만. 값표 대기(바탕 · 모서리 · 여백 · 아이콘 · 글자) | `dd4Jv` / `h9sFd` | `_HeroChip` | A14 |
| 아래 묶음 | 세로 gap 2. 여백 값표 대기 | `IUcwD` | `ProfileHero` 안 `Column` | A14 |
| 닉네임 + 인증 | 값표 대기(글자 · 아이콘 · 간격) | `fXWlF` / `CM0QK` / `HxtCZ` | `ProfileHero` 안 `Row` | A14 |
| 학교 줄 | 학교는 한 줄 말줄임(N7). 값표 대기(글자 · gap) | `p2UWV` / `JUKgk` / `C9JEi` | `Expanded(Text(maxLines: 1, ellipsis))` | A14 |
| 다시 만들기 · 10 | 높이 34 → 누름 44(N7). 값표 대기(폭 · 여백 · 모서리 · 바탕 · 하트 · 글자) | `R5Quru` | `_RegenerateButton` | A14 · A8 |
| 15-2 버튼 | 비활성 #E5E5E5 · 아이콘 끔 · 글자 #929292(배정문). 토스트 값표 대기 | `p3BJ38` / 히어로 `EAqjZ` | `_RegenerateButton(enabled: false)` | A8 |
| 15-3 토스트 | 옛 계획서 C7 문구. 위치 값표 대기 | `LbGpP` / 히어로 `WfE36` | 화면 15 토스트 | A8 |
| 본문 | 여백 · 히어로↔입구↔리뷰 간격 · 아래 여백 값표 대기 | `rcsgx` | `ListView` padding | A14 |
| 입구 두 줄 | gap 12(배정문) | `sx7MA` | `SizedBox(height: 12)` | A14 |
| 남이 보는 내 프로필 카드 | "남이 보는 내 프로필 카드" / "상대에게 보이는 모습을 미리 봐요", eye → 15-4 | `k3r5C` | `ProfileEntryRow` | A14 |
| 프로필 편집 | "프로필 편집" / "사진·기본 정보·선호 조건·자기소개", pencil → 15-5 | `sC8BR` | `ProfileEntryRow` | A14 |
| 지인 리뷰 섹션 | N3 — 채팅탭 PR 4. PR 3 은 자리 주석만 | `Cux1p` / `o9BA0` | — | — |
| 내비 | 값표 대기(`AppBottomNav` 그대로인지) | `sXATD` | `AppBottomNav(current: AppTab.me)` | A14 |

**ProfileEntryRow 마스터 `fN0xc`** — `lib/me/view/profile_entry_row.dart` (A11)

| 요소 | pen 값 | 노드 id |
| --- | --- | --- |
| 바탕 · 그림자 | #FFFFFF + `AppElevation.card`(N5) | `fN0xc` |
| 모서리 · 높이 | 14 · 최소 84(글자를 키우면 늘어난다) | `fN0xc` |
| 아이콘 원 | #F7F7F7(= `AppColors.surfaceSoft`). 크기 · 아이콘 값표 대기 | `zdZqS` |
| 여백 · 제목 · 노트 · 셰브런 | 값표 대기(지금 16 · 16/600 렌더 25 · 14/400 · 셰브런 20 과 같은지) | `iksDh` · `ZMu82` · `B4ppA` · `vszZo` |

**15-4 남이 보는 내 프로필 `gnEwq`** — `lib/me/view/card_preview_screen.dart` (A13). 내비 없음.

| 요소 | pen 값 | 노드 id | 위젯 |
| --- | --- | --- | --- |
| 앱바 | 뒤로 + 제목. 값표 대기(제목 문구 · 15c `iq3jl` 과 같은지) | `QfTUe` / `KH1hX` | `EditAppBar`(같으면) |
| 본문 | 값표 대기(여백 · 간격) | `iFAyO` | `ListView` |
| 안내 | "대화 상대가 보는 내 프로필이에요. 실제 사진과 카카오톡 아이디는 둘 다 수락한 뒤에 공개돼요." 링크 끔. 값표 대기(바탕 · 모서리 · 여백 · 아이콘 · 글자) | `Ocmk4`(마스터 `WQIrY`) | `_PreviewNotice` |
| 카드 | 14c 카드 사본 — 실사진 · 카톡 · 신고 줄 끔, 이름 · 학교 줄 있음. 이름 줄 오른쪽 "신뢰 확인 완료" 는 값표 대기 | `kpIeX` | `ProfileCard(detail:)` 슬롯 없음 |
| 리뷰 섹션 | N3 — 채팅탭 PR 4(깃발 숨김 N6 포함) | `kpIeX` 안 | — |

**15-5 프로필 편집 `rrJ27`** — `lib/me/view/profile_manage_screen.dart` (A12). 내비 없음.

| 요소 | pen 값 | 노드 id | 위젯 |
| --- | --- | --- | --- |
| 앱바 | 뒤로 + "프로필 편집". 값표 대기(`iq3jl` 과 같은지) | `VBRNa` / `KH1hX` | `EditAppBar` |
| 본문 | gap 32, padding 24/16/40/16(배정문) | `H4VWO` | `ListView` |
| 실제 사진 | 교체 버튼 → 15e(PR 4 전까지 "곧 열려요"). 값표 대기(제목 문구 · 슬라이더 크기 · 배지 · 버튼) | `Rn3AC` | 15 에서 옮긴 `_RealPhotoSection` |
| 기본 정보 | 카드 흰 바탕 + 그림자. 헤더 오른쪽 "수정 ›" → 15d(PR 3-2 전까지 "곧 열려요"), 누름 44. 값표 대기(헤더 글자 · 카드 모서리 · 여백 · 줄 칸들) | `QldHz` / `PfZjU` / `A8LX2` / `N1dIuc` | 15 에서 옮긴 `_ProfileFacts` + 헤더 |
| 선호 조건 | 줄 → 06-1 편집. 값표 대기(헤더 · 줄 모양 · 간격) | `J0ZhR6` | 15 에서 옮긴 선호 나이 · 키 `ProfileEntryRow` |
| 자기소개 | 글 + "자기소개 · 태그" 줄 → 15c. 값표 대기(헤더 · 글자 · 줄 모양) | `jVQAw` | 15 에서 옮긴 `_BioSection` + `m2szef` 줄 |

**15b · 15-2 · 15-3** — 옛 계획서 4절 15b 표 · A8 그대로. 바뀌는 것은 입구(`JaHig` → `R5Quru`)와 15-2 모양(`EAqjZ`).

## Global Constraints

- 새 의존성 금지. `dart format` 금지. 주변 코드의 주석 밀도 · 이름 · 관용구를 따른다(한국어 주석, "왜" 를 적는다).
- 공유 파일 — **아래 표 범위 그대로 대장 허락(2026-09-28).** 표를 넘는 변경은 다시 묻는다.

  | 파일 | 바꾸는 것 | Task |
  | --- | --- | --- |
  | `frontend/lib/core/router/app_routes.dart` | 상수 2개(`myCardPreview` · `myProfileManage`) | A10 |
  | `frontend/lib/core/router/app_router.dart` | `_meRoutes()` 안 GoRoute 2개 + import 2줄 | A10 |
  | `frontend/lib/core/router/placeholder_screens.dart:33` · `frontend/test/core/router/placeholder_screens_test.dart:46` | 주석의 pen id `r8oJc` → `nkFJV` | A14 |
  | `frontend/lib/core/theme/app_elevation.dart` | 주석 한 줄(적용 대상에 ProfileEntryRow) | A11 |
  | `frontend/lib/profile/model/avatar_repository.dart` · `http_avatar_repository.dart` | `regenerateAvatar()` 하나(옛 A1) | A8 |
  | `frontend/lib/profile/viewmodel/avatar_generation_view_model.dart` | `regenerate()` 하나(옛 A8) | A8 |
  | `frontend/lib/safety/view/safety_sheet.dart`(안전담당) | `SafetySheetButton.primary` 에 선택 인자 `leading` 하나(옛 C4) | A8 |

  `matching/view/card_detail_screen.dart` · `matching/model/card_detail.dart` · `backend/app/cards/*` 는 **읽기 ·
  import 만** 한다.
- 겹침: 프로필탭 #150(16e) · 커뮤니티 PR 3 이 `app_routes` · `app_router` 를 만진다 — 내 블록(`_meRoutes`) 안에만 더한다.
- 글자 배율 1.0 · 1.3 · 1.5 · 2.0 에서 잘림 없음(학교 줄만 의도한 말줄임). 고정 높이 대신 minHeight(DESIGN §11.2).
- 스크롤 안 누르는 위젯은 크기를 맞춘 Material 위에 잉크(COMMON §4-2).
- 로컬 DB 명령 금지(차례 없음). git stash 금지. 전체 `flutter test` 는 대장에게 한 줄 알린 뒤.
- 커밋 · PR 에 도구 표식(Co-Authored-By · Generated with · Claude-Session)을 넣지 않는다.

## Review Focus

1. **15-4 에 실사진 · 카톡 아이디가 새는가** → 서버 S1 `test_preview_never_carries_what_opens_only_after_both_accept`,
   앱 A13 "카드에 사진 슬라이더 · 카카오 카드 · 신고/차단 링크가 없다".
2. **15-5 에서 15c 를 열어 저장** → 15 가 아니라 15-5 로 돌아오고 새 자기소개가 보인다. A12
   `saving_in_15c_returns_to_15_5_with_the_new_bio`.
3. **다시 만들기를 두 번 빨리 누름 · 만드는 중에 15 를 떠났다 돌아옴** → POST 1회, 떠나면 폴링 멈춤, 돌아오면 지금
   상태(옛 A8 테스트 그대로).
4. **긴 닉네임 · 긴 학교 이름 · 배율 2.0 의 히어로** → 학교만 말줄임, "다시 만들기" 누름 44 유지, 넘침 없음. A14.
5. **아바타가 없는 사람의 15 · 15-4** → 히어로 빈 칸 · 칩 · 닉네임이 그대로 읽히고, 15-4 카드는 기본 아바타 규칙(10b 와
   같다). A13 · A14.

---

## 파일 구조 · PR

**서버 PR `feat/me-card-preview`**(main 에서) — S1. `backend/app/me/router.py` · 새 `backend/tests/me/test_me_card_preview.py`.

**앱 PR 3 `feat/me-profile-app`**(#151 `8e00007` 위, #151 merge 뒤 main 으로 rebase)

| 파일 | 할 일 | Task |
| --- | --- | --- |
| `docs/superpowers/plans/2026-09-27-me-edit.md` | 앱 PR 2 편차 13개(첫 커밋) | P0 |
| `docs/superpowers/plans/2026-09-28-me-profile.md` | 이 문서(첫 커밋) | P0 |
| `frontend/lib/me/model/me_repository.dart` · `http_me_repository.dart` | `fetchCardPreview()` | A9 |
| `frontend/lib/me/viewmodel/card_preview_provider.dart`(새) | `myCardPreviewProvider` | A9 |
| `frontend/lib/core/router/app_routes.dart` · `app_router.dart`(공유) | `/me/preview` · `/me/manage` | A10 |
| `frontend/lib/me/view/profile_entry_row.dart` · `app_elevation.dart`(주석) | 흰 바탕 + 그림자 | A11 |
| `frontend/lib/me/view/profile_manage_screen.dart`(새) | 15-5 — 15 의 섹션을 옮겨 온다 | A12 |
| `frontend/lib/me/view/card_preview_screen.dart`(새) | 15-4 | A13 |
| `frontend/lib/me/view/profile_hero.dart`(새) · `my_profile_screen.dart` | 15 새 모양 | A14 |
| `frontend/lib/me/model/my_profile.dart` · `placeholder_screens.dart` · 테스트 2곳 | pen id `r8oJc` → `nkFJV` | A14 |
| 옛 A8 파일들(공유 표) · 새 `frontend/lib/me/view/avatar_regen_sheet.dart` | 15b · 15-2 · 15-3 | A8 |

**앱 PR 3-2** — 옛 A7(15d) + `/me/basic-info`, 입구는 15-5 `A8LX2`. **앱 PR 4** — 옛 A6(15e), 입구는 15-5 `Rn3AC`.
**채팅탭 지인 리뷰 PR 4** — 15 `Cux1p` · 15-4 리뷰 섹션(N3).

---

## Part S — 서버

### Task S1: `GET /me/card-preview` (끝남 — 서버 PR)

**Files:**
- Modify: `backend/app/me/router.py`(import 2줄 + 엔드포인트)
- Test: `backend/tests/me/test_me_card_preview.py`(새)

- [x] **Step 1: 실패하는 테스트** — 3개: 몸통이 내 행의 카드 상세 전부(profile · 9축(빈 축 0) · 동물 · 인상 · 종교 ·
  흡연 · 태그 3종 · 키 · MBTI · 학번 · 자기소개 · "이런 사람이 좋아요") / 수락 뒤 공개 값 없음(키 집합 = 10b 에서
  card_id 뺀 것, 행에 섞여 온 카톡 · 실사진 값이 응답에 없음, 서명 요청 0, select 에 kakao · profile_photos ·
  profile_private 없음) / 인증 전 403. `tests/me/test_me_profile.py` 의 `_wire` · `overrides` 를 import 한다.
- [x] **Step 2: 실패 확인** — 3개 모두 404 로 FAIL.
- [x] **Step 3: 구현**

```python
@router.get("/me/card-preview")
async def get_my_card_preview(
    caller: Caller = Depends(get_verified_caller), now: datetime = Depends(get_now),
) -> dict:
    settings, client, profile_id = caller
    cards = CardRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    profile = await cards.fetch_card_detail_profile(profile_id)
    return await profile_detail(cards, profile, settings.supabase_url, now)
```

- [x] **Step 4: 통과 확인** — 3 passed, 전체 backend 693 passed.
- [ ] **Step 5: 검토 → campus-git draft PR.**

## Part A — 앱 (PR 3)

작업 자리: `…/campus_mate_compose-me-profile/frontend`. 테스트: `flutter test <경로>`(한 워크트리에서 동시에 두 개
돌리지 않는다). 배율 테스트는 `test/me/view/my_profile_screen_test.dart` 의 배율 도우미 모양을 따른다.

### Task P0: 계획서 커밋(첫 커밋)

- [x] 옛 계획서 구현 편차 기록에 "앱 PR 2 — A1 ~ A5" 13개 + 남긴 것 4개.
- [ ] 이 계획서. 커밋 `📝 docs(me): 앱 PR 2 편차 기록 · 화면 15 개편 계획서`.

### Task A9: 카드 미리보기 읽기 (pen 무관)

**Files:**
- Modify: `frontend/lib/me/model/me_repository.dart`, `http_me_repository.dart`, `frontend/test/me/model/fake_me_repository.dart`
- Create: `frontend/lib/me/viewmodel/card_preview_provider.dart`
- Test: `frontend/test/me/model/http_me_repository_test.dart`, 새 `frontend/test/me/viewmodel/card_preview_provider_test.dart`

**Interfaces:**
- Produces:
  - `MeRepository.fetchCardPreview() -> Future<Result<CardDetail>>`
  - `final myCardPreviewProvider = FutureProvider.autoDispose<Result<CardDetail>>(...)` — autoDispose: 15-4 를 열 때마다
    새로 읽는다(15-5 에서 고치고 돌아와 보면 새 값).

- [ ] **Step 1: 실패하는 테스트** — `GET /me/card-preview` 를 부른다 / 응답을 `CardDetail` 로 읽고 `cardId` 에
  `profile.profile_id` 가 든다 / 실패는 `FailureResult` 그대로. provider: 열 때마다 저장소를 다시 부른다.
- [ ] **Step 2: 실패 확인** — `flutter test test/me/model test/me/viewmodel` → 컴파일 오류로 FAIL.
- [ ] **Step 3: 구현**

```dart
  /// 10b 카드 상세와 같은 몸통이라 모델을 다시 만들지 않는다 — card_id 자리에는 내 profile_id 를 넣는다
  /// (14c 가 match_id 를 넣는 것과 같은 모양, `partner_profile.dart`).
  @override
  Future<Result<CardDetail>> fetchCardPreview() => _api.send('GET', '/me/card-preview', (body) {
        final json = body as Map<String, dynamic>;
        final profile = json['profile'] as Map<String, dynamic>;
        return CardDetail.fromJson({...json, 'card_id': profile['profile_id']});
      });
```
- [ ] **Step 4: 통과 확인** — Step 2 명령 → PASS.
- [ ] **Step 5: 커밋** `✨ feat(me): 남이 보는 내 카드 읽기(GET /me/card-preview)`.

### Task A10: 경로 `/me/preview` · `/me/manage` (공유 — 허락 범위)

**Files:**
- Modify: `frontend/lib/core/router/app_routes.dart`, `app_router.dart`
- Test: `frontend/test/core/router/app_router_test.dart`

**Interfaces:**
- `AppRoutes.myCardPreview = '/me/preview'`(15-4), `AppRoutes.myProfileManage = '/me/manage'`(15-5).
- `_meRoutes()` 에 `GoRoute(path: AppRoutes.myCardPreview, builder: … CardPreviewScreen())`,
  `GoRoute(path: AppRoutes.myProfileManage, builder: … ProfileManageScreen())`.

- [ ] **Step 1: 실패하는 테스트** — 완료한 사람이 두 경로에 가면 돌려보내지지 않고 그 화면이 뜬다(PR 2 의
  `/me/edit` 테스트와 같은 모양).
- [ ] **Step 2 ~ 4:** 실패 확인 → 구현(A12 · A13 의 화면이 있어야 컴파일된다 — 두 Task 뒤에 붙이거나 같은 커밋) →
  `flutter test test/core/router` PASS.
- [ ] **Step 5: 커밋** — A12 · A13 커밋에 각자의 경로를 함께 넣는다(경로만 먼저 들어가면 가리킬 화면이 없다).

### Task A11: ProfileEntryRow 흰 바탕 + 카드 그림자 (값표: `fN0xc` · `zdZqS`)

**Files:**
- Modify: `frontend/lib/me/view/profile_entry_row.dart`, `frontend/lib/core/theme/app_elevation.dart`(주석 한 줄)
- Test: `frontend/test/me/view/profile_entry_row_test.dart`

**Interfaces:** `ProfileEntryRow` 인자는 그대로(`icon · title · note · onTap`).

- [ ] **Step 1: 실패하는 테스트** — 바탕 #FFFFFF · 그림자 = `AppElevation.card` · 모서리 14 · 최소 높이 84 · 아이콘 원
  #F7F7F7 · 값표의 여백 · 글자. 누르는 행은 잉크가 행 크기 Material 위(COMMON §4-2) — 그림자는 Material 밖
  `DecoratedBox` 가 그린다(Material 에 elevation 을 주면 §6 한 단계 규칙이 깨진다).
- [ ] **Step 2 ~ 4:** 실패 확인 → 구현 → `flutter test test/me` PASS.

```dart
    // 그림자는 §6 카드 토큰 두 겹 그대로 — Material elevation 은 쓰지 않는다(모양이 토큰과 달라진다).
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.card),
      child: Material(
        color: AppColors.canvas,
        borderRadius: radius,
        child: InkWell(borderRadius: radius, onTap: tap, child: content),
      ),
    );
```

  `app_elevation.dart` 주석: "화면 15 · 15-5 의 ProfileEntryRow(pen `fN0xc`, 사용자 결정 09-28)" 한 줄.
- [ ] **Step 5: 커밋** `💄 style(me): ProfileEntryRow 흰 바탕 + 카드 그림자(fN0xc)`.

### Task A12: 15-5 프로필 편집 (값표: `rrJ27` 표 전부)

**Files:**
- Create: `frontend/lib/me/view/profile_manage_screen.dart`
- Modify: `frontend/lib/me/view/my_profile_screen.dart`(옮길 섹션 · 표기 함수 · "곧 열려요" 토스트를 떼어 온다)
- Modify: `frontend/lib/core/router/app_routes.dart` · `app_router.dart`(A10 의 `/me/manage`)
- Test: 새 `frontend/test/me/view/profile_manage_screen_test.dart`(지금 `my_profile_screen_test.dart` 의 실사진 ·
  Facts · 선호 줄 · 자기소개 · 15c 입구 테스트를 옮겨 온다)

**Interfaces:**
- `ProfileManageScreen`(ConsumerStatefulWidget — 토스트 타이머) — `myProfileProvider` 를 본다. 로딩 · 실패는 N9.
- 옮겨 오는 private 위젯: `_RealPhotoSection` · `_ReplacePhotoButton` · `_ProfileFacts` · `_FactRow` · `_BioSection`
  · `_ageRangeNote` · `_heightRangeNote` · `_LoadError` · "곧 열려요" 토스트. 15 에서 더는 안 쓰는 것은 지운다.
  두 화면이 같이 쓰게 되는 것(`_LoadError` · 토스트)은 A14 에서 쓰임이 확정되면 그때 한 곳으로 모은다.
- "수정 ›"(`A8LX2`, 누름 44) · "교체"(`Rn3AC`)는 "곧 열려요"(N4).

- [ ] **Step 1: 실패하는 테스트** — 값표(15-5 표 전부 · 본문 gap 32 · padding 24/16/40/16) / 섹션 순서 실제 사진 →
  기본 정보 → 선호 조건 → 자기소개 / 선호 줄 → `/me/ideal-conditions`, "자기소개 · 태그" → `/me/edit` /
  "수정 ›" · "교체" → "곧 열려요" 2초 / 내비 없음 / **15c 에서 저장하면 15-5 로 돌아와 새 자기소개**(Review Focus 2 —
  가짜 저장소 + 실제 라우터) / 로딩 · 실패 / 배율 4개 / 잉크 검사.
- [ ] **Step 2 ~ 4:** 실패 확인 → 구현 → `flutter test test/me test/core/router` PASS.
- [ ] **Step 5: 커밋** `✨ feat(me): 15-5 프로필 편집(rrJ27) — 화면 15 섹션을 옮김`.

### Task A13: 15-4 남이 보는 내 프로필 (값표: `gnEwq` 표 전부)

**Files:**
- Create: `frontend/lib/me/view/card_preview_screen.dart`
- Modify: `app_routes.dart` · `app_router.dart`(A10 의 `/me/preview`)
- Test: 새 `frontend/test/me/view/card_preview_screen_test.dart`

**Interfaces:**
- `CardPreviewScreen`(ConsumerWidget) — `myCardPreviewProvider` 를 본다.
  `ProfileCard(detail: detail)` — header · nameTrailing · footer 모두 null(값표가 "신뢰 확인 완료" 켬이면 nameTrailing
  만 대장에게 묻고 더한다 — 14c 의 `_TrustBadge` 는 private 이라 공유 파일 문제가 된다).
- 지인 리뷰 섹션 자리는 주석 한 줄(N3): `// 지인 리뷰 섹션(kpIeX 안) — 채팅탭 지인 리뷰 PR 4 가 넣는다(깃발 숨김 N6).`

- [ ] **Step 1: 실패하는 테스트** — 안내 문구 원문 · 값표 모양 / 카드가 서버 값(닉네임 · 나이 · 학교 · 자기소개 · 태그) /
  **사진 슬라이더 · 카카오 카드 · 신고/차단 링크가 없다**(Review Focus 1 — `PhotoSlider` · "카카오톡 아이디" · "신고하기"
  findsNothing) / 뒤로 → pop / 내비 없음 / 로딩 · 실패 → "다시 시도" 가 다시 읽는다 / 아바타 없음 / 배율 4개.
- [ ] **Step 2 ~ 4:** 실패 확인 → 구현 → `flutter test test/me test/core/router` PASS.
- [ ] **Step 5: 커밋** `✨ feat(me): 15-4 남이 보는 내 프로필(gnEwq)`.

### Task A14: 15 새 모양 — 히어로 + 입구 두 줄 (값표: `nkFJV` · `l8p6X` 표 전부)

**Files:**
- Create: `frontend/lib/me/view/profile_hero.dart`
- Modify: `frontend/lib/me/view/my_profile_screen.dart`, `frontend/lib/me/model/my_profile.dart:3`(pen id),
  `frontend/lib/core/router/placeholder_screens.dart:33`(pen id)
- Test: `frontend/test/me/view/my_profile_screen_test.dart`(옛 섹션 테스트는 A12 로 옮겼다 — 남은 것을 새 모양으로),
  새 `frontend/test/me/view/profile_hero_test.dart`, `frontend/test/core/router/placeholder_screens_test.dart:46`(pen id)

**Interfaces:**
- `ProfileHero({required MyProfile profile, required VoidCallback? onRegenerate})` — `onRegenerate` null 이면 15-2
  비활성 모양(#E5E5E5 · 아이콘 끔 · 글자 #929292, 눌러도 아무 일 없음). A14 는 `null` 을 넘기고, 같은 PR 의
  A8 마지막 커밋이 15b 시트로 잇는다 — PR 단위로는 꺼진 버튼이 나가지 않는다.
- 15 본문: 히어로 → 입구 두 줄(`k3r5C` → `/me/preview`, `sC8BR` → `/me/manage`, gap 12) → 지인 리뷰 자리 주석(N3).
- 클래스 주석의 pen id 는 `nkFJV`, 지운 노드(`r8oJc` · `JaHig` · `ZCpM4` · `o0yhI0`) 이름을 코드에서 없앤다.

- [ ] **Step 1: 실패하는 테스트** — 히어로 값표 전부(328×360 · 스크림 · 칩 문구 "상대에게 이렇게 보여요" · 닉네임 + 인증 ·
  학교 말줄임 · 버튼 누름 44) / 입구 두 줄 문구 · 아이콘 · 이동 / 옛 섹션(실사진 · Facts · 선호 줄 · 자기소개 ·
  "프로필 수정")이 **없다** / 톱니 → 16 그대로 / 아바타 없음 빈 칸 / 긴 닉네임 · 긴 학교 · 배율 2.0(Review Focus 4) /
  배율 4개 / 잉크 검사.
- [ ] **Step 2 ~ 4:** 실패 확인 → 구현 → `flutter test test/me test/core/router` PASS.
- [ ] **Step 5: 커밋** `✨ feat(me): 화면 15 새 모양(nkFJV) — 히어로 · 입구 두 줄`.

### Task A8: 15b 아바타 다시 만들기 · 15-2 · 15-3 (옛 계획서 A8 그대로 — 입구만 `R5Quru`)

옛 계획서 A8 의 Files · Interfaces · 코드 · Step 을 그대로 따른다. 바뀌는 것만:

- `AvatarRepository.regenerateAvatar()`(옛 A1 에서 미룬 것)를 이 Task 첫 커밋으로 — 옛 A1 Step 1 의 테스트 한 줄
  (`POST /me/avatar/regenerate` · `pending` → `AvatarPending`) 그대로.
- 15 연결: `ProfileHero.onRegenerate` 가 15b 시트를 연다. generating 동안 `onRegenerate: null`(15-2 `EAqjZ`),
  failed 면 15-3 토스트 뒤 다시 켜짐(`WfE36`). 토스트 자리는 값표(`p3BJ38` · `LbGpP`).
- 15b-3 "하트 충전하기"(C5)의 "곧 열려요" 는 15 에 남는 토스트를 부른다(A12 로 옮긴 토스트와 같은 모양 — 한 곳으로
  모으는 것은 A12 Interfaces 대로).
- 테스트는 옛 A8 Step 1 그대로, `JaHig` 자리를 `R5Quru` 로.
- 커밋: `regenerateAvatar` / 시트 버튼 `leading` / 뷰모델 `regenerate()` / 15b 시트 / 15 연결(15-2 · 15-3).

---

## 검증 · 보고

- 서버 PR: 루트 `backend/.venv` 파이썬 `-m pytest -q` 개수.
- 앱 PR 3: `flutter analyze` 0 · `flutter test test/me test/core test/profile test/safety` 개수 · 배율 4개 테스트 이름.
  전체 `flutter test` 는 대장에게 알린 뒤.
- campus-reviewer(새로 부름)가 이 계획서 · 2절 · 4절 값표 대조 · RED 재현으로 PASS 를 낸 뒤 campus-git 이 draft PR.
- 순서: 서버 PR merge · 배포 → #151 merge → PR 3 을 main 으로 rebase → ready(대장).

## 구현 편차 기록

### S1 (나 탭, 2026-09-28)

- 계획서 코드 그대로. 테스트 3개 RED(404) → GREEN, 전체 693 passed.
- "누수 테스트가 누수를 잡는지" 변형 확인(응답에 카톡 칸을 일부러 더하기)은 권한 분류기가 막아 하지 않았다. 대신
  테스트가 키 · 값 · 서명 요청 · select 네 갈래로 본다.

### A8 앞부분 (나 탭, 2026-09-28) — 저장소 · 시트 버튼 · 뷰모델 · 15b 시트(화면 15 연결 빼고)

- `regenerateAvatar()` · `SafetySheetButton.primary(leading:)` · `regenerate()` 는 계획서 코드 그대로.
- 옛 A8 Files 의 `test/safety/view/safety_sheet_test.dart` 는 없던 파일이라 새로 만들었다(`leading` 3개).
- `FakeAvatarRepository.regenerateAvatar` 는 등록과 같은 `nextResult` · `generateGate` 를 쓰고 `regenerateCount` 만 따로 센다.
- 15b 시트는 화면 15 연결 없이 **고른 것을 돌려주는 함수**로 뒀다 — `showAvatarRegenSheet(context, cost:, heartBalance:)
  -> Future<AvatarRegenChoice?>`(`regenerate` · `chargeHearts`, 취소 · 바깥 null). 옛 A8 의 "하트 충전하기 → 시트 닫힘 +
  '곧 열려요'" 중 토스트는 화면 15 연결 몫으로 남는다(히어로 pen 값 대기).
- 하트 그림은 `heart-flat-vector-on-primary-v1.png`(pen `n3D3iC`) 한 장 — 사용자 결정 (가)(통합대장 전달 09-28)로 이
  파일만 커밋 대상이 됐다. 1024 한 장이라 @2x/@3x 는 없다.
- 화면 읽기: 하트 그림은 두 모양 모두 **뺀다**. 처음엔 15b 에서 "하트" 로 읽게 뒀는데, 검토 탐침에서 버튼과 따로 떨어진
  노드가 되어 "10 쓰고 만들기, 버튼" · "하트" 로 두 번 멈췄다(검토 권고 1). 단위는 바로 위 설명("하트 10개가
  차감돼요")이 읽는다. CLAUDE.md "재화 글리프는 `Semantics(label: '하트')`" 는 글리프가 단위를 혼자 나타낼 때의 규칙으로
  보고, 버튼 장식인 이 자리는 뺐다.
- 15b-2 제목은 4절 표에 따로 없어 15b 와 같은 "아바타를 다시 만들까요?" 로 뒀다 — pen 값표로 확인한다.

### A8 앞부분 검토 반영 (campus-reviewer PASS · 필수 0, 2026-09-28)

- **권고 2 — `regenerate()` 가 NetworkFailure 를 곧바로 실패로 두던 것.** 응답만 놓쳤으면 서버는 이미 큐에 넣었을 수 있어,
  실패로 두면 15-3 "하트는 차감되지 않았어요" 가 뒤늦게 거짓이 된다. 온보딩 `_blockingMessage` 처럼 만드는 중으로 두고
  상태 조회로 잇는다. 테스트 `응답만 놓치면(네트워크) 실패로 두지 않고 상태를 물어 이어 간다` — 분기를 끄면
  `Expected: null, Actual: '네트워크 연결을 확인해 주세요'` 로 떨어지는 것을 봤다.
- **사소 1 — 가드 테스트가 떨어질 때 30초 교착.** 두 번째 호출을 기다리기 전에 문을 열도록 순서를 바꿨다. 가드를 끄면
  `Expected: <1>, Actual: <2>` 로 바로 떨어진다.
- 사소 2(비활성 버튼의 하트 색)는 쓰는 곳이 없어 두었다.
- 중간 검토 결과: `flutter test test/me test/profile test/safety test/core/router` 629 passed, analyze 0(반영 뒤 내가 다시 돌림).
