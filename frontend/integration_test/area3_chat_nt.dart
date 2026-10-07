part of 'area3.dart';

// 영역 3 알림 10개(E-CHAT-17 · 26 · 27 · 28 · 29 · 30 · 31 · 33 · 35 · 59). PC 쪽은 e2e/area3_chat_nt.py 의 같은 번호 — 알림을 만들고(상대가 API 로 보냄) 읽고 누르는 것은 전부 PC 이고,
// 앱은 로그인해 홈에 머물거나(26 · 27 · 59, 17 의 첫 판) 방 · 목록 · 알림 설정을 열어 두고 본 것을 Map 으로 말한다. 판정은 PC 가 한다.
// 앱이 `step` 에서 멈춰 있는 동안 PC 가 알림을 최대 60초씩 지켜보므로 그 멈춤은 [_ntHold] 만큼 기다린다(기본 2분이면 모자란다).
// 최상위 이름은 모두 `_nt` 로 시작한다 — 같은 라이브러리의 다른 part 와 겹치지 않게. 이미 있는 것(_session · _tab · _row · _openRoom · _bubbles · _liveBody …)은 그대로 쓴다.

const _ntHold = Duration(minutes: 6); // PC 가 토큰 · 알림 · 대조를 기다리는 동안 앱이 멈춰 기다리는 시간
const _ntRoomWait = Duration(seconds: 15); // 방을 열고 뷰모델이 읽기를 끝내기를 기다리는 시간
const _ntListWait = Duration(seconds: 30); // 30: 목록이 저절로 새로 고쳐지기를 기다리는 시간
const _ntSwitchWait = Duration(seconds: 15); // 33: 스위치가 기대한 값이 되기를 기다리는 시간

/// 로그인해 홈에 닿아 3초 머문다(알림 토큰 등록은 홈에 닿은 뒤 앱이 알아서 한다 — 영역 1 E-ONB-61 과 같은 동작). 말할 것은 없다.
Future<Map<String, Object?>?> _ntHome(WidgetTester tester, Map<String, dynamic> job) async {
  await arrive(tester, 'home');
  await wait(tester, const Duration(seconds: 3));
  return null;
}

/// 방을 열고 뷰모델이 방 읽기를 끝낼 때까지 기다린다 — 들어올 때 읽음 시각을 찍는 markRead 는 그 읽기 뒤라 PC 가 DB 로 찍힌 것을 본다. 못 읽으면 blocked.
Future<void> _ntEnterRoom(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  final provider = chatRoomViewModelProvider(tester.widget<ChatRoomScreen>(room).matchId);
  final watch = Stopwatch()..start();
  while (container.read(provider).isLoading && watch.elapsed < _ntRoomWait) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final state = container.read(provider);
  if (state.isLoading || state.errorMessage != null) {
    throw E2eBlocked('방이 안 읽힘(오류 ${state.errorMessage}) — 로그인 · 방 확인');
  }
}

/// E-CHAT-17 phase room — 방을 열어 줄바꿈이 든 글의 말풍선을 찾고, 그 글을 그려진 폭으로 다시 짜 본 줄 수를 말한다.
Future<Map<String, Object?>?> _ntRoomLines(WidgetTester tester, Map<String, dynamic> job) async {
  final body = job['body'] as String;
  await _openRoom(tester, job['nickname'] as String);
  final bubble = find.byWidgetPredicate((w) => w is MessageBubble && w.message.body == body, skipOffstage: false);
  final shown = await appears(tester, bubble, const Duration(seconds: 10)) != null;
  var lines = 0;
  if (shown) {
    final text = find.descendant(
        of: bubble, matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == body, skipOffstage: false));
    final rich = tester.widget<RichText>(text.first);
    final painter = TextPainter(text: rich.text, textDirection: TextDirection.ltr, textScaler: rich.textScaler)
      ..layout(maxWidth: tester.getSize(text.first).width + 1);
    lines = painter.computeLineMetrics().length;
    painter.dispose();
  }
  return {'shown': shown, 'lines': lines, 'bodies': _bubbles(tester)};
}

