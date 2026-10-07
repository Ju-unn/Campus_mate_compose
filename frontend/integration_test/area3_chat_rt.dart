part of 'area3.dart';

// 영역 3 실시간 · 화면 10개(E-CHAT-01 · 02 · 03 · 07 · 22 · 23 · 24 · 58 · 61 · 72). PC 쪽은 e2e/area3_chat_rt.py 의 같은 번호 — 폰 한 대 8개는 번호 그대로,
// 두 기기 둘(03 · 58)은 `번호/A`(폰) · `번호/B`(에뮬)이다. PC 가 계정 · 매칭을 만들고 상대(A)의 보내기 · 나가기 · 수락은 API 로 하며,
// 앱은 방 뷰모델(chatRoomViewModelProvider)과 화면에서 본 것을 Map 으로 말하고 판정은 PC 가 한다.
// 시각은 앱 시계(UTC) — 서버가 찍은 messages.created_at 과의 시계 차가 섞인다(PC 메모에 남는다). 뷰모델이 글을 가진 프레임에는 말풍선이 아직 안 그려졌을 수 있어
// (E-CHAT-67 에서 확인) 끝 글의 말풍선은 몇 프레임 더 흘린 뒤에 본다. 이 파일의 이름은 모두 `_rt` 로 시작한다 — 이미 있는 것(_openRoom · _row · _chatField · _sendButton · _has …)은 쓰기만 한다.
// 이 파일은 flutter analyze 도, 기기에서도 아직 안 돌려 봤다.

const _rtDisconnected = '연결이 끊겼어요'; // chat_room_screen.dart:160 — 끊김 배너 제목(TrustBanner)
const _rtRetry = '다시 시도'; // chat_room_screen.dart:163 — 배너 버튼
const _rtLoadWait = Duration(seconds: 15); // 방 머리말 · 첫 쪽을 읽는 시간
const _rtLong = Duration(minutes: 5); // PC 가 한참 일하는 멈춤(support.step 기본은 2분)
const _rtBannerWait = Duration(seconds: 60); // 망을 끊은 뒤 끊김 배너가 뜨기를 기다리는 상한 — Realtime 하트비트가 늦게 알아챌 수 있다
const _rtCatchUp = Duration(seconds: 20); // "다시 시도" 뒤 놓친 글이 찾아오기를 기다리는 상한

/// 방을 열고 방 뷰모델이 읽기를 끝낼 때까지 — (container, matchId, 읽었나). 읽기를 못 끝냈거나 오류면 false 이고 PC 는 글을 보내지 않는다.
Future<(ProviderContainer, String, bool)> _rtOpen(WidgetTester tester, String nickname) async {
  await _openRoom(tester, nickname);
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final matchId = tester.widget<ChatRoomScreen>(room).matchId;
  final loading = Stopwatch()..start();
  while (container.read(chatRoomViewModelProvider(matchId)).isLoading && loading.elapsed < _rtLoadWait) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final state = container.read(chatRoomViewModelProvider(matchId));
  return (container, matchId, !state.isLoading && state.errorMessage == null);
}

/// 방 뷰모델이 [bodies] 의 글을 처음 가진 앱 시계(UTC, 글마다 한 번)와, 끊김 상태가 한 번이라도 켜졌는지. [close] 로 구독을 끝낸다.
({Map<String, String> seen, bool Function() disconnected, void Function() close}) _rtWatch(
    ProviderContainer container, String matchId, Iterable<String> bodies) {
  final wanted = bodies.toSet();
  final seen = <String, String>{};
  var disconnected = false;
  final sub = container.listen(chatRoomViewModelProvider(matchId), (_, next) {
    if (next.isDisconnected) disconnected = true;
    for (final message in next.messages) {
      if (wanted.contains(message.body) && !seen.containsKey(message.body)) seen[message.body] = _utcNow();
    }
  });
  return (seen: seen, disconnected: () => disconnected, close: sub.close);
}

