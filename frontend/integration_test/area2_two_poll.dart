import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/community/view/community_feed_screen.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_detail_screen.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

/// 영역 2 두 기기(폰 A + 에뮬 B) 투표 글 8 — E-POLL-11 · 12 · 19 · 20 · 21 · 22 · 23 · 29. 가설 하나가 `E-POLL-NN/A` · `E-POLL-NN/B` 두 줄이고,
/// PC 쪽은 e2e/area2_two_poll.py(e2e/twodev.py 위) — 글 올리기 · 지우기 · 가림 · 정지 · 신고(API)와 두 기기의 순서(Sync)를 맡는다.
/// 앱이 `step(이름)` 에서 멈추면 PC 가 할 일을 하고 풀어 준다. step 이름은 PC 쪽 plan 키와 같아야 한다. 판정은 이 화면이 보이는 것만 한다.
/// 화면 글자는 시나리오가 아니라 지금 화면 코드에서 옮겼다. 찾기는 Key 없이 글자 · 툴팁 · 위젯 종류로 한다.

// 15d 피드 · 17c 상세 — frontend/lib/community/view/
const _moreTooltip = '더보기'; // poll_card.dart:116 — 내 글에만
const _reportLabel = '신고하기'; // poll_card.dart:153 — 남의 글에만(머리줄 오른쪽 끝)
const _openDetail = '자세히 보기'; // poll_card.dart:317
const _detailTitle = '투표 상세'; // poll_detail_screen.dart:42
const _notFound = '질문을 찾을 수 없어요'; // 서버 POLL_NOT_FOUND(토스트) · poll_detail_screen.dart:45(없는 글 자리)
const _alreadyVoted = '이미 투표했어요'; // 서버 POLL_ALREADY_VOTED(토스트)
const _menuDelete = '삭제하기'; // poll_sheets.dart:129(메뉴 줄) · :209(확인 시트 버튼)
const _confirmTitle = '이 질문을 삭제할까요?'; // poll_sheets.dart:201
const _deleted = '삭제했어요'; // poll_toast.dart:9

/// 상대 기기를 기다리는 step 의 상한 — PC 쪽 기다림(WAIT 150초)보다 길어서 PC 가 먼저 이유를 말한다.
const _waitOther = Duration(minutes: 3);