/// 목록 줄의 안 읽은 수 글자(없으면 null).
String? _ntBadge(WidgetTester tester, Finder row) {
  final badge = find.descendant(of: row, matching: find.byType(UnreadBadge));
  return badge.evaluate().isEmpty ? null : tester.widget<Text>(find.descendant(of: badge, matching: find.byType(Text)).first).data;
}

/// E-CHAT-30 — 대화 목록에서 멈춘 채 PC 가 보내기를 기다리고, 그 글이 마지막 줄로 저절로 올라오는지 · 뱃지가 늘었는지 본다(새로고침은 안 누른다).
Future<Map<String, Object?>?> _ntListLive(WidgetTester tester, Map<String, dynamic> job) async {
  final nickname = job['nickname'] as String;
  final body = job['body'] as String;
  await _ntHome(tester, job);
  await step('home', timeout: _ntHold); // PC: 기기 토큰이 서버에 올라오기를 기다린다
  await _toConversations(tester);
  final row = _row(nickname);
  await pumpUntil(tester, row);
  await wait(tester, const Duration(seconds: 1));
  final lastBefore = tester.widget<ChatListRow>(row).conversation.lastMessage;
  final badgeBefore = _ntBadge(tester, row);
  await step('ready', timeout: _ntHold); // PC: 앞 알림을 읽어 두고 상대가 보낸다
  final watch = Stopwatch()..start();
  while (tester.widget<ChatListRow>(row).conversation.lastMessage != body && watch.elapsed < _ntListWait) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final ms = watch.elapsedMilliseconds;
  await tester.pump(const Duration(milliseconds: 500)); // 뱃지가 같은 프레임에 그려지게
  final seen = <String, Object?>{
    'last_before': lastBefore,
    'last': tester.widget<ChatListRow>(row).conversation.lastMessage,
    'badge_before': badgeBefore,
    'badge': _ntBadge(tester, row),
    'nav_badge': _navBadge(tester),
    'ms': ms,
    // 앞에 머물렀다는 증거는 PC 가 HOME 으로 내리기 전(아래 judged 멈춤 앞)에 잰다 — 뒤에 재면 내려간 뒤 값이라 아무것도 증명 못 한다.
    'list_front': find.byType(ConversationsScreen).evaluate().isNotEmpty,
    'resumed': WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
  };
  await step('judged', timeout: _ntHold); // PC: 알림이 0건인지 지켜보고, HOME 으로 내려 대조 알림을 본다
  return seen;
}

Finder _ntTile(String title) => find.widgetWithText(SwitchListTile, title);

bool _ntOn(WidgetTester tester, String title) => tester.widget<SwitchListTile>(_ntTile(title)).value;