/// 뷰모델이 들고 있는 글 중 [bodies] 인 것의 본문을 화면 순서대로 — 같은 본문이 두 줄이면 두 번 나온다.
List<String> _rtOrder(ProviderContainer container, String matchId, Iterable<String> bodies) {
  final wanted = bodies.toSet();
  return [
    for (final message in container.read(chatRoomViewModelProvider(matchId)).messages)
      if (wanted.contains(message.body)) message.body,
  ];
}

/// 본문이 [body] 인 말풍선이 그려졌는지(화면 밖 캐시 포함).
bool _rtBubble(String body) =>
    _has(find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == body, skipOffstage: false));

/// [done] 이 참이 될 때까지 [within] 동안 프레임을 흘린다 — 참이 됐으면 true.
Future<bool> _rtUntil(WidgetTester tester, bool Function() done, Duration within) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < within) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return done();
}

/// step 과 같지만 PC 가 읽을 값을 같이 말한다(두 기기 가설은 앱의 끝 값이 PC 로 안 오므로 step 에 실어 보낸다).
Future<Map<String, dynamic>> _rtStep(String name, Map<String, Object?> data, {Duration timeout = const Duration(minutes: 2)}) async {
  await say({'step': name, ...data});
  return hear(timeout: timeout);
}

/// 방을 못 읽었을 때의 말 — PC 가 이것을 보면 글을 보내지 않고 blocked 로 닫는다.
Map<String, Object?> _rtNotLoaded(ProviderContainer container, String matchId) =>
    {'loaded': false, 'error': container.read(chatRoomViewModelProvider(matchId)).errorMessage};

/// E-CHAT-01 · 02 — 방을 열고 읽기를 끝낸 뒤(구독 전에 보내면 글이 안 온다) `stream` 에서 멈춘다. PC 가 3초 간격으로 20건을 보내는 동안(1분 남짓)
/// 뷰모델이 글마다 처음 가진 앱 시계를 모은다. 끝나면 마지막 글이 말풍선으로 그려질 시간을 두고 화면 순서와 말풍선을 말한다.
Future<Map<String, Object?>> _rtLive(WidgetTester tester, Map<String, dynamic> job) async {
  final bodies = (job['bodies'] as List).cast<String>();
  final (container, matchId, loaded) = await _rtOpen(tester, job['nickname'] as String);
  if (!loaded) return _rtNotLoaded(container, matchId);
  final watch = _rtWatch(container, matchId, bodies);
  try {
    await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
    await step('stream', timeout: _rtLong);
    await _rtUntil(tester, () => watch.seen.length == bodies.length, const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 500)); // 뷰모델이 글을 가진 프레임엔 말풍선이 아직 안 그려졌을 수 있다
    return {'loaded': true, 'seen': watch.seen, 'order': _rtOrder(container, matchId, bodies), 'bubble_last': _rtBubble(bodies.last)};
  } finally {
    watch.close();
  }
}

