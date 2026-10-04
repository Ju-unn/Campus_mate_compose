part of 'area3.dart';

// 영역 3 폰 A 한 대 2차 — 채팅 · 지인 리뷰에서 앱이 입력하고 누르는 19개. PC 쪽은 e2e/area3_phone2.py 의 같은 번호(계정 · 매칭 · 추천 연결 ·
// 리뷰를 준비하고, 보낸 글 · 쓴 리뷰 · 신고 행은 DB 에서 센다). 앱은 누르고 입력한 뒤 화면에서 본 것을 Map 으로 돌려준다.
// 화면 글자 · 위젯은 시나리오가 아니라 지금 화면 코드(chat_input_bar · chat_room_screen · trust_gate_sheet · friend_review_compose_sheet ·
// written/received_reviews_screen · report_sheet)에서 옮겼다. 글자를 길게 넣는 가설은 PC 가 코드포인트 목록(`paste.runes` × `paste.count`)을
// 주고 앱이 String.fromCharCodes 로 만든다 — 이모지를 JSON · 소스 문자열로 건너지 않는다.

const _reportTitle = '무엇을 신고할까요?'; // report_sheet.dart:56
const _abuse = '욕설·비방·혐오'; // report_reason.dart:5 — ReportReason.abuse
const _acceptBanner = '수락하기'; // chat_room_screen.dart:387 — 미리 수락 배너 버튼
const _acceptSheet = '수락하고 공유하기'; // trust_gate_sheet.dart:90
const _acceptConfirm = '수락'; // chat_dialogs.dart:27 — 확인 창
const _cancel = '취소'; // written_reviews_screen · chat_dialogs 의 취소

/// PC 가 준 `paste` — 코드포인트 목록 × 횟수.
String _pasted(Map<String, dynamic> job) {
  final paste = job['paste'] as Map<String, dynamic>;
  return String.fromCharCodes((paste['runes'] as List).cast<int>()) * (paste['count'] as int);
}

// ── 채팅 입력 ────────────────────────────────────────────────────────────────────────────────────────

Finder get _chatField => find.descendant(of: find.byType(ChatInputBar), matching: find.byType(TextField));

/// 보내기 원형 버튼(chat_input_bar.dart `_SendButton`) — 입력 바 안의 InkWell 은 이것 하나다.
Finder get _sendButton => find.descendant(of: find.byType(ChatInputBar), matching: find.byType(InkWell)).last;

String _chatText(WidgetTester tester) => tester.widget<TextField>(_chatField).controller?.text ?? '';

bool _sendEnabled(WidgetTester tester) => tester.widget<InkWell>(_sendButton).onTap != null;

/// 방 뷰모델이 들고 있는 화면 오류 문구(`_ErrorLine` 이 그린다). 없으면 null.
String? _roomError(WidgetTester tester) {
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  return container.read(chatRoomViewModelProvider(tester.widget<ChatRoomScreen>(room).matchId)).errorMessage;
}

/// 방을 열고 입력칸에 [text] 를 넣는다.
Future<void> _openAndType(WidgetTester tester, Map<String, dynamic> job, String text) async {
  await _openRoom(tester, job['nickname'] as String);
  await pumpUntil(tester, find.byType(ChatInputBar));
  await type(tester, _chatField, text);
}

/// E-CHAT-11 · 12 · 13 — 길게 붙여 넣고 보낸다. 입력칸 글자 수는 코드포인트로 센다(시나리오 기준, `.length` 는 UTF-16).
Future<Map<String, Object?>> _longSend(WidgetTester tester, Map<String, dynamic> job) async {
  await _openAndType(tester, job, _pasted(job));
  final inputLen = _chatText(tester).runes.length;
  await tap(tester, _sendButton);
  await wait(tester, const Duration(seconds: 3));
  return {'input_len': inputLen, 'error': _roomError(tester)};
}

/// E-CHAT-43 — 수락 확인 창(배너) 또는 14f 시트(sheet)의 수락을 같은 프레임에 두 번 누른다(pump 없이 연달아 tap).
Future<Map<String, Object?>> _acceptTwice(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final matchId = tester.widget<ChatRoomScreen>(room).matchId;
  if (job['variant'] == 'sheet') {
    await pumpUntil(tester, find.text(_sheetTitle));
    final accept = button(_acceptSheet);
    await tester.tap(accept);
    await tester.tap(accept, warnIfMissed: false);
  } else {
    await pumpUntil(tester, button(_acceptBanner));
    await tap(tester, button(_acceptBanner));
    final confirm = find.widgetWithText(TextButton, _acceptConfirm);
    await pumpUntil(tester, confirm);
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
  }
  await wait(tester, const Duration(seconds: 4)); // 응답 · 방 다시 읽기
  return {'error': container.read(chatRoomViewModelProvider(matchId)).errorMessage};
}

