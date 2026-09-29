# 친구 초대(16 설정 줄 · 16i 시트) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**앱만 바뀐다.** 서버 `GET /referral/my-code` 는 이미 운영에 있다(배포 00034-gxd). 서버 · DB · 마이그레이션 변경 0 — 로컬 DB 명령도 0.

**pen 값(16 설정 줄 · 16i 친구 초대 시트)은 아직 안 왔다.** campus-pen 이 그리는 중이고 값표는 `C:/Users/user/OneDrive/Desktop/조각6_검토/값표_친구초대.md` 로 온다. 그 전에는 Task 1(데이터)만 한다. Task 2 · 3 은 뼈대와 동작 테스트, Task 4 에서 pen 값을 맞춘다.

**Goal:** 이미 학교가 열린 사용자도 설정 → "친구 초대" 줄 → 시트에서 내 추천 코드를 크게 보고, 복사하고, 공유할 수 있게 한다.

**Architecture:** 내 코드는 `FutureProvider.autoDispose<Result<String>>`(16e `accountInfoProvider` 와 같은 모양)로 읽는다. 시트는 조각 6 시트 틀(`showSafetySheet` · `SafetySheet` · `SafetySheetButton`)에 올린다. 공유는 홈탭 19 의 `shareTextProvider`(share_plus) 를 그대로 쓰고, 공유 글은 19 계획서 결정 5 문구와 같다. 복사는 `Clipboard.setData`, 안내는 시트 안 `AppToast`(19 `_showToast` 와 같은 방식 — 한 번에 하나, 3초).

**Tech Stack:** Flutter · Riverpod 3 · go_router · share_plus(이미 있음) · flutter_test.

**Spec:** 대장 배정(2026-09-29, 사용자 결정 "가") · `docs/superpowers/plans/2026-09-28-referral.md`(서버 계약) · `docs/superpowers/plans/2026-09-28-cohort-wait.md` 결정 5(공유 글) · `frontend/docs/DESIGN.md` §9 화면 16.

## 결정

| # | 무엇 | 결정 | 쓰는 Task |
| --- | --- | --- | --- |
| I1 | 자리 | 설정(16) 목록 "계정" 바로 위. 커뮤니티 A6 "무료로 하트 모으기" 줄이 먼저 merge 되면 그 줄 아래 · 계정 위. 뒤에 merge 되는 쪽이 두 줄을 다 살린다 | 3 |
| I2 | 시트 내용 | 내 코드 크게 · 복사 · 공유하기 · 닫기 | 2 |
| I3 | 설명 문구 | `친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.` — 50 은 `redeem_referral` 이 양쪽에 주는 값(마이그레이션 `20260928010000_create_referrals.sql`)과 같아야 한다 | 2 |
| I4 | 복사 안내 | `코드를 복사했어요` | 2 |
| I5 | 공유 글 | 19 결정 5 그대로: `CampusMate 에서 같이 해요! 가입할 때 추천 코드 {code} 를 넣어 줘.` | 1 · 2 |
| I6 | 코드를 못 읽었을 때 | pen 에 없으면 16e `_LoadError` 와 같은 모양: 회색 `failure.toDisplayMessage()` + `다시 시도`(다시 읽기). 복사 · 공유는 코드가 있을 때만 보인다 | 2 |

### 대장에게 물은 것 — **Q1 (가) · Q2 허락(2026-09-29 대장)**

| # | 물음 | 선택지 | 추천 |
| --- | --- | --- | --- |
| Q1 | 공유 글 · `shareTextProvider` 가 홈 화면 파일 `home/view/cohort_wait_view.dart` 안에 있다. 시트가 같이 쓰려면? | (가) `referral/model/invite_share.dart` 로 옮기고 19 는 import 만 바꾼다 — 홈 파일 2개(뷰 · 테스트)의 import 줄과 provider 정의 11줄. 홈탭 `fix/cohort-wait-pen` 도 같은 파일을 고치지만 겹치는 줄은 없다 (나) 시트가 `home/view/cohort_wait_view.dart` 를 import — 홈 파일 0줄, 대신 추천 기능이 홈 화면 파일에 기댄다 | **(가)** — 공유 글이 한 곳에만 있어 문구를 바꿀 때 한 번만 고친다. 홈 파일은 import 줄만 바뀐다 |
| Q2 | `settings_screen.dart` 는 공유 파일 | import 1줄 + `ListTile` 6줄(I1 자리) + `settings_screen_test.dart` 에 테스트 · override 추가 — 줄 단위 허락 요청 | 허락 요청 |

