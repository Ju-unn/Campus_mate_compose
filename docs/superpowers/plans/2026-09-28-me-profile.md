# 화면 15 개편 — 15 내 프로필 · 15-4 남이 보는 내 프로필 · 15-5 프로필 편집 · 15b 아바타 다시 만들기 Implementation Plan

> **09-30 화면 번호 개정:** 15d→15-6(15d-2→15-6-2) · 15e→15-7. 본문은 옛 번호 그대로 둔다(DESIGN §13-136 ⑤).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> 앞 계획서 `2026-09-27-me-edit.md` 의 뒤를 잇는다. 그 계획서의 서버(Part S) · DB(Part D) · 앱 PR 2(A1 ~ A5, #151)는
> 그대로 쓰고, **화면 15 의 모양과 입구 자리만 이 계획서가 바꾼다**(사용자가 15 새 디자인을 확정, 대장 배정 09-28).
> 15b 시트 · 15-2 · 15-3 의 값과 규칙(옛 A8, 옛 4절 15b 표, C4 · C5 · C7 · C8 · D6 · T2)은 옛 계획서 그대로이고,
> 입구만 히어로 안 `R5Quru` 로 옮긴다.
> **pen 값표 받음(09-28, `Desktop/조각6_검토/값표_15_개편.md`)** — 4절에 옮겼고, 값표의 어긋남 · 빈 곳에 대한 대장
> 결정은 1절 N10 ~ N19 다.

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
| N9 | pen 에 없는 상태 | 15 · 15-4 · 15-5 로딩 · 실패 = 지금 화면 15 모양(가운데 로딩 / "잠시 뒤 다시 시도해 주세요" + "다시 시도"). 아바타 없음 = 히어로 같은 크기 surface-soft 빈 칸(옛 15 와 같은 규칙). 만든 모양은 편차 절에 적는다 | 나 탭 판단(기존 패턴) · 대장 값표 결정 10 | A12 · A13 · A14 |
| N10 | 15-2 비활성 알약 | 문구 "다시 만들기 · 10" 그대로 + #E5E5E5 / #929292 / 하트 숨김 — pen 대로 | 대장 09-28 값표 결정 1 | A8 |
| N11 | 15 내비 대화 배지 "4" | pen 목데이터 — 앱은 지금처럼 실제 안 읽은 수 | 결정 2 | A14 |
| N12 | 15-5 "수정 ›"(`A8LX2`) | pen 대로 회색 #6A6A6A 14/400 글자만(15c `cOkl1` 분홍과 달라도 화면마다 pen 기준). 누름 44 | 결정 3 | A12 |
| N13 | 15b 딤 | 앱 기존 시트 딤 그대로. pen Scrim `RoxU2` #00000080 = `AppColors.scrim`(검정 0.5) 이라 같다 | 결정 8 | A8 |
| N14 | 15-4 · 15-5 앱바 | `KH1hX` 대응 위젯(`EditAppBar`) 재사용 — 15c `iq3jl` 과 값 같음 | 결정 4 | A12 · A13 |
| N15 | 보기 칩 `h9sFd` | #222222 불투명 — pen 대로 | 결정 5 | A14 |
| N16 | 옛 `ffOFL` | 코드 · 테스트의 id 를 `hwVQB` 로 바꾼다(값 같음) | 결정 7 | A14 |
| N17 | 15-4 카드 높이 | 내용 맞춤 | 결정 6 | A13 |
| N18 | 15-2 · 15-3 토스트 자리 | 04-3 토스트와 같은 자리 | 결정 9 | A8 |
| N19 | 15-5 저장 버튼 | 없다 — 화면마다 저장(pen 대로) | 결정 10 | A12 |

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

## 4. 화면 대조표 (값표 `Desktop/조각6_검토/값표_15_개편.md` 1 ~ 12, PNG 5장 `값표_15_개편_png/`, 2026-09-28)

lh = 줄높이 속성, 없으면 렌더 높이로 맞춘다(화면 15 코드와 같은 방식 — `height: 렌더/글자`). "→" 는 인스턴스가 덮어쓴 값.
pen 이 고정 높이여도 코드는 minHeight(DESIGN §11.2).

**15 내 프로필 `nkFJV`(360×922, #FFFFFF)** — `lib/me/view/my_profile_screen.dart` · `lib/me/view/profile_hero.dart`

| 요소 | pen 값 | 노드 id | 위젯 | Task |
| --- | --- | --- | --- | --- |
| 배치 | 앱바 0..56 / 히어로 자리 56..444 / 본문 444..841 / 내비 841..922 | `nkFJV` | `Scaffold` | A14 |
| 앱바 | 56, padding [0,8,0,20]. 제목 "내 프로필" 20/700 #222222 lh1.5(렌더 31) x20. 톱니 48×48 settings 22 #222222, 오른쪽 여백 8. 알림 배지 꺼짐 — **옛 `ffOFL` 과 값 같음(N16) → 지금 `AppBar` 그대로, 주석 · 테스트 id 만 `hwVQB`** | `hwVQB` / `C7teyl` | `AppBar` | A14 |
| 히어로 자리 | padding [8,16,20,16] | `nrcYh` | `ListView` 첫 칸 여백 | A14 |
| 본문 | gap 32, padding [24,16,40,16] → 히어로 ↔ 입구 줄 = 20 + 24 = **44**, 입구 줄 ↔ 지인 리뷰 32, 아래 40 → 내비 | `rcsgx` | `ListView` padding | A14 |
| 입구 두 줄 | gap 12 | `sx7MA` | `SizedBox(height: 12)` | A14 |
| 남이 보는 내 프로필 카드 | eye, "남이 보는 내 프로필 카드" / "상대에게 보이는 모습을 미리 봐요" → 15-4 | `k3r5C` | `ProfileEntryRow` | A14 |
| 프로필 편집 | pencil, "프로필 편집" / "사진·기본 정보·선호 조건·자기소개" → 15-5 | `sC8BR` | `ProfileEntryRow` | A14 |
| 지인 리뷰 섹션 | 헤더 "지인 리뷰" 17/700 + 분홍 줄 `o9BA0` — **N3 채팅탭 PR 4.** PR 3 은 자리 주석만. 그래서 PR 3 의 본문 끝은 입구 줄 뒤 아래 여백 40 | `Cux1p` | — | — |
| 내비 | `AppBottomNav(current: AppTab.me)` 그대로. 대화 배지 "4" 는 목데이터(N11) | `sXATD` | 그대로 | A14 |

**ProfileHero 마스터 `l8p6X`(328×360)** — `lib/me/view/profile_hero.dart` (A14)

| 요소 | pen 값 | 노드 id |
| --- | --- | --- |
| 틀 | 모서리 24, clip, padding [16,16,20,16], 세로 space_between(위 줄은 위, 이름 묶음은 아래) | `l8p6X` |
| 그림 | 아바타 그림 **cover**(꽉 채워 자름). 아바타 없음 = 같은 크기 surface-soft 빈 칸(N9) | `l8p6X` |
| 스크림 | 위치 y150, 높이 210(아래 끝까지), 위 → 아래 선형: #222222 α0 @0 · α0.45 @0.35 · α0.65 @0.6 · α0.85 @1 | `gyzqh` |
| 위 줄 | 가로 space_between, 세로 가운데 — 칩 하나 | `dd4Jv` |
| 보기 칩 | Badge `XPRBv` → eye 14 #FFFFFF + "상대에게 이렇게 보여요" 13/600 #FFFFFF lh1.5(렌더 21). 바탕 #222222 **불투명**(N15), r999, padding [6,10], gap 4(렌더 33) | `h9sFd` |
| 이름 묶음 | 세로 gap 2, 자체 여백 없음 | `IUcwD` · `ynlrz` |
| 이름 줄 | 가로 gap 8, 세로 가운데 | `fXWlF` |
| 닉네임 | "늑대, 24" 24/700 #FFFFFF lh1.35(렌더 33) | `CM0QK` |
| 인증 배지 | Badge `XPRBv` → 바탕 #FFFFFF, badge-check 13 #222222, "학생 인증" 12/600 #222222 lh1.5, r999, padding [6,10], gap 4(렌더 31) | `HxtCZ` |
| 학교 줄 | 가로 gap 12, 세로 가운데. 학교 칸 fill + clip — 코드는 한 줄 말줄임(N7) | `p2UWV` / `JUKgk` |
| 학교 | "서울대학교 · 컴퓨터공학과" 14/400 #FFFFFF lh1.55(렌더 23) | `C9JEi` |
| 다시 만들기 알약 | 높이 34(**누름 44**, N7), 폭 hug, #FFFFFF, r9999, padding [0,10], gap 4, 테두리 없음 | `R5Quru` |
| 알약 하트 | Heart Value Icon `l4vdk` 16×16 = `heart-flat-vector-v3.png`(흰 바탕이라 원본, DESIGN §8.3) | `yhwPU` |
| 알약 글자 | "다시 만들기 · 10" 13/600 #C4224B lh1.5(렌더 21). 10 은 서버 `avatarRegenCost` 가 아니라 pen 고정(D6 — 무료 차례에도 같다) | `TXsBS` |

**15-2 · 15-3** (A8 — 히어로 상태 + 토스트)

| 요소 | pen 값 | 노드 id |
| --- | --- | --- |
| 15-2 알약 | #E5E5E5, 하트 숨김, 글자 #929292, 문구 "다시 만들기 · 10" 그대로(N10). 눌러도 아무 일 없음 | `EAqjZ` |
| 15-2 토스트 | `AppToast`(Toast `I8UOWm` 기본): #222222 r9999 padding [10,16] gap 8, loader-circle 16 #FFFFFF + "아바타로 변환 중이에요" 14/600 #FFFFFF | `fLkE8` |
| 15-3 알약 | 기본(활성)으로 돌아옴 | `WfE36` |
| 15-3 토스트 | triangle-alert 16 + "아바타를 만들지 못했어요.\n하트는 차감되지 않았어요."(두 줄) | `k110R` |
| 토스트 자리 | pen 은 흐름 배치만 — **04-3 토스트와 같은 자리**(N18) | — |

**ProfileEntryRow 마스터 `fN0xc`** — `lib/me/view/profile_entry_row.dart` (A11)

| 요소 | pen 값 | 노드 id |
| --- | --- | --- |
| 틀 | 328×84(코드 minHeight 84), **#FFFFFF**, r14, 가로 gap 12, padding 16, 세로 가운데 | `fN0xc` |
| 그림자 | 두 겹 #1A16190F (0,2) blur 8 · #1A161914 (0,8) blur 24 = `AppElevation.card` 그대로(N5) | `fN0xc` |
| 아이콘 원 | 44×44 #F7F7F7 r999 — **지금 코드 `AppColors.canvas`(#FFFFFF)에서 바뀜**(흰 바탕 위라 원이 보여야 한다) | `zdZqS` |
| 아이콘 | 22 #6A6A6A | `GAMlp` |
| 글 칸 | 세로 gap 3, 제목 16/600 #222222 lh1.5(렌더 25), 노트 14/400 #6A6A6A lh1.5 | `iksDh` / `ZMu82` / `B4ppA` |
| 셰브런 | chevron-right 20 #6A6A6A | `vszZo` |
| (분홍 변형 `o9BA0` 은 채팅탭 PR 4 — 바탕 #FFF0F2 · 원 #FFFFFF · heart-handshake #C4224B · 셰브런 #C4224B) | — | `o9BA0` |

**15-4 남이 보는 내 프로필 `gnEwq`(360×1714)** — `lib/me/view/card_preview_screen.dart` (A13). 내비 없음.

| 요소 | pen 값 | 노드 id | 위젯 |
| --- | --- | --- | --- |
| 앱바 | AppBar · Sub `KH1hX`: 56, padding [0,8], gap 4, 뒤로 48(arrow-left 22 #222222), 제목 "남이 보는 내 프로필" 20/700 lh1.5. 15c `iq3jl` 과 값 같음(N14) | `QfTUe` | `EditAppBar` |
| 본문 | 세로 gap 32, padding [24,16,40,16] | `iFAyO` | `ListView` |
| 안내 | #FFF0F2 r12 padding 14, **아이콘 없음**, 링크 끔. "대화 상대가 보는 내 프로필이에요. 실제 사진과 카카오톡 아이디는 둘 다 수락한 뒤에 공개돼요." 14/400 #3F3F3F lh1.5 | `Ocmk4`(`WQIrY`) | `_PreviewNotice` |
| 카드 | 14c 카드 사본: #FFFFFF r24 테두리 #EBEBEB 1, padding 20, **높이는 내용 맞춤**(N17). 실사진 · 점 · 카카오 카드 · 구분선 · 신고/차단 줄 끔 | `kpIeX` | `ProfileCard(detail:)` 슬롯 없음 |
| 이름 줄 오른쪽 | "신뢰 확인 완료" 자리 `CTtPd` **꺼짐** — `nameTrailing` 없음 | `CTtPd` | — |
| 리뷰 섹션 | N3 — 채팅탭 PR 4(깃발 숨김 N6 포함) | `lLY1f` · `vOLQ1` · `muTFX` | — |

**15-5 프로필 편집 `rrJ27`(360×1131)** — `lib/me/view/profile_manage_screen.dart` (A12). 내비 · 저장 버튼 없음(N19).

| 요소 | pen 값 | 노드 id | 위젯 |
| --- | --- | --- | --- |
| 앱바 | `KH1hX` → "프로필 편집"(15-4 와 같음) | `VBRNa` | `EditAppBar` |
| 본문 | 세로 gap 32, padding [24,16,40,16] | `H4VWO` | `ListView` |
| 섹션 헤더 | SectionHeader `Ymhdq`: 제목 17/700 #222222(렌더 25), 오른쪽 글자 14/400 #6A6A6A(렌더 20), 가로 space_between. 섹션 안 gap 12 | `GimcE` · `PfZjU` · `Gjodp` · `ZpArm` | `_SectionHeader` |
| 실제 사진 | 헤더 "실제 사진" + 오른쪽 "서로 수락하면 전달돼요". 슬라이더 gap 8, 사진 252×184 r14 cover, 배지 lock "수락 후 공개"(Badge · Small, 위 12 · 오른쪽 13), 점 6 gap 6 #222222/#DDDDDD, 교체 버튼 328×44 #F2F2F2 r8 "실제 사진 교체" 14/600 #222222 lh1.5 → **"곧 열려요"**(N4) | `Rn3AC` / `c9Co2` / `r6b8Vu` / `RaYKc` / `E7Cv2` | 15 에서 옮긴 `_RealPhotoSection` (제목만 헤더로) |
| 기본 정보 | 헤더 "기본 정보" + "수정 ›" **14/400 #6A6A6A 글자만**(N12 — 15c 분홍과 다름), 누름 44 → "곧 열려요"(N4). 카드 **#FFFFFF r14 + 카드 그림자**, padding [4,16], 줄 48(아이콘 19 #6A6A6A · gap 10 · 라벨 14/400 #6A6A6A · 값 14/600 #222222), 구분선 없음. 내 키 · MBTI · 학과 | `QldHz` / `PfZjU` / `A8LX2` / `N1dIuc` | 15 에서 옮긴 `_ProfileFacts`(바탕 · 그림자만 바뀜) |
| 선호 조건 | 헤더 "선호 조건"(오른쪽 없음) + ProfileEntryRow 2개 gap 12: calendar "선호 나이 범위" · ruler "선호 키 범위" → 06-1 편집 | `J0ZhR6` / `sR3If` · `t1Eok` | 15 에서 옮긴 두 행 |
| 자기소개 | 헤더 "자기소개"(오른쪽 없음) → 본문 16/400 #3F3F3F lh1.6 → 12 → ProfileEntryRow tags "자기소개 · 태그" / "관심사 · 나의 특징 · 이상형" → 15c | `jVQAw` / `IUPXc` / `bTDTS` | 15 에서 옮긴 `_BioSection` + `m2szef` 행 |

**15b 시트 `aGaPA` · `N5lXcc` · `i8rkW`** — 옛 계획서 4절 15b 표 그대로(A8 앞부분에서 구현 · 검토 끝). 값표로 확인한 것:
15b-2 제목 "아바타를 다시 만들까요?"(`pHsgT`, 15b 와 같음) · 15b-3 CTA 하트 on-primary 26 gap 8(`DW3Zn`) · 15b-2 ·
15b-3 도 취소 · 36 여백 있음 · `n3D3iC` = `heart-flat-vector-on-primary-v1.png`(md5 같음) · 딤 Scrim `RoxU2` #00000080 =
`AppColors.scrim`(검정 0.5, N13 — 같다).

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

## Part A — 앱 PR 4 (15e 사진 수정, 대장 배정 09-29 — PR 3-2 보다 먼저)

브랜치 `feat/me-photos-app`, 워크트리 `…/campus_mate_compose-me-photos`. #161(PR 3, `75cecbf`) 위에 쌓고 #161 merge
뒤 main 으로 옮긴다(`rebase --onto origin/main 75cecbf`).

### Task A15: 15e 사진 수정 (옛 계획서 A1 사진 쓰기 · A2 `/me/photos` · A6 그대로 — 입구만 15-5)

옛 계획서 `2026-09-27-me-edit.md` 의 Task A6(Files · Interfaces · `SelectedPhoto` 두 모양 · `MyPhotosViewModel.save()` ·
Step), A1 에서 미룬 `PhotoSlot` · `savePhotos`(Interfaces · multipart 테스트 · 코드), A2 의 `myPhotos` 상수, 4절 15e
표(C2 · C9 · D10 · U2 · U3), 공유 파일 허락 표(photos_ui_state · photos_view_model · photos_screen · avatar_source_screen ·
11번째 `photo_tiles.dart`)를 그대로 따른다. 바뀌는 것만:

- **입구**: 화면 15 의 "실제 사진 교체" 는 PR 3 에서 15-5(`profile_manage_screen.dart` 실제 사진 섹션 `E7Cv2`)로 옮겼다. 그
  버튼의 `onTap` 을 "곧 열려요" 에서 `context.push(AppRoutes.myPhotos)` 로 바꾼다. 15-5 의 "곧 열려요" 테스트는 "누르면
  사진 수정 화면으로 간다" 로 바꾼다. `me_toast.dart` 의 `comingSoonToast` 는 15-5 "수정 ›"(15d, PR 3-2) · 15b-3 충전이
  계속 쓰므로 그대로 둔다.
- **저장하면 15-5 로 돌아온다**(N8) — `pop` 이라 코드 변경 없음. 테스트: 15-5 → 15e 저장 → 15-5 의 사진 줄이 새 값.
- **경로**: `app_routes.dart` 상수 1개(`myPhotos = '/me/photos'`) · `app_router.dart` `_meRoutes()` 안 GoRoute 1개 + import
  1줄 — 옛 허락 표 범위.
- 칸 모양은 04-2 모양(C9), 칸 수 대표 1 + 보조 3(D10). 값은 옛 4절 15e 표.
- 커밋: `PhotoSlot` · `savePhotos` / `SelectedPhoto` 두 모양(온보딩 동작 그대로) / 칸 위젯 `photo_tiles.dart` 로 옮기기(04-2
  동작 · 테스트 0 변경) / 편집 뷰모델 / 15e 화면 + `/me/photos` / 15-5 연결 / 계획서.

## Part A — 앱 PR 3-2 (15d 기본 정보 수정, 대장 배정 09-29 — PR 4 뒤)

브랜치 `feat/me-basic-info-app`, 워크트리 `…/campus_mate_compose-me-basic`. PR 4(#166, `feat/me-photos-app` `718e83a`)
위에 쌓는다 — 15-5 · 라우터가 겹친다. #166 merge 뒤 `rebase --onto origin/main 718e83a`.

### 결정 (대장 09-29, 값표 `Desktop/조각6_검토/값표_15d.md` · PNG `값표_15d_png/` 01 mhdYA · 02 ZuPTD)

| # | 무엇 | 답 |
| --- | --- | --- |
| B1 | 키 값 글자 색 | **#222222**(`AppColors.ink`). pen `BdRVU` 는 색 override 가 빠져 자리표시 #929292 — 채워진 수정 가능 값이라 대비 2.9 미달 |
| B2 | 저장 꺼짐 | 바뀐 것이 없거나 형식 오류면 `AppButton` 꺼짐(button-disabled #E5E5E5 / #929292, DESIGN 462). 15d-2 도 키를 바꾸면 켜진다 |
| B3 | 닉네임 확인 시트 | 만들지 않는다(pen 없음) — helper(30일 1회)로 충분 |
| B4 | 저장 성공 | 15-5 로 돌아가 `me_toast` 토스트 **"저장했어요"**(15c · 태그 · 06-1 · 15e 는 토스트 없이 돌아온다 — 15d 만 다름) |
| B5 | 오류 | **칸 탓 오류**(닉네임 형식 · 중복 · 서버 409 두 종 · 키 형식 · 키 422)는 **칸 아래 빨간 helper**, **칸 탓이 아닌 실패**(네트워크 등)는 04-1 처럼 **버튼 위 오류 글**(대장 확인 09-29 — 어느 칸의 잘못도 아니므로) |
| B6 | 저장 중 | `AppButton(isLoading: true)`(버튼 안 흰 스피너, D8) |
| B7 | 앱바 | `EditAppBar(title: '기본 정보 수정')` — pen `m2PTHo` 는 인스턴스가 아니지만 값이 같다 |

### 화면 대조표 — 15d `mhdYA`(360×780) · 15d-2 `ZuPTD` — `lib/me/view/basic_info_edit_screen.dart`

| 요소 | pen 값 | 노드 id |
| --- | --- | --- |
| 앱바 | 56, padding [0,8], gap 4, 뒤로 48(arrow-left 22 #222222), 제목 "기본 정보 수정" 20/700 lh1.5(렌더 31) | `m2PTHo` / `a5tD2` / `WyAy6` |
| 본문 | padding [0,24,28,24], 위 32 → 닉네임 → 16 → 키 → Spacer(fill) → 저장. 내비 없음 | `fP8cs` / `We4y3` / `MNhYr` / `YXKHl` |
| 칸 틀(TextInput `PccKZ`) | 세로 gap 8(라벨 ↔ 상자 ↔ helper). 라벨 14/600 #3F3F3F(렌더 20). 상자 높이 56, #F7F7F7, r8, 테두리 #767676 1, padding [0,16], 세로 가운데. 값 16/400(렌더 23). helper 12/400, 아이콘 14 + gap 4 | `PccKZ` / `VCwQo` / `TDM1r` / `p3T9Jb` / `a1eaV` |
| 닉네임 | 라벨 "닉네임", 값 #222222, helper info #6A6A6A + "30일에 한 번 바꿀 수 있어요" #6A6A6A | `G1tl8` |
| 키 | 라벨 **"키 (cm)"**(상자 안 단위 글자 없음), 값 **#222222(B1)**, helper 없음(오류 때만) | `BdRVU` |
| 저장 | `AppButton` "저장" 312×56 #FF385C r16, 좌우 24 · 아래 28, 바닥 고정(15c · 15e 와 같은 구조) | `fx0HX` |
| 15d-2 잠긴 닉네임 | 테두리 **#DDDDDD**(hairline), 바탕 #F7F7F7 그대로, 값 #929292(disabled), 오른쪽 lock 20 #929292(오른쪽 16, 값과 gap 8), 입력 불가. helper clock-3 14 #6A6A6A + "`M`월 `D`일부터 바꿀 수 있어요" #6A6A6A | `V3sicJ` |
| 15d-2 키 · 저장 | 키는 고칠 수 있다. 저장은 B2 규칙 | `fFMVJ` / `qOevq` |
| 오류 helper(B5) | circle-alert 14 #C13515 + 12/400 #C13515(마스터 `a1eaV` 기본값) — 04-1 과 같은 모양 | `PccKZ/a1eaV` |

### Task A16: 15d 기본 정보 수정 (옛 계획서 A7 + A2 `/me/basic-info` — 입구만 15-5 `A8LX2`)

옛 계획서 `2026-09-27-me-edit.md` Task A7(Interfaces · 날짜는 한국 시각 `at.toUtc().add(Duration(hours: 9))` · 닉네임 형식 ·
중복 확인 · 키 3자리 · `updateProfile(nickname:, heightCm:)` · 서버 409 문구), A2 의 `myBasicInfo` 상수, 1절 U6 · C6 · D7,
2-5 `PATCH /me/profile` 계약을 따른다. 바뀌는 것:

- **입구**: 15-5 "수정 ›"(`A8LX2`) — "곧 열려요" 에서 `context.push(AppRoutes.myBasicInfo)` 로. 15-5 테스트 "수정 › → 곧 열려요" 는
  "누르면 15d" 로 바꾼다. `comingSoonToast` 는 15b-3 충전이 계속 쓴다.
- **저장 뒤**(B4): `context.pop(true)` → 15-5 가 `push` 결과가 true 면 `showTimedToast("저장했어요")`. 15-5 는 invalidate 된
  `myProfileProvider` 로 새 값을 그린다.
- **보내는 칸**: 바뀐 칸만 보낸다. 닉네임이 그대로면 보내지 않는다(잠금 중에 같은 닉네임을 보내는 일 자체를 없앤다). 키가
  그대로면 보내지 않는다. 둘 다 그대로면 저장 꺼짐(B2).
- **닉네임 중복 확인**: `GET /profile-onboarding/nickname-availability?nickname=`(서버가 내 행은 빼고 본다). 04-1 과 같은
  형식 규칙 · 같은 확인 시점(04-1 뷰모델을 읽고 따른다). 지금 닉네임과 같으면 묻지 않는다.
- **오류 자리**(B5): 닉네임 형식 · 중복 · 서버 409(`NICKNAME_TAKEN` · `NICKNAME_CHANGE_TOO_SOON`) → 닉네임 칸 아래. 키 형식 ·
  서버 422(범위) → 키 칸 아래. 그 밖의 저장 실패(네트워크 등) → 04-1 이 저장 실패 문구를 두는 자리와 같게.
- **글자 배율 · 잉크**: 배율 1.0 / 1.3 / 1.5 / 2.0 잘림 없음, 상자는 minHeight 56.
- 커밋: 뷰모델 / 화면 + `/me/basic-info` / 15-5 연결 + "저장했어요" / 계획서.

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

### A10 · A11 · A12 · A13 (campus-coder, 2026-09-29)

**A10 경로**
- 상수 2개(`myProfileManage` · `myCardPreview`, 주석 포함) · `_meRoutes()` 안 GoRoute 2개 · import 2줄. `_meRoutes()` 안에
  주석 한 줄("15 입구에서 push 로 연다")을 더했다. 경로는 A12 · A13 에 각각 붙였다(Step 5 그대로).
- 화면 15 입구 두 줄 연결은 A14 몫이라 하지 않았다.

**A11 ProfileEntryRow**
- 계획서 코드 그대로(Material 밖 `DecoratedBox` 가 `AppElevation.card`, Material 은 canvas · elevation 0).
- 누르지 않는 행도 같은 틀이다 — Material 이 바탕을 칠하고 InkWell 만 없다(모양을 한 갈래로).
- `app_elevation.dart` 주석 한 줄에 15-5 기본 정보 카드 `N1dIuc` 도 같이 적었다(같은 토큰을 쓰는 두 번째 자리).

**A12 15-5**
- `_LoadError` 는 공개 `MeLoadError`(`lib/me/view/me_load_error.dart`)로 뺐다. 15 · 15-4 · 15-5 세 곳이 지금 쓴다 —
  Interfaces 의 "A14 에서 모은다" 를 앞당겼다. 테스트 `test/me/view/me_load_error_test.dart` 2개.
- "곧 열려요" 토스트는 15-5 에만 private 으로 둔다. 15 에는 누를 곳("실제 사진 교체")이 떠나 지웠다(15 는
  `ConsumerWidget` 이 됐다). A8 의 15 연결(충전 → "곧 열려요", 15-2 · 15-3 토스트)에서 15 에 다시 필요하다 — 그때 두
  화면이 같이 쓰는 모양으로 뺀다.
- **사진 ↔ 점 간격 12(pen `rrJ27`) — 대장 (가) 허락(09-29) → 12.** 공용 `PhotoSlider` 에 선택 인자 `dotsGap`(기본 8 = 화면
  15 · 14c 값) 하나만 더하고 15-5 가 12 를 넘긴다 → 실제 사진 섹션 295(pen 그대로). 14c · 기존 호출은 인자를 안 넘겨 그대로.
- "수락 후 공개" 배지는 15 의 `_InkBadge(small)` 를 옮기지 않고 15-5 에 `_LockBadge` 로 새로 뒀다 — 15 는 A14 전까지 헤더 ·
  아바타 배지로 `_InkBadge` 를 계속 쓴다. A14 에서 15 의 `_InkBadge` 가 없어지면 겹침도 없어진다.
- "수정 ›" 누름 44(N12)는 15c `_TagSection` 과 같은 방식이다 — 위 섹션과의 간격 32 를 기본 정보 상자 안에 넣고 44 칸을
  헤더 줄 가운데에 겹친다(상자 밖은 누름 검사가 닿지 않는다).
- 자기소개가 비면 옛 15 는 섹션째 숨겼는데, 15-5 는 **본문만** 숨기고 헤더 · 15c 입구 행(`bTDTS`)을 남긴다 — 입구 행이
  자기소개 섹션 안이라 숨기면 다시 채울 길이 없다. 옮긴 테스트도 이 규칙으로 바꿨다.
- 자기소개 본문 줄높이는 pen 속성 1.6(body 토큰 그대로). pen 렌더는 81(3줄 × 27)이고 옛 15 는 렌더 25 로 맞췄었다 —
  4절 규칙("lh 속성이 있으면 속성")대로 1.6.
- 헤더 오른쪽 글자는 `Flexible` — 배율 2.0 에서 "서로 수락하면 전달돼요" 가 제목을 밀지 않고 줄을 바꾼다.
- **pen 에 없는 상태(N9) 모양**: 로딩 = 가운데 `CircularProgressIndicator`, 실패 = `MeLoadError`("잠시 뒤 다시 시도해 주세요" +
  "다시 시도"), 둘 다 앱바는 남는다. 토스트 자리 = 화면 아래 12 · 가로 가운데(하단 버튼 · 내비가 없어 §8.5 "버튼 위 12" 를
  화면 끝에 적용).
- 화면 15 테스트에서 옮긴 것: 실사진 · "실제 사진 교체" · Facts · 선호 행 두 개 · 자기소개 · 15c 입구(`m2szef`) 그룹 전부와
  좌표 · 글자 · 아이콘 테스트의 해당 줄(값은 `rrJ27` 로 새로). 입구 행의 "자기소개 아래 24 · 폭 328" 과 "자기소개가 비면 선호
  키 행 아래 24" 는 15-5 좌표 테스트와 "비면 헤더 아래 12" 테스트로 합쳤다. 15 에서 뺀 것: "본문 아래 32(입구 행 ↔ 내비)" —
  입구 행이 떠나 뜻이 없어졌고 15-5 의 "아래 40" 이 갈음한다.

**A13 15-4**
- 계획서대로 `ProfileCard(detail:)` 슬롯 셋 다 null. 실패하면 안내 상자도 그리지 않고 `MeLoadError` 만(N9, 15-5 와 같다).
- 안내 상자 모서리 12 · 안쪽 14 · 본문 아래 40 은 토큰 사이 값이라 리터럴(주석).
- Review Focus 1 테스트(`card_preview_has_no_photos_kakao_or_report_links`)는 "차단하기" 까지 보고, 슬롯 테스트가 "신뢰 확인
  완료" 없음(`CTtPd` 꺼짐)을 본다. 카드 끝 ↔ 화면 끝 40 도 확인했다.

### A14 · A8 15 연결 (campus-coder, 2026-09-29)

**A14 히어로 `l8p6X`(`lib/me/view/profile_hero.dart`)**
- 글자 줄높이는 pen **속성**(닉네임 1.35 = headline 토큰, 학교 1.55 = bodySmall 토큰, 칩 · 배지 · 알약 1.5)이다. pen 렌더
  높이(33 · 23 · 21)와 0.5 ~ 1.5 차이가 나서, 좌표 테스트는 pen 렌더 값이 아니라 속성으로 계산한 값을 본다(A12 자기소개와
  같은 규칙).
- 13 · 12 글자(칩 · 알약 · 인증 배지)는 타입 토큰 사이 값이라 `labelSmall`(14/600)에 `fontSize` 만 덮어썼다. 칩과 인증
  배지는 같은 마스터(`XPRBv`)라 private `_PillBadge` 하나에 생성자 둘(`viewChip` · `verified`)로 뒀다.
- **알약 누름 44(N7)는 아래로만 10 늘렸다.** 위로 늘리면 이름 줄이 5 밀려 pen 좌표가 어긋난다. 히어로 아래 여백 20 중 10 을
  누름 칸이 쓰고(히어로 패딩 아래 10 + 칸 10), 몸통 밖 10 은 `GestureDetector`(화면 읽기 제외), 몸통 안은 `InkWell` 이 받는다 —
  안쪽이 이겨 한 번만 불린다. 눌림 효과는 몸통(34) 크기 Material 위(COMMON §4-2). 그래서 학교 줄은 위 맞춤이고 학교 글자는
  몸통 높이 34 안에서 스스로 가운데를 잡는다.
- **알약은 학교 줄 폭의 3/4 까지**(`_pillMaxShare`). 글자를 키워 그보다 넓어지면 알약 글자가 줄을 바꾼다. 알약이 폭을 다
  먹으면 학교가 안 보이고, 반대로 알약에 `Flexible` 만 주면 1.0 에서도 학교 칸이 반으로 묶인다. Pretendard 로 2.0 까지 한
  줄(약 218 · 74%). 테스트 글꼴은 한글이 넓어 1.0 에서도 60% 로는 알약이 두 줄이 됐다(그래서 3/4).
- 히어로 높이 360 은 최소값(§11.2) — 긴 닉네임 · 2.0 에서 늘어난다. 스크림은 y150 부터 **히어로 끝까지**라 같이 늘어난다.
- 닉네임은 말줄임하지 않고 줄을 바꾼다(말줄임은 학교 줄만, Review Focus 4). 보기 칩 글자도 2.0 에서 줄을 바꾼다.
- **화면 읽기.** 알약은 `MergeSemantics` 안의 버튼 하나 — 라벨 "하트\n다시 만들기 · 10"(하트 글리프 `Semantics(label: '하트')`,
  CLAUDE.md §7). 15b 는 하트를 뺐지만(단위를 위 설명이 읽음) 여기는 "10" 의 단위를 읽어 줄 설명이 없어 넣었다. 테스트:
  `getSemantics` 라벨 · 버튼 · 탭 동작 · 자식 노드 0, `bySemanticsLabel('하트')` 없음. 꺼진 알약은 누를 수 없는 버튼, 라벨
  "다시 만들기 · 10". `MergeSemantics` 를 빼면 알약 글자가 그림 노드("내 AI 아바타")에 섞이는 것을 변형으로 봤다.
- 아바타 그림은 있을 때만 "내 AI 아바타" 이미지로 읽는다(빈 칸은 이미지가 아니다). 히어로의 칩 · 이름 · 학교는 그 노드에 한
  번에 읽힌다(카드 한 장 = 한 번 멈춤).
- 아바타 없음(N9): 같은 크기 surface-soft 빈 칸 + 스크림 그대로 — 흰 글자가 밝은 빈 칸 위에서도 읽힌다.

**A14 화면 15(`my_profile_screen.dart`)**
- 본문은 `ListView` 하나(padding 16 · 8 · 16 · 40) — 히어로 자리 `nrcYh` 위 8 과 본문 `rcsgx` 아래 40 을 겉 여백으로, 히어로 ↔
  입구 줄 44(20 + 24)를 `SizedBox` 로. 지인 리뷰 섹션 자리는 주석(N3).
- 입구 두 줄 높이 84 는 최소값 — 테스트 글꼴은 두 노트가 두 줄로 내려가(127) 테스트는 폭 · 간격 · 최소값을 본다.
- `app_icons.dart` 에 `pencil` 한 줄(대장 (가) 09-29). `sparkles` 는 이제 화면 15 에서 안 써서(추천 코드 화면만 쓴다) 주석을
  "20 추천 코드 "마지막 단계" 배지 (pen `h1CMd`)" 로 고쳤다(대장 허락 09-29).
- 옛 헤더 · 아바타 섹션 · `_InkBadge` · `_sectionTitleStyle` 은 지웠다. 코드 · 테스트에 `r8oJc` · `ffOFL` · `JaHig` · `ZCpM4` ·
  `o0yhI0` 가 남지 않는다(`grep -rn` 0건).

**A8 15 연결**
- "곧 열려요" 토스트를 15 와 15-5 가 같이 쓰게 되어 `lib/me/view/me_toast.dart` 로 모았다 — `comingSoonToast` · `MeToastHost`
  (2초 타이머 · 한 번에 하나 · dispose 때 끊음) · `MeToastLayer`(본문 아래 12 · 가로 가운데). 15-5 는 이것으로 바꿨다(동작 같음,
  테스트 그대로 통과). 테스트 `test/me/view/me_toast_test.dart` 4개.
- 토스트 자리(N18): 15 는 하단 버튼 대신 내비가 있어 **내비 위 12** — 04-3 "하단 버튼 위 12" 와 같은 규칙.
- 한 번에 하나: 만드는 동안은 변환 중 토스트가 자리를 쥔다(그동안 알약이 꺼져 다른 안내가 생길 길이 없다). 끝나면 2초짜리
  안내(15-3 · 서버 문구 · "곧 열려요")가 서로를 바로 바꾼다.
- **실패 안내는 상태 변화 하나로 받는다.** generating → failed 에서 `errorMessage` 가 없으면 15-3, 있으면(402 등 등록 거절) 그
  서버 문구를 같은 자리 · 모양(triangle-alert)으로. 처음엔 `regenerate()` 가 돌려주는 문구를 따로 띄우고 listener 는 문구 없는
  실패만 봤는데, 변형(가드 제거)을 해 보니 같은 프레임에 뒤 토스트가 앞 것을 덮어 테스트로 가를 수 없었다 — 순서에 기대는
  두 갈래 대신 한 곳에서 가른다. 402 토스트 아이콘은 pen 에 없어 15-3 과 같게 뒀다.
- generating → ready(와 fallback)이면 `ref.invalidate(myProfileProvider)`. failed 는 다시 읽지 않는다(그림 · 하트 그대로).
- 15 를 열 때 뷰모델이 **이미 만드는 중일 때만** `refreshStatus()`. idle 에서 부르면 `isWaiting` 이 idle 도 기다림으로 봐 계속
  묻는다 — 테스트 "만드는 중이 아니면 화면을 열어도 상태를 묻지 않는다".
- **더한 것 — 등록 응답을 기다리는 사이 떠나면.** dispose 의 `stopPolling()` 은 이미 지나갔고 그 뒤 `regenerate()` 가 폴링을
  건다. `_regenerate` 가 끝난 뒤 `mounted` 가 아니면 `stopPolling()`. 테스트 "등록 응답을 기다리는 사이 떠나도 폴링이 남지 않는다".
- 뷰모델 · 시트 · 온보딩 파일은 고치지 않았다.

**PhotoSlider `dotsGap`(대장 (가) 09-29)** — 위 A12 줄 참고. `photo_slider_test` 에 `dotsGap: 12` 테스트 하나, 15-5 좌표
테스트는 사진 ↔ 점 12 · 섹션 295 로.

**RED 로 본 것**: 히어로 · 토스트 · `dotsGap` 은 컴파일 오류(없는 이름), 15-5 좌표는 `Expected 275 / Actual 271`, 화면 15 는
`AppIcons.pencil` 없음 → 넣은 뒤 옛 화면에서 20개 실패. 변형으로 다시 떨어지는 것을 본 것: 떠날 때 `stopPolling` 빼기 ·
돌아올 때 `refreshStatus` 빼기 · 기다리는 사이 떠날 때 가드 빼기 · ready invalidate 빼기 · 만드는 중에도 알약 켜기 · 402 문구를
15-3 으로 · failed 분기 없애기 · 알약 누름 칸 10 빼기 · 닉네임 `Flexible` 빼기 · `MergeSemantics` 빼기.

### PR 3 화면 검토 반영 (campus-reviewer PASS · 필수 0, 2026-09-29)

- **권고 1 — 등록 응답을 기다리는 사이 떠났다가 응답 전에 돌아오면 "변환 중" 에 멈추던 것.** 뷰모델의 폴링 타이머는 하나라, 떠난
  화면의 `if (!mounted) stopPolling()` 이 돌아온 화면의 폴링까지 끊었다. 열려 있는 화면 15 수(`_openCount`, initState ++ ·
  dispose --)를 세어 0 일 때만 끊는다 — 뷰모델 파일은 그대로. 테스트 `등록 응답을 기다리는 사이 떠났다가 응답 전에 돌아오면
  폴링을 잇는다` — 고치기 전 `Expected: a value greater than <2>, Actual: <2>` 로 떨어지는 것을 봤다.
- **사소 1** — 위 `sparkles` 줄을 실제 코드에 맞게 고쳤다. 공유 파일 허락은 이 절 위 A12 · A14 줄과 1절 N 결정에 적혀 있다.
- **사소 2** — 알약 아래 10 누름 칸 `GestureDetector` 의 `excludeFromSemantics: true` 를 히어로 화면 읽기 테스트에 한 줄로 고정.

### A15 (PR 4, campus-coder, 2026-09-29)

**1 `PhotoSlot` · `savePhotos`** — 옛 A1 코드 그대로. `KeptPhoto` · `NewPhoto` 에 `==` · `hashCode`(행 id · 파일 경로)를
더했다 — 뷰모델 테스트가 보낸 칸을 값으로 비교한다(`photo_slot_test` 3). multipart 테스트 4: 옛 A1 예(`layout`
`[{"keep":"p-a"},{"new":0}]` · `avatar_source` `"1"` · 파일 칸 `photos` 1개), 새 사진 둘의 번호 · 파일 순서, 남길 사진만이면
파일 칸 없음, 409 문구 그대로. 가짜 저장소에 `photoSaves` · `savePhotosResult` · `holdSavePhotos`.

**2 `SelectedPhoto` 두 모양** — 옛 A6 코드 그대로. 온보딩 쪽은 끌기 열쇠 2줄(`photo.key`), 그림 2줄(04-2 · 04-3
`Image(image: photo.image)`), 업로드 1줄(`photo.file!`). **기존 테스트 3줄**(`photos_view_model_test` 의 `photo.file.path`)이
null 안전 컴파일 오류라 `photo.file!.path` 로 바꿨다(값 · 뜻 같음). 새 `photos_ui_state_test` 4.

**3 `photo_tiles.dart`** — 칸 위젯 6개를 글자 그대로 옮겼다(옮기기 전 파일과 비교해 이름 3개 말고 같다). 15e 가 쓰는 셋
(`DraggablePhotoTile` · `CheckingTile` · `AddPhotoTile`)만 공개, `_PhotoTile` · `_LiftedTile` · `_DropOutline` 는 private.
공개 생성자에 `super.key`(린트 `use_key_in_widget_constructors`). 04-2 · 04-3 테스트 0 변경, `test/profile` 187 그대로 통과.

**4 편집 뷰모델** — 옛 A6 `save()` 그대로에 둘을 더했다.
- `canSave` = 2~4장 · 살펴보는 중 아님 · 저장 중 아님. 04-2 "다음" 과 같은 까닭(늦게 끝난 얼굴 검사가 보낸 목록에서 빠진다).
  `PhotosUiState` 는 허락 범위 밖이라 뷰모델 getter 로 뒀다.
- **실패해도 `invalidate(myProfileProvider)`.** 옛 A6 Step 1 은 "409 면 문구 · 칸 그대로" 만 적었고, 계약 2-2 는 "앱은 실패
  문구를 보이고 화면을 다시 읽는다". 다시 읽지 않으면 409 "다시 열어 주세요" 뒤에 다시 열어도 같은 옛 id 로 채워져 409 가
  되풀이된다. 칸은 그대로다(build 가 read 라 다시 읽혀도 안 바뀐다).
- 테스트 12. 변형 4개(U3 기본값 0 빼기 · 실패 때 다시 읽기 빼기 · `keepAlive` 빼기 · 살펴보는 중 가드 빼기)가 각각 한 테스트씩
  떨어뜨리는 것을 봤다.

**5 15e 화면 · 경로**
- 경로는 상수 1 · GoRoute 1 · import 1(허락 범위). 라우터 테스트 `/me/photos 는 15e 사진 수정이다`.
- 칸 고르기(사진 / 살펴보는 중 / 빈 칸)는 04-2 `_PhotoGrid` 와 같은 세 갈래다. 04-2 쪽은 private 이라 15e 에 다시 적었다.
- **대장 확인(pen `lfmT0` · `m2cAn`, 09-29)**: 사진 줄 `lfmT0` 은 alignItems start — **위 맞춤**(보조 184 가 대표 200 의 위에
  붙고 아래 16 이 빈다). "저장" `m2cAn` 은 Spacer `BCwfQ` 뒤라 **바닥 고정 · 아래 28**(15c `zUZFx` 와 같은 구조). 둘 다 처음
  구현 그대로이고, 테스트에 한 줄씩 고정했다(보조 위 = 대표 위, 버튼 아래 28).
- 안내문 14/400 muted 줄 20(줄높이 속성 없음 · 두 줄 렌더 40), 폭 312 에서 줄을 바꾼다(C2).
- 오류는 두 모양이다. 저장 실패 = 버튼 위 오류 글(편집 공통 규칙), 고르기 안내(얼굴 없음 · 최대 4장) = 04-2 모양 토스트
  (alert-triangle, 버튼 위 12). 둘 다 `errorMessage` 로 와서, 화면이 "저장이 끝난 순간(isSubmitting true → false)의 문구" 만
  오류 글로 가른다. 토스트 시간은 나 탭 `MeToastHost` 의 2초(04-2 는 3초).
- 테스트 22. 변형(오류 글 가르기 · D10 빈 자리 · 저장 뒤 pop · 위 맞춤)이 모두 떨어지는 것을 봤다.

**6 15-5 연결** — "실제 사진 교체" → `context.push(AppRoutes.myPhotos)`. "곧 열려요" 는 "수정 ›" 만 남아, 토스트 자리 · 줄인
움직임 · 타이머 테스트는 "수정 ›" 를 누른다. 새 테스트: "교체 → 15e" · N8 `saving_in_15e_returns_to_15_5_with_the_new_photos`
(실제 라우터 · 가짜 저장소, 저장 중에 서버 값을 바꿔 15-5 사진 줄이 새 값인지). `me_toast.dart` 주석 한 줄(교체는 연결됨).

**배율** — 2.0 에서 66×88 "사진 추가" 칸(`AddPhotoTile` 의 Column)이 세로로 넘쳤다(테스트 글꼴 12, 계산 plus 24 + 8 + 글자
두 줄 67.2 = 99.2 > 88). 1.3 · 1.5 는 글자가 두 줄로 바뀌고 칸 안에 들어간다. 옛 A6 대로 멈추고 물었고, **대장 결정 (가)(09-29)
— 글자가 칸에 안 들어가면 더하기 아이콘만, 낭독 이름 "사진 추가" 는 아이콘에.** `AddPhotoTile` 만 고쳤다(허락 범위): `LayoutBuilder`
안에서 `TextPainter` 로 실제 글꼴 · 배율 · 칸 폭의 글자 높이를 재어 아이콘 24 + 8 + 글자가 칸 높이를 넘으면 글자를 뺀다(배율 숫자를
박지 않는다). 새 `photo_tiles_test` 6(66×88 1.0 · 1.3 · 1.5 글자 보임, 2.0 넘침 0 · 글자 숨김 · 아이콘 · 낭독 "사진 추가" + 누름,
1.0 낭독도 같은 모양, 04-2 158×158 은 2.0 에서도 글자 보임) — 고치기 전 2.0 테스트가 `RenderFlex overflowed by 12` 로 떨어지는 것을
봤다. 변형 2개(늘 숨기기 · 아이콘 낭독 이름 빼기)도 떨어진다. 04-2 테스트 그대로 통과, 15e 배율 2.0 테스트도 통과.

**RED 로 본 것**: 1 · 2 · 4 · 5 는 없는 이름으로 컴파일 오류, 6 은 "교체" 를 눌러도 15e 가 안 뜨고(`Found 0 widgets with text
"15e 사진 수정 화면"`) N8 은 `MyPhotosScreen` 0개. 1 의 번호 매기기는 `next++` → `next` 변형으로 layout 테스트가 떨어지는
것을 봤다. 라우터는 GoRoute 를 빼면 `/me/photos` 테스트가 떨어진다.

### PR 4 검토 반영 (campus-reviewer PASS · 필수 0 · 권고 0, 2026-09-29)

- **사소 2 — 저장 중에도 칸이 눌리던 것.** 보내는 동안 칸을 바꾸면 성공 뒤 버려지고, 얼굴 검사 안내가 토스트 대신 저장 오류
  자리로 샜다. `_PhotoSlots` 를 `IgnorePointer(ignoring: state.isSubmitting)` 로 감쌌다. 테스트 `저장 중에는 칸을 누를 수
  없다` — 고치기 전 `Expected: <0>, Actual: <1>` 로 떨어지는 것을 봤다.
- **사소 1 — 남김.** 409 직후 너무 빨리 다시 열면 `myProfileProvider`(autoDispose 아님)가 다시 읽는 동안 옛 값을 줘 409 가
  한 번 더 뜰 수 있다. 다시 열면 풀린다. 실기기에서 보이면 편집 뷰모델 build 가 로딩 중일 때 칸을 비우는 쪽으로 고친다.

### A16 (PR 3-2, campus-coder, 2026-09-29)

**뷰모델 `lib/me/viewmodel/basic_info_edit_view_model.dart`** — `BasicInfoEditViewModel`(autoDispose) + `BasicInfoEditUiState` 한
파일(15c `profile_edit_view_model.dart` 와 같은 모양).
- 열 때 `myProfileProvider` 를 read(watch 아님 — 15c · 15e 와 같다)해 닉네임 · 키 · `nicknameChangeableAt` 을 서버 값(saved)과
  입력값에 같이 담는다. 키가 null 이면 빈 글자, 바꾸지 않으면 보내지 않는다.
- 바뀐 칸만 보낸다(`isNicknameChanged` · `isHeightChanged`). 둘 다 그대로거나 바뀐 칸이 형식 오류면 `canSave` false(B2).
- **중복 확인은 04-1 저장소(`basicInfoRepositoryProvider.checkNicknameAvailability`)를 그대로 쓴다** — 같은 GET 이라
  `MeRepository` 에 새 메서드를 만들지 않았다. 형식 · 300ms 디바운스 · 낡은 결과 버리기 · 네트워크 실패는 말없이 = 04-1 과 같다.
  지금 닉네임으로 되돌리면 묻지 않는다.
- 문구(형식 · 중복 · 확인 중 · 사용 가능)는 UiState 에 다시 적었다 — 04-1 `BasicInfoUiState` 는 인스턴스 getter 라 빌려 쓸 수
  없다. 테스트 하나가 04-1 문구와 글자 하나까지 같은지 고정한다. 키 범위 120~230 · "3자리를 다 친 뒤" 오류도 04-1 그대로.
- 날짜는 `at.toUtc().add(9시간)` 의 월 · 일(옛 A7). `2026-10-26T15:00:00+00:00` → "10월 27일부터", `toLocal()` 로 받아도 같다.
- **오류 자리(B5).** 서버 문구로 가른다(`chat_errors.dart` 방식): `NICKNAME_TAKEN` · `NICKNAME_CHANGE_TOO_SOON` → 닉네임 칸,
  키를 보냈고 `INVALID_INPUT`(422) → 키 칸, 그 밖(네트워크 등) → 버튼 위 저장 실패 글(A16 "04-1 이 저장 실패 문구를 두는 자리").
  B5 표의 "실패" 는 이 줄(A16 본문)로 읽었다. 서버 칸 오류는 그 칸을 고칠 때까지 남고 그동안 저장이 꺼진다(같은 409 반복 방지).
  닉네임 · 키를 둘 다 보냈는데 422 면 어느 칸인지 몰라 버튼 위로 간다(앱 형식 검사가 막아 드물다).
- 저장 중 `ref.keepAlive()`, 성공하면 `invalidate(myProfileProvider)` + completed. 실패하면 다시 읽지 않는다(15c 와 같다).

**화면 `lib/me/view/basic_info_edit_screen.dart` + 경로**
- `app_routes.dart` 상수 `myBasicInfo` 1 · `app_router.dart` `_meRoutes()` GoRoute 1 + import 1(허락 범위). 라우터 테스트
  `/me/basic-info 는 15d 기본 정보 수정이다`.
- **`app_icons.dart` 에 `info` 한 줄 + 주석(대장 (가) 09-29)** — 15d helper `G1tl8` 아이콘이 AppIcons 에 없었다. 채팅탭 지인 리뷰
  PR 도 같은 이름을 넣는다 — rebase 때 정리는 대장 몫.
- 칸은 04-1 `LabeledField`(common, 고치지 않음)를 쓰지 않고 `_InputField` 로 다시 그렸다 — 잠김(입력 불가 · hairline · lock
  suffix) · helper 앞 아이콘(info · clock-3) · 상자 56 · 라벨 ↔ 상자 8 이 `LabeledField` 에 없다. 오류 모양(테두리 error 2 ·
  circle-alert 14 · 12/400 error)과 누름 테두리 primary, 입력 포매터(`nicknameInputFormatters` · `heightInputFormatters`)는 04-1
  그대로 가져왔다.
- **값 여백.** Material 3 는 외곽선 칸 값 양옆에 `gapPadding`(4)을 더 둔다 — 그대로면 값이 pen 16 이 아니라 20 에서 시작해
  `gapPadding: 0`. (04-1 `LabeledField` 도 같은 기본값이라 20 일 것으로 보인다 — 재지 않았고 고치지 않았다, 참고만.)
- 상자 위아래 여백은 (56 − 23) / 2 = 16.5 — 자물쇠가 pen 대로 상자 한가운데(y18)에 온다. pen 값 글자는 y17 이라 0.5 차이.
  56 은 `constraints` 최소값이라 글자를 키우면 늘어난다.
- 줄높이는 pen 렌더: 라벨 20/14, 값 23/16(body 토큰 1.6 이면 상자가 57.6), helper 17/12(04-1 caption 1.4 는 16.8).
- 잠김은 `TextField(enabled: false)` — 화면 읽기가 "사용 불가 입력란" 으로 읽는다. 자물쇠는 suffix(앞 4 + 입력기 4 = 값과 8,
  뒤 16).
- 닉네임 helper 순서: 잠김(clock-3) > 오류 > 확인 중(04-1 도는 원) > 사용 가능(circle-check success) > 평소(info). 확인 중 ·
  사용 가능은 pen 에 없어 04-1 모양을 그대로 쓴다.
- 저장은 15c · 15e 와 같은 바닥 고정 · 아래 28, 저장 중 `AppButton(isLoading: true)`(B6). 성공하면 `context.pop(true)`.
- 04-1 의 3자리 제한 포매터는 이미 3자리면 더 친 글자를 버린다(옛 값 유지) — 키를 바꾸려면 지우고 친다. 04-1 과 같다.

**15-5 연결** — "수정 ›" → `context.push<bool>(AppRoutes.myBasicInfo)`, 결과가 true 면 `showTimedToast(savedToast)`.
`savedToast`("저장했어요")는 `me_toast.dart` 에 두었고 아이콘은 circle-check 16 흰색 — pen 에 이 토스트가 없어 조각 6 완료
토스트(`yEDB9`, `showSafetyToast` 기본값)를 따랐다. `comingSoonToast` 는 15b-3 충전이 계속 쓴다(주석만 고침). 15-5 의 "곧 열려요"
토스트 테스트 4개(2초 · 자리 · 줄인 움직임 · 떠날 때 타이머)는 "15d 에서 저장하고 돌아오기" 로 띄운다(15d 자리 가짜 화면이
`pop(true)` · `pop()`). 새 테스트: "누르면 15d" · "저장 없이 돌아오면 안내 없음" · N8 + B4
`saving_in_15d_returns_to_15_5_with_the_new_height_and_a_toast`(실제 라우터 · 가짜 저장소, 저장 중에 서버 키를 181 로 바꿔
15-5 가 "181cm" + "저장했어요").
- 남긴 것: 저장 중에 뒤로 나가면 저장은 끝까지 되고(keepAlive) 15-5 도 새 값을 그리지만, 15d 가 pop(true) 를 못 해 "저장했어요"
  는 뜨지 않는다.

**테스트** — 뷰모델 26 · 화면 37(배율 1.0/1.3/1.5/2.0 × 15d · 15d-2 = 8) · 15-5 +7(새 흐름) · 라우터 +1.
**RED 로 본 것**: 뷰모델 · 화면은 없는 이름(파일 · `AppRoutes.myBasicInfo` · `AppIcons.info`)으로 컴파일 오류, 15-5 는 7개가
"15d 기본 정보 수정 화면" · `BasicInfoEditScreen` 0개로 떨어졌다. 화면 첫 실행에서 자물쇠 중심 `Expected 144 / Actual 143.5`
(→ 16.5 여백). 잉크 테스트는 `find.byType(InkResponse)` 가 하위 클래스 InkWell 을 못 찾아 빈 목록으로 통과하던 것을 "하나
이상" 단언으로 잡고 술어로 고쳤다. 변형으로 다시 떨어지는 것을 본 것: keepAlive 즉시 닫기 · 닉네임 늘 보내기 · UTC 날짜 ·
같은 닉네임도 묻기 · B2 빼기 · `gapPadding` 빼기 · `pop(true)` → `pop()` · 키 값 색 disabled · 잠금에도 입력 허용 · 오류 표식
빼기 · 15-5 토스트 조건 빼기 · GoRoute 빼기.

### PR 3-2 검토 반영 (campus-reviewer PASS · 필수 0 · 권고 0, 2026-09-29)

- **사소 1 — 저장 중에도 칸에 입력이 들어가던 것.** 180 을 보내는 동안 190 을 치면 180 이 저장되고 190 은 말없이 버려졌다.
  15e 처럼 저장 중엔 칸을 막는다 — 다만 `IgnorePointer` 는 이미 열린 키보드 입력을 못 막아 `TextField(readOnly: isSaving)`
  로 막았다(`enabled` 를 끄면 테두리가 hairline 으로 바뀌어 모양이 달라진다). 테스트 `저장 중에는 칸을 고칠 수 없다` — 고치기
  전 `Found 1 widget with text "190"` 으로 떨어지는 것을 봤다.
- **사소 2** — 위 B5 줄을 "칸 탓 오류는 칸 아래, 칸 탓이 아닌 실패는 04-1 처럼 버튼 위" 로 고쳤다(대장 확인 09-29, 코드는 그대로).
- **사소 3** — 날짜 테스트 상수에 "한국 시간대 PC 에서는 `toLocal()` 변형을 못 잡고 UTC CI 가 잡는다" 주석 한 줄.
- **main 위로 옮기며(09-29) — `AppIcons.info` 겹침.** 채팅탭 지인 리뷰 PR 3(#167)가 먼저 merge 돼 main `app_icons.dart` 에 같은
  이름 `info` 가 있다(20c · 14d). 대장 규칙대로 나중 쪽인 이 PR 이 자기 줄 · 주석을 빼고, main 줄의 주석에 "15d 닉네임
  helper(`G1tl8`)" 만 덧붙였다(같은 이름 두 번이면 컴파일 오류). 화면 커밋을 고쳐 커밋마다 컴파일되게 했다.
