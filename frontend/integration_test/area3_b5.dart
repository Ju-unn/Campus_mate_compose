part of 'area3.dart';

// 영역 3 배치 가설 8개(E-CHAT-50 · 51 · 52 · 55 · 57 · 65 · 66 · 67) — 운영 chat-gate 배치를 실제로 부르는 가설의 폰(B) 쪽. PC 쪽은 e2e/area3_phone5.py 의 같은 번호
// (계정 · 방을 만들고, 시각 관문을 지나 matches.created_at 을 옮기고, 배치를 불러 DB · 알림을 센다). 앱은 로그인 · 목록 · 방에서 본 것만 Map 으로 돌려주고
// 판정은 PC 가 한다. E-CHAT-69(정리 배치)는 폰이 필요 없어 이 파일에 없다.
// 화면 글자 · 위젯은 시나리오가 아니라 지금 화면 코드(chat_room_screen · trust_reveal_bubble · chat_errors · conversations_screen)에서 옮겼다.
// 알림 도착을 기다리는 가설(50 · 51 · 52 · 65)은 `phase: login` 에서 홈까지만 가고(알림 토큰 등록은 홈에 닿은 뒤 앱이 알아서 한다) PC 가 프로세스를 죽인다.
// 50 의 `phase: tap` 은 알림 누름으로 콜드 스타트한 앱이 e2e_test.dart 의 hear() 로 받는다 — area3_b3.dart 의 E-CHAT-32 와 같은 길이라 두 함수를 그대로 쓴다.

const _batchListWait = Duration(seconds: 30); // 로그인 · 목록 조회 · 첫 그림
const _batchCardWait = Duration(seconds: 15); // 방 머리말을 읽고 14b 카드를 그리는 시간
const _batchTrustDone = '신뢰 확인 완료'; // trust_reveal_bubble.dart:49
const _batchRoomLoadWait = Duration(seconds: 15); // 방 뷰모델이 머리말 · 첫 페이지 읽기를 끝내는 시간
// 가설(실물 미확인): 방 뷰모델은 구독을 첫 페이지 읽기 직전에 걸어(chat_room_view_model.dart:49-60) 읽기가 끝난 직후엔 실시간 채널이 아직 안 붙었을 수 있다.
// PC 가 보내기 전에 채널이 붙을 시간을 준다 — E-CHAT-67 이 구독 전에 글이 들어가 못 받은 것인지 가르려는 것이라 이 시간 자체가 판정을 바꾸지 않는다.
const _batchSubscribeWait = Duration(seconds: 2);

/// E-CHAT-55 · 65 — 배치 뒤 로그인해 대화 목록을 읽는다. 목록이 그려졌다는 증거로 PC 가 닫지 않고 둔 다른 방(control) 줄이 뜰 때까지 기다린 뒤,
/// 목록 줄의 닉네임을 모두 말한다(그 방이 있는지 없는지는 PC 가 가린다). 안 뜨면 `waited: false` — PC 는 판정 대신 blocked 로 본다.
Future<Map<String, Object?>> _batchListRows(WidgetTester tester, Map<String, dynamic> job) async {
  await _toConversations(tester);
  final drawn = await _ever(tester, _row(job['control'] as String), _batchListWait);
  if (drawn) await wait(tester, const Duration(seconds: 2)); // 목록을 다시 읽는 사이의 빈 순간이 아닌지
  final rows = tester.widgetList<ChatListRow>(find.byType(ChatListRow)).map((row) => row.conversation.partner.nickname).toList();
  return {'waited': drawn, 'rows': rows};
}

