part of 'area4.dart';

// 영역 2·4 미등록 가설 10개 — E-HEART 49 · 51, E-SET 04 · 12 · 26 · 43 · 52 · 53 · 67(E-HEART-46 은 앱 없이 PC 만). PC 쪽은 e2e/area4_extra.py 의 같은 번호.
// 화면 글자는 시나리오가 아니라 지금 화면 코드에서 옮겼다(설정 · FAQ · 대화 탭). 판정 값(서버에 남은 것)은 PC 가 본다.

/// 하트를 현금으로 바꾸거나 남에게 주는 길을 암시하는 글(E-HEART-49).
const _heartMoneyWords = ['환급', '선물', '송금', '현금', '출금'];

/// 잠긴 카드 · 하트 스토어 · 구매를 암시하는 글(E-HEART-51). 하트 스토어(18, `/hearts/store`)는 생겼지만 오늘 · 나 · 설정 화면에는 스토어로 가는 글이 아직 없다 — 설정의 "하트 충전" 블록이 붙으면 이 목록을 다시 정한다.
const _heartStoreWords = ['한 명 더', '잠긴 카드', '잠금 카드', '스토어', '하트 충전', '카드 구매'];

const _faqJunk = 'ㅋㅋㅋzzqq';
const _noChatTitle = '아직 시작된 대화가 없어요'; // matching/view/conversations_screen.dart
const _set67Wait = Duration(minutes: 12); // 상대 기기가 일을 끝내기를(PC 쪽 PEER 420초 + HOLD 300초)

void _seeNone(List<String> words, String where) {
  for (final word in words) {
    must(find.textContaining(word, findRichText: true).evaluate().isEmpty, '$where 에 "$word" 글자가 있음');
  }
}

/// 홈 → ([today] 면 오늘 탭) → 나 탭 → 설정 16 을 위에서 아래로 훑으며 [words] 가 어디에도 없다.
Future<void> _noneOnHeartScreens(WidgetTester tester, List<String> words, {bool today = false}) async {
  await arrive(tester, 'home');
  if (today) {
    await tap(tester, _tab('오늘'));
    await wait(tester, const Duration(seconds: 3)); // 카드 · 안내가 그려지기를
    _seeNone(words, '오늘 탭');
  }
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byIcon(AppIcons.settings));
  await wait(tester, const Duration(seconds: 2));
  _seeNone(words, '나 탭');
  await tap(tester, find.byIcon(AppIcons.settings));
  await arrive(tester, 'settings');
  for (final row in _settingsRows) {
    await _reveal(tester, find.text(row));
    _seeNone(words, '설정($row 까지)');
  }
}

/// 하단 내비가 다시 보일 때까지 뒤로 간다(설정 · 차단 목록 같은 위에 얹힌 화면을 걷어 낸다).
Future<void> _backToTabs(WidgetTester tester) async {
  for (var i = 0; i < 5 && find.byType(AppBottomNav).evaluate().isEmpty; i++) {
    await tap(tester, find.byType(BackButton));
    await wait(tester, const Duration(milliseconds: 600));
  }
  must(find.byType(AppBottomNav).evaluate().isNotEmpty, '뒤로 갔는데 하단 내비가 안 보임');
}

/// 하단 내비 "대화" 탭을 열고 목록이 읽힌 모습(수락 대기 · 대화 중 · 빈 화면 중 하나)이 될 때까지.
Future<void> _openChatTab(WidgetTester tester) async {
  await tap(tester, _tab('대화'));
  await pumpUntil(tester, find.byType(ConversationsScreen), timeout: const Duration(seconds: 15));
  await pumpUntil(
    tester,
    find.byWidgetPredicate((w) => w is AcceptanceRow || w is ChatListRow || (w is Text && w.data == _noChatTitle)),
    timeout: const Duration(seconds: 20),
  );
}

Finder _chatRowOf(String nickname) => find.descendant(of: find.byType(ChatListRow), matching: find.text(nickname));

Future<void> _faqNoResult(WidgetTester tester) async {
  await _openFaq(tester);
  await pumpUntil(tester, find.byKey(const ValueKey('faq-list')));
  await _search(tester, _faqJunk);
  await pumpUntil(tester, find.text('찾는 질문이 없어요'), timeout: const Duration(seconds: 5));
}

