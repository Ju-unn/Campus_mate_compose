part of 'area3.dart';

// 영역 3 안전 폰 한 대 — 신고 · 차단 · 정지에서 앱이 누르고 화면을 읽는 27개(02 · 03 · 04 · 06 · 22 · 25 · 32 · 53 · 55 는 시나리오의 두 기기 줄을 폰 한 대 + PC 가 상대 역할로 옮긴 것). PC 쪽은 e2e/area3_safe_phone.py 의 같은 번호(계정 · 매칭 ·
// 메시지 · 차단 · 정지를 준비하고, 신고 · 차단 · 나감 행은 DB 에서 센다). 앱은 누른 뒤 화면에서 본 것을 Map 으로 돌려준다.
// 화면 글자 · 위젯은 시나리오가 아니라 지금 화면 코드(chat_room_screen · chat_room_menu_sheet · bubble_report_menu · report_sheet ·
// block_confirm_sheet · partner_profile_screen · block_list_screen · poll_card · account_suspended_screen)에서 옮겼다.
// 망 끊기는 PC 가 한다 — 앱은 step 에서 멈춰 PC 가 끝내고 go 를 넣기를 기다린다.

const _reportAction = '신고하기'; // 방 ⋯ 줄 · 14c 링크 · 투표 카드 버튼 · 신고 시트 버튼이 같은 글자다
const _blockAction = '차단하기'; // chat_room_menu_sheet.dart · partner_profile_screen.dart
const _blockConfirm = '차단'; // block_confirm_sheet.dart confirmLabel
const _moreTooltip = '더보기'; // 방 앱바 ⋯ · 내 투표 글 …
const _bubbleMenuLabel = '이 메시지 신고'; // bubble_report_menu.dart
const _offlineLine = '네트워크 연결을 확인해 주세요'; // common/failure.dart:16
const _suspendedTitle = '이용이 제한된 계정이에요'; // account_suspended_screen.dart
const _supportEmail = 'appmailerl4538@gmail.com'; // account_suspended_screen.dart supportEmail
const _withdrawLink = '탈퇴하기'; // account_suspended_screen.dart 글자 버튼(A5)
const _logoutButton = '로그아웃'; // account_suspended_screen.dart AppButton
const _blocksTitle = '차단 목록'; // settings_screen.dart 줄 · block_list_screen.dart 앱바
const _blocksEmpty = '아직 차단한 상대가 없어요'; // block_list_screen.dart:304
const _blocksEmptySub = '신고하거나 차단한 상대가 있으면\n여기에 모여요.'; // block_list_screen.dart
const _contactNotice = '연락처로 차단한 지인은 여기가 아니라 설정 > 연락처 차단에서 관리해요.'; // block_list_screen.dart
const _communityTab = '커뮤니티'; // app_bottom_nav.dart
const _unblock = '해제'; // block_list_screen.dart:257 줄 오른쪽 글자 버튼 · :96 확인 시트 confirmLabel(둘 다 같은 글자)
const _unblockTitle = '차단을 해제할까요?'; // block_list_screen.dart:94 확인 시트 제목
const _trustDone = '신뢰 확인 완료'; // trust_reveal_bubble.dart:49 공개 카드 배지(chat_room_screen.dart:473 — 상대가 나간 · 정지된 방엔 안 그린다)
const _suspendedWord = '정지'; // 정지 사실은 상대 화면 어디에도 글자로 나오면 안 된다(backend chat/gate.py is_gone · chat_room_screen.dart:182 isPartnerGone 이 입력창을 나감 안내로 바꾼다)

bool _has(Finder finder) => finder.evaluate().isNotEmpty;

// ── 신고 시트 · 방 메뉴 ──────────────────────────────────────────────────────────────────────────────

/// 신고 시트의 주색 "신고하기" 버튼(SafetySheetButton). 같은 글자의 메뉴 줄 · 링크와 겹치지 않게 종류까지 짚는다.
Finder get _sheetSubmit => find.widgetWithText(SafetySheetButton, _reportAction);

bool _submitOn(WidgetTester tester) => tester.widget<SafetySheetButton>(_sheetSubmit).onPressed != null;

Finder get _noteField => find.descendant(of: find.byKey(reportNoteBoxKey), matching: find.byType(TextField));

