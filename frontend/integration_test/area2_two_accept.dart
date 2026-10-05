import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/trust_banner.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

/// 영역 2 두 기기(폰 A + 에뮬 B) 카드 수락 6개 — E-CARD-33 · 42 · 47 · 49 · 85 · 87. PC 쪽은 e2e/area2_two_accept.py 의 같은 번호 —
/// 열쇠는 `번호/A`(폰) · `번호/B`(에뮬)이고, 두 앱이 서로 기다리는 순서는 PC 가 `step` 에서 잇는다(e2e/twodev.py).
/// 화면 글자는 시나리오가 아니라 지금 화면 코드에서 옮겼다. 알림은 보지 않는다(마지막 묶음).
/// 이 파일은 `flutter analyze` 만 돌렸고 기기에서는 아직 안 돌려 봤다.
///
/// 목록은 앱이 처음 읽을 때의 서버 상태로 굳는다 — provider 는 로그아웃 때만 비워지고(core/auth/session_scope.dart), 대화 탭은 들어갈 때 새로 읽지 않으며,
/// 'match' 푸시는 수락함만 새로 읽는다(main.dart:154-158). 그래서 서버 쪽 일이 끝난 뒤의 모습을 보는 기기는 로그아웃한 채 멈춰 있다가
/// PC 가 go 에 실어 준 새 토큰으로 로그인한다([_loginAfter]).

const _accept = '수락하기'; // common/widgets/card_action_bar.dart:43
const _reject = '거절'; // :29 · acceptance_row.dart:65
const _acceptStart = '수락하고 대화 시작'; // acceptance_row.dart:73
const _waitingHeader = '수락 대기'; // matching/view/conversations_screen.dart:88
const _chatHeader = '대화 중'; // :118
const _emptyTitle = '아직 시작된 대화가 없어요'; // :187
const _matchMade = '매칭됐어요!'; // match_made_screen.dart:30
const _startChat = '대화 시작하기'; // :39
const _preAccept = '카카오톡 아이디를 먼저 공유해도 돼요'; // chat/view/chat_room_screen.dart:385
const _pausedSwitch = '매칭 활성화'; // matching/view/settings_screen.dart:53 — 켜짐 = 일시중지 아님
const _longWait = Duration(minutes: 8); // 상대 기기가 일을 끝내기를 기다리는 멈춤(support.step 은 2분까지만 기다린다)

int _count(Finder finder) => finder.evaluate().length;

/// 하단 내비의 탭([label] = 메인 · 오늘 · 커뮤니티 · 대화 · 나).
Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

Future<void> _signOut() => Supabase.instance.client.auth.signOut(scope: SignOutScope.local);

/// 앞 가설의 세션을 지우고 일감의 토큰으로 곧바로 로그인한 뒤 [body] 를 돈다.
Area1Case _login(Area1Case body) => (tester, job) async {
      await _signOut();
      await signIn(job['token_hash'] as String);
      return body(tester, job);
    };

/// 앞 가설의 세션을 지우고 로그아웃한 채 [name] 에서 멈춘다 — PC 가 상대 기기의 일을 확인한 뒤 go 에 새 토큰을 실어 주면 그때 로그인해 [body] 를 돈다.
Area1Case _loginAfter(String name, Area1Case body) => (tester, job) async {
      await _signOut();
      final go = await step(name, timeout: _longWait);
      await signIn(go['token_hash'] as String);
      return body(tester, job);
    };

/// [finder] 가 [within] 안에 사라지면 true.
Future<bool> _gone(WidgetTester tester, Finder finder, Duration within) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isNotEmpty) {
    if (watch.elapsed > within) return false;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

/// 홈 → 하단 내비 "대화" 탭(13).
Future<void> _openChat(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('대화'));
  await pumpUntil(tester, find.byType(ConversationsScreen), timeout: const Duration(seconds: 15));
}