/// 앞 가설의 세션을 지우고 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area1.dart 와 같은 모양).
Area1Case _login(Area1Case body) => (tester, job) async {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

int _count(Finder finder) => finder.evaluate().length;

Finder get _feed => find.byType(CommunityFeedScreen);

/// 하단 내비의 탭([label] = 메인 · 오늘 · 커뮤니티 · 대화 · 나).
Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

Finder _cardOf(String question) => find.widgetWithText(PollCard, question);

Finder _inCard(String question, Finder matching) => find.descendant(of: _cardOf(question), matching: matching);

Finder _vote(String question, IconData icon) => _inCard(question, find.widgetWithIcon(FilledButton, icon));

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

/// 피드를 서버 값으로 다시 읽는다(당겨서 새로 고침이 부르는 함수 그대로 — 글이 하나도 없으면 당길 수 없어서 직접 부른다).
/// [onScreen] 은 지금 맨 위에 있는 화면의 위젯 — 그 아래 Provider 범위를 찾는 데 쓴다(상세가 위에 있으면 피드 위젯은 안 보인다).
Future<void> _refresh(WidgetTester tester, Finder onScreen) async {
  await ProviderScope.containerOf(tester.element(onScreen)).read(communityFeedViewModelProvider.notifier).refresh();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _shows(WidgetTester tester, String question) =>
    pumpUntil(tester, _cardOf(question), timeout: const Duration(seconds: 15));

/// [question] 카드가 목록에서 사라질 때까지.
Future<void> _gone(WidgetTester tester, String question) async {
  final watch = Stopwatch()..start();
  while (_cardOf(question).evaluate().isNotEmpty) {
    must(watch.elapsed < const Duration(seconds: 15), '15초 안에 글이 목록에서 안 빠짐: $question');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 내 글 카드: 머리줄 오른쪽 끝에 "…" 하나, "신고하기" 없음.
void _mustOwn(String question) {
  final more = _count(_inCard(question, find.byTooltip(_moreTooltip)));
  final report = _count(_inCard(question, find.text(_reportLabel)));
  must(more == 1, '내 글 카드에 "…" $more개(기대 1)');
  must(report == 0, '내 글 카드에 "$_reportLabel" $report개(기대 0)');
}

/// 남의 글 카드: "신고하기" 하나, "…" 없음.
void _mustBeOthers(String question) {
  final more = _count(_inCard(question, find.byTooltip(_moreTooltip)));
  final report = _count(_inCard(question, find.text(_reportLabel)));
  must(more == 0, '남의 글 카드에 "…" $more개(기대 0)');
  must(report == 1, '남의 글 카드에 "$_reportLabel" $report개(기대 1)');
}

/// O 를 눌러 투표하고 그 카드가 도넛이 될 때까지.
Future<void> _voteO(WidgetTester tester, String question) async {
  await tap(tester, _vote(question, AppIcons.circle));
  await pumpUntil(tester, _inCard(question, find.byType(PollDonut)), timeout: const Duration(seconds: 20));
}

/// 투표를 마친 카드: 도넛 하나, 투표 버튼 없음.
Future<void> _mustBeVoted(WidgetTester tester, String question) async {
  await pumpUntil(tester, _inCard(question, find.byType(PollDonut)), timeout: const Duration(seconds: 15));
  final buttons = _count(_inCard(question, find.byType(FilledButton)));
  must(buttons == 0, '투표한 글에 투표 버튼 $buttons개가 남음(기대 0)');
}

/// 내 글을 "…" → "삭제하기" → 확인 → "삭제했어요" 로 지운다.
Future<void> _deleteMine(WidgetTester tester, String question) async {
  await tap(tester, _inCard(question, find.byTooltip(_moreTooltip)));
  await pumpUntil(tester, find.text(_menuDelete), timeout: const Duration(seconds: 5));
  await tap(tester, find.text(_menuDelete));
  await pumpUntil(tester, find.text(_confirmTitle), timeout: const Duration(seconds: 5));
  await wait(tester, const Duration(milliseconds: 500)); // 확인 시트가 다 올라오게
  await tap(tester, button(_menuDelete));
  await pumpUntil(tester, find.text(_deleted), timeout: const Duration(seconds: 20));
  await _gone(tester, question);
}

/// 글쓴이 쪽(21 · 22): 내 글을 띄워 PC 에 알리고(`seen`), 상대 기기의 일이 끝나면(`after`) 새로 고쳐 그 글이 사라졌는지 본다.
final Area1Case _authorSeesItVanish = _login((tester, job) async {
  final question = job['question'] as String;
  await _openCommunity(tester);
  await _shows(tester, question);
  _mustOwn(question);
  await step('seen', timeout: _waitOther); // PC: 상대 기기의 일을 풀어 준다
  await step('after', timeout: _waitOther); // PC: 상대 기기의 일이 끝난 뒤(글쓴이 삭제 · 운영자 가림)
  await _refresh(tester, _feed);
  await _gone(tester, question);
  return null;
});

final Map<String, Area1Case> area2TwoPollCases = {
  // ── E-POLL-11 같은 글에 다시 투표 못 한다 — B 는 O 를 눌러 도넛이 되고, PC 가 같은 계정으로 반대표(API)를 보내 409 를 본다.
  // 화면: B 의 글은 도넛이고 투표 버튼이 없다. A(글쓴이)의 카드는 "1명 참여"(두 번째 표가 안 들어감).
  'E-POLL-11/A': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    _mustOwn(question);
    await step('after-vote', timeout: _waitOther); // PC: B 가 투표하고 반대표(API)가 409 로 막힌 뒤
    await _refresh(tester, _feed);
    await pumpUntil(tester, _inCard(question, find.textContaining('1명 참여')), timeout: const Duration(seconds: 15));
    return null;
  }),
  'E-POLL-11/B': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    await _voteO(tester, question);
    await step('voted', timeout: _waitOther); // PC: 같은 글에 반대표(API) → 409
    await _refresh(tester, _feed);
    await _mustBeVoted(tester, question);
    return null;
  }),

  // ── E-POLL-12 같은 계정을 두 기기에 켜 두고 A 폰이 투표한 뒤 B 에뮬이(옛 화면에서) 투표 → 토스트 "이미 투표했어요" · 그 카드 도넛.
  // B 는 일감에 토큰이 없다 — 1회용 토큰은 새로 받으면 앞의 것이 죽어서, A 가 로그인을 마친 뒤 PC 가 같은 계정의 새 토큰을 `need-login` 에 실어 준다.
  'E-POLL-12/A': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    await step('signed-in', timeout: _waitOther); // PC: B 가 같은 계정으로 들어와 같은 글을 띄울 때까지 붙잡는다
    await _voteO(tester, question);
    await step('voted'); // PC: B 에게 알린다
    return null;
  }),
  'E-POLL-12/B': (tester, job) async {
    final question = job['question'] as String;
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    final got = await step('need-login', timeout: _waitOther); // PC: A 가 로그인을 마친 뒤 같은 계정의 새 토큰을 준다
    await signIn(got['token_hash'] as String);
    await _openCommunity(tester);
    await _shows(tester, question);
    final buttons = _count(_inCard(question, find.byType(FilledButton)));
    must(buttons == 2, '투표 전 카드에 투표 버튼 $buttons개(기대 2)');
    await step('ready', timeout: _waitOther); // PC: A 가 투표한 뒤에 풀어 준다 — 이 화면은 옛 모습(버튼 있음)
    await tap(tester, _vote(question, AppIcons.x));
    await pumpUntil(tester, find.text(_alreadyVoted), timeout: const Duration(seconds: 15));
    await _mustBeVoted(tester, question); // 서버 상태(A 의 O)로 도넛이 된다
    return null;
  },

  // ── E-POLL-19 내 글에만 "…" → "삭제하기" → "이 질문을 삭제할까요?" → "삭제하기" → "삭제했어요". B 가 투표해 하트를 받은 글을 A 가 지운다.
  // 투표 · 하트 잔액은 PC 가 본다. B 는 A 가 지운 뒤 새로 고치면 그 글이 목록에서 빠진다.
  'E-POLL-19/A': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    _mustOwn(question);
    await step('wait-vote', timeout: _waitOther); // PC: B 가 투표해 하트를 받은 뒤
    await _deleteMine(tester, question);
    await step('deleted'); // PC: B 쪽을 풀어 준다
    return null;
  }),
  'E-POLL-19/B': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    _mustBeOthers(question);
    await _voteO(tester, question);
    await step('voted', timeout: _waitOther); // PC: 잔액을 적고 A 가 글을 지울 때까지 붙잡는다
    await _refresh(tester, _feed);
    await _gone(tester, question);
    return null;
  }),

  // ── E-POLL-20 남의 글은 "…" 이 없고 "신고하기" 가 있다(A 는 보는 사람 · B 는 글쓴이). PC 가 A 토큰으로 DELETE → 404, 글 그대로.
  'E-POLL-20/A': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    _mustBeOthers(question);
    await step('seen', timeout: _waitOther); // PC: 내 토큰으로 이 글을 지워 보고 404 를 본다
    await _refresh(tester, _feed);
    await _shows(tester, question); // 글은 그대로
    return null;
  }),
  'E-POLL-20/B': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    _mustOwn(question);
    await step('seen', timeout: _waitOther); // PC: A 가 지워 보는 동안 기다린다
    await _refresh(tester, _feed);
    await _shows(tester, question);
    _mustOwn(question);
    return null;
  }),

  // ── E-POLL-21 내가 열어 둔 글을 작성자가 지운 뒤 투표 → 토스트 "질문을 찾을 수 없어요" · 목록에서 그 글 0.
  'E-POLL-21/A': _authorSeesItVanish,
  'E-POLL-21/B': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    await step('seen', timeout: _waitOther); // PC: A 가 글을 띄운 것을 본 뒤 글쓴이 토큰으로 지운다 — 이 화면은 옛 모습
    must(_cardOf(question).evaluate().isNotEmpty, '지운 직후인데 B 목록에서 글이 이미 빠짐(옛 화면이어야 한다)');
    await tap(tester, _vote(question, AppIcons.circle));
    await pumpUntil(tester, find.text(_notFound), timeout: const Duration(seconds: 15));
    await _gone(tester, question);
    return null;
  }),

  // ── E-POLL-22 운영자가 글을 가리면(status=blinded) 피드 · 상세에서 사라지고 투표도 "없는 글". B 는 상세를 열어 둔다 —
  // 17c 는 피드 목록의 같은 글을 보므로 새로 고치면 "질문을 찾을 수 없어요" 가 된다. PC 가 가리고 투표(API)·상세(API)를 404 로 본다.
  'E-POLL-22/A': _authorSeesItVanish,
  'E-POLL-22/B': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    await tap(tester, _inCard(question, find.text(_openDetail)));
    await pumpUntil(tester, find.text(_detailTitle), timeout: const Duration(seconds: 10));
    await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
    await step('detail', timeout: _waitOther); // PC: 글을 가리고 B 토큰으로 투표 · 상세를 보낸다
    final detail = find.byType(PollDetailScreen);
    await _refresh(tester, detail);
    await pumpUntil(tester, find.text(_notFound), timeout: const Duration(seconds: 15));
    must(_count(find.text(_notFound)) == 1, '상세에 "$_notFound" ${_count(find.text(_notFound))}개(기대 1)');
    Navigator.of(tester.element(detail)).pop();
    await wait(tester, const Duration(milliseconds: 500));
    await _gone(tester, question); // 피드에서도 빠졌다
    return null;
  }),

  // ── E-POLL-23 글쓴이가 정지되면 그 글이 안 보인다 — 되돌리면 다시 보인다(지워진 게 아니라 숨은 것). PC 가 A 계정 status 를 바꾼다.
  'E-POLL-23/A': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    _mustOwn(question);
    await step('seen'); // PC: B 쪽에서 A 계정을 정지한다 — 이 가설에서 A 는 더 하는 일이 없다
    return null;
  }),
  'E-POLL-23/B': _login((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _shows(tester, question);
    await step('suspended', timeout: _waitOther); // PC: A 가 글을 띄운 것을 본 뒤 A 계정을 정지한다
    await _refresh(tester, _feed);
    await _gone(tester, question);
    await step('restored', timeout: _waitOther); // PC: 정지를 푼다
    await _refresh(tester, _feed);
    await _shows(tester, question);
    return null;
  }),

  // ── E-POLL-29 남의 투표 글에는 머리줄 오른쪽 끝에 "신고하기", 내 글에는 없다(대신 "…"). 두 기기 다 자기 글 · 상대 글을 한 장씩 띄운다.
  // PC 가 A 토큰으로 POST /reports(남의 글 201 · 내 글 · 가려진 글 404) — 신고 뒤에도 카드는 그대로(자동 가림 없음).
  'E-POLL-29/A': _login(_headerCheck),
  'E-POLL-29/B': _login(_headerCheck),
};

Future<Map<String, Object?>?> _headerCheck(WidgetTester tester, Map<String, dynamic> job) async {
  final mine = job['mine'] as String;
  final other = job['other'] as String;
  await _openCommunity(tester);
  await _shows(tester, mine);
  await _shows(tester, other);
  _mustOwn(mine);
  _mustBeOthers(other);
  await step('checked', timeout: _waitOther); // PC: 두 기기가 다 본 뒤 A 토큰으로 신고 3번
  await _refresh(tester, _feed);
  await _shows(tester, mine);
  await _shows(tester, other);
  _mustOwn(mine);
  _mustBeOthers(other);
  return null;
}