## 화면 대조표 (값표 `조각6_검토/값표_친구초대.md`, campus-pen 2026-09-29)

| 화면 요소 | pen 노드 | 값 | 코드 자리 |
| --- | --- | --- | --- |
| 16 줄 자리 | `auq6h` 3번째 · 계정 `B1RIX` 위 | 대장 결정 ①: 매칭 활성화 → 무료로 하트 모으기(A6) → 친구 초대 → 계정 | `settings_screen.dart` |
| 16 줄 | `b1fvA`(K4uiNp, 72) | 앱은 이웃 `ListTile` 모양(A6 와 같은 결정, 16 전체 pen 맞추기는 백로그 70) | 〃 |
| 16 줄 아이콘 | `b1fvA/RqtqK` user-plus | `AppIcons.userPlus` muted | 〃 |
| 16 줄 설명 | `b1fvA/m4SK5` "내 추천 코드를 친구에게 보내요" 12/400 lh1.4 | 글은 pen, 모양은 이웃 매칭 활성화 설명(`bodySmall` muted) — 편차 1 | 〃 |
| 시트 틀 | `vBZjk`(D0TvG) 흰 · 위 24 · 그림자 #00000026 (0,-2) 16 · 손잡이 영역 [12,0] · 내용 [8,16,32,16] 간격 16 | 같은 값, 15d-2 `_DeleteConfirmSheet` 와 같은 모양 | `invite_friends_sheet.dart` |
| 제목 | `xd8je` 20/700 렌더 29 | `navTitle` · height 29/20 | 〃 |
| 설명 | `LEq3I` 14/400 lh1.55 #6A6A6A | `bodySmall` muted | 〃 |
| 코드 상자 | `e3n2P` surface-soft · 14 · [12,12,12,16] · 간격 12 | `_CodeBox` | 〃 |
| 코드 | `Kf6Wi` display 32/700/1.3/-0.96 | `display` ink, 자리가 모자라면 줄여 보임(`FittedBox`) | 〃 |
| 복사 | `yAaQX` 44 · 12 · #E5E5E5 · [0,14] · 간격 6 · copy 16 #222 · 14/600 렌더 20 | `_CopyButton` | 〃 |
| 공유하기 | `ECxPJ` 주 버튼 56 · 16 · 18/700 | `AppButton` primary | 〃 |
| 닫기 | `HKdWX` CancelButton 48 · 14/600 #C4224B | `AppButton` text | 〃 |
| 버튼 간격 | `KMbP4` 8 | `AppSpacing.xs` | 〃 |
| 토스트 | `CuNVR` check 16 흰 · 시트 윗변 16 위 · 가운데 | `AppToast` + `AppIcons.check`, 공유 창 실패 안내에는 아이콘 없음 | 〃 |
| 20 자리표시 | `e8YTTe` "예: CAMPUS-2409" → 대장이 "예: K7M2QX" 로 고침 | `_fieldHint = '예: K7M2QX'`(대장 결정 ②) | `referral_code_screen.dart` |

### pen 과 다른 점(편차)

1. 16 줄은 pen 72 높이 카드 줄이 아니라 이웃과 같은 `ListTile` 이고, 설명 글자는 12 가 아니라 이웃 매칭 활성화 설명과 같은 14(`bodySmall`)다. 16 화면 전체를 pen 에 맞추는 일은 백로그 70.
2. 코드를 불러오는 중(가운데 스피너)과 못 읽음(회색 문구 + `다시 시도`, 공유하기 숨김)은 pen 에 없다. 16e `_LoadError` 와 같은 모양이다(대장 결정 ③).
3. 공유 창을 못 열었을 때의 안내는 pen 에 없다. 복사 토스트와 같은 자리 · 모양에 아이콘 없이 `UnknownFailure` 문구를 띄운다.

## Global Constraints