/// "수락 대기" · "대화 중" 머리줄 오른쪽의 "N명" — 그 섹션이 없으면 null.
String? _sectionCount(WidgetTester tester, String title) {
  final row = find.ancestor(of: find.text(title), matching: find.byType(Row));
  if (row.evaluate().isEmpty) return null;
  final count = find.descendant(of: row.first, matching: find.textContaining('명'));
  return count.evaluate().isEmpty ? null : tester.widget<Text>(count.first).data;
}

/// 대화 탭이 비었다 — 수락 대기도 대화 중도 없고 빈 화면 글만 있다(13 의 빈 모습).
Future<void> _expectEmptyChat(WidgetTester tester, String who) async {
  await _openChat(tester);
  // 줄이 있으면 빈 화면 글은 영영 안 뜬다 — 셋 중 하나가 뜨면 그 모습으로 판정한다.
  await pumpUntil(
    tester,
    find.byWidgetPredicate((w) => w is AcceptanceRow || w is ChatListRow || (w is Text && w.data == _emptyTitle)),
    timeout: const Duration(seconds: 20),
  );
  must(_count(find.byType(AcceptanceRow)) == 0, '$who 대화 탭에 수락 대기 줄 ${_count(find.byType(AcceptanceRow))}개(기대 0)');
  must(_count(find.byType(ChatListRow)) == 0, '$who 대화 탭에 대화 중 줄 ${_count(find.byType(ChatListRow))}개(기대 0)');
  must(_count(find.text(_emptyTitle)) == 1, '$who 대화 탭에 "$_emptyTitle" ${_count(find.text(_emptyTitle))}개(기대 1)');
  must(_count(find.text(_matchMade)) == 0, '$who 에게 "$_matchMade" 화면이 뜸');
}

/// 수락 대기에 [nickname] 한 줄만 있다("수락 대기" 옆 "1명") — 대화 탭을 연 직후.
Future<void> _expectOneAcceptance(WidgetTester tester, String nickname, String who) async {
  await _openChat(tester);
  await pumpUntil(tester, find.byType(AcceptanceRow), timeout: const Duration(seconds: 20));
  await wait(tester, const Duration(seconds: 1)); // 둘째 줄이 늦게 붙는 일이 없는지
  must(_count(find.byType(AcceptanceRow)) == 1, '$who 수락 대기 줄 ${_count(find.byType(AcceptanceRow))}개(기대 1)');
  must(_sectionCount(tester, _waitingHeader) == '1명', '$who "$_waitingHeader" 옆 ${_sectionCount(tester, _waitingHeader)}(기대 1명)');
  final named = find.descendant(of: find.byType(AcceptanceRow), matching: find.textContaining(nickname));
  must(_count(named) == 1, '$who 수락 대기 줄에 "$nickname" ${_count(named)}개(기대 1)');
}

/// 대화 중에 [nickname] 한 줄만 있고("대화 중" 옆 "1명") 수락 대기는 없다.
void _expectOneChat(WidgetTester tester, String nickname, String who) {
  must(_count(find.byType(ChatListRow)) == 1, '$who 대화 중 줄 ${_count(find.byType(ChatListRow))}개(기대 1)');
  final named = find.descendant(of: find.byType(ChatListRow), matching: find.text(nickname));
  must(_count(named) == 1, '$who 대화 중 줄에 "$nickname" ${_count(named)}개(기대 1)');
  must(_sectionCount(tester, _chatHeader) == '1명', '$who "$_chatHeader" 옆 ${_sectionCount(tester, _chatHeader)}(기대 1명)');
  must(_count(find.text(_waitingHeader)) == 0, '$who 에 "$_waitingHeader" 가 남음');
  must(_count(find.byType(AcceptanceRow)) == 0, '$who 수락 대기 줄 ${_count(find.byType(AcceptanceRow))}개(기대 0)');
}