/// 홈 → 나 탭 → 톱니바퀴 → 설정 16 → "알림"(16d). 서버 값을 다 읽어 올 때까지 기다린다 — 늦게 온 처음 값이 방금 누른 스위치를 덮지 않게(notification_settings_view_model.dart).
Future<void> _ntOpen16d(WidgetTester tester, String title) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byIcon(AppIcons.settings));
  await tap(tester, find.byIcon(AppIcons.settings));
  await arrive(tester, 'settings');
  if (find.text('알림').evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text('알림'), 300, scrollable: find.byType(Scrollable).first);
  }
  await tap(tester, find.text('알림'));
  await pumpUntil(tester, find.descendant(of: find.byType(AppBar), matching: find.text('알림')));
  if (_ntTile(title).evaluate().isEmpty) {
    await tester.scrollUntilVisible(_ntTile(title), 300, scrollable: find.byType(Scrollable).first);
  }
  final container = ProviderScope.containerOf(tester.element(_ntTile(title)));
  final watch = Stopwatch()..start();
  while (container.read(notificationSettingsViewModelProvider).isLoading) {
    must(watch.elapsed < const Duration(seconds: 20), '20초 안에 알림 설정을 못 읽음');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// [title] 스위치를 누르고 [expected] 값이 되기를 기다린 뒤 서버 저장이 끝나기를 3초 더 기다린다.
Future<void> _ntFlip(WidgetTester tester, String title, bool expected) async {
  await tap(tester, _ntTile(title));
  final watch = Stopwatch()..start();
  while (_ntTile(title).evaluate().isEmpty || _ntOn(tester, title) != expected) {
    must(watch.elapsed < _ntSwitchWait, '"$title" 스위치가 ${expected ? '켜짐' : '꺼짐'}이 안 됨');
    await tester.pump(const Duration(milliseconds: 200));
  }
  await wait(tester, const Duration(seconds: 3));
}

final Map<String, Area1Case> area3CasesChatNt = {
  // 17: 첫 판은 로그인해 홈에 머문다(PC 가 알림을 읽는다). phase room 은 앱을 새로 켠 판 — 방을 열어 줄바꿈 글의 줄 수를 본다.
  'E-CHAT-17': _session((tester, job) async => job['phase'] == 'room' ? _ntRoomLines(tester, job) : _ntHome(tester, job)),
  'E-CHAT-26': _session(_ntHome),
  'E-CHAT-27': _session(_ntHome),
  // 28: 홈 → (PC 토큰) → 방을 열고 읽기를 끝냄 → 멈춤 — PC 가 읽음 시각을 확인하고 HOME 으로 내려 상대가 보낸다. 방 화면인 채 기다린다.
  'E-CHAT-28': _session((tester, job) async {
    await _ntHome(tester, job);
    await step('home', timeout: _ntHold);
    await _ntEnterRoom(tester, job);
    await step('in_room', timeout: _ntHold);
    return {'in_room': find.byType(ChatRoomScreen).evaluate().isNotEmpty};
  }),
  // 29: 홈 → (PC 토큰) → 방을 열었다 바로 뒤로(나갈 때 읽음이 찍힌다) → 멈춤 — PC 가 HOME 으로 내려 10초 · 40초에 보낸다.
  'E-CHAT-29': _session((tester, job) async {
    await _ntHome(tester, job);
    await step('home', timeout: _ntHold);
    await _ntEnterRoom(tester, job);
    await wait(tester, const Duration(seconds: 2));
    Navigator.of(tester.element(find.byType(ChatRoomScreen))).pop();
    await wait(tester, const Duration(seconds: 1));
    must(find.byType(ChatRoomScreen).evaluate().isEmpty, '뒤로 갔는데 방 화면이 남아 있음');
    await step('left', timeout: _ntHold);
    return {'left': true};
  }),
  'E-CHAT-30': _session(_ntListLive),
  // 31: 홈에서 멈춰(PC 가 HOME · 보내기 · 알림 누르기를 하는 동안) 있다가, 눌려서 열린 방에서 본 것을 말한다(E-CHAT-32 와 같은 읽기).
  'E-CHAT-31': _session((tester, job) async {
    await _ntHome(tester, job);
    await step('holding', timeout: _ntHold);
    return _openedByNotification(tester, job);
  }),
  // 33: 홈 → (PC 토큰) → 16d 에서 "새 메시지" 끔 → 멈춤(PC: 서버 값 · HOME · 보내기 · 0건 · 앱 앞으로) → 켬 → 멈춤(PC: 서버 값 · HOME · 보내기 · 1건).
  'E-CHAT-33': _session((tester, job) async {
    await _ntHome(tester, job);
    await step('home', timeout: _ntHold);
    await _ntOpen16d(tester, '새 메시지');
    must(_ntOn(tester, '새 메시지'), '끄기 전에 "새 메시지" 가 꺼져 있음');
    await _ntFlip(tester, '새 메시지', false);
    await step('off', timeout: _ntHold);
    await _ntFlip(tester, '새 메시지', true);
    await step('on', timeout: _ntHold);
    return null;
  }),
  // 35: phase again 은 PC 가 권한을 켠 뒤 새로 로그인한 판(대조). 첫 판은 권한이 꺼진 채 로그인 — 5초 프레임을 돌린 뒤 멈춰 PC 가 권한 창을 거부하게 하고(area4 E-PUSH-59 와 같다),
  // 이어서 방을 열어 실시간 표시를 본다(E-CHAT-10 과 같은 읽기).
  'E-CHAT-35': _session((tester, job) async {
    if (job['phase'] == 'again') return _ntHome(tester, job);
    await wait(tester, const Duration(seconds: 5));
    await step('signed_in', timeout: _ntHold);
    return _liveBody(tester, job);
  }),
  'E-CHAT-59': _session(_ntHome),
};