/// 이 기기(B)의 세션이 서버에서도 살아 있다 — 세션이 있고, 서버가 그 세션의 사용자를 알려 주고(getUser 는 서버에 묻는다),
/// 새 열쇠를 받을 수 있다(A 가 모든 기기를 로그아웃시켰다면 서버가 세션을 지워 여기서 막힌다).
Future<void> _sessionAlive(String when) async {
  final auth = Supabase.instance.client.auth;
  must(auth.currentSession != null, '$when: 이 기기의 세션이 사라짐');
  final user = await auth.getUser();
  must(user.user != null, '$when: 서버가 이 기기의 세션을 모름');
  final refreshed = await auth.refreshSession();
  must(refreshed.session != null, '$when: 서버가 새 열쇠를 안 줌(세션이 끊김)');
}

/// E-SET-67 의 B 쪽 확인 — 로그인 화면으로 쫓겨나지 않았고, 서버가 이 기기의 세션을 그대로 알고, 대화 탭을 새로 열어도 상대 방이 그대로다.
Future<void> _chatStillWorks(WidgetTester tester, String nickname, String when) async {
  must(screen('login').evaluate().isEmpty, '$when: 로그인 화면으로 쫓겨남');
  await _sessionAlive(when);
  await tap(tester, _tab('나'));
  await wait(tester, const Duration(seconds: 1));
  await _openChatTab(tester);
  await pumpUntil(tester, _chatRowOf(nickname), timeout: const Duration(seconds: 20));
  must(screen('login').evaluate().isEmpty, '$when: 로그인 화면으로 쫓겨남');
}