/// 방 앱바 ⋯ 를 눌러 [row]("신고하기" · "차단하기") 줄을 고른다.
Future<void> _roomMenu(WidgetTester tester, String row) async {
  await tap(tester, find.byTooltip(_moreTooltip));
  await pumpUntil(tester, find.text(row));
  await tap(tester, find.text(row));
}

/// 방을 열고 ⋯ → "신고하기" 로 신고 시트까지.
Future<void> _openReportSheet(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  await pumpUntil(tester, find.byType(ChatInputBar));
  await _roomMenu(tester, _reportAction);
  await pumpUntil(tester, find.text(_reportTitle));
}

/// 14c 상대 프로필을 라우터로 바로 연다(방 머리말은 눌리지 않는다 — _partnerReviews 와 같은 길). 제목은 프로필을 읽은 뒤에 뜬다.
Future<void> _openPartnerProfile(WidgetTester tester, Map<String, dynamic> job) async {
  await arrive(tester, 'home');
  unawaited(GoRouter.of(tester.element(screen('home'))).push('${AppRoutes.partnerProfile}/${job['profile_id']}'));
  await pumpUntil(tester, find.text('${job['nickname']} 님 프로필'));
}

/// 14c 맨 아래 링크 줄("신고하기" · "차단하기")의 [label] 을 누른다.
Future<void> _profileLink(WidgetTester tester, String label) async {
  final link = find.text(label);
  await tester.scrollUntilVisible(link, 300,
      scrollable: find.descendant(of: find.byType(PartnerProfileScreen), matching: find.byType(Scrollable)).first);
  await tap(tester, link);
}

/// 시트의 "신고하기" 를 누르고 토스트 글자를 읽는다.
Future<String?> _submitReport(WidgetTester tester) async {
  await tap(tester, _sheetSubmit);
  return _toast(tester);
}

/// 신고 · 차단이 끝나 대화 목록에 닿았는지와 그 방이 목록에서 사라졌는지(목록을 다시 읽을 시간을 준다).
Future<Map<String, Object?>> _afterSafety(WidgetTester tester, String nickname, {String? toast}) async {
  await pumpUntil(tester, find.byType(ConversationsScreen), timeout: const Duration(seconds: 15));
  await wait(tester, const Duration(seconds: 3));
  return {
    'toast': toast,
    'on_list': _has(find.byType(ConversationsScreen)),
    'room_listed': _has(_row(nickname)),
  };
}

/// 사유 [reason] 으로 신고한다 — 입구는 방 ⋯ 또는 14c([fromProfile]).
Future<Map<String, Object?>> _reportThrough(WidgetTester tester, Map<String, dynamic> job, ReportReason reason,
    {required bool fromProfile}) async {
  if (fromProfile) {
    await _openPartnerProfile(tester, job);
    await _profileLink(tester, _reportAction);
    await pumpUntil(tester, find.text(_reportTitle));
  } else {
    await _openReportSheet(tester, job);
  }
  await tap(tester, find.text(reason.label));
  final toast = await _submitReport(tester);
  return _afterSafety(tester, job['nickname'] as String, toast: toast);
}

/// E-SAFE-08 · 09 — "기타" 를 골라 메모 칸을 연다.
Future<void> _pickOther(WidgetTester tester, Map<String, dynamic> job) async {
  await _openReportSheet(tester, job);
  await tap(tester, find.text(ReportReason.other.label));
}

/// 방 메뉴 "차단하기" → 확인 시트("$nickname 님을 차단할까요?")까지.
Future<String> _openBlockConfirm(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  final title = '$nickname 님을 차단할까요?'; // block_confirm_sheet.dart
  await _openRoom(tester, nickname);
  await pumpUntil(tester, find.byType(ChatInputBar));
  await _roomMenu(tester, _blockAction);
  await pumpUntil(tester, find.text(title));
  return title;
}

// ── E-SAFE-05 말풍선 길게 누르기 ─────────────────────────────────────────────────────────────────────

Finder _bubbleOf(String body) => find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == body);

Finder _systemOf(String body) => find.byWidgetPredicate((w) => w is SystemMessage && w.body == body);

