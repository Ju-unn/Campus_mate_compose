part of 'area3.dart';

// 영역 3 폰 A 한 대 8차 — 채팅 · 지인 리뷰 8개(E-CHAT-10 · 16 · E-REV-20 · 24 · 27 · 31 · 34 · 35). PC 쪽은 e2e/area3_phone8.py 의 같은 번호
// (계정 · 매칭 · 추천 연결 · 리뷰를 준비하고, 보낸 글 · 쓴 리뷰 행은 DB 에서 센다). E-CHAT-68 은 폰이 필요 없어 이 파일에 없다.
// 이미 있는 것(입력 · 쓰기 시트 · 목록 열기 · 토스트)은 area3.dart · area3_b2.dart 의 것을 그대로 쓴다.

const _deleteSheetTitle = '리뷰를 지울까요?'; // written_reviews_screen.dart:25 — 20e-2 확인 시트
const _deleteConfirm = '지우기'; // written_reviews_screen.dart:182

/// E-CHAT-10 — 방을 열고 `step` 에서 멈춘다. PC 가 그사이 A 로 [body] 를 보내면 방 뷰모델이 그 글을 처음 가진 앱 시계(UTC)와 말풍선이 그려졌는지를 말한다.
/// 보낸 시각은 PC 가 서버가 찍은 messages.created_at 으로 읽는다 — 폰 시계와 서버 시계의 차가 섞인다(PC 메모에 남는다).
Future<Map<String, Object?>> _liveBody(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final body = job['body'] as String;
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final matchId = tester.widget<ChatRoomScreen>(room).matchId;
  String? seenAt;
  final sub = container.listen(chatRoomViewModelProvider(matchId), (_, next) {
    if (seenAt == null && next.messages.any((message) => message.body == body)) seenAt = DateTime.now().toUtc().toIso8601String();
  });
  try {
    await step('ready'); // PC 가 A 로 한 건 보낸다
    final watch = Stopwatch()..start();
    while (seenAt == null && watch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500)); // 뷰모델이 글을 가진 프레임엔 말풍선이 아직 안 그려졌을 수 있다
    final bubble = find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == body, skipOffstage: false).evaluate().isNotEmpty;
    return {'seen_at': seenAt, 'bubble': bubble};
  } finally {
    sub.close();
  }
}

/// 나 탭 지인 리뷰 칸의 개수 글자("받은 리뷰 2개" · "쓴 리뷰 1개") — 읽는 중엔 비어 있어 숫자가 보일 때까지 기다린다. 나 탭이 열려 있어야 한다.
Future<Map<String, Object?>> _myTabCounts(WidgetTester tester) async {
  final scrollable = find.descendant(of: find.byType(MyProfileScreen), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(find.text(_writtenEntry), 300, scrollable: scrollable);
  Finder note(String label) => find.byWidgetPredicate((w) => w is Text && RegExp('^$label \\d+개\$').hasMatch(w.data ?? ''));
  await pumpUntil(tester, note('받은 리뷰'));
  await pumpUntil(tester, note('쓴 리뷰'));
  String? text(Finder finder) => tester.widget<Text>(finder.first).data;
  return {'received': text(note('받은 리뷰')), 'written': text(note('쓴 리뷰'))};
}

/// E-REV-24 — "내가 쓴 리뷰" 첫 카드 휴지통 → 시트 "리뷰를 지울까요?" → "지우기". 토스트 · 남은 카드 수, 나 탭으로 돌아와 개수.
Future<Map<String, Object?>> _deleteWritten(WidgetTester tester, Map<String, dynamic> job) async {
  final page = await _openReviews(tester, received: false);
  await tap(tester, find.descendant(of: page, matching: find.byTooltip(_trash)).first);
  await pumpUntil(tester, find.text(_deleteSheetTitle));
  await tap(tester, button(_deleteConfirm));
  final toast = await _toast(tester);
  await wait(tester, const Duration(seconds: 1)); // 시트가 닫히고 카드가 빠지는 시간
  final cards = _cardCount(page);
  Navigator.of(tester.element(page)).pop();
  await wait(tester, const Duration(seconds: 1));
  return {'toast': toast, 'cards': cards, ...await _myTabCounts(tester)};
}

/// E-REV-31 · 35 — 14c(상대 프로필)의 지인 리뷰 칸 카드 수. 0개면 칸 자체가 없어 [_partnerReviews] 처럼 카드가 뜨길 기다릴 수 없다 —
/// 대신 목록 뷰모델이 읽기를 끝낼 때까지 기다리고, 끝났는지 · 오류가 없었는지를 함께 말한다.
Future<Map<String, Object?>> _aboutCards(WidgetTester tester, Map<String, dynamic> job) async {
  final profileId = job['about'] as String;
  await arrive(tester, 'home');
  unawaited(GoRouter.of(tester.element(screen('home'))).push('${AppRoutes.partnerProfile}/$profileId'));
  await pumpUntil(tester, find.text('${job['nickname']} 님 프로필'));
  final container = ProviderScope.containerOf(tester.element(find.byType(PartnerProfileScreen)));
  final provider = friendReviewListViewModelProvider((source: FriendReviewListSource.about, profileId: profileId));
  final watch = Stopwatch()..start();
  while (container.read(provider).isLoading && watch.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await wait(tester, const Duration(seconds: 1)); // 카드가 그려지는 시간
  final state = container.read(provider);
  final section = find.byType(PartnerReviewsSection);
  return {
    'cards': find.descendant(of: section, matching: find.byType(FriendReviewCard)).evaluate().length,
    'loaded': !state.isLoading,
    'error': state.errorMessage,
  };
}

/// E-REV-31 · 34 · 35 — 일감의 `about` 이 있으면 그 사람 14c, 없으면 `list`(received · written) 목록. 둘 다 0장일 수 있다.
Future<Map<String, Object?>> _reviewsSeen(WidgetTester tester, Map<String, dynamic> job) =>
    job['about'] != null ? _aboutCards(tester, job) : _reviewList(tester, job);

final Map<String, Area1Case> area3Cases8 = {
  'E-CHAT-10': _session(_liveBody),
  'E-CHAT-16': _session((tester, job) async {
    await _openAndType(tester, job, _pasted(job));
    await tap(tester, _sendButton);
    await wait(tester, const Duration(seconds: 3)); // 서버 응답과 실시간 줄이 둘 다 올 시간
    return {'bubbles': _bubbles(tester), 'error': _roomError(tester)};
  }),
  'E-REV-20': _session((tester, job) async {
    await _openMyTab(tester);
    return _myTabCounts(tester);
  }),
  'E-REV-24': _session(_deleteWritten),
  'E-REV-27': _session(_composeAndSubmit),
  'E-REV-31': _session(_reviewsSeen),
  'E-REV-34': _session(_reviewsSeen),
  'E-REV-35': _session(_reviewsSeen),
};