// ── 지인 리뷰 쓰기 ───────────────────────────────────────────────────────────────────────────────────

Finder _chip(String tag) => find.widgetWithText(TextButton, tag);

Finder get _commentField =>
    find.descendant(of: find.byKey(friendReviewCommentBoxKey), matching: find.byType(TextField));

Finder get _submit => find.byKey(friendReviewSubmitKey);

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<InkWell>(find.descendant(of: _submit, matching: find.byType(InkWell))).onTap != null;

List<String> _chosen(WidgetTester tester, Map<String, dynamic> job) {
  final container = ProviderScope.containerOf(tester.element(find.byType(FriendReviewComposeSheet)));
  return container.read(friendReviewComposeViewModelProvider(job['profile_id'] as String)).selected;
}

/// 고른 칩의 선택 표시 — 칩은 `Semantics(selected: …)` 로 감싼다(그 밖의 selected 는 시트에 없다).
int _marks(WidgetTester tester) => find
    .descendant(
      of: find.byType(FriendReviewComposeSheet),
      matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true),
    )
    .evaluate()
    .length;

/// 화면에 떠 있는 토스트 글자(없으면 null). 시트 안 토스트도 같은 AppToast 다.
String? _toastNow(WidgetTester tester) {
  final toasts = find.byType(AppToast);
  return toasts.evaluate().isEmpty ? null : tester.widget<AppToast>(toasts.first).label;
}

/// [within] 안에 토스트가 뜨면 그 글자, 아니면 null.
Future<String?> _toast(WidgetTester tester, {Duration within = const Duration(seconds: 15)}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < within) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_toastNow(tester) case final String label) return label;
  }
  return null;
}

/// 20b 를 열고 일감의 `tags` 를 차례로 누른 뒤 `paste` 가 있으면 한마디 칸에 붙여 넣는다.
Future<void> _fillCompose(WidgetTester tester, Map<String, dynamic> job) async {
  await arrive(tester, 'home');
  GoRouter.of(tester.element(screen('home'))).go('${AppRoutes.friendReviewWrite}/${job['profile_id']}');
  await pumpUntil(tester, find.text(_tagQuestion));
  await pumpUntil(tester, _submit);
  for (final tag in ((job['tags'] as List?) ?? const []).cast<String>()) {
    await tap(tester, _chip(tag));
  }
  if (job['paste'] != null) await type(tester, _commentField, _pasted(job));
}

/// E-REV-01 · 02 · 04 · 06 · 07 — 채우고 "리뷰 남기기". 누르기 전 고른 수 · 선택 표시와, 누른 뒤 토스트 · 시트 닫힘.
Future<Map<String, Object?>> _composeAndSubmit(WidgetTester tester, Map<String, dynamic> job) async {
  await _fillCompose(tester, job);
  final selected = _chosen(tester, job).length;
  final marks = _marks(tester);
  await tap(tester, _submit);
  final toast = await _toast(tester);
  await wait(tester, const Duration(seconds: 1)); // 시트가 닫히는 애니메이션
  return {
    'selected': selected,
    'marks': marks,
    'toast': toast,
    'closed': find.text(_tagQuestion).evaluate().isEmpty,
  };
}

// ── 나 탭 → 지인 리뷰 목록 · 신고 ────────────────────────────────────────────────────────────────────

/// 나 탭 → "친구들이 본 나"(received) 또는 "내가 쓴 리뷰" → 카드가 그려질 때까지. 그 화면을 돌려준다.
Future<Finder> _openReviews(WidgetTester tester, {required bool received}) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byType(MyProfileScreen));
  final entry = find.text(received ? _receivedEntry : _writtenEntry);
  await tester.scrollUntilVisible(entry, 300,
      scrollable: find.descendant(of: find.byType(MyProfileScreen), matching: find.byType(Scrollable)).first);
  await tap(tester, entry);
  final page = find.byType(received ? ReceivedReviewsScreen : WrittenReviewsScreen);
  await pumpUntil(tester, find.descendant(of: page, matching: find.byType(FriendReviewCard)));
  await wait(tester, const Duration(seconds: 2)); // 들어올 때 다시 읽기
  return page;
}

int _cardCount(Finder page) => find.descendant(of: page, matching: find.byType(FriendReviewCard)).evaluate().length;

