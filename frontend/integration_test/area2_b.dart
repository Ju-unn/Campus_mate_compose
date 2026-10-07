import 'dart:io';

import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/trait_bar.dart';
import 'package:campus_mate/community/view/community_feed_screen.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_composer_screen.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/viewmodel/community_feed_ui_state.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

/// 영역 2 폰 A 한 대 2차 18(투표 9 · 하트 제출 흐름 8 · 카드 상세 1). PC 쪽은 e2e/area2_phone_b.py 의 같은 번호 — 계정을 만들어
/// 1회용 토큰을 넘기고 DB 값을 본다. 화면 글자는 시나리오가 아니라 지금 화면 코드에서 옮겼다(줄 번호는 옮긴 때 기준).
/// 찾기는 Key 없이 화면 글자 · 툴팁 · 공용/화면 위젯 종류로 한다(이미 있는 Key — poll-question 등 · heart-task-uploader — 만 쓴다).
/// 인증샷은 18b 의 사진 고르기 훅(`HeartTaskSubmitViewModel.pickFromGallery`)을 앱에 든 그림으로 갈아 끼워 넣는다.

// 15d 피드 · 17b 쓰기 · 17c 상세 — frontend/lib/community/view/
const _newPollTooltip = '질문 올리기'; // community_feed_screen.dart:62
const _anonymous = '익명'; // poll_card.dart:102
const _justNow = '방금 전'; // poll_time.dart:10 — 기기 시계가 서버보다 1분 넘게 앞서면 "1분 전" 이 되어 틀어진다
const _noVotes = '0명 참여'; // poll_card.dart:205
const _openDetail = '자세히 보기'; // poll_card.dart:266
const _detailTitle = '투표 상세'; // poll_detail_screen.dart:42
const _commentsSoon = '댓글 기능은 아직 준비 중이에요'; // poll_detail_screen.dart:60
const _post = '익명으로 올리기'; // poll_composer_screen.dart:135
const _dailyLimit = '오늘은 질문을 더 올릴 수 없어요'; // poll_composer_screen.dart:19
const _pageSize = 20; // backend POLL_PAGE_SIZE(community/repository.py:11) — 처음 읽는 개수
const _total = 25; // PC 가 올려 두는 시험 글 수(피드에 원래 보이던 글은 job 의 existing 으로 따로 온다)
// 👍🏻 = 코드 포인트 2개(U+1F44D U+1F3FB). 79자 뒤에 붙이면 80 에서 잘려 👍 만 남는다.
const _thumbs = '\u{1F44D}\u{1F3FB}';
const _thumb = '\u{1F44D}';

// 설정 → 18a — frontend/lib/matching/view/settings_screen.dart:69 · billing/view/heart_task_row.dart · heart_task_submit_screen.dart
const _heartTasksRow = '무료로 하트 모으기'; // settings_screen.dart:69
const _everytime = '에브리타임 홍보'; // heart_task_row.dart:88
const _kakao = '학교 단톡방 공유'; // :89
const _vote = '커뮤니티 투표'; // :90
const _join = '참여'; // :101
const _reviewing = '검수중'; // :108
const _done = '완료'; // :114
const _again = '다시 제출'; // :118 — 반려 줄 끝(빨강)
const _submit = '제출하기'; // heart_task_submit_screen.dart:131
const _resubmit = '다시 제출하기'; // :131 — 반려 뒤 18b-2
const _rejectLead = '반려 사유: '; // :163
const _submitTitle = '인증샷 제출'; // :103
// 반려 사유 문구 — frontend/lib/billing/model/heart_task.dart:27-29
const _rejectLabels = {
  'date_missing': '날짜가 안 보여요',
  'not_verified': '게시글·공유가 확인되지 않아요',
  'reused': '이미 쓴 캡처예요',
};
// 18c — billing/view/heart_task_pending_screen.dart:6 · 8
const _pendingTitle = '확인하고 있어요';
const _pendingDuration = '보통 영업일 1~2일 걸려요';

// 10b — frontend/lib/matching/view/card_detail_screen.dart:197-218 · daily_card_summary.dart:47
const _detailLink = '프로필 자세히 보기';
const _traitTitle = '성향'; // :197
const _lookTitle = '외모 타입'; // :211
const _noteTitle = '이런 사람이 좋아요'; // :218