- 서버 · DB · 마이그레이션 변경 0. **`supabase db reset` · `supabase test db` 등 로컬 DB 명령 금지.** 도우미 요청문에도 "supabase db reset·test db 등 로컬 DB 명령 금지, 수치는 리뷰어 값 인용" 한 줄.
- `git stash` 금지(워크트리끼리 한 목록). 필요하면 scratchpad 사본.
- 도우미는 pencil 을 직접 부르지 않는다 — pen 값은 값표로만 대조. 권한이 막은 동작은 다른 자리에서 다시 하지 않는다.
- 공유 파일(`core/router/*` · `core/theme/*` · `common/widgets/*` · pubspec · `matching/view/settings_screen.dart`)은 대장 허락 뒤에만. 이 계획은 새 의존성 · 새 경로 · 새 아이콘 토큰을 만들지 않는다.
- 커밋 · PR 에 도구 표식(Co-Authored-By · Generated with) 금지. `dart format` 금지.
- 로그에 코드 · id 를 남기지 않는다.
- 커밋 · PR 은 campus-git. 리뷰 PASS 뒤에만.

## Review Focus

1. **코드를 못 읽음(비행기 모드 · 서버 오류)** — 시트가 빈 칸이나 영원히 도는 표시로 남지 않는다. 오류 문구 + `다시 시도`, 누르면 다시 읽어 코드가 뜬다. 복사 · 공유는 코드가 없을 때 안 보인다. → Task 2 "못 읽으면 문구와 다시 시도, 누르면 코드가 뜬다".
2. **공유하기를 빠르게 두 번** — 공유 창이 두 번 뜨지 않는다. → Task 2 "공유하기를 두 번 눌러도 한 번만 공유한다".
3. **공유 창을 못 엶(기기 쪽 오류)** — 조용히 끝나지 않고 `UnknownFailure` 문구로 안내, 시트는 그대로. → Task 2 "공유 창을 못 열면 안내하고 시트는 남는다".
4. **복사 안내가 떠 있는 동안 시트를 닫음** — 닫힌 시트의 타이머가 남아 오류를 내지 않는다. → Task 2 "안내가 떠 있을 때 닫아도 타이머가 남지 않는다".
5. **글자를 키운 기기(2배)** — 코드 6자가 잘리거나 넘침 오류 없이 보이고, 시트는 스크롤된다. → Task 2 "글자 2배에서도 넘치지 않는다".

---

### Task 1: 내 코드 provider · 공유 글 한 곳으로 (데이터 — pen 없이 한다)

**Files:**
- Create: `frontend/lib/referral/viewmodel/my_referral_code_provider.dart`
- Create(Q1 (가)일 때만): `frontend/lib/referral/model/invite_share.dart`
- Modify(Q1 (가)일 때만): `frontend/lib/home/view/cohort_wait_view.dart`(import · provider 정의 빼기 · 공유 글을 `inviteShareText` 로) · `frontend/test/home/view/cohort_wait_view_test.dart`(import 한 줄)
- Modify: `frontend/test/referral/model/fake_referral_repository.dart`(`myCodeCalls` 카운터)
- Test: `frontend/test/referral/viewmodel/my_referral_code_provider_test.dart` · `frontend/test/referral/model/invite_share_test.dart`

**Interfaces:**
- Produces: `final myReferralCodeProvider = FutureProvider.autoDispose<Result<String>>(...)` · `final shareTextProvider = Provider<Future<void> Function(String)>(...)` · `String inviteShareText(String code)`

> **진행(2026-09-29):** Q1 = (가) · Q2 = 허락(대장). Task 1~4 끝. 각 테스트는 먼저 실패를 확인하고 구현했다.
> - 시트의 두 번 공유 막기와 닫을 때 타이머 끄기는 그 코드를 빼 보면 테스트가 실패한다.
> - Task 4 에서 기존 16g 테스트("빠르게 두 번 눌러도 한 번")가 깨졌다.
>   - 닫히는 시트는 누름을 아래 화면으로 흘려보낸다. 두 번째 탭이 새 줄로 내려온 로그아웃 줄에 떨어졌다.
>   - 대장 허락으로 그 테스트만 논리 800×1400 으로 키웠다(3줄).
> - `flutter analyze` 0 · `flutter test` 1427 전부 통과.

- [x] **Step 1: 가짜 저장소에 부른 횟수를 센다**

```dart
  int myCodeCalls = 0;

  @override
  Future<Result<String>> myCode() async {
    myCodeCalls++;
    return nextMyCode;
  }
```

- [x] **Step 2: 실패하는 테스트**