/// [target] 을 길게 눌러 "이 메시지 신고" 팝업이 뜨는지 — 떴으면 신고하지 않고 닫는다.
Future<bool> _menuOnLongPress(WidgetTester tester, Finder target) async {
  await pumpUntil(tester, target);
  await tester.ensureVisible(target.first);
  await tester.pump();
  // 위젯 가운데가 아니라 안의 글자를 누른다 — MessageBubble 은 줄 폭 전체를 차지하는 Align 이라 가운데는 말풍선 옆 빈 자리다(상대 말풍선은 왼쪽에 붙는다).
  await tester.longPress(find.descendant(of: target.first, matching: find.byType(Text)).first);
  final shown = await appears(tester, find.text(_bubbleMenuLabel), const Duration(seconds: 2)) != null;
  if (shown) {
    Navigator.of(tester.element(find.text(_bubbleMenuLabel))).pop();
    await wait(tester, const Duration(milliseconds: 500));
  }
  return shown;
}

/// 방에 보이는 모든 Text 중 [word] 가 들어간 것의 수 — "신고" · "차단" · "정지" 같은 글자가 화면에 새지 않았는지.
int _wordCount(WidgetTester tester, String word) => tester
    .widgetList<Text>(find.byType(Text))
    .where((text) => (text.data ?? text.textSpan?.toPlainText() ?? '').contains(word))
    .length;

/// 상대 말풍선([body])을 길게 눌러 "이 메시지 신고" 를 **누르고** 사유 · 시트 제출까지(E-SAFE-04). `_menuOnLongPress` 는 메뉴를 닫아 버려 쓸 수 없다.
Future<String?> _reportBubble(WidgetTester tester, String body, ReportReason reason) async {
  final bubble = _bubbleOf(body);
  await pumpUntil(tester, bubble);
  await tester.ensureVisible(bubble.first);
  await tester.pump();
  // 가운데가 아니라 안의 글자를 누른다 — MessageBubble 은 줄 폭 전체를 차지하는 Align 이다.
  await tester.longPress(find.descendant(of: bubble.first, matching: find.byType(Text)).first);
  await pumpUntil(tester, find.text(_bubbleMenuLabel));
  await tap(tester, find.text(_bubbleMenuLabel));
  await pumpUntil(tester, find.text(_reportTitle));
  await tap(tester, find.text(reason.label));
  return _submitReport(tester);
}

/// 상대가 나간(또는 정지된) 방에서 본 것 — [line] 이 실시간으로 뜨길 기다린 뒤 시스템 줄 전부 · 입력창 자리의 나감 안내 · "신고" · "차단" 글자 수.
/// [prefix] 로 두 방의 값을 한 Map 에 담는다(E-SAFE-03).
Future<Map<String, Object?>> _goneRoomSeen(WidgetTester tester, String line, String prefix) async {
  await appears(tester, _systemOf(line), const Duration(seconds: 15)); // chat_room_screen.dart:505 SystemMessage
  final notice = await _ever(tester, find.text(_partnerGone), const Duration(seconds: 10));
  await wait(tester, const Duration(seconds: 1));
  return {
    '${prefix}lines': [for (final message in tester.widgetList<SystemMessage>(find.byType(SystemMessage, skipOffstage: false))) message.body],
    '${prefix}notice': notice,
    '${prefix}words': _wordCount(tester, '신고') + _wordCount(tester, '차단'),
  };
}

/// 방 앱바 뒤로가기로 목록에 나가 [nickname] 방을 새로 연다(방 뷰모델이 새로 읽힌다).
Future<void> _reopenRoom(WidgetTester tester, String nickname) async {
  await tap(tester, find.byType(BackButton));
  await pumpUntil(tester, _row(nickname)); // 방이 덮고 있는 동안은 목록 줄이 안 보인다
  await tap(tester, _row(nickname));
  await pumpUntil(tester, _roomTitle(nickname));
}