/// 방이 열렸고(앱바에 상대 닉네임) 미리 수락 배너가 하나다.
Future<void> _expectRoom(WidgetTester tester, String nickname, String who) async {
  await pumpUntil(tester, find.byType(ChatRoomScreen), timeout: const Duration(seconds: 15));
  await pumpUntil(tester, find.descendant(of: find.byType(AppBar), matching: find.text(nickname)),
      timeout: const Duration(seconds: 20));
  await pumpUntil(tester, find.byType(TrustBanner), timeout: const Duration(seconds: 20));
  final titles = tester.widgetList<TrustBanner>(find.byType(TrustBanner)).map((banner) => banner.title).toList();
  must(titles.length == 1 && titles.single == _preAccept, '$who 방의 배너 $titles(기대 ["$_preAccept"] 하나)');
}

/// 오늘 탭 → 카드 한 장 → 10b(수락하기 · 거절 버튼이 보일 때까지).
Future<void> _openCard(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('오늘'));
  await pumpUntil(tester, find.byType(DailyCardSummary), timeout: const Duration(seconds: 30));
  must(_count(find.byType(DailyCardSummary)) == 1, '카드 ${_count(find.byType(DailyCardSummary))}장(기대 1)');
  await tap(tester, find.byType(DailyCardSummary));
  await pumpUntil(tester, find.text(_accept), timeout: const Duration(seconds: 15));
}

/// 결정이 끝나 10b 가 닫히고(수락하기 글이 사라짐) 오늘 탭에 그 카드가 남지 않는다. 10b 가 위에 있는 동안은 아래 목록이 안 잡히므로 닫힌 뒤에 본다.
Future<void> _decidedAndGone(WidgetTester tester) async {
  must(await _gone(tester, find.text(_accept), const Duration(seconds: 20)), '결정 뒤에도 10b 가 안 닫힘');
  must(await _gone(tester, find.byType(DailyCardSummary), const Duration(seconds: 15)), '돌아왔는데 오늘 탭에 카드가 남음');
}

// ── 33 일시중지 ──────────────────────────────────────────────────────────────────────────────────────

Finder get _switch => find.widgetWithText(SwitchListTile, _pausedSwitch);

bool _on(WidgetTester tester) => tester.widget<SwitchListTile>(_switch).value;

/// 홈 → 나 탭 → 톱니(설정 16).
Future<void> _openSettings(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byTooltip('설정'), timeout: const Duration(seconds: 10));
  await tap(tester, find.byTooltip('설정'));
  await arrive(tester, 'settings', timeout: const Duration(seconds: 10));
  await pumpUntil(tester, _switch, timeout: const Duration(seconds: 10));
}