/// E-CHAT-57 — 방을 열고(젊은 방 — PC 가 만든 그대로) 입력 줄이 뜨면 `step` 에서 멈춘다. PC 가 그사이 방을 48시간 5분 지난 것으로 옮기고 배치로 닫으면
/// (몇 분 걸려 step 기다림이 길다) 이어서 한 건 보내고, 방 뷰모델에 처음 뜬 오류 문구와 끝 값을 말한다. 오류 줄은 다음 동작이 시작되면 지워지므로
/// (chat_room_ui_state.dart copyWith) 처음 값을 구독으로 잡는다.
Future<Map<String, Object?>> _batchSendIntoClosed(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  await pumpUntil(tester, find.byType(ChatInputBar));
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final matchId = tester.widget<ChatRoomScreen>(room).matchId;
  String? first;
  final sub = container.listen(chatRoomViewModelProvider(matchId), (_, next) => first ??= next.errorMessage);
  try {
    await step('closed', timeout: const Duration(minutes: 5)); // PC 가 배치를 돌려 방이 닫힌 뒤에 이어 간다
    await type(tester, _chatField, job['text'] as String);
    await tap(tester, _sendButton);
    final watch = Stopwatch()..start();
    while (first == null && watch.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await wait(tester, const Duration(seconds: 1));
    return {'error': first, 'error_now': container.read(chatRoomViewModelProvider(matchId)).errorMessage};
  } finally {
    sub.close();
  }
}

/// E-CHAT-66 — 배치가 통과 도장을 찍은 방을 열어 14b "신뢰 확인 완료" 카드가 뜨는지.
Future<Map<String, Object?>> _batchCardInRoom(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  return {'card': await _ever(tester, find.text(_batchTrustDone), _batchCardWait)};
}

/// 본문 앞 40자 · 마지막 5건 — 진단 문구가 길어지지 않게.
List<String> _batchTail(List<String> bodies) =>
    bodies.skip(bodies.length > 5 ? bodies.length - 5 : 0).map((body) => body.length > 40 ? body.substring(0, 40) : body).toList();

/// E-CHAT-67 — 방을 열고 뷰모델이 방 읽기를 끝낸 뒤(E-CHAT-10 과 같다) 구독 채널이 붙을 시간을 더 주고 `step` 에서 멈춘다. PC 가 그사이 A 로 한 건 보내면(본문 `body`)
/// 방 뷰모델이 그 글을 처음 가진 앱 시계(UTC)를 말한다. 읽기를 못 끝내거나 오류면 `step` 을 부르지 않고 `loaded: false` 로 끝낸다.
/// 보낸 시각은 PC 가 서버가 찍은 messages.created_at 으로 읽는다 — 폰 시계와 서버 시계의 차가 섞인다(PC 메모에 남는다).
/// 끝에 진단(방 읽기 · 통과 도장 · 뷰모델 글 수 · 뷰모델 · 화면 본문 · 오류)을 실어 말풍선이 안 떴을 때 PC 메모가 원인을 가르게 한다.
Future<Map<String, Object?>> _batchLiveBubble(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final body = job['body'] as String;
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final matchId = tester.widget<ChatRoomScreen>(room).matchId;
  final loading = Stopwatch()..start();
  while (container.read(chatRoomViewModelProvider(matchId)).isLoading && loading.elapsed < _batchRoomLoadWait) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final loaded = container.read(chatRoomViewModelProvider(matchId));
  if (loaded.isLoading || loaded.errorMessage != null) {
    return {'loaded': false, 'error': loaded.errorMessage, 'seen_at': null, 'bubble': false};
  }
  await wait(tester, _batchSubscribeWait);
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
    await tester.pump(const Duration(milliseconds: 500)); // 뷰모델이 글을 가진 프레임엔 말풍선이 아직 안 그려졌을 수 있다(10-06 02:06 bubble False)
    final bubble = _has(find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == body, skipOffstage: false));
    final now = container.read(chatRoomViewModelProvider(matchId));
    return {
      'loaded': true,
      'passed': now.room?.gate.passed,
      'vm_count': now.messages.length,
      'vm_bodies': _batchTail(now.messages.map((message) => message.body).toList()),
      'screen_bodies': _batchTail(_bubbles(tester)),
      'error': now.errorMessage,
      'seen_at': seenAt,
      'bubble': bubble,
    };
  } finally {
    sub.close();
  }
}

final Map<String, Area1Case> area3Cases5 = {
  'E-CHAT-50': (tester, job) async => switch (job['phase']) {
        'login' => await _session(_homeAfterLogin)(tester, job),
        'tap' => await _openedByNotification(tester, job),
        final other => throw E2eBlocked('E-CHAT-50 일감 phase 를 모름: $other'),
      },
  'E-CHAT-51': _session(_homeAfterLogin),
  'E-CHAT-52': _session(_homeAfterLogin),
  'E-CHAT-55': _session(_batchListRows),
  'E-CHAT-57': _session(_batchSendIntoClosed),
  'E-CHAT-65': (tester, job) async => switch (job['phase']) {
        'login' => await _session(_homeAfterLogin)(tester, job),
        'list' => await _session(_batchListRows)(tester, job),
        final other => throw E2eBlocked('E-CHAT-65 일감 phase 를 모름: $other'),
      },
  'E-CHAT-66': _session(_batchCardInRoom),
  'E-CHAT-67': _session(_batchLiveBubble),
};