/// E-CHAT-03 — 두 앱이 방을 열고 `ready` 에서 서로 기다렸다가(PC 가 함께 놓아 준다) 각자 `gap` 초 간격으로 자기 글 20건을 입력칸에 쓰고 보내기를 누른다.
/// B 는 `offset` 초 늦게 시작해 두 기기가 번갈아 보내게 된다. 끝나면 40줄이 다 들어올 때까지 기다렸다가 화면 순서와 글마다 처음 본 시각을 `done` 으로 PC 에 말한다.
Future<Map<String, Object?>?> _rtAlternate(WidgetTester tester, Map<String, dynamic> job) async {
  final mine = (job['mine'] as List).cast<String>();
  final all = [...mine, ...(job['theirs'] as List).cast<String>()];
  final (container, matchId, loaded) = await _rtOpen(tester, job['nickname'] as String);
  if (!loaded) throw E2eBlocked('방이 안 읽힘(${container.read(chatRoomViewModelProvider(matchId)).errorMessage})');
  final watch = _rtWatch(container, matchId, all);
  try {
    await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
    await _rtStep('ready', {}, timeout: _rtLong); // 두 기기가 다 열린 뒤 함께
    final gap = Duration(milliseconds: ((job['gap'] as num) * 1000).round());
    final start = DateTime.now().add(Duration(milliseconds: ((job['offset'] as num) * 1000).round()));
    for (var i = 0; i < mine.length; i++) {
      final at = start.add(gap * i);
      while (DateTime.now().isBefore(at)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // 앞 보내기가 끝나기 전에 또 누르면 뷰모델이 버린다(isSending) — 끝나기를 기다렸다 누른다.
      await _rtUntil(tester, () => !container.read(chatRoomViewModelProvider(matchId)).isSending, const Duration(seconds: 5));
      await type(tester, _chatField, mine[i]);
      await tap(tester, _sendButton);
    }
    await _rtUntil(tester, () => watch.seen.length == all.length, const Duration(seconds: 20));
    await tester.pump(const Duration(milliseconds: 500));
    await _rtStep('done', {'seen': watch.seen, 'order': _rtOrder(container, matchId, all)});
    return null;
  } finally {
    watch.close();
  }
}

/// 대화 목록 [nickname] 줄의 안 읽은 수 글자와 아래 탭 뱃지 — 없으면 null.
Map<String, String?> _rtBadges(WidgetTester tester, String nickname) {
  final badge = find.descendant(of: _row(nickname), matching: find.byType(UnreadBadge));
  return {
    'row': badge.evaluate().isEmpty ? null : tester.widget<Text>(find.descendant(of: badge, matching: find.byType(Text)).first).data,
    'nav': _navBadge(tester),
  };
}

/// E-CHAT-07 — 대화 목록을 열고 `sent` 에서 멈춘다(PC 가 A 로 3건 보낸다 — 목록은 실시간이 아니라 새로고침해야 안다). 당겨서 새로고침(끌기 → 안 되면 같은 표시기를 직접 띄움)한 뒤
/// 목록 뱃지 · 아래 탭 뱃지를 읽고, 방에 들어갔다 뒤로 나온 다음(나갈 때 읽음이 찍히고 목록이 다시 읽힌다) 다시 읽는다.
Future<Map<String, Object?>> _rtUnread(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  await _toConversations(tester);
  await pumpUntil(tester, _row(nickname));
  await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
  await step('sent');
  final badge = find.descendant(of: _row(nickname), matching: find.byType(UnreadBadge));
  var pulled = 'drag';
  final list = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(CustomScrollView)).first;
  await tester.fling(list, const Offset(0, 400), 1000);
  if (await appears(tester, badge, const Duration(seconds: 6)) == null) {
    pulled = 'show';
    unawaited(tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
    await appears(tester, badge, const Duration(seconds: 10));
  }
  await wait(tester, const Duration(seconds: 1)); // 아래 탭 합이 같이 그려지게
  final before = _rtBadges(tester, nickname);
  await tap(tester, _row(nickname));
  await pumpUntil(tester, find.descendant(of: find.byType(AppBar), matching: find.text(nickname)));
  await pumpUntil(tester, find.byType(ChatInputBar));
  await wait(tester, const Duration(seconds: 2)); // 들어올 때 읽음
  await tap(tester, find.descendant(of: find.byType(AppBar), matching: find.byType(BackButton)));
  await pumpUntil(tester, find.byType(ConversationsScreen));
  await _rtUntil(tester, () => _rtBadges(tester, nickname)['row'] == null && _rtBadges(tester, nickname)['nav'] == null, const Duration(seconds: 10));
  await wait(tester, const Duration(seconds: 1)); // 늦게 다시 켜지는 뱃지가 없는지
  return {'before': before, 'after': _rtBadges(tester, nickname), 'pulled': pulled};
}

/// E-CHAT-22 — 방을 열고 `cut` 에서 멈춘다(PC 가 망을 끊는다). 끊김 배너가 뜨기를 기다린 뒤 `offline` 에서 멈춘다(PC 가 A 로 5건을 보내고 망을 되살린다).
/// 배너가 있으면 "다시 시도" 를 눌러 놓친 5건이 모두 · 순서대로 들어오기를 기다린다. 배너가 안 뜨면 누르지 않고 자동으로 채워지는지만 본다.
Future<Map<String, Object?>> _rtReconnect(WidgetTester tester, Map<String, dynamic> job) async {
  final bodies = (job['bodies'] as List).cast<String>();
  final (container, matchId, loaded) = await _rtOpen(tester, job['nickname'] as String);
  if (!loaded) return _rtNotLoaded(container, matchId);
  final watch = _rtWatch(container, matchId, bodies);
  try {
    await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
    await step('cut'); // PC 가 망을 끊는다
    final banner = find.text(_rtDisconnected);
    final shown = await appears(tester, banner, _rtBannerWait);
    await step('offline', timeout: const Duration(minutes: 3)); // PC 가 A 로 보내고 망을 되살린다
    var retried = false;
    if (_has(banner)) {
      await tap(tester, find.text(_rtRetry));
      retried = true;
    }
    await _rtUntil(tester, () => watch.seen.length == bodies.length, _rtCatchUp);
    await tester.pump(const Duration(milliseconds: 500));
    return {
      'loaded': true,
      'banner': shown != null || watch.disconnected(),
      'banner_seconds': shown == null ? null : shown.inMilliseconds / 1000,
      'retried': retried,
      'seen': watch.seen,
      'order': _rtOrder(container, matchId, bodies),
      'bubble_last': _rtBubble(bodies.last),
    };
  } finally {
    watch.close();
  }
}

/// E-CHAT-72 — 방을 열고 `cut` 에서 멈춘다. PC 가 망을 끊고 → A 로 3건 → 끊은 지 5초 뒤 망을 켠다(기다림 없이). 돌아온 뒤 10초 안에
/// 끊김 배너가 아직 떠 있거나 3건이 모두 뷰모델에 들어오는지를 본다(배너가 켜졌다 꺼졌는데 3건이 없으면 PC 가 fail 로 본다).
Future<Map<String, Object?>> _rtBlink(WidgetTester tester, Map<String, dynamic> job) async {
  final bodies = (job['bodies'] as List).cast<String>();
  final (container, matchId, loaded) = await _rtOpen(tester, job['nickname'] as String);
  if (!loaded) return _rtNotLoaded(container, matchId);
  final watch = _rtWatch(container, matchId, bodies);
  try {
    await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
    await step('cut', timeout: _rtLong); // PC: 끊기 → 3건 → 5초 → 켜기. 끝난 뒤에 돌아온다
    final back = Stopwatch()..start();
    // 배너가 떠 있어도 10초를 다 기다린다 — 통로가 다시 붙어 배너가 꺼지고 글이 채워지는지(또는 글 없이 꺼지는지) 보려고.
    await _rtUntil(tester, () => watch.seen.length == bodies.length, const Duration(seconds: 10));
    return {
      'loaded': true,
      'banner': _has(find.text(_rtDisconnected)), // 끝 시각에 아직 떠 있다
      'banner_was': watch.disconnected(), // 한 번이라도 켜졌다
      'shown': watch.seen.length,
      'order': _rtOrder(container, matchId, bodies),
      'seconds': back.elapsedMilliseconds / 1000,
    };
  } finally {
    watch.close();
  }
}

/// E-CHAT-23 — 방을 열고 `home` 에서 멈춘다(PC 가 앱을 HOME 으로 보내고 → A 로 3건 → 앱을 다시 앞으로 가져온다). 돌아온 뒤 아무것도 누르지 않고
/// 3건이 모두 뷰모델에 들어오기를 기다린다. 배경에 들어갔다 나왔는지(paused)와 앞으로 돌아온 시각(resumed_at)도 말한다 — 프레임은 배경에서는 안 흐르므로 멈춘 동안은 pump 하지 않는다.
Future<Map<String, Object?>> _rtResume(WidgetTester tester, Map<String, dynamic> job) async {
  final bodies = (job['bodies'] as List).cast<String>();
  final (container, matchId, loaded) = await _rtOpen(tester, job['nickname'] as String);
  if (!loaded) return _rtNotLoaded(container, matchId);
  final watch = _rtWatch(container, matchId, bodies);
  var paused = false;
  String? resumedAt;
  final lifecycle = AppLifecycleListener(
    onPause: () => paused = true,
    onResume: () {
      if (paused) resumedAt ??= _utcNow();
    },
  );
  try {
    await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
    await step('home', timeout: _rtLong);
    final back = Stopwatch()..start();
    await _rtUntil(tester, () => watch.seen.length == bodies.length, const Duration(seconds: 15));
    final waited = back.elapsedMilliseconds;
    await tester.pump(const Duration(milliseconds: 500));
    return {
      'loaded': true,
      'seen': watch.seen,
      'order': _rtOrder(container, matchId, bodies),
      'bubble_last': _rtBubble(bodies.last),
      'paused': paused,
      'resumed_at': resumedAt,
      'waited_ms': waited,
    };
  } finally {
    lifecycle.dispose();
    watch.close();
  }
}

/// E-CHAT-24 — 방을 열고 `cut` 에서 멈춘다(PC 가 망을 끊는다). 끊김 배너를 기다린 뒤 `changed` 에서 멈춘다(PC 가 `variant` 에 따라 A 를 나가게 하거나 둘 다 수락시키고 망을 되살린다).
/// 배너가 있으면 "다시 시도" 를 눌러 방 머리말을 다시 읽게 하고, 화면이 바뀌기를 기다린다 — left 는 입력창이 사라지고 안내 한 줄, passed 는 "신뢰 확인 완료" 카드 + 상대 카카오톡 아이디.
Future<Map<String, Object?>> _rtMissed(WidgetTester tester, Map<String, dynamic> job) async {
  final left = job['variant'] == 'left';
  final (container, matchId, loaded) = await _rtOpen(tester, job['nickname'] as String);
  if (!loaded) return _rtNotLoaded(container, matchId);
  final watch = _rtWatch(container, matchId, const <String>[]);
  try {
    await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
    await step('cut'); // PC 가 망을 끊는다
    final banner = find.text(_rtDisconnected);
    final shown = await appears(tester, banner, _rtBannerWait);
    await step('changed', timeout: const Duration(minutes: 3)); // PC: 나가기 / 두 수락 → 망을 되살린다
    var retried = false;
    if (_has(banner)) {
      await tap(tester, find.text(_rtRetry));
      retried = true;
    }
    final back = Stopwatch()..start();
    await _rtUntil(
      tester,
      () => left ? !_has(find.byType(ChatInputBar)) && _has(find.text(_partnerGone)) : _has(find.text(_batchTrustDone)),
      _rtCatchUp,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final kakao = job['kakao'] as String?;
    return {
      'loaded': true,
      'banner': shown != null || watch.disconnected(),
      'retried': retried,
      'seconds': back.elapsedMilliseconds / 1000,
      'input': _has(find.byType(ChatInputBar)),
      'notice': _has(find.text(_partnerGone)),
      'card': _has(find.text(_batchTrustDone)),
      'kakao': kakao != null && _has(find.text(kakao)),
    };
  } finally {
    watch.close();
  }
}

/// E-CHAT-61 — 방을 열고(입력창이 있다) `ready` 에서 멈춘다(PC 가 A 를 나가게 한다). 나감 줄이 화면에 뜨면 그 순간부터 입력창이 사라지고 안내 한 줄로 바뀌기까지의 시간을 잰다(최대 8초).
/// 안 바뀌면 시나리오대로 한 건 보내 보고 화면 오류 문구를 말한다.
Future<Map<String, Object?>> _rtLeftOpen(WidgetTester tester, Map<String, dynamic> job) async {
  final (container, matchId, loaded) = await _rtOpen(tester, job['nickname'] as String);
  if (!loaded) return _rtNotLoaded(container, matchId);
  await pumpUntil(tester, find.byType(ChatInputBar));
  await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
  await step('ready'); // PC: A 가 나간다
  final line = await appears(tester, find.text(job['line'] as String), const Duration(seconds: 15));
  if (line == null) return {'loaded': true, 'line': false};
  bool switched() => !_has(find.byType(ChatInputBar)) && _has(find.text(_partnerGone));
  final watch = Stopwatch()..start();
  while (!switched() && watch.elapsed < const Duration(seconds: 8)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final ms = switched() ? watch.elapsedMilliseconds : null;
  String? error;
  if (ms == null && _has(find.byType(ChatInputBar))) {
    await type(tester, _chatField, job['text'] as String);
    await tap(tester, _sendButton);
    await wait(tester, const Duration(seconds: 3));
    error = _roomError(tester) ?? '(오류 문구 없음)';
  }
  return {
    'loaded': true,
    'line': true,
    'switched_ms': ms,
    'input': _has(find.byType(ChatInputBar)),
    'notice': _has(find.text(_partnerGone)),
    'send_error': error,
  };
}

/// E-CHAT-58 A 쪽 — 방을 열고 `ready` 에서 B 를 기다린 뒤 ⋯ → "채팅방 나가기" → 확인 창 "나가기" 를 실제로 눌러 방이 닫히고 대화 목록으로 가는지,
/// 목록에 B 줄이 없는지를 `left` 로 PC 에 말한다.
Future<Map<String, Object?>?> _rtLeaveRoom(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  final (container, matchId, loaded) = await _rtOpen(tester, nickname);
  if (!loaded) throw E2eBlocked('A 방이 안 읽힘(${container.read(chatRoomViewModelProvider(matchId)).errorMessage})');
  await pumpUntil(tester, find.byType(ChatInputBar));
  await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
  await _rtStep('ready', {}, timeout: _rtLong);
  await tap(tester, find.byTooltip(_moreTooltip));
  await pumpUntil(tester, find.text(_leaveChat));
  await tap(tester, find.text(_leaveChat));
  await pumpUntil(tester, find.text(_gateLeaveTitle));
  await tap(tester, find.widgetWithText(TextButton, _gateLeaveConfirm));
  final roomGone = await _rtUntil(tester, () => !_has(find.byType(ChatRoomScreen)), const Duration(seconds: 15));
  final onList = await _rtUntil(tester, () => _has(find.byType(ConversationsScreen)), const Duration(seconds: 15));
  final rowGone = await _rtUntil(tester, () => !_has(_row(nickname)), const Duration(seconds: 10));
  await _rtStep('left', {'room_gone': roomGone, 'on_list': onList, 'row_gone': rowGone});
  return null;
}

/// E-CHAT-58 B 쪽 — 방을 열고 `ready` 에서 A 를 기다린 뒤, A 가 나가기를 누를 때까지(최대 90초) 나감 줄이 뜨기를 기다린다. 뷰모델이 그 줄을 처음 가진 앱 시계를 `seen` 으로 PC 에 말한다.
Future<Map<String, Object?>?> _rtSeeLeft(WidgetTester tester, Map<String, dynamic> job) async {
  final line = job['line'] as String;
  final (container, matchId, loaded) = await _rtOpen(tester, job['nickname'] as String);
  if (!loaded) throw E2eBlocked('B 방이 안 읽힘(${container.read(chatRoomViewModelProvider(matchId)).errorMessage})');
  final watch = _rtWatch(container, matchId, [line]);
  try {
    await wait(tester, const Duration(seconds: 2)); // 구독이 붙기 전에 PC 가 첫 글을 보내면 1번 글을 놓친다
    await _rtStep('ready', {}, timeout: _rtLong);
    final shown = await appears(tester, find.text(line), const Duration(seconds: 90));
    await tester.pump(const Duration(milliseconds: 500));
    await _rtStep('seen', {
      'seen_at': watch.seen[line],
      'shown': shown != null,
      'input': _has(find.byType(ChatInputBar)),
      'notice': _has(find.text(_partnerGone)),
    });
    return null;
  } finally {
    watch.close();
  }
}

final Map<String, Area1Case> area3CasesChatRt = {
  'E-CHAT-01': _session(_rtLive),
  'E-CHAT-02': _session(_rtLive),
  'E-CHAT-03/A': _session(_rtAlternate),
  'E-CHAT-03/B': _session(_rtAlternate),
  'E-CHAT-07': _session(_rtUnread),
  'E-CHAT-22': _session(_rtReconnect),
  'E-CHAT-23': _session(_rtResume),
  'E-CHAT-24': _session(_rtMissed),
  'E-CHAT-58/A': _session(_rtLeaveRoom),
  'E-CHAT-58/B': _session(_rtSeeLeft),
  'E-CHAT-61': _session(_rtLeftOpen),
  'E-CHAT-72': _session(_rtBlink),
};