/// 설정을 서버에서 다 읽을 때까지 — 늦게 온 처음 값이 방금 누른 스위치를 덮지 않게(notification_settings_view_model.dart:23-37).
Future<void> _settingsLoaded(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(_switch));
  final watch = Stopwatch()..start();
  while (container.read(notificationSettingsViewModelProvider).isLoading) {
    must(watch.elapsed < const Duration(seconds: 20), '20초 안에 설정을 못 읽음');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// "매칭 활성화" 스위치가 [expected] 가 될 때까지 — 아니면 [problem].
Future<void> _waitSwitch(WidgetTester tester, bool expected, String problem) async {
  final watch = Stopwatch()..start();
  while (_switch.evaluate().isEmpty || _on(tester) != expected) {
    must(watch.elapsed < const Duration(seconds: 15), problem);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

final Map<String, Area1Case> area2TwoAcceptCases = {
  // A 는 후보를 API 로 조회당하는 쪽이라 화면에서 할 일이 없다 — 로그인해 홈까지 온다.
  'E-CARD-33/A': _login((tester, job) async {
    await arrive(tester, 'home');
    return null;
  }),
  // B: 끈다 → PC 가 서버 저장 · A 의 후보 · 카드 대상을 본다 → 로그아웃 후 새 토큰으로 다시 로그인(앱을 다시 켠 것과 같게 상태를 새로 읽는다)
  // → 16 을 열면 서버 값(꺼짐) 그대로 → 다시 켠다 → PC 가 돌아온 것을 본다.
  'E-CARD-33/B': _login((tester, job) async {
    await _openSettings(tester);
    await _settingsLoaded(tester);
    must(_on(tester), '끄기 전에 "$_pausedSwitch" 스위치가 꺼져 있음');
    await tap(tester, _switch);
    await _waitSwitch(tester, false, '눌렀는데 "$_pausedSwitch" 스위치가 안 꺼짐');
    final go = await step('paused');
    await _signOut();
    await signIn(go['token_hash'] as String);
    await _openSettings(tester);
    await _waitSwitch(tester, false, '다시 로그인해 16 을 열었는데 스위치가 서버 값(꺼짐)이 아니라 켜짐으로 그려짐');
    await tap(tester, _switch);
    await _waitSwitch(tester, true, '다시 켜려고 눌렀는데 스위치가 안 켜짐');
    await step('resumed');
    return null;
  }),

  // 42: A 가 거절 → 10b 가 닫히고 카드가 사라진다 → PC 가 card_decisions · B 수락함을 본다 → B 가 그 뒤에 로그인해 대화 탭이 비어 있다.
  'E-CARD-42/A': _login((tester, job) async {
    await _openCard(tester);
    await tap(tester, find.text(_reject));
    await _decidedAndGone(tester);
    await step('rejected');
    return null;
  }),
  'E-CARD-42/B': _loginAfter('wait', (tester, job) async {
    await _expectEmptyChat(tester, 'B');
    return null;
  }),

  // 47: B 가 수락함에서 "수락하고 대화 시작" → 12 → "대화 시작하기" → 방(배너 1) → 뒤로 → 대화 중 1줄. A 는 방이 생긴 뒤 로그인해 대화 중 1줄 → 방(배너 1).
  'E-CARD-47/A': _loginAfter('open', (tester, job) async {
    final nickname = job['nickname'] as String;
    await _openChat(tester);
    await pumpUntil(tester, find.byType(ChatListRow), timeout: const Duration(seconds: 20));
    _expectOneChat(tester, nickname, 'A');
    await tap(tester, find.byType(ChatListRow));
    await _expectRoom(tester, nickname, 'A');
    return null;
  }),
  'E-CARD-47/B': _login((tester, job) async {
    final nickname = job['nickname'] as String;
    await _expectOneAcceptance(tester, nickname, 'B');
    await tap(tester, button(_acceptStart));
    await pumpUntil(tester, find.text(_matchMade), timeout: const Duration(seconds: 20));
    await step('matched'); // PC 가 matches · match_participants 를 본다
    await tap(tester, button(_startChat));
    await _expectRoom(tester, nickname, 'B');
    await tap(tester, find.byType(BackButton)); // 푸시로 들어온 방처럼 스택이 한 장이라 목록으로 내려간다(chat_room_screen.dart:92-100)
    await pumpUntil(tester, find.byType(ChatListRow), timeout: const Duration(seconds: 20));
    _expectOneChat(tester, nickname, 'B');
    return null;
  }),

  // 49: B 가 수락함에서 "거절" → 줄이 사라지고 매칭 화면 없음 → PC 가 acceptance_responses · matches 를 본다 → A 는 그 뒤에 로그인해 대화 탭이 비어 있다.
  'E-CARD-49/A': _loginAfter('wait', (tester, job) async {
    await _expectEmptyChat(tester, 'A');
    return null;
  }),
  'E-CARD-49/B': _login((tester, job) async {
    await _expectOneAcceptance(tester, job['nickname'] as String, 'B');
    await tap(tester, button(_reject));
    must(await _gone(tester, find.byType(AcceptanceRow), const Duration(seconds: 20)), '거절했는데 수락 대기 줄이 안 사라짐');
    await wait(tester, const Duration(seconds: 2)); // 뒤늦게 매칭 화면이 뜨는 일이 없는지
    must(_count(find.text(_matchMade)) == 0, '거절했는데 "$_matchMade" 화면이 뜸');
    must(_count(find.text(_waitingHeader)) == 0, '거절한 뒤에도 "$_waitingHeader" 가 남음');
    await step('rejected');
    return null;
  }),

  // 85: A 가 10b 에서 "수락하기" 를 0.1초 간격으로 두 번 누른다 → 화면이 정상으로 돌아온다 → PC 가 card_decisions 한 행을 본다 → B 가 그 뒤에 로그인해 수락 대기 한 줄.
  'E-CARD-85/A': _login((tester, job) async {
    await _openCard(tester);
    final accept = find.text(_accept);
    await tester.ensureVisible(accept.last);
    await tester.pump();
    await tester.tap(accept.last); // tap() 도우미는 누른 뒤 0.3초 쉰다 — 연타라서 쓰지 않는다
    await wait(tester, const Duration(milliseconds: 100)); // 실제 시간 0.1초(pump 의 시간이 가짜여도 벽시계로 기다린다)
    if (accept.evaluate().isEmpty) {
      throw E2eBlocked('두 번째를 누르기 전에 10b 가 이미 닫힘(응답이 0.1초보다 빠름) — 연타 방어를 확인하지 못함');
    }
    await tester.tap(accept.last, warnIfMissed: false); // 처리 중이라 꺼진 버튼 — 눌려도 아무 일이 없어야 한다
    await _decidedAndGone(tester);
    await step('accepted');
    return null;
  }),
  'E-CARD-85/B': _loginAfter('wait', (tester, job) async {
    await _expectOneAcceptance(tester, job['nickname'] as String, 'B');
    return null;
  }),

  // 87: A 가 수락함에서 B 를 수락 → 12 → PC 가 matches 한 행 · B 수락함에서 A 가 빠졌는지 본다 → B 가 그 뒤에 로그인해 수락함을 연다(대화 중 1줄만)
  // → PC 가 남은 카드(A→B)에 B 로 API 응답(같은 방) → B 가 목록을 서버에서 다시 읽어도 같은 방 한 줄.
  'E-CARD-87/A': _login((tester, job) async {
    final nickname = job['nickname'] as String;
    await _expectOneAcceptance(tester, nickname, 'A');
    await tap(tester, button(_acceptStart));
    await pumpUntil(tester, find.text(_matchMade), timeout: const Duration(seconds: 20));
    must(_count(find.textContaining('$nickname 님도 수락했어요')) == 1, '12 의 "$nickname 님도 수락했어요" ${_count(find.textContaining('$nickname 님도 수락했어요'))}개(기대 1)');
    await step('matched');
    await tap(tester, button(_startChat));
    await pumpUntil(tester, find.byType(ChatRoomScreen), timeout: const Duration(seconds: 15));
    return null;
  }),
  'E-CARD-87/B': _loginAfter('wait', (tester, job) async {
    final nickname = job['nickname'] as String;
    await _openChat(tester);
    await pumpUntil(tester, find.byType(ChatListRow), timeout: const Duration(seconds: 20));
    must(_count(find.byType(AcceptanceRow)) == 0, '이미 매칭된 사람이 B 수락함에 ${_count(find.byType(AcceptanceRow))}줄 남음');
    _expectOneChat(tester, nickname, 'B');
    await step('opened'); // PC 가 남은 카드에 B 로 API 응답을 보낸다
    final container = ProviderScope.containerOf(tester.element(find.byType(ConversationsScreen)));
    await container.read(acceptancesViewModelProvider.notifier).refresh();
    await container.read(conversationsViewModelProvider.notifier).refresh();
    await wait(tester, const Duration(seconds: 1));
    _expectOneChat(tester, nickname, 'B');
    return null;
  }),
};