/// E-SAFE-22 — 자동 가림이 된 상대와의 방. 방 읽기가 끝나면 `step` 에서 멈춰 PC 가 B 로 한 건 보내게 하고(≤ 2.0초 표시), 이어 내가 입력해 보내고, 14c 를 연다.
/// 읽기를 못 끝내면 `step` 을 부르지 않고 `loaded: false` 로 끝낸다(구독 전에 보내면 글이 안 온다).
Future<Map<String, Object?>> _chatWithHidden(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  final body = job['body'] as String;
  final text = job['text'] as String;
  await _openRoom(tester, nickname);
  await pumpUntil(tester, find.byType(ChatInputBar));
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final matchId = tester.widget<ChatRoomScreen>(room).matchId;
  final loading = Stopwatch()..start();
  while (container.read(chatRoomViewModelProvider(matchId)).isLoading && loading.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final loaded = container.read(chatRoomViewModelProvider(matchId));
  if (loaded.isLoading || loaded.errorMessage != null) {
    return {'loaded': false, 'error': loaded.errorMessage};
  }
  String? seenAt;
  final sub = container.listen(chatRoomViewModelProvider(matchId), (_, next) {
    if (seenAt == null && next.messages.any((message) => message.body == body)) seenAt = DateTime.now().toUtc().toIso8601String();
  });
  try {
    await step('ready'); // PC 가 B 로 한 건 보낸다
    final watch = Stopwatch()..start();
    while (seenAt == null && watch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500)); // 뷰모델이 글을 가진 프레임엔 말풍선이 아직 안 그려졌을 수 있다
    final bubble = _has(_bubbleOf(body));
    await type(tester, _chatField, text);
    await tap(tester, _sendButton);
    await wait(tester, const Duration(seconds: 3)); // 서버 응답과 실시간 줄이 둘 다 올 시간
    final mine = _bubbles(tester).contains(text);
    unawaited(GoRouter.of(tester.element(room)).push('${AppRoutes.partnerProfile}/${job['profile_id']}'));
    final profile = await _ever(tester, find.text('$nickname 님 프로필'), const Duration(seconds: 15));
    return {'loaded': true, 'seen_at': seenAt, 'bubble': bubble, 'mine': mine, 'profile': profile};
  } finally {
    sub.close();
  }
}

/// E-SAFE-55 — B 가 정지당한 A 의 방을 연다(PC 가 신뢰 확인 통과 · 카톡 공개까지 만든 방). 입력창 자리의 나감 안내 · 공개 카드 · 카톡 아이디 · "정지" 글자 수,
/// 14c 를 라우터로 열었을 때의 토스트, `step('release')`(PC 가 정지를 풂) 뒤 방을 다시 열어 입력창 · 카드 · 카톡이 돌아오고 글이 보내지는지.
Future<Map<String, Object?>> _suspendedPartnerRoom(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  final kakao = job['kakao'] as String;
  await _openRoom(tester, nickname);
  await pumpUntil(tester, find.text(_partnerGone)); // 정지된 상대 = 나간 방과 같은 안내(chat_room_screen.dart:549)
  await wait(tester, const Duration(seconds: 1)); // 공개 카드 · 입력창 자리까지 다 그려지게
  final result = <String, Object?>{
    'gone_notice': true, // pumpUntil 이 기다려 봤다(못 보면 거기서 실패한다)
    'input_during': _has(find.byType(ChatInputBar)),
    'card_during': _has(find.text(_trustDone)),
    'kakao_during': _has(find.text(kakao)),
    'words_during': _wordCount(tester, _suspendedWord),
  };
  unawaited(GoRouter.of(tester.element(find.byType(ChatRoomScreen))).push('${AppRoutes.partnerProfile}/${job['profile_id']}'));
  result['toast'] = await _toast(tester); // 방 머리말은 눌리지 않아 라우터로 연다 — 정지된 상대의 14c 는 "프로필을 찾을 수 없어요" 토스트와 함께 닫힌다
  result['words_after_toast'] = _wordCount(tester, _suspendedWord);
  await wait(tester, const Duration(seconds: 2));
  final profile = find.byType(PartnerProfileScreen);
  result['profile_open'] = _has(profile);
  if (_has(profile)) Navigator.of(tester.element(profile)).pop();
  await wait(tester, const Duration(milliseconds: 500));
  await step('release'); // PC 가 방 머리말 · 보내기 시도를 보고 A 를 active 로 되돌린다
  await _reopenRoom(tester, nickname);
  result['input_after'] = await _ever(tester, find.byType(ChatInputBar), const Duration(seconds: 15));
  result['card_after'] = await _ever(tester, find.text(_trustDone), const Duration(seconds: 15));
  result['kakao_after'] = _has(find.text(kakao));
  final text = job['text'] as String;
  await type(tester, _chatField, text);
  await tap(tester, _sendButton);
  await wait(tester, const Duration(seconds: 3)); // 서버 응답과 실시간 줄이 둘 다 올 시간
  result['bubble'] = _bubbles(tester).contains(text);
  return result;
}

// ── 차단 목록 16f ────────────────────────────────────────────────────────────────────────────────────

