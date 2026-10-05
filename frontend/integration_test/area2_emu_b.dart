import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/community/view/community_feed_screen.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

/// 영역 2 B에뮬 단독 가설 11(수락함 3 · 투표 5 · 추천 코드 3). PC 쪽은 e2e/area2_emu_b.py 의 같은 번호 — 계정을 만들어 1회용 토큰을 넘기고
/// 서버 · DB 값을 본다. 화면 글자는 시나리오가 아니라 지금 화면 코드에서 옮겼다(줄 번호는 옮긴 때 기준).
/// 비공개 도우미(_session · _tab 등)는 area2_b.dart · area2_c.dart 의 것을 복사했다. lib/ 는 바꾸지 않았다.
/// 이 파일은 `flutter analyze` 만 돌렸고 기기에서는 아직 안 돌려 봤다 — 특히 당겨서 새로 고침(E-POLL-02)의 제스처 크기.

// 13 대화 — frontend/lib/matching/view/conversations_screen.dart · acceptance_row.dart · match_made_screen.dart
const _acceptWaiting = '수락 대기'; // conversations_screen.dart:88
const _reject = '거절'; // acceptance_row.dart:65
const _accept = '수락하고 대화 시작'; // acceptance_row.dart:73
const _noChats = '아직 시작된 대화가 없어요'; // conversations_screen.dart _EmptyState
const _acceptanceNotFound = '수락을 찾을 수 없어요'; // backend core/errors.py ACCEPTANCE_NOT_FOUND — 오류 줄로 그대로 뜬다
const _matchMade = '매칭됐어요!'; // match_made_screen.dart:32

// 15d 피드 — frontend/lib/community/view/poll_card.dart · community_feed_view_model.dart
const _rewardToast = '하트 10개를 받았어요'; // community_feed_view_model.dart pollRewardMessage

// 18a — frontend/lib/billing/view/heart_task_row.dart
const _heartTasksRow = '무료로 하트 모으기'; // settings_screen.dart
const _voteTitle = '커뮤니티 투표'; // heart_task_row.dart _title
const _join = '참여'; // heart_task_row.dart _trailing(open · 투표 줄)

/// 앞 가설의 세션을 지우고([fresh] 가 false 면 그대로 둔다) 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area2_b.dart 와 같은 모양).
Area1Case _session(Area1Case body) => (tester, job) async {
      if (job['fresh'] != false) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

/// 하단 내비의 탭([label] = 메인 · 오늘 · 커뮤니티 · 대화 · 나).
Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

int _count(Finder finder) => finder.evaluate().length;

/// 오래 걸리는 PC 일(HOME · 수락 · 알림 도착 · 알림 누르기)을 기다리는 멈춤 — support.step 은 2분까지만 기다린다.
Future<void> _longStep(String name, Duration within) async {
  await say({'step': name});
  await hear(timeout: within);
}

// ── 수락함 3 ────────────────────────────────────────────────────────────────────────────────────────

/// 수락 대기 줄 중 [nickname] 의 것.
Finder _acceptanceOf(String nickname) =>
    find.byWidgetPredicate((w) => w is AcceptanceRow && w.acceptance.profile.nickname == nickname);

/// 홈 → 대화 탭 → 13 이 뜰 때까지.
Future<void> _openConversations(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('대화'));
  await pumpUntil(tester, find.byType(ConversationsScreen), timeout: const Duration(seconds: 10));
}