final Map<String, Area1Case> _extraCases = {
  // 49: 나 탭 · 설정에 환급 · 선물 · 송금으로 이어지는 글이 없다. 서버 경로는 PC 가 /openapi.json 으로 본다.
  'E-HEART-49': _session((tester, job) async {
    await _noneOnHeartScreens(tester, _heartMoneyWords);
    return null;
  }),
  // 51: 오늘 · 나 · 설정에 잠긴 카드(한 명 더) · 하트 스토어 글이 없다. locked_card_available · 서버 경로는 PC 가 본다.
  'E-HEART-51': _session((tester, job) async {
    await _noneOnHeartScreens(tester, _heartStoreWords, today: true);
    return null;
  }),
  // 04: 설정 16 의 "매칭 활성화" 를 끈다(켜짐 = 일시중지 아님). 저장은 PC 가 matching_paused 로 보고 배치 뒤 카드 0 을 본다.
  'E-SET-04': _session((tester, job) async {
    await _openSettings(tester);
    await _expectValue(tester, '매칭 활성화', true);
    await tap(tester, _tile('매칭 활성화'));
    await _expectValue(tester, '매칭 활성화', false);
    await wait(tester, const Duration(seconds: 3)); // 서버 저장이 끝나기를
    return null;
  }),
  // 12: 폰 한 대로 — 처음엔 "새 메시지" 켜짐 → (PC 가 다른 기기처럼 서버 값을 끔) → 16d 를 닫았다 다시 열어도 켜짐(상태가 로그아웃 때까지 남는다) →
  // 앱을 다시 켜면(fresh=false 로 한 번 더) 꺼짐.
  'E-SET-12': _session((tester, job) async {
    await _open16d(tester);
    if (job['phase'] == 'relaunched') {
      await _expectValue(tester, '새 메시지', false);
      return null;
    }
    await _expectValue(tester, '새 메시지', true);
    await step('other-device');
    await tap(tester, find.byType(BackButton));
    await arrive(tester, 'settings');
    await _reveal(tester, find.text('알림'));
    await tap(tester, find.text('알림'));
    await pumpUntil(tester, _screenTitle('알림'));
    await wait(tester, const Duration(seconds: 2)); // 다시 읽는다면 이 사이에 반영됐을 것이다
    await _expectValue(tester, '새 메시지', true, timeout: const Duration(seconds: 3));
    return null;
  }),
  // 26: 차단 목록에서 상대 줄의 "해제" → 확인 → 목록이 빈다 → 대화 탭에 그 사람 방이 없다(PC 가 blocks · left_at 을 본다).
  'E-SET-26': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _openBlockList(tester);
    await pumpUntil(tester, find.byKey(blockedRowKey));
    await _seeAll(tester, [nickname]);
    await tap(tester, find.widgetWithText(TextButton, '해제').first);
    await pumpUntil(tester, find.text('차단을 해제할까요?'));
    await _seeAll(tester, [_unblockDescription]); // 시나리오 시트 문구 — E-SET-27 과 같은 글
    await tap(tester, find.widgetWithText(SafetySheetButton, '해제'));
    await pumpUntil(tester, find.text('아직 차단한 상대가 없어요'), timeout: const Duration(seconds: 15));
    await _backToTabs(tester);
    await _openChatTab(tester);
    await wait(tester, const Duration(seconds: 2)); // 늦게 붙는 줄이 없는지
    must(_chatRowOf(nickname).evaluate().isEmpty, '차단을 풀었더니 대화 탭에 "$nickname" 방이 돌아옴');
    return null;
  }),
  // 43: 앱은 연락처에서 그 사람을 골라 차단하는 데까지(E-SAFE-38 과 같다). 배치 뒤 서로 카드가 없는지는 PC 가 본다.
  'E-SET-43': _session((tester, job) async {
    await _inBlockList(tester);
    await _blockAndWait(tester, job);
    return null;
  }),
  // 52: FAQ 에서 없는 말을 검색해 빈 화면의 메일 주소를 누른다. 메일 앱이 맨 위로 뜨는지는 PC 가 본다(밖으로 나가면 앱 프레임이 멎어 바로 끝낸다).
  'E-SET-52': _session((tester, job) async {
    await _faqNoResult(tester);
    await tester.ensureVisible(find.text(_faqMail));
    await tester.pump();
    await tester.tap(find.text(_faqMail));
    return null;
  }),
  // 53: 메일 앱이 없는 기기(PC 가 끔) — 같은 줄을 누르면 앱 안에 오류 안내가 뜨고 3초쯤 뒤 사라진다.
  'E-SET-53': _session((tester, job) async {
    await _faqNoResult(tester);
    final notice = find.text(const UnknownFailure().toDisplayMessage());
    must(notice.evaluate().isEmpty, '누르기 전부터 안내가 떠 있음');
    await tap(tester, find.text(_faqMail));
    await pumpUntil(tester, notice, timeout: const Duration(seconds: 3));
    await wait(tester, const Duration(seconds: 2));
    must(notice.evaluate().isNotEmpty, '안내가 3초가 되기 전에 사라짐');
    final gone = Stopwatch()..start();
    while (notice.evaluate().isNotEmpty) {
      must(gone.elapsed < const Duration(seconds: 3), '안내가 5초가 지나도 안 사라짐');
      await tester.pump(const Duration(milliseconds: 100));
    }
    return null;
  }),
  // 67 A폰: 로그인 → 대화 탭에 상대 방 → (B 가 들어올 때까지) → 설정에서 로그아웃 → 로그인 화면.
  'E-SET-67/A': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await arrive(tester, 'home');
    await _openChatTab(tester);
    await pumpUntil(tester, _chatRowOf(nickname), timeout: const Duration(seconds: 20));
    await step('a-in', timeout: _set67Wait); // PC 가 B 가 들어와 방을 볼 때까지 기다렸다 돌려준다
    await tap(tester, _tab('나'));
    await pumpUntil(tester, find.byIcon(AppIcons.settings));
    await tap(tester, find.byIcon(AppIcons.settings));
    await arrive(tester, 'settings');
    await _confirmLogout(tester);
    await arrive(tester, 'login', timeout: const Duration(seconds: 15));
    await step('a-out');
    return null;
  }),
  // 67 B에뮬: 로그아웃한 채 기다렸다가(A 가 로그인한 뒤 PC 가 새 토큰을 준다) 로그인 → 대화 탭에 상대 방 →
  // A 가 로그아웃한 직후에도, 5분 뒤에도 쫓겨나지 않고 대화 탭이 그대로다.
  'E-SET-67/B': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    final go = await step('wait', timeout: _set67Wait);
    await signIn(go['token_hash'] as String);
    await arrive(tester, 'home', timeout: const Duration(seconds: 40));
    await _openChatTab(tester);
    await pumpUntil(tester, _chatRowOf(nickname), timeout: const Duration(seconds: 20));
    await step('b-in', timeout: _set67Wait); // A 가 로그아웃할 때까지
    await _chatStillWorks(tester, nickname, 'A 로그아웃 직후');
    await step('b-now', timeout: _set67Wait); // PC 가 ${job['hold']}초를 보낸다
    await _chatStillWorks(tester, nickname, '${job['hold']}초 뒤');
    return null;
  }),
};