```dart
// test/referral/viewmodel/my_referral_code_provider_test.dart
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/viewmodel/my_referral_code_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_referral_repository.dart';

void main() {
  late FakeReferralRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeReferralRepository();
    container = ProviderContainer(overrides: [referralRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
  });

  test('내 코드를 읽는다', () async {
    final sub = container.listen(myReferralCodeProvider, (_, _) {});
    addTearDown(sub.close);
    final result = await container.read(myReferralCodeProvider.future);
    expect(result.when(onSuccess: (code) => code, onFailure: (_) => null), 'K7QMX2');
  });

  test('실패도 던지지 않고 Result 로 준다', () async {
    repository.nextMyCode = const FailureResult(NetworkFailure());
    final sub = container.listen(myReferralCodeProvider, (_, _) {});
    addTearDown(sub.close);
    expect(await container.read(myReferralCodeProvider.future), isA<FailureResult<String>>());
  });

  test('invalidate 하면 다시 읽는다(다시 시도)', () async {
    final sub = container.listen(myReferralCodeProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(myReferralCodeProvider.future);
    container.invalidate(myReferralCodeProvider);
    await container.read(myReferralCodeProvider.future);
    expect(repository.myCodeCalls, 2);
  });
}
```

```dart
// test/referral/model/invite_share_test.dart — Q1 (가)일 때만
import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('공유 글은 19 결정 5 문구다', () {
    expect(inviteShareText('K7QMX2'), 'CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘.');
  });
}
```

- [x] **Step 3: 실패 확인**

Run: `cd frontend && flutter test test/referral/viewmodel/my_referral_code_provider_test.dart test/referral/model/invite_share_test.dart`
Expected: FAIL — `my_referral_code_provider.dart` · `invite_share.dart` 없음.

- [x] **Step 4: 구현**

```dart
// lib/referral/viewmodel/my_referral_code_provider.dart
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16i 친구 초대 시트가 읽는 내 추천 코드. 실패도 [Result] 그대로 — 던지면 Riverpod 3 이 재시도 타이머를 건다(16e 와 같다).
/// autoDispose: 시트를 닫으면 내려가고, 못 읽었던 사람은 다시 열 때 새로 읽는다.
final myReferralCodeProvider = FutureProvider.autoDispose<Result<String>>((ref) {
  return ref.watch(referralRepositoryProvider).myCode();
});
```

Q1 (가)일 때 — `cohort_wait_view.dart` 16~24줄의 `shareTextProvider` 를 그대로 옮긴다:

```dart
// lib/referral/model/invite_share.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// 휴대폰 공유 창(19 계획서 결정 5). 테스트는 받은 글을 모은다. 19 대기 화면과 16i 친구 초대 시트가 같이 쓴다.
final shareTextProvider = Provider<Future<void> Function(String)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

/// 공유 글(19 결정 5). 하트 숫자 · 스토어 링크는 넣지 않는다.
String inviteShareText(String code) => 'CampusMate 에서 같이 해요! 가입할 때 추천 코드 $code 를 넣어 줘.';
```

`cohort_wait_view.dart`: `share_plus` import 와 provider 정의를 빼고 `import 'package:campus_mate/referral/model/invite_share.dart';` 를 더한다. 84줄은 `onSuccess: (code) => ref.read(shareTextProvider)(inviteShareText(code)),` 로, 위 주석 "공유 글은 계획서 결정 5 제안…" 은 지운다(함수 주석으로 갔다). `cohort_wait_view_test.dart` 는 `shareTextProvider` import 를 `invite_share.dart` 로 바꾼다.

- [x] **Step 5: 통과 확인**

Run: `cd frontend && flutter test test/referral test/home/view/cohort_wait_view_test.dart`
Expected: 전부 PASS(19 공유 글 테스트 139줄도 그대로 통과).

---

### Task 2: 16i 친구 초대 시트 (동작 먼저 — pen 값은 Task 4)

**Files:**
- Create: `frontend/lib/referral/view/invite_friends_sheet.dart`
- Test: `frontend/test/referral/view/invite_friends_sheet_test.dart`

**Interfaces:**
- Consumes: `myReferralCodeProvider` · `shareTextProvider` · `inviteShareText`(Task 1) · `showSafetySheet` · `SafetySheet` · `SafetySheetButton`(`safety/view/safety_sheet.dart`) · `AppToast` · `UnknownFailure().toDisplayMessage()` · `Failure.toDisplayMessage()`
- Produces: `Future<void> showInviteFriendsSheet(BuildContext context)` · `class InviteFriendsSheet extends ConsumerStatefulWidget`

- [x] **Step 1: 실패하는 테스트**