/// 수락 대기 섹션이 "수락 대기 1명" 에 [nickname] 줄 하나와 두 버튼(거절 · 수락하고 대화 시작)뿐인지.
Future<void> _oneWaiting(WidgetTester tester, String nickname) async {
  final row = _acceptanceOf(nickname);
  final shown = await appears(tester, row, const Duration(seconds: 15));
  // 알림을 눌러 연 13 이 켜진 뒤 수락함을 다시 읽지 않으면 빈 화면이 남는다 — acceptances_view_model 은 처음 한 번 ·
  // 켜져 있는 동안 온 푸시 · 당겨서 새로 고침 · 응답 뒤에만 읽는다(main.dart _refreshForRoute 는 앱이 앞에 있을 때만 받는다).
  must(shown != null, '대화 탭에 "$nickname" 수락 대기 줄이 15초 안에 안 나옴${_count(find.text(_noChats)) > 0 ? ' — 빈 화면 "$_noChats" 가 보임(수락함을 새로 읽지 않았나)' : ''}');
  must(_count(find.byType(AcceptanceRow)) == 1, '수락 대기 줄 ${_count(find.byType(AcceptanceRow))}개(기대 1)');
  must(_count(find.text(_acceptWaiting)) == 1, '"$_acceptWaiting" 제목 ${_count(find.text(_acceptWaiting))}개(기대 1)');
  must(_count(find.text('1명')) == 1, '"1명" ${_count(find.text('1명'))}개(기대 1)');
  for (final label in [_reject, _accept]) {
    final seen = _count(find.descendant(of: row, matching: button(label)));
    must(seen == 1, '"$nickname" 줄에 "$label" 버튼 $seen개(기대 1)');
  }
}

Future<void> _tapAccept(WidgetTester tester, String nickname) =>
    tap(tester, find.descendant(of: _acceptanceOf(nickname), matching: button(_accept)));

final Map<String, Area1Case> _acceptanceCases = {
  // 홈에서 멈춰 PC 가 HOME → B 의 기기 토큰 확인 → A 가 카드 수락 → 알림 → 알림 누르기를 한 뒤: 앱이 앞으로 와 13 의 수락 대기 1명(A).
  'E-CARD-41': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await arrive(tester, 'home');
    await wait(tester, const Duration(seconds: 2));
    await _longStep('tap', const Duration(minutes: 6));
    final opened = await appears(tester, find.byType(ConversationsScreen), const Duration(seconds: 30));
    must(opened != null, '알림을 눌렀는데 30초 안에 대화 탭이 안 열림${screen('home').evaluate().isNotEmpty ? ' — 아직 홈이 보임' : ''}');
    await _oneWaiting(tester, nickname);
    return null;
  }),
  // PC 가 A 의 수락을 앱 켜기 전에 넣어 두었다 — 대화 탭의 수락함에서 "수락하고 대화 시작" → 12 "매칭됐어요!" · "{A닉} 님도 수락했어요.".
  'E-CARD-45': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _openConversations(tester);
    await _oneWaiting(tester, nickname);
    await _tapAccept(tester, nickname);
    await pumpUntil(tester, find.text(_matchMade), timeout: const Duration(seconds: 20));
    await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
    must(_count(find.text(_matchMade)) == 1, '"$_matchMade" ${_count(find.text(_matchMade))}개(기대 1)');
    final sentence = find.textContaining('$nickname 님도 수락했어요.');
    must(_count(sentence) == 1, '"$nickname 님도 수락했어요." ${_count(sentence)}개(기대 1)');
    return null;
  }),
  // 수락 대기를 띄운 뒤 PC 가 A 를 정지 → "수락하고 대화 시작" → 오류 줄 "수락을 찾을 수 없어요", 줄이 사라지고 12 는 안 뜬다.
  'E-CARD-86': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _openConversations(tester);
    await _oneWaiting(tester, nickname);
    await step('suspended');
    await _tapAccept(tester, nickname);
    await pumpUntil(tester, find.text(_acceptanceNotFound), timeout: const Duration(seconds: 20));
    await wait(tester, const Duration(seconds: 1)); // 응답 뒤 목록을 다시 읽는 것까지
    must(_count(find.text(_acceptanceNotFound)) == 1, '"$_acceptanceNotFound" ${_count(find.text(_acceptanceNotFound))}개(기대 1)');
    must(_count(find.byType(AcceptanceRow)) == 0, '정지한 사람의 수락 줄이 목록에 남음');
    must(_count(find.text(_matchMade)) == 0, '정지한 사람의 수락으로 12 "$_matchMade" 가 뜸');
    return null;
  }),
};

// ── 투표 5 ──────────────────────────────────────────────────────────────────────────────────────────

Finder get _feed => find.byType(CommunityFeedScreen);

CommunityFeedUiState _feedState(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(_feed)).read(communityFeedViewModelProvider);