/// E-REV-36 · 37 — 받은 리뷰 카드 깃발 → 사유 "욕설·비방·혐오" → "신고하기". 토스트 · 카드 · 시트가 닫혔는지.
Future<Map<String, Object?>> _reportCard(WidgetTester tester, Map<String, dynamic> job) async {
  final page = await _openReviews(tester, received: true);
  await tap(tester, find.descendant(of: page, matching: find.byTooltip(_flag)).first);
  await pumpUntil(tester, find.text(_reportTitle));
  await tap(tester, find.text(_abuse));
  await tap(tester, find.widgetWithText(SafetySheetButton, _flag));
  final toast = await _toast(tester);
  await wait(tester, const Duration(seconds: 1)); // 시트가 닫히는 애니메이션
  return {
    'toast': toast,
    'cards': _cardCount(page),
    'sheet_open': find.text(_reportTitle).evaluate().isNotEmpty,
  };
}

final Map<String, Area1Case> area3Cases2 = {
  'E-CHAT-04': _session((tester, job) async {
    final text = job['text'] as String;
    await _openAndType(tester, job, text);
    await tap(tester, _sendButton);
    await wait(tester, const Duration(seconds: 3)); // 서버 응답과 실시간 줄이 둘 다 올 시간
    return {'lines': _bubbles(tester).where((body) => body == text).length};
  }),
  'E-CHAT-05': _session((tester, job) async {
    await _openAndType(tester, job, job['text'] as String);
    for (var i = 0; i < 5; i++) {
      await tester.tap(_sendButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await wait(tester, const Duration(seconds: 3));
    return null;
  }),
  'E-CHAT-11': _session(_longSend),
  'E-CHAT-12': _session(_longSend),
  'E-CHAT-13': _session(_longSend),
  'E-CHAT-15': _session((tester, job) async {
    await _openAndType(tester, job, _pasted(job));
    final enabled = _sendEnabled(tester);
    await tester.tap(_sendButton, warnIfMissed: false); // 꺼진 버튼을 눌러도 아무 일 없다
    await wait(tester, const Duration(seconds: 1));
    return {'send_enabled': enabled};
  }),
  'E-CHAT-25': _session((tester, job) async {
    await _openAndType(tester, job, job['text'] as String);
    await step('cut'); // PC 가 망을 끊는다
    await tap(tester, _sendButton);
    final watch = Stopwatch()..start();
    while (_roomError(tester) == null && watch.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await wait(tester, const Duration(seconds: 1)); // 실패하면 쓴 글을 입력칸에 되돌린다
    return {'error': _roomError(tester), 'input': _chatText(tester)};
  }),
  'E-CHAT-43': _session(_acceptTwice),
  'E-REV-01': _session(_composeAndSubmit),
  'E-REV-02': _session(_composeAndSubmit),
  'E-REV-03': _session((tester, job) async {
    await _fillCompose(tester, job); // 태그 없이 한마디만
    final enabled = _submitEnabled(tester);
    final selected = _chosen(tester, job).length;
    await tester.tap(_submit, warnIfMissed: false); // 꺼진 버튼을 눌러도 요청은 안 나간다
    await wait(tester, const Duration(seconds: 1));
    return {'submit_enabled': enabled, 'selected': selected};
  }),
  'E-REV-04': _session(_composeAndSubmit),
  'E-REV-05': _session((tester, job) async {
    await _fillCompose(tester, job);
    final counter = find.descendant(
      of: find.byKey(friendReviewCommentBoxKey),
      matching: find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+ / \d+$').hasMatch(w.data ?? '')),
    );
    return {
      'input_len': (tester.widget<TextField>(_commentField).controller?.text ?? '').runes.length,
      'counter': counter.evaluate().isEmpty ? null : tester.widget<Text>(counter.first).data,
    };
  }),
  'E-REV-06': _session(_composeAndSubmit),
  'E-REV-07': _session(_composeAndSubmit),
  'E-REV-11': _session((tester, job) async {
    await _fillCompose(tester, job);
    await step('api'); // PC 가 같은 상대에게 API 로 먼저 쓴다
    await tap(tester, _submit); // 서버가 409 로 막는다 — 시트 안 토스트
    return {'toast': await _toast(tester)};
  }),
  'E-REV-25': _session((tester, job) async {
    final page = await _openReviews(tester, received: false);
    await tap(tester, find.descendant(of: page, matching: find.byTooltip(_trash)).first);
    await pumpUntil(tester, button(_cancel));
    await tap(tester, button(_cancel));
    await wait(tester, const Duration(seconds: 1));
    return {'cards': _cardCount(page), 'confirm_open': button(_cancel).evaluate().isNotEmpty, 'toast': _toastNow(tester)};
  }),
  'E-REV-36': _session(_reportCard),
  'E-REV-37': _session(_reportCard),
};