/// 홈 → 나 탭 → 톱니바퀴 → 설정 → "차단 목록".
Future<void> _openBlockList(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byIcon(AppIcons.settings));
  await tap(tester, find.byIcon(AppIcons.settings));
  await arrive(tester, 'settings');
  final row = find.text(_blocksTitle);
  if (!_has(row)) {
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
  }
  await tap(tester, row);
  await pumpUntil(tester, find.descendant(of: find.byType(AppBar), matching: find.text(_blocksTitle)));
}

// ── 투표 글 E-SAFE-11 ────────────────────────────────────────────────────────────────────────────────

Finder _pollCard(String question) => find.byWidgetPredicate((w) => w is PollCard && w.poll.question == question);

final Map<String, Area1Case> area3CasesSafe = {
  'E-SAFE-01': _session((tester, job) async {
    await _openReportSheet(tester, job);
    // 사유 순서는 화면 위치(위 → 아래)로 읽는다 — enum 순서가 아니라 보이는 순서다.
    final labels = [for (final reason in ReportReason.values) reason.label];
    final tops = {for (final label in labels) label: tester.getTopLeft(find.text(label)).dy};
    final shown = (labels.toList()..sort((a, b) => tops[a]!.compareTo(tops[b]!)));
    final rows = find.byWidgetPredicate((w) => w is Semantics && w.properties.inMutuallyExclusiveGroup == true).evaluate().length;
    final before = _submitOn(tester);
    await tap(tester, find.text(ReportReason.spam.label)); // 대조군: 하나 고르면 켜진다
    return {
      'title': _has(find.text(_reportTitle)) ? _reportTitle : null,
      'reasons': shown,
      'rows': rows,
      'submit_before': before,
      'submit_after': _submitOn(tester),
    };
  }),
  'E-SAFE-02': _session((tester, job) => _reportThrough(tester, job, ReportReason.spam, fromProfile: false)),
  'E-SAFE-03': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    final other = job['other'] as String;
    await _openRoom(tester, nickname);
    await pumpUntil(tester, find.byType(ChatInputBar)); // 아직 둘 다 말짱한 방
    await step('reported'); // PC: A 가 B(폰 계정)를 신고하고, 다른 방의 C 가 보통 나가기
    final reported = await _goneRoomSeen(tester, '$nickname님이 채팅방을 나갔어요', ''); // chat/repository.py:183 의 문장 — 앱은 조립하지 않는다
    await _reopenRoom(tester, other);
    return {...reported, ...await _goneRoomSeen(tester, '$other님이 채팅방을 나갔어요', 'other_')};
  }),
  'E-SAFE-04': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _openRoom(tester, nickname);
    await pumpUntil(tester, find.byType(ChatInputBar));
    final toast = await _reportBubble(tester, job['theirs'] as String, ReportReason.abuse);
    return _afterSafety(tester, nickname, toast: toast);
  }),
  'E-SAFE-05': _session((tester, job) async {
    await _openRoom(tester, job['nickname'] as String);
    await pumpUntil(tester, find.byType(ChatInputBar));
    // 상대 말풍선이 대조군이다 — 거기서 메뉴가 안 뜨면 아래 둘의 "없음" 은 길게 누르기가 안 된 것일 수도 있다.
    final onTheirs = await _menuOnLongPress(tester, _bubbleOf(job['theirs'] as String));
    final onMine = await _menuOnLongPress(tester, _bubbleOf(job['mine'] as String));
    final onSystem = await _menuOnLongPress(tester, _systemOf(job['system'] as String));
    return {'menu_on_mine': onMine, 'menu_on_system': onSystem, 'menu_on_theirs': onTheirs};
  }),
  'E-SAFE-06': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _openRoom(tester, nickname);
    await pumpUntil(tester, find.text(_partnerGone)); // 입력창 대신 나감 안내 — `_openReportSheet` 의 ChatInputBar 기다림을 쓰지 않는다
    final input = _has(find.byType(ChatInputBar));
    await _roomMenu(tester, _reportAction);
    await pumpUntil(tester, find.text(_reportTitle));
    await tap(tester, find.text(ReportReason.spam.label));
    final toast = await _submitReport(tester);
    return {'gone_notice': true, 'input_bar': input, ...await _afterSafety(tester, nickname, toast: toast)};
  }),
  'E-SAFE-07': _session((tester, job) => _reportThrough(tester, job, ReportReason.spam, fromProfile: true)),
  'E-SAFE-08': _session((tester, job) async {
    await _openReportSheet(tester, job);
    final boxBefore = _has(find.byKey(reportNoteBoxKey)); // 사유를 고르기 전에는 메모 칸이 없다
    await tap(tester, find.text(ReportReason.other.label));
    final box = _has(find.byKey(reportNoteBoxKey));
    final empty = _submitOn(tester);
    await type(tester, _noteField, '   ');
    final blank = _submitOn(tester);
    await type(tester, _noteField, job['note'] as String);
    final filled = _submitOn(tester);
    final toast = await _submitReport(tester);
    return {
      'note_box_before': boxBefore,
      'note_box': box,
      'submit_empty': empty,
      'submit_blank': blank,
      'submit_filled': filled,
      ...await _afterSafety(tester, job['nickname'] as String, toast: toast),
    };
  }),
  'E-SAFE-09': _session((tester, job) async {
    await _pickOther(tester, job);
    await type(tester, _noteField, _pasted(job));
    final counter = find.descendant(
      of: find.byKey(reportNoteBoxKey),
      matching: find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+ / \d+$').hasMatch(w.data ?? '')),
    );
    final length = fieldText(tester, _noteField).runes.length;
    final shown = _has(counter) ? tester.widget<Text>(counter.first).data : null;
    final toast = await _submitReport(tester);
    return {
      'input_len': length,
      'counter': shown,
      ...await _afterSafety(tester, job['nickname'] as String, toast: toast),
    };
  }),
  'E-SAFE-11': _session((tester, job) async {
    await arrive(tester, 'home');
    await tap(tester, _tab(_communityTab));
    await pumpUntil(tester, find.byType(PollCard));
    final mine = _pollCard(job['own'] as String);
    final theirs = _pollCard(job['question'] as String);
    final feed = find.byType(Scrollable).first;
    // 새 글이 위다 — 내 글(나중에 올림) → 남의 글 순으로 내려가며, 화면에 있을 때 바로 읽는다(목록은 보이는 카드만 만든다).
    await tester.scrollUntilVisible(mine, 300, scrollable: feed);
    final ownEntry = _has(find.descendant(of: mine, matching: find.text(_reportAction)));
    final ownMore = _has(find.descendant(of: mine, matching: find.byTooltip(_moreTooltip)));
    await tester.scrollUntilVisible(theirs, 300, scrollable: feed);
    final reportButton = find.descendant(of: theirs, matching: find.text(_reportAction));
    final entry = _has(reportButton);
    await tap(tester, reportButton);
    await pumpUntil(tester, find.text(_reportTitle));
    await tap(tester, find.text(_abuse));
    final toast = await _submitReport(tester);
    await wait(tester, const Duration(seconds: 1)); // 시트가 닫히는 애니메이션
    return {
      'entry': entry,
      'own_entry': ownEntry,
      'own_more': ownMore,
      'toast': toast,
      'card': _has(theirs),
    };
  }),
  'E-SAFE-13': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _openRoom(tester, nickname);
    await pumpUntil(tester, find.byType(ChatInputBar));
    await step('api'); // PC 가 같은 상대를 API 로 먼저 신고한다 — 신고 + 차단 + 나감이 이미 일어났다
    await _roomMenu(tester, _reportAction);
    await pumpUntil(tester, find.text(_reportTitle));
    await tap(tester, find.text(_abuse));
    final toast = await _submitReport(tester);
    return _afterSafety(tester, nickname, toast: toast);
  }),
  'E-SAFE-15': _session((tester, job) async {
    await _openReportSheet(tester, job);
    await tap(tester, find.text(_abuse));
    final toast = await _submitReport(tester);
    await wait(tester, const Duration(seconds: 2));
    return {
      'toast': toast,
      'in_room': _has(find.byType(ChatRoomScreen)),
      'on_list': _has(find.byType(ConversationsScreen)),
    };
  }),
  'E-SAFE-18': _session((tester, job) => _reportThrough(tester, job, ReportReason.spam, fromProfile: false)),
  'E-SAFE-22': _session(_chatWithHidden),
  'E-SAFE-25': _session((tester, job) async {
    await _openBlockConfirm(tester, job);
    await tap(tester, find.widgetWithText(SafetySheetButton, _blockConfirm));
    return _afterSafety(tester, job['nickname'] as String);
  }),
  'E-SAFE-26': _session((tester, job) async {
    final title = await _openBlockConfirm(tester, job);
    await tap(tester, find.widgetWithText(SafetySheetButton, _cancel));
    await wait(tester, const Duration(seconds: 1));
    return {
      'sheet_seen': true, // _openBlockConfirm 이 시트 제목을 기다려 봤다(못 보면 거기서 실패한다)
      'sheet_closed': !_has(find.text(title)),
      'in_room': _has(find.byType(ChatRoomScreen)),
      'on_list': _has(find.byType(ConversationsScreen)),
    };
  }),
  'E-SAFE-27': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _openPartnerProfile(tester, job);
    await _profileLink(tester, _blockAction);
    await pumpUntil(tester, find.text('$nickname 님을 차단할까요?'));
    await tap(tester, find.widgetWithText(SafetySheetButton, _blockConfirm));
    return _afterSafety(tester, nickname);
  }),
  'E-SAFE-28': _session((tester, job) async {
    await arrive(tester, 'home');
    unawaited(GoRouter.of(tester.element(screen('home'))).push('${AppRoutes.partnerProfile}/${job['profile_id']}'));
    final toast = await _toast(tester); // 상대가 나를 막았다 — 14c 는 "프로필을 찾을 수 없어요" 토스트와 함께 닫힌다
    await wait(tester, const Duration(seconds: 2));
    return {
      'toast': toast,
      'profile_open': _has(find.byType(PartnerProfileScreen)),
      'on_home': _has(screen('home')),
    };
  }),
  'E-SAFE-30': _session((tester, job) async {
    await _openBlockList(tester);
    await pumpUntil(tester, find.byKey(blockedRowKey));
    await wait(tester, const Duration(seconds: 1));
    final rows = find.byKey(blockedRowKey);
    final lines = <Map<String, Object?>>[];
    for (var i = 0; i < rows.evaluate().length; i++) {
      final texts = tester.widgetList<Text>(find.descendant(of: rows.at(i), matching: find.byType(Text))).map((t) => t.data ?? '').toList();
      lines.add({'nickname': texts.first, 'date': texts.length > 1 ? texts[1] : null, 'button': texts.last});
    }
    final avatars = find.byKey(blockedAvatarKey);
    final drawn = [
      for (var i = 0; i < avatars.evaluate().length; i++)
        if (_has(find.descendant(of: avatars.at(i), matching: find.byType(CachedNetworkImage)))) i,
    ];
    return {
      'rows': lines,
      'avatars': drawn.length,
      'notice': _has(find.text(_contactNotice)),
      'reason_words': _has(find.textContaining('신고')) || _has(find.textContaining('사유')),
    };
  }),
  'E-SAFE-31': _session((tester, job) async {
    await _openBlockList(tester);
    final empty = await appears(tester, find.text(_blocksEmpty), const Duration(seconds: 15)) != null;
    return {
      'empty': empty,
      'sub': _has(find.text(_blocksEmptySub)),
      'rows': find.byKey(blockedRowKey).evaluate().length,
    };
  }),
  'E-SAFE-32': _session((tester, job) async {
    final nickname = job['nickname'] as String;
    await _openBlockList(tester);
    final row = find.ancestor(of: find.text(nickname), matching: find.byKey(blockedRowKey));
    await pumpUntil(tester, row);
    final before = _has(row);
    await tap(tester, find.descendant(of: row, matching: find.text(_unblock)));
    await pumpUntil(tester, find.text(_unblockTitle));
    await tap(tester, find.widgetWithText(SafetySheetButton, _unblock));
    final watch = Stopwatch()..start();
    while (_has(row) && watch.elapsed < const Duration(seconds: 15)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final empty = await _ever(tester, find.text(_blocksEmpty), const Duration(seconds: 10));
    return {'sheet': true, 'row_before': before, 'row_after': _has(row), 'empty': empty}; // 'sheet' — pumpUntil 이 확인 시트 제목을 기다려 봤다
  }),
  'E-SAFE-50': _session((tester, job) async {
    await _toConversations(tester);
    await pumpUntil(tester, _row(job['nickname'] as String));
    await step('suspend'); // PC 가 status=suspended 로 바꾼다
    // 당겨서 새로고침 — 손가락 끌기가 안 먹으면 같은 새로고침 표시기를 직접 띄운다(어느 쪽인지 pulled 로 말한다).
    var pulled = 'drag';
    final list = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(CustomScrollView)).first;
    await tester.fling(list, const Offset(0, 400), 1000);
    var at = await appears(tester, screen('suspended'), const Duration(seconds: 6));
    if (at == null) {
      pulled = 'show';
      unawaited(tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
      at = await appears(tester, screen('suspended'), const Duration(seconds: 10));
    }
    must(at != null, '정지 안내 화면이 안 나옴(새로고침 $pulled)');
    final buttons = tester.widgetList<AppButton>(find.byType(AppButton)).map((b) => b.label).toList();
    final result = <String, Object?>{
      'title': _has(find.text(_suspendedTitle)),
      'support': _has(find.textContaining(_supportEmail)),
      'buttons': buttons,
      'withdraw_link': _has(find.widgetWithText(TextButton, _withdrawLink)),
      'pulled': pulled,
    };
    final router = GoRouter.of(tester.element(screen('suspended')));
    final stays = <String, bool>{};
    for (final path in [AppRoutes.home, AppRoutes.conversations]) {
      router.go(path);
      await wait(tester, const Duration(seconds: 2));
      stays[path] = _has(screen('suspended')) && !_has(screen('home')) && !_has(find.byType(ConversationsScreen));
    }
    return {...result, 'stays': stays};
  }),
  'E-SAFE-53': _session(_homeAfterLogin), // 알림만 본다 — 앱은 로그인 뒤 홈에서 끝나고 PC 가 프로세스를 죽인다(area3_b3.dart · E-CHAT-50 의 login 판과 같은 길)
  'E-SAFE-55': _session(_suspendedPartnerRoom),
  'E-SAFE-57': _session((tester, job) async {
    await arrive(tester, 'suspended'); // 정지된 채 로그인 — 첫 요청이 403
    final again = await step('relogin'); // PC 가 정지를 풀고 새 로그인 토큰을 go 에 실어 준다
    await tap(tester, button(_logoutButton));
    await arrive(tester, 'start', timeout: const Duration(seconds: 15));
    await signIn(again['token_hash'] as String); // 같은 프로세스 — 로그아웃마다 계정 상태가 새로 시작하는지(Ruling 36)
    await arrive(tester, 'home', timeout: const Duration(seconds: 40));
    final text = job['text'] as String;
    await _openRoom(tester, job['nickname'] as String);
    await pumpUntil(tester, find.byType(ChatInputBar));
    await type(tester, _chatField, text);
    await tap(tester, _sendButton);
    await wait(tester, const Duration(seconds: 3)); // 서버 응답과 실시간 줄이 둘 다 올 시간
    return {
      'suspended_first': true, // arrive 가 못 닿았으면 위에서 실패했다
      'home_after': true,
      'bubble': _bubbles(tester).contains(text),
    };
  }),
  'E-SAFE-60': _session((tester, job) async {
    await _openReportSheet(tester, job);
    await tap(tester, find.text(ReportReason.spam.label));
    await step('cut'); // PC 가 망을 끊는다
    await tap(tester, _sheetSubmit);
    final error = await appears(tester, find.text(_offlineLine), const Duration(seconds: 25));
    final first = {
      'error': error != null,
      'sheet_open': _has(find.text(_reportTitle)),
      'toast': _toastNow(tester),
      'in_room': _has(find.byType(ChatRoomScreen)),
    };
    await step('restore'); // PC 가 reports 0 을 확인하고 망을 켠다
    final toast = await _submitReport(tester);
    return {'first': first, 'second': await _afterSafety(tester, job['nickname'] as String, toast: toast)};
  }),
  'E-SAFE-61': _session((tester, job) async {
    final title = await _openBlockConfirm(tester, job);
    await step('cut'); // PC 가 망을 끊는다
    await tap(tester, find.widgetWithText(SafetySheetButton, _blockConfirm));
    final error = await appears(tester, find.text(_offlineLine), const Duration(seconds: 25));
    await wait(tester, const Duration(seconds: 1));
    final line = find.text(_offlineLine);
    return {
      'error': error != null,
      'in_room': _has(find.byType(ChatRoomScreen)),
      'confirm_closed': !_has(find.text(title)),
      // 입력창 위 한 줄 — 문구가 입력 바보다 위쪽에 그려진다(chat_room_screen.dart `_ErrorLine`).
      'above_input': _has(line) && _has(find.byType(ChatInputBar)) &&
          tester.getTopLeft(line.first).dy < tester.getTopLeft(find.byType(ChatInputBar)).dy,
    };
  }),
};