/// 앞 가설의 세션을 지우고([fresh] 가 false 면 그대로 둔다) 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area1.dart 와 같은 모양).
Area1Case _session(Area1Case body) => (tester, job) async {
      if (job['fresh'] != false) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

int _count(Finder finder) => finder.evaluate().length;

/// 하단 내비의 탭([label] = 메인 · 오늘 · 커뮤니티 · 대화 · 나).
Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

/// [finder] 가 [within] 안에 사라지면 true.
Future<bool> _gone(WidgetTester tester, Finder finder, Duration within) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isNotEmpty) {
    if (watch.elapsed > within) return false;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

/// 맨 위 화면을 뒤로 보낸다. 실제 뒤로 가기(handlePopRoute)는 돌아갈 곳이 없으면 앱을 닫아 시험이 멎는다.
Future<void> _back(WidgetTester tester, Finder onScreen) async {
  Navigator.of(tester.element(onScreen)).pop();
  await wait(tester, const Duration(milliseconds: 500));
}

// ── 투표 ────────────────────────────────────────────────────────────────────────────────────────────

Finder get _feed => find.byType(CommunityFeedScreen);
Finder get _composer => find.byType(PollComposerScreen);
Finder get _questionField => find.byKey(PollComposerScreen.questionKey);

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

/// 피드 → "질문 올리기"(+) → 17b.
Future<void> _openComposer(WidgetTester tester) async {
  await tap(tester, find.byTooltip(_newPollTooltip));
  await pumpUntil(tester, _composer, timeout: const Duration(seconds: 5));
  await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
}

/// 질문을 넣고 "익명으로 올리기" 를 누른다.
Future<void> _submitQuestion(WidgetTester tester, String question) async {
  await type(tester, _questionField, question);
  must(enabled(tester, _post), '질문을 넣었는데 "$_post" 이 꺼져 있음');
  await tap(tester, button(_post));
}

/// 올리기가 되면 17b 가 닫히고 피드로 돌아온다. 안 닫히면 17b 에 뜬 빨간 글을 메모에 남긴다.
Future<void> _closed(WidgetTester tester) async {
  if (await _gone(tester, _composer, const Duration(seconds: 30))) return;
  final reds = tester
      .widgetList<Text>(find.descendant(of: _composer, matching: find.byType(Text)))
      .where((t) => t.style?.color == AppColors.error)
      .map((t) => t.data)
      .join(' / ');
  must(false, '올린 뒤 30초 안에 17b 가 안 닫힘${reds.isEmpty ? '' : ' — 화면 글: $reds'}');
}

/// 피드 맨 위 카드의 질문이 [question] 이 될 때까지(올린 뒤 피드를 다시 읽는다).
Future<void> _firstCardIs(WidgetTester tester, String question) async {
  final watch = Stopwatch()..start();
  while (true) {
    final cards = find.byType(PollCard);
    if (cards.evaluate().isNotEmpty && tester.widget<PollCard>(cards.first).poll.question == question) return;
    must(watch.elapsed < const Duration(seconds: 20), '20초 안에 피드 맨 위가 "$question" 이 안 됨');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Finder _cardOf(String question) => find.widgetWithText(PollCard, question);

/// 17b 를 열어 [question] 을 올리고 닫힐 때까지.
Future<void> _postFromFeed(WidgetTester tester, String question) async {
  await _openComposer(tester);
  await _submitQuestion(tester, question);
  await _closed(tester);
}

final Map<String, Area1Case> _pollCases = {
  // 첫 카드: 입력한 질문 · "익명" 1 · "방금 전" 1 · "0명 참여" 1 · O/X 버튼(아이콘) 하나씩. polls 1행은 PC 가 본다.
  'E-POLL-01': _session((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _postFromFeed(tester, question);
    await _firstCardIs(tester, question);
    final card = find.byType(PollCard).first;
    for (final text in [_anonymous, _justNow, _noVotes]) {
      final seen = _count(find.descendant(of: card, matching: find.text(text)));
      must(seen == 1, '첫 카드에 "$text" $seen개(기대 1)');
    }
    for (final (icon, name) in [(AppIcons.circle, 'O'), (AppIcons.x, 'X')]) {
      final seen = _count(find.descendant(of: card, matching: find.byIcon(icon)));
      must(seen == 1, '첫 카드에 $name 버튼 아이콘 $seen개(기대 1)');
    }
    return null;
  }),
  // PC 가 올려 둔 글에 글쓴이(이 계정)가 O 를 누른다 → 도넛. poll_votes 1행은 PC 가 본다.
  'E-POLL-13': _session((tester, job) async {
    final card = _cardOf(job['question'] as String);
    await _openCommunity(tester);
    await pumpUntil(tester, card, timeout: const Duration(seconds: 15));
    await tap(tester, find.descendant(of: card, matching: find.widgetWithIcon(FilledButton, AppIcons.circle)));
    await pumpUntil(tester, find.descendant(of: card, matching: find.byType(PollDonut)), timeout: const Duration(seconds: 20));
    return null;
  }),
  // PC 가 오늘 글 9개를 채운 뒤 — 10번째는 17b 가 닫히고, 11번째는 17b 에 빨간 글 1개가 뜨고 안 닫힌다(429 · polls 10행은 PC).
  'E-POLL-14': _session((tester, job) async {
    await _openCommunity(tester);
    await _postFromFeed(tester, job['tenth'] as String);
    await _openComposer(tester);
    await _submitQuestion(tester, job['eleventh'] as String);
    final limit = find.text(_dailyLimit);
    await pumpUntil(tester, limit, timeout: const Duration(seconds: 20));
    must(_count(limit) == 1, '"$_dailyLimit" ${_count(limit)}개(기대 1)');
    must(tester.widget<Text>(limit).style?.color == AppColors.error, '"$_dailyLimit" 이 빨간 글이 아님');
    must(_composer.evaluate().isNotEmpty, '11번째인데 17b 가 닫힘(올라간 것 아닌가)');
    return null;
  }),
  // PC 가 10개를 채우고 하나 지운 뒤 — 새 글이 올라가 17b 가 닫히고 피드 맨 위가 된다.
  'E-POLL-15': _session((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await _postFromFeed(tester, question);
    await _firstCardIs(tester, question);
    return null;
  }),
  // 못 올리는 입력: 공백만 · 같은 선택지는 버튼 꺼짐, 질문 81자는 80 · 선택지 7자는 6 에서 입력이 막힌다. 누르지 않는다(API 422 는 PC).
  'E-POLL-18': _session((tester, job) async {
    await _openCommunity(tester);
    await _openComposer(tester);
    final optionA = find.byKey(PollComposerScreen.optionAKey);
    final optionB = find.byKey(PollComposerScreen.optionBKey);
    await type(tester, _questionField, '   ');
    must(!enabled(tester, _post), '질문이 공백뿐인데 "$_post" 이 켜짐');
    await type(tester, _questionField, '가' * 81);
    final question = fieldText(tester, _questionField).runes.length;
    must(question == 80, '질문 81자를 넣었더니 입력칸이 $question자(기대 80 에서 막힘)');
    // 보기 입력칸은 "직접 적기" 탭에만 있다(기본은 O/X 탭, 10-08 개편).
    await tap(tester, find.text('직접 적기'));
    must(optionA.evaluate().isNotEmpty, '"직접 적기" 탭을 눌렀는데 보기 입력칸이 안 나옴');
    await type(tester, optionA, 'abcdefg');
    final option = fieldText(tester, optionA).runes.length;
    must(option == 6, '선택지 7자를 넣었더니 입력칸이 $option자(기대 6 에서 막힘)');
    await type(tester, optionA, '같음');
    await type(tester, optionB, '같음');
    must(!enabled(tester, _post), '두 선택지가 같은데 "$_post" 이 켜짐');
    return null;
  }),
  // PC 가 시험 글 25개를 얹었다(원래 보이던 글 existing 개는 그대로) — 처음 20(새 글이 최신순 맨 앞이라 모두 시험 글) → 끝까지 내리면 25 + existing,
  // 같은 id 중복 0, 끝(더 없음 · 아래 로딩 표시 없음). 글에 끝 글자는 없다.
  'E-POLL-25': _session((tester, job) async {
    final expected = _total + (job['existing'] as int);
    await _openCommunity(tester);
    final first = _feedState(tester).polls.length;
    must(first == _pageSize, '처음 읽은 글 $first개(기대 $_pageSize)');
    final scroll = tester.state<ScrollableState>(find.descendant(of: _feed, matching: find.byType(Scrollable)).first);
    final watch = Stopwatch()..start();
    while (_feedState(tester).hasMore || _feedState(tester).isLoadingMore) {
      must(watch.elapsed < const Duration(seconds: 60), '60초 안에 끝까지 못 읽음(지금 ${_feedState(tester).polls.length}개)');
      final position = scroll.position;
      position.jumpTo((position.maxScrollExtent - 600).clamp(0, position.maxScrollExtent)); // 다시 바닥에 닿아야 다음 쪽을 부른다
      await tester.pump();
      position.jumpTo(position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 500));
    }
    final ids = _feedState(tester).polls.map((poll) => poll.id).toList();
    must(ids.length == expected, '끝까지 내린 글 ${ids.length}개(기대 $expected = 시험 $_total + 기존 ${expected - _total})');
    must(ids.toSet().length == ids.length, '같은 id 가 ${ids.length - ids.toSet().length}번 겹침');
    final spinner = find.descendant(of: _feed, matching: find.byType(CircularProgressIndicator));
    must(_count(spinner) == 0, '끝인데 아래에 로딩 표시가 남음');
    return null;
  }),
  'E-POLL-26': _session((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await pumpUntil(tester, _cardOf(question), timeout: const Duration(seconds: 15));
    await tap(tester, find.descendant(of: _cardOf(question), matching: find.text(_openDetail)));
    await pumpUntil(tester, find.text(_detailTitle), timeout: const Duration(seconds: 10));
    await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
    must(_count(find.text(_commentsSoon)) == 1, '"$_commentsSoon" ${_count(find.text(_commentsSoon))}개(기대 1)');
    must(_count(_cardOf(question)) == 1, '상세에 같은 카드(질문 "$question")가 ${_count(_cardOf(question))}개');
    must(_count(find.text(_openDetail)) == 0, '상세 카드에 "$_openDetail" 줄이 남음(피드 카드 모양)');
    return null;
  }),
  // 선택지를 직접 적은 글 — 글자 버튼 두 개, O/X 아이콘 0.
  'E-POLL-27': _session((tester, job) async {
    final question = job['question'] as String;
    await _openCommunity(tester);
    await pumpUntil(tester, _cardOf(question), timeout: const Duration(seconds: 15));
    final card = _cardOf(question);
    for (final label in [job['a'] as String, job['b'] as String]) {
      final seen = _count(find.descendant(of: card, matching: find.widgetWithText(FilledButton, label)));
      must(seen == 1, '버튼 "$label" $seen개(기대 1)');
    }
    for (final icon in [AppIcons.circle, AppIcons.x]) {
      must(_count(find.descendant(of: card, matching: find.byIcon(icon))) == 0, '글자 버튼 글인데 O/X 아이콘이 남음');
    }
    return null;
  }),
  // 질문 79자 + 👍🏻 → 입력칸 80(코드 포인트) · 카운터 "80 / 80" · 올리기 되면 17b 가 닫히고 피드 맨 위가 79자 + 👍. 서버가 받은 글은 PC 가 본다.
  'E-POLL-31': _session((tester, job) async {
    final base = job['base'] as String;
    await _openCommunity(tester);
    await _openComposer(tester);
    await type(tester, _questionField, '$base$_thumbs');
    final length = fieldText(tester, _questionField).runes.length;
    must(length == 80, '79자 + 👍🏻 를 넣었더니 입력칸이 $length(기대 코드 포인트 80)');
    must(_count(find.text('80 / 80')) == 1, '카운터 "80 / 80" ${_count(find.text('80 / 80'))}개(기대 1)');
    must(enabled(tester, _post), '80자인데 "$_post" 이 꺼짐');
    await tap(tester, button(_post));
    await _closed(tester);
    await _firstCardIs(tester, '$base$_thumb');
    return null;
  }),
};

// ── 하트 제출 흐름 ──────────────────────────────────────────────────────────────────────────────────

/// 메인 → 나 → 톱니(설정). 설정은 나 탭 위에 쌓인다.
Future<void> _openSettings(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byTooltip('설정'), timeout: const Duration(seconds: 10));
  await tap(tester, find.byTooltip('설정'));
  await arrive(tester, 'settings', timeout: const Duration(seconds: 5));
  await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
}

/// 설정 → 18a, 세 줄을 받을 때까지.
Future<void> _openHeartTasks(WidgetTester tester) async {
  await _openSettings(tester);
  await _enterHeartTasks(tester);
}

Future<void> _enterHeartTasks(WidgetTester tester) async {
  await tap(tester, find.text(_heartTasksRow));
  await pumpUntil(tester, find.byType(HeartTaskRow), timeout: const Duration(seconds: 15));
}

/// 18a 에서 나갔다가 다시 들어온다 — 18a 는 들어올 때마다 서버에서 새로 읽는다.
Future<void> _reopenHeartTasks(WidgetTester tester) async {
  await _back(tester, find.byType(HeartTasksScreen));
  await _enterHeartTasks(tester);
}

Finder _row(String title) => find.widgetWithText(HeartTaskRow, title);
Finder _inRow(String title, String text) => find.descendant(of: _row(title), matching: find.text(text));

/// [title] 줄 끝에 [state] 글이 뜰 때까지.
Future<void> _rowShows(WidgetTester tester, String title, String state) =>
    pumpUntil(tester, _inRow(title, state), timeout: const Duration(seconds: 15));

/// 18a 의 [title] 줄 → 18b(반려 뒤면 18b-2).
Future<void> _toSubmit(WidgetTester tester, String title) async {
  await tap(tester, _row(title));
  await pumpUntil(tester, find.byType(HeartTaskSubmitScreen), timeout: const Duration(seconds: 10));
  await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
}

/// 18b 의 업로더에 앱에 든 그림을 넣는다(갤러리 훅).
Future<void> _attachProof(WidgetTester tester) async {
  final data = await rootBundle.load('assets/images/mascot-male.png');
  final file = File('${(await getTemporaryDirectory()).path}/e2e-proof.png');
  await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  final container = ProviderScope.containerOf(tester.element(find.byType(HeartTaskSubmitScreen)));
  container.read(heartTaskSubmitViewModelProvider.notifier).pickFromGallery = () async => file;
  await tap(tester, find.byKey(heartTaskUploaderKey));
  final watch = Stopwatch()..start();
  while (container.read(heartTaskSubmitViewModelProvider).photo == null) {
    must(watch.elapsed < const Duration(seconds: 5), '업로더를 눌렀는데 5초 안에 사진이 안 들어감');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 사진을 넣고 [label] 버튼을 눌러 18c 가 뜰 때까지(압축 + 올리기). 서버가 막으면 그 문구를 메모에 남긴다.
Future<void> _sendProof(WidgetTester tester, String label) async {
  await _attachProof(tester);
  must(enabled(tester, label), '사진을 넣었는데 "$label" 이 꺼짐');
  await tap(tester, button(label));
  final pending = find.text(_pendingTitle);
  final watch = Stopwatch()..start();
  while (pending.evaluate().isEmpty) {
    final submit = find.byType(HeartTaskSubmitScreen);
    if (submit.evaluate().isNotEmpty) {
      final error = ProviderScope.containerOf(tester.element(submit)).read(heartTaskSubmitViewModelProvider).errorMessage;
      must(error == null, '제출이 막힘: $error');
    }
    must(watch.elapsed < const Duration(seconds: 60), '제출 뒤 60초 안에 18c "$_pendingTitle" 가 안 뜸');
    await tester.pump(const Duration(milliseconds: 200));
  }
  await wait(tester, const Duration(milliseconds: 500));
}

/// 18c 의 두 글이 그대로 있다.
void _pendingTexts() {
  for (final text in [_pendingTitle, _pendingDuration]) {
    must(_count(find.text(text)) == 1, '18c 에 "$text" ${_count(find.text(text))}개(기대 1)');
  }
}

/// 반려 줄이 빨간 "다시 제출" 이고, 누르면 18b-2 에 사유 글과 "다시 제출하기" 가 있다.
Future<void> _openRejected(WidgetTester tester, String reason) async {
  final again = _inRow(_everytime, _again);
  await pumpUntil(tester, again, timeout: const Duration(seconds: 15));
  must(_count(again) == 1, '"$_again" ${_count(again)}개(기대 1)');
  must(tester.widget<Text>(again).style?.color == AppColors.error, '"$_again" 이 빨간 글이 아님');
  await _toSubmit(tester, _everytime);
  final label = '$_rejectLead${_rejectLabels[reason]}';
  must(_count(find.text(label)) == 1, '18b-2 에 "$label" ${_count(find.text(label))}개(기대 1)');
  must(_count(button(_resubmit)) == 1, '18b-2 에 "$_resubmit" 버튼 ${_count(button(_resubmit))}개(기대 1)');
}

final Map<String, Area1Case> _heartCases = {
  'E-HEART-04': _session((tester, job) async {
    await _openHeartTasks(tester);
    await _toSubmit(tester, _everytime);
    await _sendProof(tester, _submit);
    _pendingTexts();
    return null;
  }),
  // 제출 → 18c → 뒤로 → 18a 에브리타임 줄이 "검수중" → 눌러도 18a 에 그대로(18b · 18c 로 안 감).
  'E-HEART-05': _session((tester, job) async {
    await _openHeartTasks(tester);
    await _toSubmit(tester, _everytime);
    await _sendProof(tester, _submit);
    await _back(tester, find.text(_pendingTitle));
    await _rowShows(tester, _everytime, _reviewing);
    await tap(tester, _row(_everytime));
    await wait(tester, const Duration(seconds: 1));
    must(_count(find.byType(HeartTasksScreen)) == 1, '"$_reviewing" 줄을 눌렀더니 18a 를 떠남');
    must(_count(find.text(_submitTitle)) == 0 && _count(find.text(_pendingTitle)) == 0, '"$_reviewing" 줄을 눌렀더니 18b · 18c 가 열림');
    return null;
  }),
  // PC 가 미리 제출해 둔 줄 — 18a 에서 "검수중" 을 본 뒤 멈춰 PC 가 승인하고, 18a 를 다시 열면 "완료"(검수중은 사라짐).
  'E-HEART-09': _session((tester, job) async {
    await _openHeartTasks(tester);
    await _rowShows(tester, _everytime, _reviewing);
    await step('approved');
    await _reopenHeartTasks(tester);
    await _rowShows(tester, _everytime, _done);
    must(_count(_inRow(_everytime, _reviewing)) == 0, '"$_done" 인데 "$_reviewing" 도 보임');
    return null;
  }),
  // PC 가 반려해 둔 줄 — 빨간 "다시 제출" → 18b-2 사유 글.
  'E-HEART-12': _session((tester, job) async {
    await _openHeartTasks(tester);
    await _openRejected(tester, job['reason'] as String);
    return null;
  }),
  // 사유마다 PC 가 새로 반려하고 앱을 새로 켠다(fresh=false).
  'E-HEART-13': _session((tester, job) async {
    await _openHeartTasks(tester);
    await _openRejected(tester, job['reason'] as String);
    return null;
  }),
  // 반려 뒤 같은 달 — 18b-2 에서 "다시 제출하기" 가 되어 18c, 18a 에브리타임 줄이 "검수중"(빨간 "다시 제출" 은 사라짐). 새 행은 PC.
  'E-HEART-14': _session((tester, job) async {
    await _openHeartTasks(tester);
    await _openRejected(tester, job['reason'] as String);
    await _sendProof(tester, _resubmit);
    _pendingTexts();
    await _back(tester, find.text(_pendingTitle));
    await _rowShows(tester, _everytime, _reviewing);
    must(_count(_inRow(_everytime, _again)) == 0, '"$_reviewing" 인데 "$_again" 도 보임');
    return null;
  }),
  // PC 가 단톡방 승인 3건을 넣어 두었다 — 단톡방 줄 "완료". 4번째 429 · 원장 +25 × 3 은 PC.
  'E-HEART-16': _session((tester, job) async {
    await _openHeartTasks(tester);
    await _rowShows(tester, _kakao, _done);
    return null;
  }),
  // 이번 주 적립 2건이면 "참여" → 누르면 커뮤니티 탭, 3건이면 "완료" → 눌러도 18a 에 그대로.
  'E-HEART-21': _session((tester, job) async {
    final open = job['expect'] == 'open';
    await _openHeartTasks(tester);
    await _rowShows(tester, _vote, open ? _join : _done);
    must(_count(_inRow(_vote, open ? _done : _join)) == 0, '투표 줄에 "${open ? _done : _join}" 도 보임');
    await tap(tester, _row(_vote));
    if (open) {
      await pumpUntil(tester, _feed, timeout: const Duration(seconds: 10));
    } else {
      await wait(tester, const Duration(seconds: 1));
      must(_count(find.byType(HeartTasksScreen)) == 1 && _count(_feed) == 0, '"$_done" 줄을 눌렀더니 18a 를 떠남');
    }
    return null;
  }),
};

// ── 카드 상세 10b ───────────────────────────────────────────────────────────────────────────────────

List<String> _texts(WidgetTester tester, Finder scope) =>
    tester.widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text))).map((t) => t.data ?? '').toList();