/// 메인 → 커뮤니티 탭 → 첫 쪽을 받을 때까지.
Future<void> _openCommunity(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('커뮤니티'));
  await pumpUntil(tester, _feed, timeout: const Duration(seconds: 10));
  final watch = Stopwatch()..start();
  while (_feedState(tester).isLoading) {
    must(watch.elapsed < const Duration(seconds: 30), '30초 안에 커뮤니티 피드를 못 받음');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Finder _cardOf(String question) => find.widgetWithText(PollCard, question);

/// [question] 카드의 O(찬성) 버튼.
Finder _agree(String question) => find.descendant(of: _cardOf(question), matching: find.widgetWithIcon(FilledButton, AppIcons.circle));

/// [question] 카드가 피드에 뜰 때까지 기다렸다 O 를 누르고 도넛이 뜰 때까지.
Future<void> _voteAgree(WidgetTester tester, String question) async {
  await pumpUntil(tester, _cardOf(question), timeout: const Duration(seconds: 15));
  await tap(tester, _agree(question));
  await pumpUntil(tester, find.descendant(of: _cardOf(question), matching: find.byType(PollDonut)), timeout: const Duration(seconds: 20));
}

/// 카드 안 글자들 — 기대와 다를 때 메모에 실제 글을 남긴다.
String _cardTexts(WidgetTester tester, String question) => tester
    .widgetList<Text>(find.descendant(of: _cardOf(question), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .join(' | ');

final Map<String, Area1Case> _pollCases = {
  // 바탕 글이 있는 피드를 연 채 PC 가 다른 계정으로 새 글을 올린다 → 몇 초 지나도 안 보임(실시간 아님) → 당겨서 새로 고침 뒤 1개.
  'E-POLL-02': _session((tester, job) async {
    final anchor = job['anchor'] as String;
    final question = job['question'] as String;
    await _openCommunity(tester);
    await pumpUntil(tester, _cardOf(anchor), timeout: const Duration(seconds: 15));
    must(_count(_cardOf(question)) == 0, '올리기 전인데 "$question" 카드가 이미 있음');
    await step('posted');
    await wait(tester, const Duration(seconds: 5));
    must(_count(_cardOf(question)) == 0, '새로 고침 전에 다른 계정이 올린 글이 피드에 나타남(실시간 구독은 안 쓰기로 했다)');
    final list = find.descendant(of: _feed, matching: find.byType(ListView)).first;
    for (var attempt = 1; attempt <= 3; attempt++) {
      await tester.fling(list, const Offset(0, 500), 1500); // 아래로 당긴다
      await tester.pump();
      if (await appears(tester, _cardOf(question), const Duration(seconds: 8)) != null) break;
    }
    must(_count(_cardOf(question)) == 1, '당겨서 새로 고침을 3번 했는데 "$question" 카드 ${_count(_cardOf(question))}개(기대 1)');
    return null;
  }),
  // V 가 찬성 1표 — 누르기 전 결과 한 줄, O 를 누르면 버튼 자리가 도넛 + "2명 참여". 두 표는 PC 가 DB 에서 본다.
  'E-POLL-04': _session((tester, job) async {
    final question = job['question'] as String;
    const before = '찬성 100% · 반대 0% · 1명 참여';
    await _openCommunity(tester);
    await pumpUntil(tester, _cardOf(question), timeout: const Duration(seconds: 15));
    final line = find.descendant(of: _cardOf(question), matching: find.text(before));
    must(_count(line) == 1, '누르기 전 "$before" ${_count(line)}개(기대 1) — 카드 글: ${_cardTexts(tester, question)}');
    must(_count(find.descendant(of: _cardOf(question), matching: find.byType(PollDonut))) == 0, '누르기 전인데 도넛이 보임');
    await _voteAgree(tester, question);
    for (final text in ['2명 참여', '찬성 100% · 반대 0%']) {
      final seen = _count(find.descendant(of: _cardOf(question), matching: find.text(text)));
      must(seen == 1, '누른 뒤 "$text" $seen개(기대 1) — 카드 글: ${_cardTexts(tester, question)}');
    }
    must(_count(line) == 0, '누른 뒤에도 투표 전 한 줄 "$before" 이 남음');
    must(_count(_agree(question)) == 0, '누른 뒤에도 O 버튼이 남음');
    return null;
  }),
  // 오늘 첫 투표 — 도넛과 함께 토스트 "하트 10개를 받았어요" 1개. 원장 · 잔액은 PC.
  'E-POLL-05': _session((tester, job) async {
    await _openCommunity(tester);
    await _voteAgree(tester, job['question'] as String);
    final toast = find.text(_rewardToast);
    must(await appears(tester, toast, const Duration(seconds: 5)) != null, '첫 투표인데 5초 안에 토스트 "$_rewardToast" 가 안 뜸');
    must(_count(toast) == 1, '토스트 "$_rewardToast" ${_count(toast)}개(기대 1)');
    return null;
  }),
  // PC 가 API 로 먼저 한 글에 투표해 오늘 하트를 받아 둔 계정 — 다른 글에 투표해도 토스트는 안 뜬다. 원장 · 잔액은 PC.
  'E-POLL-06': _session((tester, job) async {
    await _openCommunity(tester);
    await _voteAgree(tester, job['question'] as String);
    await wait(tester, const Duration(seconds: 3)); // 토스트는 응답 직후에 뜬다 — 뜰 시간을 준다
    must(_count(find.text(_rewardToast)) == 0, '같은 날 두 번째 투표인데 토스트 "$_rewardToast" 가 뜸');
    return null;
  }),
  // PC 가 이번 주 원장 2건을 넣어 두었다 — 18a 투표 줄이 "참여"(open)이고 앱이 서버에서 읽은 used · limit 가 PC 값과 같다.
  'E-POLL-28': _session((tester, job) async {
    await arrive(tester, 'home');
    await tap(tester, _tab('나'));
    await pumpUntil(tester, find.byTooltip('설정'), timeout: const Duration(seconds: 10));
    await tap(tester, find.byTooltip('설정'));
    await arrive(tester, 'settings', timeout: const Duration(seconds: 5));
    await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
    await tap(tester, find.text(_heartTasksRow));
    await pumpUntil(tester, find.byType(HeartTaskRow), timeout: const Duration(seconds: 15));
    final state = find.descendant(of: find.widgetWithText(HeartTaskRow, _voteTitle), matching: find.text(_join));
    await pumpUntil(tester, state, timeout: const Duration(seconds: 15));
    final tasks = ProviderScope.containerOf(tester.element(find.byType(HeartTasksScreen))).read(heartTasksViewModelProvider).tasks;
    final vote = tasks.where((task) => task.kind == HeartTaskKind.pollVote).firstOrNull;
    must(vote != null, '18a 에 투표 줄이 없음');
    must(vote!.used == job['used'], '투표 줄 used ${vote.used}(기대 ${job['used']})');
    must(vote.limit == job['limit'], '투표 줄 limit ${vote.limit}(기대 ${job['limit']})');
    must(vote.state == HeartTaskState.open, '투표 줄 상태 ${vote.state.name}(기대 open)');
    return null;
  }),
};

// ── 추천 코드 3 ─────────────────────────────────────────────────────────────────────────────────────

final Map<String, Area1Case> _referralCases = {
  // 영역 1 의 같은 앱 동작을 그대로 쓴다 — 로그인은 그쪽 _session 이 한다(여기서 다시 감싸면 1회용 토큰을 두 번 쓴다).
  'E-REF-07': area1Cases['E-ONB-62']!, // 소문자 · 앞뒤 공백 코드를 붙여 넣음
  'E-REF-08': area1Cases['E-ONB-64']!, // 없는 코드
  // phase=skip: 20 → 20d → 06-4 → 홈(E-ONB-70). 그 밖: 20 에 닿기(fresh) / 다시 켜서 홈(E-ONB-71).
  'E-REF-17': (tester, job) => area1Cases[job['phase'] == 'skip' ? 'E-ONB-70' : 'E-ONB-71']!(tester, job),
};

final Map<String, Area1Case> area2EmuBCases = {..._acceptanceCases, ..._pollCases, ..._referralCases};