```dart
// test/referral/view/invite_friends_sheet_test.dart
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/view/invite_friends_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_referral_repository.dart';

void main() {
  late FakeReferralRepository repository;
  late List<String> shared;
  late Future<void> Function(String) share;
  late List<String> copied;

  Future<void> pump(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          referralRepositoryProvider.overrideWithValue(repository),
          shareTextProvider.overrideWithValue((text) => share(text)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showInviteFriendsSheet(context), child: const Text('열기')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    repository = FakeReferralRepository();
    shared = [];
    copied = [];
    share = (text) async => shared.add(text);
  });

  testWidgets('내 코드와 설명을 보여 준다', (tester) async {
    await pump(tester);
    expect(find.text('K7QMX2'), findsOneWidget);
    expect(find.text('친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.'), findsOneWidget);
  });

  testWidgets('복사하면 코드가 클립보드에 들어가고 안내가 3초 뜬다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('복사'));
    await tester.pump();
    expect(copied, ['K7QMX2']);
    expect(find.text('코드를 복사했어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('코드를 복사했어요'), findsNothing);
  });

  testWidgets('공유하기는 19 와 같은 공유 글을 보낸다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('공유하기'));
    await tester.pump();
    expect(shared, ['CampusMate 에서 같이 해요! 가입할 때 추천 코드 K7QMX2 를 넣어 줘.']);
  });

  testWidgets('공유하기를 두 번 눌러도 한 번만 공유한다', (tester) async {
    final gate = Completer<void>();
    share = (text) async {
      shared.add(text);
      await gate.future;
    };
    await pump(tester);
    await tester.tap(find.text('공유하기'));
    await tester.pump();
    await tester.tap(find.text('공유하기'));
    await tester.pump();
    expect(shared, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('공유 창을 못 열면 안내하고 시트는 남는다', (tester) async {
    share = (text) async => throw PlatformException(code: 'x');
    await pump(tester);
    await tester.tap(find.text('공유하기'));
    await tester.pump();
    expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget);
    expect(find.byType(InviteFriendsSheet), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('못 읽으면 문구와 다시 시도, 누르면 코드가 뜬다', (tester) async {
    repository.nextMyCode = const FailureResult(NetworkFailure());
    await pump(tester);
    expect(find.text(const NetworkFailure().toDisplayMessage()), findsOneWidget);
    expect(find.text('복사'), findsNothing);
    expect(find.text('공유하기'), findsNothing);

    repository.nextMyCode = const Success('K7QMX2');
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('K7QMX2'), findsOneWidget);
    expect(repository.myCodeCalls, 2);
  });

  testWidgets('닫기를 누르면 시트가 닫힌다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteFriendsSheet), findsNothing);
  });

  testWidgets('안내가 떠 있을 때 닫아도 타이머가 남지 않는다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('복사'));
    await tester.pump();
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteFriendsSheet), findsNothing);
    // 테스트가 끝날 때 남은 타이머가 있으면 flutter_test 가 실패로 잡는다.
  });

  testWidgets('글자 2배에서도 넘치지 않는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('K7QMX2'), findsOneWidget);
  });
}
```

`Completer` 는 `dart:async` import 를 더한다.

- [x] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/referral/view/invite_friends_sheet_test.dart`
Expected: FAIL — `invite_friends_sheet.dart` 없음.

- [x] **Step 3: 구현(가안 — pen 값은 Task 4)**

```dart
// lib/referral/view/invite_friends_sheet.dart
import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:campus_mate/referral/viewmodel/my_referral_code_provider.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16i 친구 초대 시트를 띄운다. 설정 "친구 초대" 줄이 부른다.
Future<void> showInviteFriendsSheet(BuildContext context) =>
    showSafetySheet<void>(context, (_) => const InviteFriendsSheet());

/// 16i(pen 값표 대기). 내 추천 코드를 크게 보여 주고 복사 · 공유한다.
class InviteFriendsSheet extends ConsumerStatefulWidget {
  const InviteFriendsSheet({super.key});

  @override
  ConsumerState<InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends ConsumerState<InviteFriendsSheet> {
  // 50 은 redeem_referral 이 양쪽에 주는 하트(20260928010000_create_referrals.sql)와 같아야 한다.
  static const String _description = '친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.';

  /// 공유 창이 떠 있는 동안 다시 눌러도 두 번 열지 않는다.
  bool _sharing = false;

  /// 지금 떠 있는 안내. 19 대기 화면과 같은 방식 — 한 번에 하나, 3초.
  String? _toast;
  Timer? _toastTimer;
  static const Duration _toastDuration = Duration(seconds: 3);

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _showToast('코드를 복사했어요');
  }

