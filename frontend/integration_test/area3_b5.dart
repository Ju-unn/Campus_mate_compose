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
const _batchReconnectWait = Duration(seconds: 5); // 글이 안 떴을 때 진단으로 방을 다시 읽는 시간의 상한(판정과 무관)

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
/// 글을 끝내 못 봤으면(`seen_at` 없음) 판정을 돌려주기 직전에 [_batchReconnectProbe] 로 방을 한 번 다시 읽어 본다 — 이 재연결은 fail 때 원인을 가르는 진단일 뿐
/// 판정에 안 쓴다(돌려주는 `seen_at` · `bubble` · 뷰모델 글 수 · 오류 같은 기존 값은 모두 재연결 **전** 값이다).
/// pass · fail 모두에 채널 측정 `joined_ms` · `joined_at_send` · `system_events` 도 싣는다([_RoomChannelWatch]) — "글이 구독이 붙기 전에 들어갔는가" 가설을
/// 확정 / 기각하려는 것이라 방 읽기 뒤 [_batchSubscribeWait] 만 기다리는 시험 자체는 그대로 둔다(채널 준비를 기다려 주면 결함이 가려진다).
Future<Map<String, Object?>> _batchLiveBubble(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final body = job['body'] as String;
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final matchId = tester.widget<ChatRoomScreen>(room).matchId;
  final channel = _RoomChannelWatch(matchId)..observe(); // 방 열림이 끝난 시점부터 채널을 지켜본다(진단만 — 앱 동작은 그대로)
  final loading = Stopwatch()..start();
  while (container.read(chatRoomViewModelProvider(matchId)).isLoading && loading.elapsed < _batchRoomLoadWait) {
    await tester.pump(const Duration(milliseconds: 100));
    channel.observe();
  }
  final loaded = container.read(chatRoomViewModelProvider(matchId));
  if (loaded.isLoading || loaded.errorMessage != null) {
    return {'loaded': false, 'error': loaded.errorMessage, 'seen_at': null, 'bubble': false};
  }
  final settling = Stopwatch()..start();
  while (settling.elapsed < _batchSubscribeWait) {
    await tester.pump(const Duration(milliseconds: 100));
    channel.observe();
  }
  String? seenAt;
  final sub = container.listen(chatRoomViewModelProvider(matchId), (_, next) {
    if (seenAt == null && next.messages.any((message) => message.body == body)) seenAt = DateTime.now().toUtc().toIso8601String();
  });
  try {
    final joinedAtSend = channel.isJoinedNow(); // PC 가 보내기 직전의 채널 — 아직 안 붙었다면 "구독 전에 보낸 글" 이다
    await step('ready'); // PC 가 A 로 한 건 보낸다
    final watch = Stopwatch()..start();
    while (seenAt == null && watch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 100));
      channel.observe(); // 보낸 뒤에 처음 joined 로 보였다면 그것도 joined_ms 가 말해 준다
    }
    await tester.pump(const Duration(milliseconds: 500)); // 뷰모델이 글을 가진 프레임엔 말풍선이 아직 안 그려졌을 수 있다(10-06 02:06 bubble False)
    final bubble = _has(find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == body, skipOffstage: false));
    final now = container.read(chatRoomViewModelProvider(matchId));
    final said = <String, Object?>{
      'loaded': true,
      'passed': now.room?.gate.passed,
      'vm_count': now.messages.length,
      'vm_bodies': _batchTail(now.messages.map((message) => message.body).toList()),
      'screen_bodies': _batchTail(_bubbles(tester)),
      'error': now.errorMessage,
      'seen_at': seenAt,
      'bubble': bubble,
      ...channel.report(joinedAtSend: joinedAtSend), // pass · fail 모두 — 재연결 진단 **전**의 값이다
    };
    if (seenAt == null) said.addAll(await _batchReconnectProbe(tester, container, matchId, body));
    return said;
  } finally {
    sub.close();
  }
}

/// 지금 붙어 있는 실시간 채널 — "topic joined=…" 글. `topic` · `isJoined` 는 realtime_client 가 안쪽 표시(@internal)로 둔 값이라 이 진단에서만 읽는다
/// (공개된 길이 없다: realtime_client-2.13.0 realtime_channel.dart:31 · 1045).
List<String> _batchChannels() => Supabase.instance.client
    .getChannels()
    // ignore: invalid_use_of_internal_member
    .map((channel) => '${channel.topic} joined=${channel.isJoined}')
    .toList();

/// E-CHAT-67 채널 측정 — 방 채널(`topic` 이 `…messages:<matchId>` 로 끝남)이 방 열림이 끝난 뒤 **언제 처음 joined 로 보였는지**와 서버가 그 채널로 보낸
/// `system` 이벤트를 재서 [report] 로 돌려준다. 앱 동작은 안 바꾼다 — 채널 목록을 읽고, 공개 API 인 `onSystemEvents` 바인딩 하나만 더한다
/// (realtime_client 가 subscribe() 안에서 error 를 channelError 로 올리려고 거는 것과 같은 길 — realtime_channel.dart:173).
/// - 시계는 만든 순간([_openRoom] 직후)부터다. [observe] 를 부를 때만 채널을 보므로 `joined_ms` 의 해상도는 호출 간격(100ms)이다.
/// - system 바인딩은 채널을 **처음 찾은 관찰**에서 건다 — 방 뷰모델이 구독을 건 뒤 그 첫 관찰까지 온 이벤트는 놓칠 수 있다(`system_events` 는 하한이다).
class _RoomChannelWatch {
  _RoomChannelWatch(this._matchId);