/// 오늘 탭의 [person](닉네임 · PC 가 DB 에서 읽은 기대 글)의 카드 → "프로필 자세히 보기" → 10b 의 각 칸이 기대와 같다.
Future<void> _checkProfile(WidgetTester tester, Map<String, dynamic> person) async {
  final nickname = person['nickname'] as String;
  final who = '"$nickname"';
  final summary = find.byWidgetPredicate((w) => w is DailyCardSummary && w.card.profile.nickname == nickname);
  await pumpUntil(tester, summary, timeout: const Duration(seconds: 30));
  await tap(tester, find.descendant(of: summary, matching: find.text(_detailLink)));
  await pumpUntil(tester, find.byType(ProfileCard), timeout: const Duration(seconds: 15));
  await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
  final card = find.byType(ProfileCard);
  Finder inCard(String text) => find.descendant(of: card, matching: find.text(text));

  // 키 · MBTI · 학번 · 종교 · 흡연 3열 2줄 — 라벨과 값이 번갈아(값이 없으면 "—").
  final facts = [for (final pair in person['facts'] as List<dynamic>) ...(pair as List<dynamic>).cast<String>()];
  final wrap = find.ancestor(of: inCard('MBTI'), matching: find.byType(Wrap)).first;
  final shown = _texts(tester, wrap);
  must(shown.join(' | ') == facts.join(' | '), '$who 사실 칸 ${shown.join(' | ')}(기대 ${facts.join(' | ')})');

  for (final title in [_traitTitle, _lookTitle]) {
    must(_count(inCard(title)) == 1, '$who "$title" 제목 ${_count(inCard(title))}개(기대 1)');
  }
  for (final look in (person['look'] as List<dynamic>).cast<String>()) {
    must(_count(inCard(look)) >= 1, '$who 외모 타입 "$look" 없음');
  }
  final survey = [for (final v in person['survey'] as List<dynamic>) (v as num).toDouble()];
  final bars = tester.widgetList<TraitBar>(find.descendant(of: card, matching: find.byType(TraitBar))).toList();
  must(bars.length == survey.length, '$who 성향 바 ${bars.length}개(기대 ${survey.length})');
  for (final (axis, bar) in bars.indexed) {
    must((bar.value - survey[axis]).abs() < 0.001, '$who 성향 ${axis + 1}번 ${bar.value}(기대 ${survey[axis]})');
  }
  for (final MapEntry(key: title, value: values) in (person['tags'] as Map<String, dynamic>).entries) {
    final tags = (values as List<dynamic>).cast<String>();
    must(_count(inCard(title)) == (tags.isEmpty ? 0 : 1), '$who "$title" 제목 ${_count(inCard(title))}개(칩 ${tags.length}개)');
    for (final tag in tags) {
      must(_count(inCard(tag)) >= 1, '$who "$title" 칩 "$tag" 없음');
    }
  }
  if (person['bio'] case final String bio) must(_count(inCard(bio)) == 1, '$who 자기소개 ${_count(inCard(bio))}개(기대 1)');
  if (person['note'] case final String note) {
    must(_count(inCard(_noteTitle)) == 1, '$who "$_noteTitle" 제목 ${_count(inCard(_noteTitle))}개(기대 1)');
    must(_count(inCard(note)) == 1, '$who 이상형 글 ${_count(inCard(note))}개(기대 1)');
  } else {
    must(_count(inCard(_noteTitle)) == 0, '$who 이상형 글이 없는데 "$_noteTitle" 제목이 보임');
  }
  await _back(tester, card);
}

final Map<String, Area1Case> _cardCases = {
  'E-CARD-90': _session((tester, job) async {
    await arrive(tester, 'home');
    await tap(tester, _tab('오늘'));
    for (final person in (job['people'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      await _checkProfile(tester, person);
    }
    return null;
  }),
};

final Map<String, Area1Case> area2bCases = {..._pollCases, ..._heartCases, ..._cardCases};