  Future<void> _share(String code) async {
    if (_sharing) return;
    _sharing = true;
    try {
      await ref.read(shareTextProvider)(inviteShareText(code));
    } catch (_) {
      // 공유 창을 못 열었다(기기 쪽 오류). 조용히 끝내지 않는다.
      if (mounted) _showToast(const UnknownFailure().toDisplayMessage());
    } finally {
      _sharing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(myReferralCodeProvider);
    void retry() => ref.invalidate(myReferralCodeProvider);
    return SafetySheet(
      children: [
        Text('친구 초대', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.md),
        Text(_description, style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5)),
        const SizedBox(height: AppSpacing.lg),
        ...code.when(
          loading: () => const [Center(child: CircularProgressIndicator())],
          error: (_, _) => _loadError(const UnknownFailure().toDisplayMessage(), retry),
          data: (result) => result.when(
            onSuccess: (value) => [
              Center(child: Text(value, style: AppTypography.display.copyWith(color: AppColors.ink))),
              const SizedBox(height: AppSpacing.md),
              SafetySheetButton.neutral(label: '복사', onPressed: () => _copy(value)),
              const SizedBox(height: AppSpacing.md),
              SafetySheetButton.primary(label: '공유하기', onPressed: () => _share(value)),
            ],
            onFailure: (failure) => _loadError(failure.toDisplayMessage(), retry),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SafetySheetButton.neutral(label: '닫기', onPressed: () => Navigator.of(context).pop()),
        if (_toast != null) ...[
          const SizedBox(height: AppSpacing.md),
          Center(child: AppToast(label: _toast!)),
        ],
      ],
    );
  }

  /// pen 에 없는 상태(I6) — 16e `_LoadError` 와 같은 회색 문구 + 다시 시도.
  List<Widget> _loadError(String message, VoidCallback onRetry) => [
        Text(message, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.body)),
        AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
      ];
}
```

- [x] **Step 4: 통과 확인**

Run: `cd frontend && flutter test test/referral/view/invite_friends_sheet_test.dart`
Expected: 9개 PASS.

---

### Task 3: 설정 "친구 초대" 줄 (공유 파일 — Q2 허락 뒤)

**Files:**
- Modify: `frontend/lib/matching/view/settings_screen.dart`(import 1줄 · `ListTile` 6줄, 계정 줄 바로 위)
- Test: `frontend/test/matching/view/settings_screen_test.dart`(import · override 2줄 · 테스트 2개)

**Interfaces:**
- Consumes: `showInviteFriendsSheet`(Task 2) · `referralRepositoryProvider` · `shareTextProvider` · `FakeReferralRepository`

- [x] **Step 1: 실패하는 테스트** — `pump` 의 overrides 에 `referralRepositoryProvider.overrideWithValue(FakeReferralRepository()),` 와 `shareTextProvider.overrideWithValue((_) async {}),` 를 더하고:

```dart
  testWidgets('"친구 초대" 줄은 계정 바로 위, user-plus 아이콘과 셰브런이다', (tester) async {
    await pump(tester);

    expect(tile('친구 초대'), findsOneWidget);
    expect(tester.getRect(tile('친구 초대')).bottom, tester.getRect(tile('계정')).top);
    expect(find.descendant(of: tile('친구 초대'), matching: find.byIcon(AppIcons.userPlus)), findsOneWidget);
    expect(find.descendant(of: tile('친구 초대'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"친구 초대" 를 누르면 16i 시트가 열린다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('친구 초대'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteFriendsSheet), findsOneWidget);
    expect(find.text('K7QMX2'), findsOneWidget);
  });
```

기존 "계정 줄은 매칭 활성화와 알림 사이" 테스트(93줄 `top > 매칭 활성화 bottom`)는 그대로 통과해야 한다.

- [x] **Step 2: 실패 확인**

Run: `cd frontend && flutter test test/matching/view/settings_screen_test.dart`
Expected: 새 2개 FAIL.

- [x] **Step 3: 구현** — 계정 `ListTile` 바로 위(A6 줄이 이미 있으면 그 아래):

```dart
              ListTile(
                leading: const Icon(AppIcons.userPlus, color: AppColors.muted),
                title: Text('친구 초대', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => showInviteFriendsSheet(context),
              ),
```

import: `import 'package:campus_mate/referral/view/invite_friends_sheet.dart';`

- [x] **Step 4: 통과 확인**

Run: `cd frontend && flutter test test/matching/view/settings_screen_test.dart test/common/ink_surface_sweep_test.dart`
Expected: 전부 PASS.

---

### Task 4: pen 값 반영 (값표 `값표_친구초대.md` 가 온 뒤)

**Files:**
- Modify: `frontend/lib/referral/view/invite_friends_sheet.dart` · `frontend/lib/matching/view/settings_screen.dart`(아이콘이 다르면 그 한 줄만)
- Modify: `frontend/test/referral/view/invite_friends_sheet_test.dart` · `frontend/test/matching/view/settings_screen_test.dart`
- Modify: 이 계획서 "화면 대조표"

- [x] **Step 1:** 값표를 읽어 화면 대조표의 "값표 대기" 칸을 노드 id · 값으로 채운다. 값표에 없는 값은 구현 전에 대장에게 노드 id 목록으로 묻는다(도우미는 pencil 을 직접 부르지 않는다).
- [x] **Step 2:** 값마다 실패하는 테스트를 먼저 쓴다 — 크기 · 색 · 간격은 `tester.getRect` · `tester.widget<Text>(...).style` 로 값표 숫자를 그대로 비교(19 A 테스트와 같은 방식). 복사가 아이콘이면 `find.text('복사')` 를 `find.byTooltip('복사')` 로 바꾼다.
- [x] **Step 3:** 실패 확인 → 가안을 pen 값으로 바꾼다 → 통과 확인.

Run: `cd frontend && flutter test test/referral test/matching/view/settings_screen_test.dart`
Expected: 전부 PASS.

---

### Task 5: 전체 확인 (superpowers:verification-before-completion)

- [x] `cd frontend && flutter analyze` → No issues found(Task 4 뒤 다시 확인).
- [x] `cd frontend && flutter test` → 1427 전부 PASS(Task 4 뒤).
- [x] 잉크 sweep(`test/common/ink_surface_sweep_test.dart`)은 통과한다. 다만 sweep 의 `_screens` 에 16 설정 · 16i 시트가 없어서 이 변경을 검증하지 못한다(리뷰 권고 — 대장에게 백로그로 올림). 새 InkWell 은 `_CopyButton` 자기 Material 하나이고, 설정 줄은 기존 투명 Material 루프 안이다(리뷰에서 코드로 확인).
- [x] campus-reviewer 검토(pen 값표 대조 포함) → PASS(2026-09-29, 막힘 0 · 권고 1 · 사소 3 — analyze 0 · test 1427 · RED 5건 재현).
- [ ] campus-git 이 의미 단위 커밋(데이터 · 시트 · 설정 줄 · 테스트 · 계획서) + draft PR.

## 문서 갱신 대상(조각 끝, 사용자에게 물은 뒤)

- `frontend/docs/DESIGN.md` §9 화면 16 줄 목록에 "친구 초대", 16i 시트 한 줄.
- 노션은 통합대장.

---

## 구현 편차 기록 (2026-09-29 문서 정리 — PR #163 설명에서 옮김)

- 편차 1~3 은 위 "pen 과 다른 점(편차)" 그대로 구현했다(16 줄은 이웃 `ListTile` · 설명 14, 로딩 · 못 읽음은 16e `_LoadError` 모양, 공유 창 실패 안내는 아이콘 없음).
- 공유 글 · `shareTextProvider` 는 Q1 (가)대로 `referral/model/invite_share.dart` 로 옮겼고 19 는 import 만 바꿨다.
- 20 자리표시는 원래 6자 `K7Q2MX` 에서 대장 결정 ② `예: K7M2QX` 로 통일.
- 16g 테스트가 시트 밑 줄 위치에 기대 있어(설정 목록이 한 줄 길어짐) 테스트 화면을 800×1400 으로 늘리는 3줄 수정을 허락받았다.
- 검토 RED 5건 재현(두 번 공유 · 타이머 · 공유 실패 안내 · 다시 시도 · 코드 없을 때 공유 숨김).
- 남긴 것(백로그 72): 잉크 전수 점검(`ink_surface_sweep_test.dart`)이 16 설정 · 16i · 조각 6 시트를 덮지 않는다.