  final String _matchId;
  final Stopwatch _clock = Stopwatch()..start();
  final List<Map<String, Object?>> _systemEvents = [];
  RealtimeChannel? _channel;
  int? _joinedMs;

  /// 채널 상태를 한 번 본다. 처음 찾으면 system 바인딩을 걸고, 처음 joined 로 보이면 그 시각(ms)을 적는다.
  void observe() {
    final channel = _channel ??= _find()?.onSystemEvents(_record);
    if (channel != null && _joinedMs == null && _isJoined(channel)) _joinedMs = _clock.elapsedMilliseconds;
  }

  /// 지금 joined 인가 — 채널을 못 찾았으면 null.
  bool? isJoinedNow() {
    observe();
    final channel = _channel;
    return channel == null ? null : _isJoined(channel);
  }

  /// 돌려줄 값. `joined_ms` 는 끝까지 joined 를 못 봤으면 null, `system_events` 는 `{ms, status, extension, message}` 목록이다.
  Map<String, Object?> report({required bool? joinedAtSend}) =>
      {'joined_ms': _joinedMs, 'joined_at_send': joinedAtSend, 'system_events': List.of(_systemEvents)};

  RealtimeChannel? _find() => Supabase.instance.client.getChannels().where(_isRoomChannel).firstOrNull;

  // `topic` · `isJoined` 는 realtime_client 가 안쪽 표시(@internal)로 둔 값이다(realtime_channel.dart:31 · 1045) — 공개된 길이 없어 이 진단에서만 읽는다.
  // ignore: invalid_use_of_internal_member
  bool _isRoomChannel(RealtimeChannel channel) => channel.topic.endsWith('messages:$_matchId');

  // ignore: invalid_use_of_internal_member
  bool _isJoined(RealtimeChannel channel) => channel.isJoined;

  /// 서버가 보낸 값이라 모양을 믿지 않는다 — Map 이 아니면 모두 null 로 적는다. 메시지는 길이만 잘라 둔다.
  void _record(dynamic payload) {
    final fields = payload is Map ? payload : const {};
    String? text(String key, [int limit = 200]) {
      final value = fields[key]?.toString();
      return value != null && value.length > limit ? value.substring(0, limit) : value;
    }

    _systemEvents.add({'ms': _clock.elapsedMilliseconds, 'status': text('status'), 'extension': text('extension'), 'message': text('message')});
  }
}

/// E-CHAT-67 에서 글을 못 봤을 때만 부르는 진단 — 재연결 **전** 상태(방 뷰모델 isDisconnected · 소켓 · 실시간이 쓰는 토큰이 로그인 세션 토큰인지 · 실시간 채널 목록)를
/// 적은 뒤 방 뷰모델 reconnect() 를 한 번 불러(상한 [_batchReconnectWait]) 다시 읽은 방에 그 글이 있는지를 `after_reconnect` 로 돌려준다. PC 메모가
/// "다시 읽으면 보인다 = 실시간 통로만 놓쳤다" 와 "다시 읽어도 없다" 를 가른다. 판정에는 안 쓰인다. 토큰은 같은지(참 · 거짓)만 말하고 값은 말하지 않는다 —
/// 서버가 RLS 를 실시간 연결에 실린 토큰으로 가리므로(익명 키가 실려 있으면 `to authenticated` 정책이 모든 줄을 가린다) 그 토큰이 사용자 것이었는지를 본다.
Future<Map<String, Object?>> _batchReconnectProbe(
  WidgetTester tester,
  ProviderContainer container,
  String matchId,
  String body,
) async {
  final client = Supabase.instance.client;
  final disconnected = container.read(chatRoomViewModelProvider(matchId)).isDisconnected;
  final socket = client.realtime.connectionState;
  final session = client.auth.currentSession?.accessToken;
  final sameToken = session != null && client.realtime.accessToken == session;
  final channels = _batchChannels();
  var finished = false;
  String? thrown;
  unawaited(container
      .read(chatRoomViewModelProvider(matchId).notifier)
      .reconnect()
      .then<void>((_) {}, onError: (Object error) => thrown = error.runtimeType.toString())
      .whenComplete(() => finished = true));
  final watch = Stopwatch()..start();
  while (!finished && watch.elapsed < _batchReconnectWait) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final after = container.read(chatRoomViewModelProvider(matchId));
  return {
    'disconnected_before': disconnected,
    'socket_before': socket,
    'rt_token_is_session': sameToken,
    'channels_before': channels,
    'after_reconnect': {
      'found': after.messages.any((message) => message.body == body),
      'vm_count': after.messages.length,
      'vm_bodies': _batchTail(after.messages.map((message) => message.body).toList()),
      'finished': finished,
      'error': thrown ?? after.errorMessage,
    },
  };
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
